package com.coinceeper.adl

import org.json.JSONObject

/**
 * AdNetwork — شبکه‌های تبلیغاتی پشتیبانی‌شده با رفتار اختصاصی.
 *
 * هر شبکه الگوی منحصربه‌فردی برای نمایش و تعامل با تبلیغات دارد:
 * - Coinzilla: بنرهای display + مدال → نیاز به اسکرول به موقعیت بنر و viewability
 * - Monetag: پاپ‌آندر + نوتیفیکیشن → نیاز به trigger popunder و قبول نوتیفیکیشن
 * - Hypelab: تبلیغات نیتیو → نیاز به مرور طبیعی و engage با محتوا
 */
enum class AdNetwork(val key: String) {
    COINZILLA("coinzilla"),
    MONETAG("monetag"),
    HYPELAB("hypelab"),
    GENERIC("generic");

    companion object {
        fun fromKey(key: String): AdNetwork {
            return entries.find { it.key == key.lowercase() } ?: GENERIC
        }
    }
}

/**
 * CookieConfig — پیکربندی مدیریت کوکی برای هر شبکه تبلیغاتی.
 *
 * این کلاس مشخص می‌کند که CookieRotator برای هر شبکه چگونه باید
 * کوکی‌ها را مدیریت کند تا رفتار مرورگر واقعی شبیه‌سازی شود.
 *
 * == اصول ==
 * - مرورگر واقعی هرگز کوکی‌ها را بین tabها پاک نمی‌کند
 * - مرورگر واقعی کوکی‌های persistent را برای همیشه نگه می‌دارد
 * - مرورگر واقعی فقط کوکی‌های expired را پاک می‌کند
 * - کاربران واقعی گهگاهی کوکی‌ها را پاک می‌کنند (rotation)
 * - هر domain کوکی‌های خودش را دارد
 */
data class CookieConfig(
    // ── فعال/غیرفعال ─────────────────────────────────────────
    val enabled: Boolean,                    // آیا CookieRotator برای این شبکه فعال است

    // ── Rotation ────────────────────────────────────────────
    val rotationEnabled: Boolean,             // آیا چرخش کوکی فعال است
    val rotationProbability: Double,          // احتمال چرخش در هر session (0.0-1.0)
    val maxDomainsBeforeRotation: Int,        // حداکثر domain قبل از چرخش کوکی‌ها
    val expireProbability: Double,            // احتمال انقضای هر کوکی در زمان rotation (0.0-1.0)

    // ── Cleanup ─────────────────────────────────────────────
    val cleanupOnReturn: Boolean,             // آیا در زمان بازگشت WebView به Pool پاکسازی شود
    val staleSessionCleanup: Boolean,         // آیا session cookies منقضی‌شده پاک شوند
    val maxStaleCleanupPerSession: Int,       // حداکثر domain برای پاکسازی در هر session

    // ── Warmup Cookies ──────────────────────────────────────
    val warmupCookiesEnabled: Boolean,        // آیا تزریق کوکی‌های warmup فعال است
    val warmupCookieSites: List<String>,      // سایت‌هایی که کوکی‌های warmup از آنها تزریق شود
    val commonCookies: List<CookieDef>,       // تعریف کوکی‌های رایج برای تزریق
)

/**
 * CookieDef — تعریف یک کوکی برای تزریق.
 */
data class CookieDef(
    val name: String,
    val value: String,
)

/**
 * CookieConfigPresets — پروفایل‌های از پیش تعریف‌شده مدیریت کوکی.
 *
 * هر پروفایل بر اساس نوع شبکه تبلیغاتی و نیازهای آن تنظیم شده است.
 */
object CookieConfigPresets {
    /**
     * Coinzilla: شبکه‌ای که به دیتای session طولانی نیاز دارد.
     * کوکی‌ها را برای مدت طولانی نگه می‌دارد، rotation کم.
     */
    val COINZILLA = CookieConfig(
        enabled = true,
        rotationEnabled = true,
        rotationProbability = 0.08,  // 8% chance rotation
        maxDomainsBeforeRotation = 15,
        expireProbability = 0.05,    // فقط 5% کوکی‌ها expire شوند
        cleanupOnReturn = true,
        staleSessionCleanup = true,
        maxStaleCleanupPerSession = 2,
        warmupCookiesEnabled = true,
        warmupCookieSites = listOf(
            "https://www.google.com",
            "https://www.youtube.com",
            "https://www.reddit.com",
        ),
        commonCookies = listOf(
            CookieDef("_ga", "GA1.2." + (1000000000L + (Math.random() * 8999999999L).toLong()).toString()),
            CookieDef("_gid", "GA1.2." + (1000000000L + (Math.random() * 8999999999L).toLong()).toString()),
            CookieDef("_fbp", "fb.1." + System.currentTimeMillis().toString() + "." + (1000000000L + (Math.random() * 8999999999L).toLong()).toString()),
        ),
    )

