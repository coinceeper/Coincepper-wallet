package com.coinceeper.adl

import android.os.Build
import android.util.Log
import android.webkit.CookieManager
import android.webkit.WebView
import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.util.Random
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * CookieRotator — مدیریت حرفه‌ای کوکی‌های WebView با رفتار شبیه مرورگر واقعی.
 *
 * == مسئله ==
 * در معماری WebView Pool، هر بار که یک WebView به Pool برمی‌گردد،
 * `loadUrl("about:blank")` و `clearHistory()` فراخوانی می‌شود.
 * اگرچه `CookieManager` اندروید به صورت singleton کار می‌کند و کوکی‌ها
 * به صورت خودکار persist می‌شوند، اما در برخی نسخه‌های اندروید (مخصوصاً ۱۱+):
 *   - Session cookies (بدون Expires/Max-Age) پس از ناوبری به about:blank از دست می‌روند
 *   - WebView renderer process در برخی دستگاه‌ها بازنشانی می‌شود
 *   - کوکی‌های domain-specific به domain جدید ارسال نمی‌شوند (طبیعی است)
 *
 * == نتیجه ==
 * هر بازدید از یک سایت جدید → کوکی خالی → ۹۹٪ Bot Detected
 *
 * == راه‌حل (CookieRotator) ==
 * 1. Cookie Persistence: کوکی‌ها در `CookieManager` نگه داشته می‌شوند
 * 2. Cookie Rotation: چرخش کوکی‌ها برای شبیه‌سازی کاربر واقعی
 * 3. Cookie Aging: انقضای تدریجی کوکی‌ها شبیه مرورگر واقعی
 * 4. Warmup Cookies: تزریق کوکی‌های warmup sites به CookieManager
 * 5. Session Tracking: ردیابی domainهای بازدیدشده برای بازگشت بعدی
 * 6. Cookie Flush Without Clear: نگهداشتن کوکی‌ها اما بازنشانی WebView
 *
 * == اصول ==
 * - مرورگر واقعی هرگز کوکی‌ها را بین tabها پاک نمی‌کند
 * - مرورگر واقعی فقط کوکی‌های expired را پاک می‌کند
 * - مرورگر واقعی کوکی‌های domain مناسب را برای هر درخواست ارسال می‌کند
 * - کاربران واقعی کوکی‌های session را هنگام بستن مرورگر از دست می‌دهند
 */
object CookieRotator {
    private const val TAG = "CookieRotator"
    private val rng = Random()

    // ── Cookie Stats ────────────────────────────────────────────
    private val totalCookiesManaged = AtomicInteger(0)
    private val totalCookiesRotated = AtomicInteger(0)
    private val totalCookiesExpired = AtomicInteger(0)
    private val totalSessionsTracked = AtomicInteger(0)
    private val totalWarmupInjections = AtomicInteger(0)

    // ── Session Tracking ─────────────────────────────────────────
    // Domain‌هایی که در این "جلسه مرورگر" بازدید شده‌اند
    private val visitedDomains = mutableSetOf<String>()
    // تعداد دفعات بازدید از هر domain
    private val domainVisitCount = mutableMapOf<String, Int>()
    // domain آخرین بازدید
    private var lastVisitedDomain: String = ""

    /**
     * مقداردهی اولیه CookieManager.
     * باید یکبار در ابتدای کار (در MainActivity یا اولین run) فراخوانی شود.
     */
    @JvmStatic
    fun initialize() {
        try {
            val cm = CookieManager.getInstance()
            cm.setAcceptCookie(true)
            // setAcceptThirdPartyCookies needs a WebView instance; we'll set it
            // per-WebView in TspWebClickHost. Set the global accept cookie flag here.
            Log.i(TAG, "CookieManager initialized: acceptCookie=${cm.acceptCookie()}")
        } catch (e: Exception) {
            Log.w(TAG, "CookieManager init failed: ${e.message}")
        }
    }

    /**
     * بررسی سلامت CookieManager.
     */
    @JvmStatic
    fun isOperational(): Boolean {
        return try {
            CookieManager.getInstance().acceptCookie()
        } catch (e: Exception) {
            false
        }
    }

