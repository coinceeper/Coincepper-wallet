package com.coinceeper.adl

import android.app.Application
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterFragmentActivity
import org.json.JSONObject
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    /** مطابق TspAgentChannel (Dart) */
    private val tspAgentChannel = "com.coinceeper.app/tsp_agent"
    private var tspNativePathDone = false

    /**
     * Application-level lifecycle callback that monitors Activity destruction
     * for diagnostic purposes. On many OEM devices (Xiaomi, Huawei, OnePlus,
     * Samsung), [onTaskRemoved] is NOT called when the user removes the app
     * from recents, so this callback helps track when the UI layer is fully
     * torn down.
     */
    private val lifecycleCallback = object : Application.ActivityLifecycleCallbacks {
        private var activityCount = 0
        override fun onActivityCreated(activity: android.app.Activity, savedInstanceState: Bundle?) {
            activityCount++
        }
        override fun onActivityStarted(activity: android.app.Activity) {}
        override fun onActivityResumed(activity: android.app.Activity) {}
        override fun onActivityPaused(activity: android.app.Activity) {}
        override fun onActivityStopped(activity: android.app.Activity) {}
        override fun onActivitySaveInstanceState(activity: android.app.Activity, outState: Bundle) {}
        override fun onActivityDestroyed(activity: android.app.Activity) {
            activityCount--
            if (activityCount <= 0 && activity.isFinishing) {
                android.util.Log.i("TspAgent", "All Activities destroyed — process may be killed. " +
                    "Foreground service should have already called stopForeground() " +
                    "via onTaskRemoved or onDestroy.")
                try {
                    application.unregisterActivityLifecycleCallbacks(this)
                } catch (e: Exception) {
                    // Ignore unregister errors during shutdown
                }
            }
        }
    }

    private fun ensureNativeLibPath() {
        if (tspNativePathDone) return
        val p = TspNativeLoader.getTspagentDiskPath()
            ?: File(applicationInfo.nativeLibraryDir, "libtspagent.so").absolutePath
        TspAgentBridge.setNativeLibPath(p)
        tspNativePathDone = true
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Register ActivityLifecycleCallbacks to detect when all activities
        // are destroyed (device reboot, force-stop, etc.). This proactively
        // cancels the foreground service state before the process is killed,
        // preventing ForegroundServiceDidNotStopInTimeException.
        application.registerActivityLifecycleCallbacks(lifecycleCallback)
        // Initialize CookieRotator as early as possible in the Activity lifecycle.
        // This ensures CookieManager is ready before any WebView is created.
        CookieRotator.initialize()
        android.util.Log.d("TspAgent", "CookieRotator initialized in MainActivity.onCreate")
    }

    override fun onResume() {
        super.onResume()
        TspWebClickHost.setCurrentActivityForWebClick(this)
    }

    override fun onDestroy() {
        TspWebClickHost.setCurrentActivityForWebClick(null)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.coinceeper.app/screen_protection",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    window.setFlags(
                        WindowManager.LayoutParams.FLAG_SECURE,
                        WindowManager.LayoutParams.FLAG_SECURE,
                    )
                    result.success(null)
                }
                "disable" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            tspAgentChannel,
        ).setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            try {
                TspAgentBridge.ensureLoaded(this@MainActivity)
                // Cache WebView class reference on the Java thread (has correct class loader)
                try { TspAgentBridge.cacheWebViewHost() } catch (e: Throwable) { android.util.Log.w("TspAgent", "cacheWebViewHost: ${e.message}") }
            } catch (e: UnsatisfiedLinkError) {
                result.error(
                    "NATIVE_GONE",
                    "Build agent native libs: scripts/build_gobridge.sh (Go + NDK). ${e.message}",
                    null,
                )
                return@setMethodCallHandler
            } catch (e: Throwable) {
                result.error("NATIVE", e.message, null)
                return@setMethodCallHandler
            }
            try {
                ensureNativeLibPath()
                when (call.method) {
                    "tspVersion" -> result.success(TspAgentBridge.versionString())
                    "tspHealth" -> result.success(TspAgentBridge.healthJson())
                    "tspFingerprint" -> result.success(TspAgentBridge.fingerprint())
                    "tspIsForegroundServiceRunning" -> {
                        result.success(TspAgentForegroundService.isRunning)
                    }
                    "tspStartForeground" -> {
                        try {
                            val i = Intent(this, TspAgentForegroundService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(i)
                            } else {
                                startService(i)
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            // Catch ForegroundServiceStartNotAllowedException and others
                            android.util.Log.e("TspAgent", "Failed to start foreground service: ${e.message}")
                            // Result success anyway to avoid Dart side crash, 
                            // as this is a non-critical background service.
                            result.success(null)
                        }
                    }
                    "tspStopForeground" -> {
                        stopService(Intent(this, TspAgentForegroundService::class.java))
                        result.success(null)
                    }
                    "tspStart" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as? Map<String, Any?>
                        val cfg = args?.get("configPath") as? String
                        if (cfg.isNullOrBlank()) {
                            result.error("ARG", "configPath required", null)
                        } else {
                            val st = args["statePath"] as? String
                            val code = TspAgentBridge.startWithPaths(cfg, st)
                            if (code == 0 || code == -2) {
                                TspAgentRuntimePrefs.setPaths(
                                    this@MainActivity,
                                    configPath = cfg,
                                    statePath = st,
                                )
                            }
                            result.success(code)
                        }
                    }
                    "tspSetStrictMode" -> {
                        val v = (call.arguments as? Number)?.toInt() ?: 0
                        result.success(TspAgentBridge.setStrictMode(v) == 0)
                    }
                    "tspPrepareAttestation" -> {
                        val hint = when (val a = call.arguments) {
                            is Map<*, *> -> (a["nonceHint"] as? String) ?: ""
                            is String -> a
                            else -> ""
                        }
                        TspAttestationProvider.getPlayIntegrityToken(
                            this@MainActivity,
                            hint,
                        ) { token ->
                            val j = JSONObject()
                            j.put("p", "play_integrity")
                            j.put("t", token)
                            TspAgentBridge.setAttestationJSON(j.toString())
                            Handler(Looper.getMainLooper()).post {
                                result.success(true)
                            }
                        }
                    }
                    "tspSetDeviceKey" -> {
                        // Isolated try so a KeyStore failure returns false (not result.error)
                        // which lets the Dart fallback path run instead of crashing.
                        try {
                            val hex = TspSecureKeyProvider.getOrCreatePayloadKeyHex(this@MainActivity)
                            result.success(TspAgentBridge.setPayloadKeyHex(hex) == 0)
                        } catch (e: Throwable) {
                            android.util.Log.w("TspAgent", "device-key setup failed: ${e.message}")
                            result.success(false)
                        }
                    }
                    "tspSetPayloadKeyHex" -> {
                        val hex = (call.arguments as? String)?.trim().orEmpty()
                        if (hex.length != 64) {
                            result.success(false)
                        } else {
                            result.success(TspAgentBridge.setPayloadKeyHex(hex) == 0)
                        }
                    }
                    "tspRequestBatteryOptOut" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(
                                android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                android.net.Uri.parse("package:${applicationContext.packageName}")
                            )
                            try {
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                android.util.Log.w("TspAgent", "Battery opt-out intent failed: ${e.message}")
                                result.success(false)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "tspIsBatteryOptOutGranted" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val powerManager = getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
                            val granted = powerManager.isIgnoringBatteryOptimizations(applicationContext.packageName)
                            result.success(granted)
                        } else {
                            result.success(true) // Pre-M devices don't have battery optimization
                        }
                    }
                    "tspSetAdNetwork" -> {
                        // تنظیم دستی شبکه تبلیغاتی (برای دیباگ و کنترل از پنل)
                        val network = (call.arguments as? String)?.trim()?.lowercase() ?: ""
                        val valid = network in listOf("coinzilla", "monetag", "hypelab", "generic", "")
                        if (valid) {
                            android.util.Log.d("TspAgent", "AdNetwork override set: '$network'")
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "tspStop" -> {
                        TspAgentRuntimePrefs.clear(this@MainActivity)
                        // CRITICAL FIX: Stop the foreground service FIRST, immediately,
                        // before any potentially-blocking JNI call. On Android 12+,
                        // stopService() starts a ~5s timeout for the service to call
                        // stopForeground(). If the main thread is blocked by
                        // TspAgentBridge.stopRuntime() (JNI), onDestroy() may not be
                        // delivered in time, causing ForegroundServiceDidNotStopInTimeException.
                        stopService(Intent(this, TspAgentForegroundService::class.java))
                        // Now stop the Go agent runtime on a background thread so the
                        // main thread is free to process the service's lifecycle callbacks.
                        Thread {
                            try {
                                TspAgentBridge.stopRuntime()
                            } catch (e: Exception) {
                                android.util.Log.e("TspAgent", "Error stopping runtime on background thread: ${e.message}")
                            }
                        }.start()
                        result.success(null)
                    }
                    "tspStopAgentRuntime" -> {
                        // Stops the Go agent runtime ONLY.
                        // Does NOT stop the foreground service, preventing the
                        // ForegroundServiceDidNotStopInTimeException race condition
                        // caused by stopService() + immediate startForegroundService().
                        TspAgentRuntimePrefs.clear(this@MainActivity)
                        // Run JNI call on background thread to avoid blocking the
                        // main thread (which could delay service lifecycle callbacks).
                        Thread {
                            try {
                                TspAgentBridge.stopRuntime()
                            } catch (e: Exception) {
                                android.util.Log.e("TspAgent", "Error stopping agent runtime: ${e.message}")
                            }
                        }.start()
                        result.success(null)
                    }
                    "tspIsRunning" -> result.success(TspAgentBridge.isRuntimeRunning())
                    "tspConfigureWebViewHost" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as? Map<String, Any?>
                        if (args != null) {
                            val configJson = JSONObject().apply {
                                args["min_pool_size"]?.let { put("min_pool_size", it) }
                                args["max_pool_size"]?.let { put("max_pool_size", it) }
                                args["idle_timeout_ms"]?.let { put("idle_timeout_ms", it) }
                                args["acquire_timeout_ms"]?.let { put("acquire_timeout_ms", it) }
                                args["auto_scaling"]?.let { put("auto_scaling", it) }
                            }.toString()
                            val res = TspAgentBridge.configureWebViewHost(configJson)
                            result.success(res)
                        } else {
                            val res = TspAgentBridge.configureWebViewHost("{}")
                            result.success(res)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                result.error("NATIVE", e.message, null)
            }
        }
    }
}