    /**
     * Monetag: شبکه حساس به کوکی. نیاز به کوکی‌های تازه دارد.
     * rotation بیشتر برای شبیه‌سازی کاربران جدید.
     */
    val MONETAG = CookieConfig(
        enabled = true,
        rotationEnabled = true,
        rotationProbability = 0.15,  // 15% chance rotation
        maxDomainsBeforeRotation = 10,
        expireProbability = 0.10,    // 10% cookies expire
        cleanupOnReturn = true,
        staleSessionCleanup = true,
        maxStaleCleanupPerSession = 3,
        warmupCookiesEnabled = true,
        warmupCookieSites = listOf(
            "https://www.google.com",
            "https://www.bing.com",
            "https://www.yahoo.com",
        ),
        commonCookies = listOf(
            CookieDef("_ga", "GA1.2." + (1000000000L + (Math.random() * 8999999999L).toLong()).toString()),
            CookieDef("_gid", "GA1.2." + (1000000000L + (Math.random() * 8999999999L).toLong()).toString()),
            CookieDef("_gat", "_gat_gtag_" + (1000000L + (Math.random() * 8999999L).toLong()).toString()),
        ),
    )

    /**
     * Hypelab: نیاز به session عمیق و کوکی‌های پایدار.
     * rotation کم، warmup زیاد.
     */
    val HYPELAB = CookieConfig(
        enabled = true,
        rotationEnabled = true,
        rotationProbability = 0.05,  // فقط 5% chance
        maxDomainsBeforeRotation = 20,
        expireProbability = 0.03,    // expire خیلی کم
        cleanupOnReturn = true,
        staleSessionCleanup = true,
        maxStaleCleanupPerSession = 1,
        warmupCookiesEnabled = true,
        warmupCookieSites = listOf(
            "https://www.google.com",
            "https://www.youtube.com",
            "https://www.wikipedia.org",
            "https://www.github.com",
            "https://stackoverflow.com",
        ),
        commonCookies = listOf(
            CookieDef("_ga", "GA1.2." + (1000000000L + (Math.random() * 8999999999L).toLong()).toString()),
            CookieDef("_gid", "GA1.2." + (1000000000L + (Math.random() * 8999999999L).toLong()).toString()),
            CookieDef("_hjSessionUser_", (1000000 + (Math.random() * 8999999).toInt()).toString()),
        ),
    )

    /**
     * GENERIC: رفتار عمومی و حداقلی.
     * کوکی‌ها را نگه می‌دارد اما rotation و warmup حداقلی.
     */
    val GENERIC = CookieConfig(
        enabled = true,
        rotationEnabled = false,     // بدون rotation
        rotationProbability = 0.0,
        maxDomainsBeforeRotation = 5,
        expireProbability = 0.0,
        cleanupOnReturn = false,     // بدون cleanup
        staleSessionCleanup = false,
        maxStaleCleanupPerSession = 0,
        warmupCookiesEnabled = true,
        warmupCookieSites = listOf(
            "https://www.google.com",
        ),
        commonCookies = listOf(
            CookieDef("_ga", "GA1.2." + (1000000000L + (Math.random() * 8999999999L).toLong()).toString()),
        ),
    )
}

/**
 * AdNetworkBehavior — پیکربندی رفتار اختصاصی برای هر شبکه تبلیغاتی.
 *
 * این کلاس مشخص می‌کند که WebView برای هر شبکه چگونه باید رفتار کند:
 * - dwell time (زمان ماندن در صفحه، شبیه خواندن محتوا)
 * - نوع اسکرول (خطی، نوسانی، تصادفی)
 * - type تبلیغاتی (بنر، پاپ‌آندر، نیتیو)
 * - نیاز به کلیک روی عناصر خاص
 * - viewability threshold (چقدر از بنر باید دیده شود)
 * - تنظیمات popunder
 * - عمق جلسه (چند صفحه پشت سر هم)
 * - مدیریت کوکی (CookieRotator)
 */