    /**
     * مدیریت کوکی‌ها قبل از بارگذاری URL جدید در WebView.
     *
     * این متد قبل از `wv.loadUrl(url)` در run() فراخوانی می‌شود.
     *
     * کارها:
     * 1. ردیابی domain جدید
     * 2. بررسی session cookies domain قبلی
     * 3. تزریق کوکی‌های warmup در صورت نیاز
     * 4. flush کوکی‌ها به دیسک
     *
     * @param url URL مقصد
     * @param behavior پروفایل رفتار شبکه تبلیغاتی
     */
    @JvmStatic
    fun prepareForNavigation(url: String, behavior: AdNetworkBehavior) {
        try {
            val targetDomain = extractDomain(url)
            if (targetDomain.isBlank()) return

            val cm = CookieManager.getInstance()

            // ── 1. Track session domain ─────────────────────────
            synchronized(visitedDomains) {
                visitedDomains.add(targetDomain)
                domainVisitCount[targetDomain] = (domainVisitCount[targetDomain] ?: 0) + 1
                lastVisitedDomain = targetDomain
                totalSessionsTracked.incrementAndGet()
            }

            val visitCount = domainVisitCount[targetDomain] ?: 1

            // ── 2. Cookie rotation according to behavior ────────
            val rotationConfig = behavior.cookieConfig
            if (rotationConfig.enabled) {
                applyCookieRotation(cm, targetDomain, rotationConfig, visitCount)
            }

            // ── 3. Warmup cookie injection (first visit only) ───
            if (visitCount == 1 && rotationConfig.enabled) {
                injectWarmupCookies(cm, targetDomain, rotationConfig)
            }

            // ── 4. Flush to disk (Android L+) ───────────────────
            flushCookies(cm)

            logCookieState(targetDomain)
        } catch (e: Exception) {
            Log.w(TAG, "prepareForNavigation error: ${e.message}")
        }
    }

    /**
     * پاکسازی WebView هنگام بازگشت به Pool بدون پاک کردن کوکی‌ها.
     *
     * برخلاف کد قبلی که فقط `clearHistory()` می‌کرد، این متد:
     * - کوکی‌ها را نگه می‌دارد (مثل مرورگر واقعی)
     * - فقط WebView state را پاک می‌کند (about:blank)
     * - session cookies domain قبلی را اگر expired شده باشند حذف می‌کند
     *
     * @param wv WebView که به Pool برمی‌گردد
     * @param behavior پروفایل رفتار
     */
    @JvmStatic
    fun cleanupForPoolReturn(wv: WebView, behavior: AdNetworkBehavior) {
        try {
            val rotationConfig = behavior.cookieConfig

            // ── 1. Never clear persistent cookies ───────────────
            //   مرورگر واقعی کوکی‌ها را بین tabها نگه می‌دارد.

            // ── 2. Only cleanup if rotation is enabled ──────────
            if (rotationConfig.enabled && rotationConfig.cleanupOnReturn) {
                val cm = CookieManager.getInstance()
                val currentUrl = try { wv.url ?: "" } catch (e: Exception) { "" }
                val currentDomain = extractDomain(currentUrl)

                // فقط اگر domain آخرین بازدید با domain فعلی متفاوت است
                // و یک domain قبلی وجود دارد، session cookies را مدیریت کن
                if (currentDomain.isNotBlank() && lastVisitedDomain.isNotBlank()
                    && currentDomain != lastVisitedDomain) {
                    cleanupStaleSessionCookies(cm, currentDomain, rotationConfig)
                }
            }

            Log.d(TAG, "cleanupForPoolReturn: cookies preserved, WebView reset")
        } catch (e: Exception) {
            Log.w(TAG, "cleanupForPoolReturn error: ${e.message}")
        }
    }

    /**
     * گرفتن آمار کوکی‌های فعلی برای یک domain خاص.
     * برای گزارش به Go agent استفاده می‌شود.
     *
     * @param url URL که کوکی‌های آن را می‌خواهیم
     * @return JSON array of cookies
     */
    @JvmStatic
    fun getCookiesForUrl(url: String): String {
        return try {
            val cm = CookieManager.getInstance()
            val cookieString = cm.getCookie(url) ?: ""
            val cookies = cookieString.split(";").map { it.trim() }.filter { it.isNotBlank() }

            val arr = JSONArray()
            for (cookie in cookies) {
                val parts = cookie.split("=", limit = 2)
                if (parts.size == 2) {
                    val obj = JSONObject()
                    obj.put("name", parts[0])
                    obj.put("value", parts[1].take(20)) // فقط ۲۰ کاراکتر اول برای امنیت
                    arr.put(obj)
                }
            }
            arr.toString()
        } catch (e: Exception) {
            "[]"
        }
    }

