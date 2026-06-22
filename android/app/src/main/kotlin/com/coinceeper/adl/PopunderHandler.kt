package com.coinceeper.adl

import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.JavascriptInterface
import android.webkit.WebView
import java.util.concurrent.atomic.AtomicBoolean

/**
 * PopunderHandler — مدیریت پاپ‌آندر Monetag در WebView.
 *
 * مشکل اصلی:
 *   Monetag از window.open() برای پاپ‌آندر استفاده می‌کند.
 *   WebView اندروید به طور پیش‌فرض window.open را مسدود می‌کند یا
 *   آن را در یک پنجره جداگانه باز می‌کند که خارج از کنترل agent است.
 *
 * راه‌حل:
 *   1. ثبت WebChromeClient سفارشی که onCreateWindow را intercept کند
 *   2. ثبت JavaScriptInterface که از سمت JS فراخوانی شود
 *   3. شبیه‌سازی popunder از طریق navigation در WebView اصلی
 *   4. مدیریت back-stack برای بازگشت به صفحه اصلی بعد از پاپ‌آندر
 *
 * معماری:
 *   PopunderHandler به عنوان JavaScriptInterface در WebView ثبت می‌شود.
 *   JavaScript Monetag متدهای آن را برای trigger popunder فراخوانی می‌کند.
 *   همچنین از WebViewClient.shouldOverrideUrlLoading برای intercept
 *   کردن navigation‌های popunder استفاده می‌کند.
 */
class PopunderHandler {
    private val TAG = "PopunderHandler"
    private val mainHandler = Handler(Looper.getMainLooper())

    // وضعیت
    private var isPopunderActive = AtomicBoolean(false)
    private var originalUrl: String = ""
    private var popunderUrl: String = ""

    /** Bridge instance for JS communication. */
    private val _bridge = PopunderBridge(this)

    /** دسترسی به bridge برای خواندن وضعیت scroll از نیتیو. */
    fun getBridge(): PopunderBridge = _bridge

    /** بازنشانی وضعیت scroll bridge (قبل از هر injection جدید). */
    fun resetScrollState() {
        _bridge.resetScrollState()
    }

    /**
     * WebViewClient callback سفارشی برای مدیریت shouldOverrideUrlLoading.
     * این تابع توسط TspWebClickHost در WebViewClient فراخوانی می‌شود.
     *
     * @return true اگر URL مصرف شد (نباید load شود)، false اگر WebView باید load کند
     */
    fun shouldOverrideUrlLoading(url: String, behavior: AdNetworkBehavior): Boolean {
        if (!behavior.triggerPopunder) return false

        // تشخیص popunder Monetag از روی الگوهای URL
        if (isPopunderUrl(url)) {
            Log.d(TAG, "Popunder detected: $url")
            popunderUrl = url
            isPopunderActive.set(true)
            // Popunder را در پس‌زمینه load کن (بدون نمایش به کاربر)
            return false // اجازه load بده
        }
        return false
    }

    /**
     * تشخیص اینکه آیا URL یک popunder Monetag است.
     */
    private fun isPopunderUrl(url: String): Boolean {
        val lower = url.lowercase()
        return lower.contains("monetag") ||
               lower.contains("popunder") ||
               lower.contains("pop.js") ||
               lower.contains("//p.") ||
               lower.contains("popad") ||
               lower.contains("clickunder") ||
               lower.contains("adserver") ||
               lower.matches(Regex(".*pop(?:up|under|ad)\\d*\\.\\w+.*", RegexOption.IGNORE_CASE))
    }

    /**
     * بررسی popunderهای معوق در صفحه بعد از بارگذاری کامل.
     * Monetag اغلب popunderها را با تأخیر ۵-۱۵ ثانیه trigger می‌کند.
     */
    fun schedulePopunderCheck(webView: WebView, behavior: AdNetworkBehavior, dwellMs: Long) {
        if (!behavior.triggerPopunder || behavior.popunderProbability <= 0.0) return

        // شبیه‌سازی popunder با JavaScript
        val delayMs = behavior.popunderDelayMs
        if (delayMs > 0 && delayMs < dwellMs) {
            mainHandler.postDelayed({
                try {
                    val popunderJS = HumanBehaviorSimulator.buildPopunderJS(0)
                    webView.evaluateJavascript(popunderJS, null)
                    Log.d(TAG, "Popunder triggered after ${delayMs}ms delay")
                } catch (e: Throwable) {
                    Log.w(TAG, "Popunder trigger failed: ${e.message}")
                }
            }, delayMs.toLong())
        }
    }

    /**
     * قبول push notification (Monetag).
     */
    fun optInPushNotifications(webView: WebView, behavior: AdNetworkBehavior) {
        if (!behavior.pushNotificationOptIn) return

        mainHandler.postDelayed({
            try {
                val pushJS = HumanBehaviorSimulator.buildPushNotificationJS()
                webView.evaluateJavascript(pushJS, null)
                Log.d(TAG, "Push notification opt-in triggered")
                } catch (e: Throwable) {
                    Log.w(TAG, "Push notification opt-in failed: ${e.message}")
                }
        }, 5000) // 5 ثانیه بعد از لود صفحه (وقتی صفحه کاملاً آماده شد)
    }

    // ═══════════════════════════════════════════════════════════════
    // JavaScriptInterface برای ارتباط دوطرفه با JS Monetag
    // ═══════════════════════════════════════════════════════════════

    /**
     * JavaScriptInterface که در WebView ثبت می‌شود تا JS Monetag
     * بتواند مستقیماً popunder را از سمت نیتیو trigger کند.
     *
     * همچنین شامل callbackهای scroll progress برای هماهنگی
     * بین scroll JS و dwell time (ضد bot detection).
     */
    class PopunderBridge(private val handler: PopunderHandler) {
        @Volatile
        private var _scrollProgress: Int = 0      // 0-100
        @Volatile
        private var _scrollComplete: Boolean = false

        @JavascriptInterface
        fun triggerPopunder(url: String) {
            android.util.Log.d("PopunderBridge", "triggerPopunder called: $url")
            handler.popunderUrl = url
            handler.isPopunderActive.set(true)
        }

        @JavascriptInterface
        fun isPopunderSupported(): Boolean {
            return true
        }

        /**
         * گزارش پیشرفت اسکرول از JS به نیتیو.
         * Scroll Patterns در HumanBehaviorSimulator این متد را
         * در هر مرحله اسکرول فراخوانی می‌کنند.
         *
         * @param progress درصد پیشرفت اسکرول (0-100)
         */
        @JavascriptInterface
        fun onScrollProgress(progress: Int) {
            _scrollProgress = progress.coerceIn(0, 100)
            if (progress >= 100) {
                _scrollComplete = true
            }
            if (progress % 25 == 0) {
                android.util.Log.d("PopunderBridge", "Scroll progress: $progress%")
            }
        }

        /**
         * گزارش اتمام کامل اسکرول.
         */
        @JavascriptInterface
        fun onScrollComplete() {
            _scrollProgress = 100
            _scrollComplete = true
            android.util.Log.d("PopunderBridge", "Scroll complete signal received")
        }

        /** گرفتن آخرین وضعیت پیشرفت اسکرول. */
        fun getScrollProgress(): Int = _scrollProgress

        /** آیا اسکرول کامل شده است؟ */
        fun isScrollComplete(): Boolean = _scrollComplete

        /** بازنشانی وضعیت اسکرول برای استفاده مجدد. */
        fun resetScrollState() {
            _scrollProgress = 0
            _scrollComplete = false
        }
    }
}