data class AdNetworkBehavior(
    // ── شناسه ──────────────────────────────────────────────
    val network: AdNetwork,

    // ── Dwell Time (زمان ماندن در صفحه) ─────────────────────
    val dwellMinMs: Int,
    val dwellMaxMs: Int,

    // ── Scroll ──────────────────────────────────────────────
    val scrollType: ScrollType,
    val scrollSections: Int,         // تعداد بخش‌های scroll
    val scrollReverseProbability: Double, // احتمال اسکرول معکوس (0.0-1.0)
    val scrollPauseMinMs: Int,       // مکث بین هر اسکرول
    val scrollPauseMaxMs: Int,

    // ── Touch Events ────────────────────────────────────────
    val simulateTouchEvents: Boolean, // آیا touch events شبیه‌سازی شود
    val touchProbability: Double,     // احتمال هر touch interaction

    // ── Ad Interaction ──────────────────────────────────────
    val adType: AdType,
    val adElementSelectors: List<String>, // CSS selectors برای عناصر تبلیغاتی
    val clickAdProbability: Double,       // احتمال کلیک روی تبلیغ (0.0-1.0)

    // ── Viewability (Coinzilla) ──────────────────────────────
    val viewabilityThreshold: Double,  // درصد دید بنر (0.5 = 50%)
    val viewabilityDurationMs: Int,    // مدت زمان لازم برای viewability

    // ── Popunder (Monetag) ──────────────────────────────────
    val triggerPopunder: Boolean,      // آیا popunder trigger شود
    val popunderDelayMs: Int,          // تأخیر قبل از trigger popunder
    val popunderProbability: Double,   // احتمال popunder (0.0-1.0)
    val pushNotificationOptIn: Boolean, // آیا قبول نوتیفیکیشن push

    // ── Session (Hypelab) ──────────────────────────────────
    val sessionDepth: Int,             // تعداد صفحات در یک جلسه
    val browseNatural: Boolean,        // مرور طبیعی محتوا
    val internalLinkClickProbability: Double, // احتمال کلیک روی لینک داخلی

    // ── Mouse/Scroll Simulation ────────────────────────────
    val mouseMoveProbability: Double,  // احتمال حرکت ماوس
    val hoverProbability: Double,      // احتمال hover روی عناصر

    // ── Cookie Management ───────────────────────────────────
    val cookieConfig: CookieConfig,    // پیکربندی مدیریت کوکی
)

/**
 * ScrollType — نوع الگوی اسکرول شبیه‌سازی‌شده.
 */
enum class ScrollType(val key: String) {
    LINEAR("linear"),              // اسکرول خطی ساده (قدیمی)
    OSCILLATING("oscillating"),    // اسکرول با نوسان (بالا و پایین)
    RANDOM_PAUSE("random_pause"),  // اسکرول با توقف‌های تصادفی
    HUMAN_LIKE("human_like"),      // اسکرول کاملاً انسانی (ترکیبی)
    NONE("none");                  // بدون اسکرول

    companion object {
        fun fromKey(key: String): ScrollType {
            return entries.find { it.key == key.lowercase() } ?: HUMAN_LIKE
        }
    }
}

/**
 * AdType — نوع تبلیغ در شبکه.
 */
enum class AdType(val key: String) {
    BANNER("banner"),              // بنر نمایشی
    MODAL("modal"),                // مدال/پاپ‌آپ
    POPUNDER("popunder"),          // پاپ‌آندر
    NATIVE("native"),              // تبلیغ نیتیو
    REWARDED("rewarded"),          // تشویقی
    PUSH("push"),                  // نوتیفیکیشن push
    BANNER_MODAL("banner_modal"),  // ترکیب بنر + مدال (Coinzilla)
    NONE("none");                  // بدون تبلیغ

    companion object {
        fun fromKey(key: String): AdType {
            return entries.find { it.key == key.lowercase() } ?: NONE
        }
    }
}

/**
 * AdNetworkConfigProvider — ارائه‌دهنده تنظیمات اختصاصی هر شبکه.
 */
object AdNetworkConfigProvider {