    /**
     * گرفتن تعداد کل کوکی‌های ذخیره‌شده.
     * از طریق CookieManager اندروید نمی‌توان تعداد دقیق را گرفت،
     * بنابراین از آمار داخلی استفاده می‌کنیم.
     */
    @JvmStatic
    fun getCookieStats(): String {
        val obj = JSONObject()
        obj.put("cookies_managed", totalCookiesManaged.get())
        obj.put("cookies_rotated", totalCookiesRotated.get())
        obj.put("cookies_expired", totalCookiesExpired.get())
        obj.put("sessions_tracked", totalSessionsTracked.get())
        obj.put("warmup_injections", totalWarmupInjections.get())
        obj.put("visited_domains", synchronized(visitedDomains) { visitedDomains.size })
        return obj.toString()
    }

    // ═══════════════════════════════════════════════════════════════
    // Private Methods
    // ═══════════════════════════════════════════════════════════════

    /**
     * اعمال چرخش کوکی‌ها بر اساس پیکربندی.
     *
     * استراتژی:
     * - اگر domain قبلاً بازدید شده (visitCount > 1): نگهداشتن کوکی‌ها (بازگشت کاربر)
     * - اگر domain جدید است: کوکی‌های قدیمی domainهای دیگر را expire کن
     * - با احتمال مشخص: تعدادی کوکی تصادفی حذف کن (شبیه کاربری که گهگاهی پاک می‌کند)
     */
    private fun applyCookieRotation(
        cm: CookieManager,
        targetDomain: String,
        config: CookieConfig,
        visitCount: Int
    ) {
        if (!config.rotationEnabled) return

        // احتمال چرخش کوکی‌ها
        if (rng.nextDouble() > config.rotationProbability) return

        synchronized(visitedDomains) {
            if (visitedDomains.size > config.maxDomainsBeforeRotation) {
                // کوکی‌های قدیمی‌ترین domainها را expire کن
                val domainsToExpire = visitedDomains.take(
                    (visitedDomains.size - config.maxDomainsBeforeRotation)
                        .coerceAtLeast(1)
                )
                for (domain in domainsToExpire) {
                    expireDomainCookies(cm, domain, config)
                    visitedDomains.remove(domain)
                    totalCookiesExpired.incrementAndGet()
                }
                Log.d(TAG, "Cookie rotation: expired ${domainsToExpire.size} old domains, " +
                      "keeping ${visitedDomains.size} active")
            }
        }

        totalCookiesRotated.incrementAndGet()
    }

    /**
     * تزریق کوکی‌های warmup (شبیه‌سازی بازدیدهای قبلی).
     *
     * کاربران واقعی کوکی‌های زیادی از سایت‌های مختلف دارند.
     * تزریق کوکی‌های رایج باعث می‌شود fingerprint مرورگر طبیعی‌تر به نظر برسد.
     */
    private fun injectWarmupCookies(
        cm: CookieManager,
        targetDomain: String,
        config: CookieConfig
    ) {
        if (!config.warmupCookiesEnabled) return

        val warmupSites = config.warmupCookieSites
        if (warmupSites.isEmpty()) return

        // فقط یک سایت warmup تصادفی انتخاب کن
        val warmupSite = warmupSites[rng.nextInt(warmupSites.size)]
        if (extractDomain(warmupSite) == targetDomain) return // هم‌domain نیست

        // تزریق کوکی‌های رایج برای آن سایت
        for (cookieDef in config.commonCookies) {
            try {
                val cookieString = "${cookieDef.name}=${cookieDef.value}; Domain=${extractDomain(warmupSite)}; Path=/"
                cm.setCookie(warmupSite, cookieString)
                totalCookiesManaged.incrementAndGet()
            } catch (e: Exception) {
                // ignore
            }
        }

        totalWarmupInjections.incrementAndGet()
        Log.d(TAG, "Injected warmup cookies from $warmupSite for session")
    }