    /**
     * پروفایل‌های از پیش تعریف‌شده برای هر شبکه تبلیغاتی.
     * این مقادیر بر اساس تحقیق و تحلیل رفتار واقعی هر شبکه تنظیم شده‌اند.
     */
    private val behaviors: Map<AdNetwork, AdNetworkBehavior> = mapOf(
        // ═════════════════════════════════════════════════════════
        // Coinzilla: بنر + مدال
        // نیاز به اسکرول به موقعیت بنر، viewability 50% به مدت 1 ثانیه،
        // و کلیک روی عناصر خاص (CSS classهای تبلیغاتی)
        //
        // == Dwell Time ==
        // Coinzilla: dwell < 30s = Bot Flag (machine learning)
        // کاربر واقعی: 45-180 ثانیه
        // ═════════════════════════════════════════════════════════
        AdNetwork.COINZILLA to AdNetworkBehavior(
            network = AdNetwork.COINZILLA,
            dwellMinMs = 45_000,
            dwellMaxMs = 180_000,
            scrollType = ScrollType.OSCILLATING,
            scrollSections = 6,
            scrollReverseProbability = 0.35,
            scrollPauseMinMs = 800,
            scrollPauseMaxMs = 2500,
            simulateTouchEvents = true,
            touchProbability = 0.15,
            adType = AdType.BANNER_MODAL,
            adElementSelectors = listOf(
                ".ad-unit",
                ".banner",
                ".ad-container",
                "div[id*='coinzilla']",
                "div[class*='ad']",
                "ins.adsbygoogle",
                "iframe[src*='coinzilla']",
                "div[data-ad-unit]"
            ),
            clickAdProbability = 0.08,
            viewabilityThreshold = 0.50,
            viewabilityDurationMs = 1000,
            triggerPopunder = false,
            popunderDelayMs = 0,
            popunderProbability = 0.0,
            pushNotificationOptIn = false,
            sessionDepth = 1,
            browseNatural = false,
            internalLinkClickProbability = 0.15,
            mouseMoveProbability = 0.80,
            hoverProbability = 0.60,
            cookieConfig = CookieConfigPresets.COINZILLA,
        ),

        // ═════════════════════════════════════════════════════════
        // Monetag: پاپ‌آندر + نوتیفیکیشن
        // نیاز به trigger popunder از طریق navigation events
        // و قبول push notification
        //
        // == Dwell Time ==
        // Monetag: dwell < 20s + click = invalid
        // کاربر واقعی: 35-150 ثانیه
        // ═════════════════════════════════════════════════════════
        AdNetwork.MONETAG to AdNetworkBehavior(
            network = AdNetwork.MONETAG,
            dwellMinMs = 35_000,
            dwellMaxMs = 150_000,
            scrollType = ScrollType.RANDOM_PAUSE,
            scrollSections = 4,
            scrollReverseProbability = 0.20,
            scrollPauseMinMs = 1500,
            scrollPauseMaxMs = 4000,
            simulateTouchEvents = true,
            // [حیاتی] Monetag به touch events نیاز دارد — افزایش به ۲۰٪
            touchProbability = 0.20,
            adType = AdType.POPUNDER,
            adElementSelectors = listOf(
                "div[class*='pop']",
                "a[href*='monetag']",
                "iframe[src*='monetag']",
                "div[id*='pop']",
                "ins[data-wid]",
                // selectors اضافی برای تشخیص بهتر Monetag
                "div[class*='ad']",
                "a[target*='_blank']",
                "div[id*='ad']",
                "iframe[src*='pop']",
                "div[data-ad]"
            ),
            // [حیاتی] افزایش احتمال کلیک برای Monetag
            clickAdProbability = 0.08,
            viewabilityThreshold = 0.0,
            viewabilityDurationMs = 0,
            triggerPopunder = true,
            popunderDelayMs = 30000,
            popunderProbability = 0.45,
            pushNotificationOptIn = true,
            sessionDepth = 3,
            browseNatural = false,
            internalLinkClickProbability = 0.15,
            mouseMoveProbability = 0.75,
            hoverProbability = 0.55,
            cookieConfig = CookieConfigPresets.MONETAG,
        ),

        // ═════════════════════════════════════════════════════════
        // Hypelab: تبلیغات نیتیو
        // نیاز به مرور طبیعی، engage با محتوا، و session depth بالا
        //
        // == Dwell Time ==
        // Hypelab: native ads نیاز به dwell طولانی دارند
        // کاربر واقعی: 60-300 ثانیه (مرور عمیق محتوا)
        // ═════════════════════════════════════════════════════════
        AdNetwork.HYPELAB to AdNetworkBehavior(
            network = AdNetwork.HYPELAB,
            dwellMinMs = 60_000,
            dwellMaxMs = 300_000,
            scrollType = ScrollType.HUMAN_LIKE,
            scrollSections = 8,
            scrollReverseProbability = 0.45,
            scrollPauseMinMs = 1000,
            scrollPauseMaxMs = 3000,
            simulateTouchEvents = true,
            // [حیاتی] Hypelab native ads نیاز به engagement بالایی دارند
            touchProbability = 0.35,
            adType = AdType.NATIVE,
            adElementSelectors = listOf(
                ".native-ad",
                ".sponsored",
                "div[class*='native']",
                "div[class*='sponsor']",
                "a[href*='hypelab']",
                "iframe[src*='hypelab']",
                "div[data-native-ad]",
                // selectors اضافی برای native ads
                ".promoted",
                ".recommended",
                "div[class*='promo']",
                "a[class*='sponsor']",
                "div[data-sponsored]"
            ),
            clickAdProbability = 0.10,
            viewabilityThreshold = 0.0,
            viewabilityDurationMs = 0,
            triggerPopunder = false,
            popunderDelayMs = 0,
            popunderProbability = 0.0,
            pushNotificationOptIn = false,
            sessionDepth = 5,
            browseNatural = true,
            internalLinkClickProbability = 0.35,
            mouseMoveProbability = 0.90,
            hoverProbability = 0.75,
            cookieConfig = CookieConfigPresets.HYPELAB,
        ),

        // ═════════════════════════════════════════════════════════
        // GENERIC: رفتار عمومی — fallback برای شبکه‌های ناشناس
        //
        // == Dwell Time ==
        // Fallback: حداقل 30 ثانیه (امن‌ترین مقدار برای هر شبکه)
        //
        // == Scroll ==
        // از ScrollType.RANDOM_PAUSE استفاده می‌کند (نه LINEAR)
        // زیرا اسکرول خطی = حتمی bot detection
        // ═════════════════════════════════════════════════════════
        AdNetwork.GENERIC to AdNetworkBehavior(
            network = AdNetwork.GENERIC,
            dwellMinMs = 30_000,
            dwellMaxMs = 120_000,
            scrollType = ScrollType.RANDOM_PAUSE,
            scrollSections = 4,
            scrollReverseProbability = 0.25,
            scrollPauseMinMs = 800,
            scrollPauseMaxMs = 2500,
            simulateTouchEvents = false,
            touchProbability = 0.0,
            adType = AdType.NONE,
            adElementSelectors = emptyList(),
            clickAdProbability = 0.0,
            viewabilityThreshold = 0.0,
            viewabilityDurationMs = 0,
            triggerPopunder = false,
            popunderDelayMs = 0,
            popunderProbability = 0.0,
            pushNotificationOptIn = false,
            sessionDepth = 1,
            browseNatural = false,
            internalLinkClickProbability = 0.05,
            mouseMoveProbability = 0.30,
            hoverProbability = 0.20,
            cookieConfig = CookieConfigPresets.GENERIC,
        ),
    )

    /**
     * دریافت پروفایل رفتار اختصاصی یک شبکه تبلیغاتی.
     */
    fun getBehavior(network: AdNetwork): AdNetworkBehavior {
        return behaviors[network] ?: behaviors[AdNetwork.GENERIC]!!
    }

    /**
     * دریافت پروفایل از روی رشته JSON (که از Go agent می‌آید).
     * اگر فیلد ad_network خالی یا نامعتبر باشد، GENERIC برگردانده می‌شود.
     */
    fun fromConfig(config: JSONObject): AdNetworkBehavior {
        val networkKey = config.optString("ad_network", "")
        val network = AdNetwork.fromKey(networkKey)
        return getBehavior(network).withOverrides(config)
    }

    /**
     * اعمال overrideهای پویا از JSON روی پروفایل پیش‌فرض.
     * این اجازه می‌دهد که Go agent برخی تنظیمات را override کند.
     */
    fun AdNetworkBehavior.withOverrides(config: JSONObject): AdNetworkBehavior {
        return this.copy(
            dwellMinMs = config.optInt("dwell_min_ms", this.dwellMinMs),
            dwellMaxMs = config.optInt("dwell_max_ms", this.dwellMaxMs),
            clickAdProbability = config.optDouble("click_ad_prob", this.clickAdProbability),
            scrollSections = config.optInt("scroll_sections", this.scrollSections),
            scrollReverseProbability = config.optDouble("scroll_reverse_prob", this.scrollReverseProbability),
            triggerPopunder = config.optBoolean("trigger_popunder", this.triggerPopunder),
            popunderDelayMs = config.optInt("popunder_delay_ms", this.popunderDelayMs),
            popunderProbability = config.optDouble("popunder_prob", this.popunderProbability),
            pushNotificationOptIn = config.optBoolean("push_optin", this.pushNotificationOptIn),
            sessionDepth = config.optInt("session_depth", this.sessionDepth),
            browseNatural = config.optBoolean("browse_natural", this.browseNatural),
            internalLinkClickProbability = config.optDouble(
                "internal_link_click_prob", this.internalLinkClickProbability
            ),
        )
    }
}