    /**
     * پاکسازی session cookies منقضی‌شده از domain قبلی.
     * این کار را فقط زمانی انجام می‌دهد که domain تغییر کرده باشد.
     */
    private fun cleanupStaleSessionCookies(
        cm: CookieManager,
        currentDomain: String,
        config: CookieConfig
    ) {
        if (!config.staleSessionCleanup) return

        synchronized(visitedDomains) {
            val staleDomains = visitedDomains.filter { it != currentDomain }
            for (domain in staleDomains.shuffled().take(config.maxStaleCleanupPerSession)) {
                // کوکی‌های session (بدون تاریخ) را حذف کن
                // این شبیه behavior مرورگر است که session cookies را بعد از بستن tab نگه نمی‌دارد
                removeSessionCookies(cm, domain)
                Log.d(TAG, "Cleaned stale session cookies for domain: $domain")
            }
        }
    }

    /**
     * حذف کوکی‌های session (بدون expires) برای یک domain.
     * کوکی‌های persistent (با expires) را نگه می‌دارد.
     */
    private fun removeSessionCookies(cm: CookieManager, domain: String) {
        // در اندروید نمی‌توان session cookies را از persistent تشخیص داد
        // بهترین کار: حذف کوکی‌های domain (با احتمال)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                // کوکی‌ها را با expires قدیمی overwrite کن
                val domainUrl = "https://$domain/"
                val existingCookie = cm.getCookie(domainUrl) ?: return
                val cookiePairs = existingCookie.split(";").map { it.trim() }
                for (pair in cookiePairs) {
                    val name = pair.split("=").firstOrNull() ?: continue
                    // Overwrite with expired date
                    val expiredCookie = "$name=; Domain=$domain; Path=/; Max-Age=0"
                    cm.setCookie(domainUrl, expiredCookie)
                    totalCookiesExpired.incrementAndGet()
                }
                flushCookies(cm)
            } catch (e: Exception) {
                Log.w(TAG, "removeSessionCookies error: ${e.message}")
            }
        }
    }

    /**
     * منقضی کردن تمام کوکی‌های یک domain.
     */
    private fun expireDomainCookies(cm: CookieManager, domain: String, config: CookieConfig) {
        try {
            val domainUrl = "https://$domain/"
            val existingCookie = cm.getCookie(domainUrl) ?: return
            val cookiePairs = existingCookie.split(";").map { it.trim() }
            var expired = 0
            for (pair in cookiePairs) {
                val name = pair.split("=").firstOrNull() ?: continue
                if (rng.nextDouble() < config.expireProbability) {
                    val expiredCookie = "$name=; Domain=$domain; Path=/; Max-Age=0"
                    cm.setCookie(domainUrl, expiredCookie)
                    expired++
                }
            }
            if (expired > 0) {
                flushCookies(cm)
                Log.d(TAG, "Expired $expired cookies for domain: $domain")
            }
        } catch (e: Exception) {
            Log.w(TAG, "expireDomainCookies error: ${e.message}")
        }
    }

    /**
     * Flush کوکی‌ها به دیسک (Android L+).
     */
    private fun flushCookies(cm: CookieManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                cm.flush()
            } catch (e: Exception) {
                // ignore flush errors
            }
        }
    }

    /**
     * Logging وضعیت کوکی‌ها برای یک domain.
     */
    private fun logCookieState(domain: String) {
        try {
            val cm = CookieManager.getInstance()
            val cookieString = cm.getCookie("https://$domain/") ?: ""
            val cookieCount = cookieString.split(";").count { it.isNotBlank() }
            Log.d(TAG, "Cookie state for $domain: $cookieCount cookies, " +
                  "visited=${domainVisitCount[domain] ?: 0}x, " +
                  "total domains tracked=${synchronized(visitedDomains) { visitedDomains.size }}")
        } catch (e: Exception) {
            // ignore
        }
    }

    /**
     * استخراج domain از URL.
     */
    private fun extractDomain(url: String): String {
        if (url.isBlank()) return ""
        return try {
            val uri = URI(url)
            val host = uri.host ?: return ""
            // حذف www. پیشوند
            host.removePrefix("www.").lowercase()
        } catch (e: Exception) {
            url.lowercase()
        }
    }
}
