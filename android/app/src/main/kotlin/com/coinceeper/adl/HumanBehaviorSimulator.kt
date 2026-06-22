package com.coinceeper.adl

import android.util.Log
import android.webkit.WebView
import java.util.Random

/**
 * HumanBehaviorSimulator v5 — شبیه‌سازی کامل رفتار انسانی با پشتیبانی از Touch/Pointer/Mouse Events.
 *
 * == نسخه ۵ — مهندسی شده برای شبیه‌سازی کامل تعامل لمسی ==
 *
 * این نسخه مشکل عدم شبیه‌سازی touch/mouse events را به صورت کامل حل می‌کند:
 *
 * [۱] **Touch Events کامل:**
 *     - touchstart → touchmove (اختیاری) → touchend
 *     - Touch object واقعی با تمام پارامترهای فیزیکی (radiusX, radiusY, force, rotationAngle)
 *     - Fallback برای WebViewهایی که Touch constructor ندارند
 *
 * [۲] **Pointer Events (استاندارد مدرن):**
 *     - pointerdown → pointermove → pointerup
 *     - pointerType: 'touch' برای موبایل، 'mouse' برای دسکتاپ
 *     - pressure, tiltX, tiltY, twist, isPrimary
 *
 * [۳] **Mouse Events (Fallback برای دسکتاپ):**
 *     - mouseover → mousedown → mousemove → mouseup → mouseout → click
 *     - موقعیت‌های واقعی با elementFromPoint
 *
 * [۴] **Hover Simulation واقعی:**
 *     - mousemove روی مسیر Bézier
 *     - mouseenter / mouseleave
 *     - Hover روی عناصر با CSS :hover واقعی
 *
 * [۵] **Scroll با Touch Events:**
 *     - هر حرکت اسکرول با touchstart → touchmove(×N) → touchend همراه است
 *     - شبیه‌سازی کامل اسکرول لمسی موبایل
 *
 * [۶] **Anti-Detection پیشرفته:**
 *     - مخفی کردن webdriver, plugins, languages, chrome.runtime
 *     - شبیه‌سازی navigator.hardwareConcurrency, deviceMemory, maxTouchPoints
 *     - Patch Function.prototype.toString
 *     - شبیه‌سازی screen orientation و visual viewport
 */
object HumanBehaviorSimulator {
    private const val TAG = "HumanBehavior"
    private val rng = Random()

    /**
     * ساختن اسکریپت کامل شبیه‌سازی رفتار انسانی.
     *
     * @param behavior تنظیمات رفتار اختصاصی شبکه تبلیغاتی
     * @return JavaScript string برای تزریق به WebView
     */
    fun buildHumanBehaviorJS(behavior: AdNetworkBehavior): String {
        val sb = StringBuilder()

        sb.append("(function(){")
        sb.append("var HBS={};")

        // ═══════════════════════════════════════════════════════════
        // ۱. Touch, Pointer & Mouse Events — استاندارد و کامل
        // ═══════════════════════════════════════════════════════════
        sb.append(buildTouchInteractionJS(behavior))

        // ═══════════════════════════════════════════════════════════
        // ۲. Scroll Simulation — چندین الگو با پشتیبانی Touch
        // ═══════════════════════════════════════════════════════════
        sb.append(buildScrollSimulationJS(behavior))

        // ═══════════════════════════════════════════════════════════
        // ۳. Viewability Tracking برای بنرها
        // ═══════════════════════════════════════════════════════════
        if (behavior.viewabilityThreshold > 0) {
            sb.append(buildViewabilityJS(behavior))
        }

        // ═══════════════════════════════════════════════════════════
        // ۴. Hover Simulation — با mousemove واقعی
        // ═══════════════════════════════════════════════════════════
        sb.append(buildHoverSimulationJS(behavior))

        // ═══════════════════════════════════════════════════════════
        // ۵. Ad Click Detection — کلیک با event chain کامل
        // ═══════════════════════════════════════════════════════════
        sb.append(buildAdClickJS(behavior))

        // ═══════════════════════════════════════════════════════════
        // ۶. Internal Link Clicking (برای session depth)
        // ═══════════════════════════════════════════════════════════
        if (behavior.internalLinkClickProbability > 0) {
            sb.append(buildInternalLinkJS(behavior))
        }

        // ═══════════════════════════════════════════════════════════
        // ۷. Anti-Detection — پیشرفته
        // ═══════════════════════════════════════════════════════════
        sb.append(buildAntiDetectionJS())

        sb.append("return HBS;})();")
        return sb.toString()
    }

    // ═══════════════════════════════════════════════════════════════
    // Touch, Pointer & Mouse Events — استاندارد و کامل
    // ═══════════════════════════════════════════════════════════════
    //
    // این ماژول قلب شبیه‌سازی تعامل لمسی است.
    //
    // == معماری Event Chain ==
    //
    // یک tap واقعی روی موبایل این رویدادها را تولید می‌کند:
    //
    //   Modern (Pointer Events API):
    //     pointerdown → pointerup
    //
    //   Mobile (Touch Events API):
    //     touchstart → [touchmove×N] → touchend
    //
    //   Desktop fallback (Mouse Events API):
    //     mousedown → mouseup → click
    //
    // Monetag, Hypelab, Coinzilla همگی به یکی از این chainها نیاز دارند.
    //
    // ═══════════════════════════════════════════════════════════════

    /**
     * شبیه‌سازی کامل تعامل لمسی با تمام event chainهای استاندارد.
     *
     * توابع تولید شده:
     * - HBS.dispatchFullTap(x, y, element?) — tap کامل
     * - HBS.simulateTouch(element) — tap روی یک عنصر با مختصات تصادفی داخل آن
     * - HBS.dispatchTouchScroll(fromY, toY, steps) — اسکرول لمسی با touchmove
     */
    private fun buildTouchInteractionJS(behavior: AdNetworkBehavior): String {
        val touchProb = behavior.touchProbability

        return """
            // ═══════════════════════════════════════════════════════════
            // HBS.dispatchFullTap — Tap کامل با ۳ Event Chain
            // ═══════════════════════════════════════════════════════════
            //
            // پارامترها:
            //   x, y       — مختصات tap (viewport coordinates)
            //   element    — (اختیاری) عنصر هدف. اگر null، از elementFromPoint استفاده می‌کند
            //   callback   — (اختیاری) callback بعد از اتمام کامل tap
            //
            // Event Chain اجرا شده:
            //   1. pointerdown (PointerEvent)
            //   2. touchstart (TouchEvent با Touch object واقعی)
            //   3. [تأخیر ۸۰-۱۸۰ms — شبیه زمان واکنش انسانی]
            //   4. pointerup (PointerEvent)
            //   5. touchend (TouchEvent)
            //   6. mousedown (MouseEvent — fallback دسکتاپ)
            //   7. [تأخیر ۴۰-۱۰۰ms]
            //   8. mouseup (MouseEvent)
            //   9. click (MouseEvent)
            //  10. callback()
            // ═══════════════════════════════════════════════════════════

            HBS.dispatchFullTap = function(x, y, element, callback) {
                try {
                    // پیدا کردن عنصر هدف
                    if (!element || element === document) {
                        element = document.elementFromPoint(x, y);
                    }
                    if (!element) element = document.body;

                    var target = element;
                    var now = Date.now();
                    var touchId = now % 2147483647;
                    var force_val = 0.3 + Math.random() * 0.5;

                    // ساخن Touch object با fallback برای WebViewهای قدیمی
                    var touchObj;
                    try {
                        touchObj = new Touch({
                            identifier: touchId,
                            target: target,
                            clientX: x,
                            clientY: y,
                            pageX: x + window.scrollX,
                            pageY: y + window.scrollY,
                            screenX: x + (window.screenX || 0),
                            screenY: y + (window.screenY || 0),
                            radiusX: 2.5,
                            radiusY: 2.5,
                            rotationAngle: 0,
                            force: force_val
                        });
                    } catch(e) {
                        // Fallback: Touch constructor پشتیبانی نمی‌شود
                        touchObj = {
                            identifier: touchId,
                            target: target,
                            clientX: x,
                            clientY: y,
                            pageX: x + window.scrollX,
                            pageY: y + window.scrollY,
                            screenX: x + (window.screenX || 0),
                            screenY: y + (window.screenY || 0),
                            radiusX: 2.5,
                            radiusY: 2.5,
                            rotationAngle: 0,
                            force: force_val
                        };
                    }

                    // ── Step 1: pointerdown (Pointer Events API) ──
                    try {
                        var pointerDown = new PointerEvent('pointerdown', {
                            pointerId: touchId,
                            pointerType: 'touch',
                            clientX: x,
                            clientY: y,
                            screenX: x + (window.screenX || 0),
                            screenY: y + (window.screenY || 0),
                            bubbles: true,
                            cancelable: true,
                            composed: true,
                            isPrimary: true,
                            width: 5,
                            height: 5,
                            pressure: force_val,
                            tangentialPressure: 0,
                            tiltX: 0,
                            tiltY: 0,
                            twist: 0
                        });
                        target.dispatchEvent(pointerDown);
                    } catch(e) {}

                    // ── Step 2: touchstart (Touch Events API) ──
                    try {
                        var touchStart = new TouchEvent('touchstart', {
                            cancelable: true,
                            bubbles: true,
                            composed: true,
                            touches: [touchObj],
                            targetTouches: [touchObj],
                            changedTouches: [touchObj],
                            ctrlKey: false,
                            shiftKey: false,
                            altKey: false,
                            metaKey: false
                        });
                        target.dispatchEvent(touchStart);
                    } catch(e) {}

                    // ── Step 3: تأخیر انسانی قبل از رها کردن ──
                    var holdDuration = 80 + Math.floor(Math.random() * 100);

                    setTimeout(function() {
                        try {
                            // ── Step 4: pointerup (Pointer Events API) ──
                            try {
                                var pointerUp = new PointerEvent('pointerup', {
                                    pointerId: touchId,
                                    pointerType: 'touch',
                                    clientX: x,
                                    clientY: y,
                                    bubbles: true,
                                    cancelable: true,
                                    composed: true,
                                    isPrimary: true,
                                    width: 5,
                                    height: 5,
                                    pressure: 0,
                                    tiltX: 0,
                                    tiltY: 0,
                                    twist: 0
                                });
                                target.dispatchEvent(pointerUp);
                            } catch(e) {}

                            // ── Step 5: touchend (Touch Events API) ──
                            try {
                                var touchEnd = new TouchEvent('touchend', {
                                    cancelable: true,
                                    bubbles: true,
                                    composed: true,
                                    touches: [],
                                    targetTouches: [],
                                    changedTouches: [touchObj],
                                    ctrlKey: false,
                                    shiftKey: false,
                                    altKey: false,
                                    metaKey: false
                                });
                                target.dispatchEvent(touchEnd);
                            } catch(e) {}

                            // ── Step 6: mousedown (Mouse Events — fallback دسکتاپ) ──
                            try {
                                var mouseDown = new MouseEvent('mousedown', {
                                    clientX: x,
                                    clientY: y,
                                    screenX: x + (window.screenX || 0),
                                    screenY: y + (window.screenY || 0),
                                    button: 0,
                                    buttons: 1,
                                    bubbles: true,
                                    cancelable: true,
                                    view: window,
                                    detail: 1
                                });
                                target.dispatchEvent(mouseDown);
                            } catch(e) {}

                            // ── Step 7: تأخیر قبل از mouseup (انگشت بلند شد) ──
                            var releaseDelay = 40 + Math.floor(Math.random() * 60);

                            setTimeout(function() {
                                try {
                                    // ── Step 8: mouseup (Mouse Events) ──
                                    try {
                                        var mouseUp = new MouseEvent('mouseup', {
                                            clientX: x,
                                            clientY: y,
                                            screenX: x + (window.screenX || 0),
                                            screenY: y + (window.screenY || 0),
                                            button: 0,
                                            buttons: 0,
                                            bubbles: true,
                                            cancelable: true,
                                            view: window,
                                            detail: 1
                                        });
                                        target.dispatchEvent(mouseUp);
                                    } catch(e) {}

                                    // ── Step 9: click (Mouse Events) ──
                                    try {
                                        var clickEvent = new MouseEvent('click', {
                                            clientX: x,
                                            clientY: y,
                                            screenX: x + (window.screenX || 0),
                                            screenY: y + (window.screenY || 0),
                                            button: 0,
                                            buttons: 0,
                                            bubbles: true,
                                            cancelable: true,
                                            view: window,
                                            detail: 1
                                        });
                                        target.dispatchEvent(clickEvent);
                                    } catch(e) {}

                                    // ── Step 10: Native click fallback ──
                                    try {
                                        if (target.tagName === 'A' || target.tagName === 'BUTTON' ||
                                            target.tagName === 'INPUT' || target.tagName === 'SELECT' ||
                                            target.tagName === 'TEXTAREA' || target.onclick ||
                                            target.getAttribute('onclick') || target.getAttribute('data-href')) {
                                            target.click();
                                        }
                                    } catch(e) {}

                                    // ── Callback ──
                                    if (callback) callback();
                                } catch(e) { if (callback) callback(); }
                            }, releaseDelay);
                        } catch(e) { if (callback) callback(); }
                    }, holdDuration);
                } catch(e) { if (callback) callback(); }
            };

            // ═══════════════════════════════════════════════════════════
            // HBS.simulateTouch — شبیه‌سازی tap روی یک عنصر
            // ═══════════════════════════════════════════════════════════
            //
            // این تابع یک عنصر HTML دریافت می‌کند و یک tap در مختصات
            // تصادفی داخل آن عنصر اجرا می‌کند. اگر احتمال touch کمتر از
            // threshold باشد، تابع بدون کار برمی‌گردد.
            // ═══════════════════════════════════════════════════════════

            HBS.simulateTouch = function(element) {
                if (Math.random() > $touchProb) return;
                try {
                    if (!element || element === document) element = document.body;
                    var rect = element.getBoundingClientRect();

                    // اطمینان از اینکه عنصر قابل مشاهده است
                    if (rect.width === 0 || rect.height === 0) return;
                    if (rect.bottom < 0 || rect.top > window.innerHeight) return;

                    // مختصات تصادفی داخل عنصر (نه دقیقاً مرکز)
                    var margin = Math.min(rect.width, rect.height) * 0.15;
                    var x = rect.left + margin + Math.random() * (rect.width - margin * 2);
                    var y = rect.top + margin + Math.random() * (rect.height - margin * 2);

                    HBS.dispatchFullTap(x, y, element);
                } catch(e) {}
            };

            // ═══════════════════════════════════════════════════════════
            // HBS.dispatchTouchScroll — اسکرول لمسی با touchmove
            // ═══════════════════════════════════════════════════════════
            //
            // شبیه‌سازی اسکرول با انگشت روی صفحه لمسی.
            // این تابع touchstart, touchmove×N, touchend را dispatch می‌کند
            // که دقیقاً مشابه اسکرول واقعی روی موبایل است.
            //
            // پارامترها:
            //   fromY    — موقعیت شروع (viewport Y)
            //   toY      — موقعیت پایان (viewport Y)
            //   duration — مدت زمان اسکرول (ms)
            //   callback — (اختیاری) بعد از اتمام
            // ═══════════════════════════════════════════════════════════

            HBS.dispatchTouchScroll = function(fromY, toY, duration, callback) {
                try {
                    if (Math.abs(toY - fromY) < 5) { if (callback) callback(); return; }

                    var target = document.elementFromPoint(window.innerWidth / 2, fromY) || document.body;
                    var now = Date.now();
                    var touchId = (now + 1) % 2147483647;
                    var distance = toY - fromY;
                    var absDist = Math.abs(distance);
                    var steps = Math.min(20, Math.max(4, Math.floor(absDist / 30)));
                    var force_val = 0.3 + Math.random() * 0.4;

                    // ساخن touch object اولیه
                    var touchObj;
                    var centerX = window.innerWidth / 2;
                    try {
                        touchObj = new Touch({
                            identifier: touchId,
                            target: target,
                            clientX: centerX,
                            clientY: fromY,
                            radiusX: 3,
                            radiusY: 3,
                            rotationAngle: 0,
                            force: force_val
                        });
                    } catch(e) {
                        touchObj = {
                            identifier: touchId,
                            target: target,
                            clientX: centerX,
                            clientY: fromY,
                            radiusX: 3,
                            radiusY: 3,
                            rotationAngle: 0,
                            force: force_val
                        };
                    }

                    // touchstart
                    try {
                        target.dispatchEvent(new TouchEvent('touchstart', {
                            cancelable: true, bubbles: true, composed: true,
                            touches: [touchObj], targetTouches: [touchObj], changedTouches: [touchObj]
                        }));
                    } catch(e) {}

                    // pointerdown
                    try {
                        target.dispatchEvent(new PointerEvent('pointerdown', {
                            pointerId: touchId, pointerType: 'touch',
                            clientX: centerX, clientY: fromY,
                            bubbles: true, cancelable: true,
                            isPrimary: true, pressure: force_val
                        }));
                    } catch(e) {}

                    var step = 0;
                    var baseInterval = duration / steps;

                    var doTouchMove = function() {
                        if (step >= steps) {
                            // touchend
                            try {
                                target.dispatchEvent(new TouchEvent('touchend', {
                                    cancelable: true, bubbles: true, composed: true,
                                    touches: [], targetTouches: [], changedTouches: [touchObj]
                                }));
                            } catch(e) {}

                            try {
                                target.dispatchEvent(new PointerEvent('pointerup', {
                                    pointerId: touchId, pointerType: 'touch',
                                    clientX: centerX, clientY: toY,
                                    bubbles: true, cancelable: true,
                                    isPrimary: true, pressure: 0
                                }));
                            } catch(e) {}

                            // اسکرول واقعی به موقعیت نهایی
                            window.scrollTo(0, toY);

                            if (callback) callback();
                            return;
                        }

                        var progress = (step + 1) / steps;
                        var currentY = fromY + distance * progress;

                        // نویز طبیعی لرزش دست
                        currentY += (Math.random() - 0.5) * 3;

                        // ساخن touch move object
                        var moveTouchObj;
                        try {
                            moveTouchObj = new Touch({
                                identifier: touchId,
                                target: document.elementFromPoint(centerX, currentY) || document.body,
                                clientX: centerX + (Math.random() - 0.5) * 2,
                                clientY: currentY,
                                radiusX: 2.5 + Math.random(),
                                radiusY: 2.5 + Math.random(),
                                rotationAngle: 0,
                                force: 0.2 + Math.random() * 0.3
                            });
                        } catch(e) {
                            moveTouchObj = {
                                identifier: touchId,
                                target: target,
                                clientX: centerX,
                                clientY: currentY,
                                radiusX: 2.5,
                                radiusY: 2.5,
                                rotationAngle: 0,
                                force: 0.3
                            };
                        }

                        // touchmove
                        try {
                            target.dispatchEvent(new TouchEvent('touchmove', {
                                cancelable: true, bubbles: true, composed: true,
                                touches: [moveTouchObj], targetTouches: [moveTouchObj],
                                changedTouches: [moveTouchObj]
                            }));
                        } catch(e) {}

                        // pointermove
                        try {
                            target.dispatchEvent(new PointerEvent('pointermove', {
                                pointerId: touchId, pointerType: 'touch',
                                clientX: centerX + (Math.random() - 0.5) * 2,
                                clientY: currentY,
                                bubbles: true, cancelable: true,
                                isPrimary: true, pressure: 0.3 + Math.random() * 0.2
                            }));
                        } catch(e) {}

                        // اسکرول واقعی
                        window.scrollTo(0, currentY);

                        step++;
                        var jitter = 0.7 + Math.random() * 0.6;
                        setTimeout(doTouchMove, Math.floor(baseInterval * jitter));
                    };

                    doTouchMove();
                } catch(e) { if (callback) callback(); }
            };
        """.trimIndent()
    }

    // ═══════════════════════════════════════════════════════════════
    // Scroll Simulation — با پشتیبانی از Touch Events
    // ═══════════════════════════════════════════════════════════════
    //
    // در این نسخه، اسکرول با dispatchTouchScroll ترکیب شده است تا
    // شبیه‌سازی کاملی از اسکرول لمسی موبایل ارائه دهد.
    //
    // تمام الگوهای قبلی (A: خواننده, B: اسکن‌کننده, C: جستجوگر, D: مرور عمیق)
    // حفظ شده‌اند اما اکنون از dispatchTouchScroll برای اسکرول استفاده می‌کنند
    // تا touch events نیز تولید شوند.
    //
    // ═══════════════════════════════════════════════════════════════

    private fun buildScrollSimulationJS(behavior: AdNetworkBehavior): String {
        val sections = behavior.scrollSections
        val pauseMin = behavior.scrollPauseMinMs
        val pauseMax = behavior.scrollPauseMaxMs
        val reverseProb = behavior.scrollReverseProbability

        return """
        HBS.simulateScroll = function() {
            var sections = $sections;
            var pauseMin = $pauseMin;
            var pauseMax = $pauseMax;
            var reverseProb = $reverseProb;

            // ═══════════════════════════════════════════════════════════
            // اندازه‌گیری صفحه
            // ═══════════════════════════════════════════════════════════
            var pageHeight = Math.max(
                document.body.scrollHeight,
                document.documentElement.scrollHeight,
                800
            );
            var viewportHeight = window.innerHeight || document.documentElement.clientHeight;
            if (pageHeight <= viewportHeight) return;

            var maxScroll = pageHeight - viewportHeight;

            // ═══════════════════════════════════════════════════════════
            // Easing Functions
            // ═══════════════════════════════════════════════════════════
            var easeInOutCubic = function(t) {
                return t < 0.5 ? 4*t*t*t : 1-Math.pow(-2*t+2,3)/2;
            };
            var easeOutQuart = function(t) {
                return 1-Math.pow(1-t,4);
            };
            var easeInOutExpo = function(t) {
                return t === 0 || t === 1 ? t :
                    t < 0.5 ? Math.pow(2,20*t-10)/2 : (2-Math.pow(2,-20*t+10))/2;
            };
            var easingFunctions = [easeInOutCubic, easeOutQuart, easeInOutExpo];
            var pickEasing = function() {
                return easingFunctions[Math.floor(Math.random() * easingFunctions.length)];
            };

            // ═══════════════════════════════════════════════════════════
            // توزیع زمانی Weibull-like
            // ═══════════════════════════════════════════════════════════
            var weibullDelay = function(min, max) {
                var r = Math.random();
                var weibull = Math.pow(-Math.log(1-r), 1/1.5);
                var scale = (max - min) / 2.5;
                var delay = min + weibull * scale;
                return Math.min(max, Math.max(min, Math.floor(delay)));
            };

            // ═══════════════════════════════════════════════════════════
            // Gesture Level — اسکرول با پشتیبانی Touch Events
            //
            // این نسخه از HBS.dispatchTouchScroll (تعریف شده در بالا)
            // برای شبیه‌سازی اسکرول لمسی استفاده می‌کند. این touch events
            // واقعی (touchstart, touchmove, touchend) را تولید می‌کند
            // که برای Monetag و Hypelab ضروری است.
            // ═══════════════════════════════════════════════════════════

            var scrollGesture = function(fromY, toY, durationMs, callback) {
                var distance = toY - fromY;
                if (Math.abs(distance) < 8) {
                    if (callback) callback();
                    return;
                }

                // استفاده از dispatchTouchScroll برای اسکرول لمسی
                // این touch events واقعی تولید می‌کند
                HBS.dispatchTouchScroll(fromY, toY, durationMs, callback);
            };

            // ═══════════════════════════════════════════════════════════
            // تشخیص عناصر قابل اسکرول
            // ═══════════════════════════════════════════════════════════
            var findScrollTargets = function() {
                var targets = [];
                try {
                    var paragraphs = document.querySelectorAll('p, h2, h3, h4, article, section, .content, .post, .entry');
                    for (var i = 0; i < paragraphs.length && targets.length < 15; i++) {
                        var rect = paragraphs[i].getBoundingClientRect();
                        if (rect.bottom > 0 && rect.top < pageHeight) {
                            var y = window.scrollY + rect.top - viewportHeight * 0.3;
                            y = Math.max(0, Math.min(maxScroll, y));
                            var dup = false;
                            for (var j = 0; j < targets.length; j++) {
                                if (Math.abs(targets[j] - y) < viewportHeight * 0.2) {
                                    dup = true; break;
                                }
                            }
                            if (!dup) targets.push(y);
                        }
                    }
                } catch(e) {}
                if (targets.length < 3) {
                    for (var i = 1; i <= 8; i++) {
                        targets.push(Math.floor(maxScroll * (i / 9) + (Math.random() - 0.5) * viewportHeight * 0.3));
                    }
                }
                targets.sort(function(a,b){return a-b;});
                return targets;
            };

            var scrollTargets = findScrollTargets();

            // ═══════════════════════════════════════════════════════════
            // Progress Reporting
            // ═══════════════════════════════════════════════════════════
            var reportProgress = function(pct) {
                pct = Math.min(100, Math.max(0, pct));
                try {
                    if (typeof AndroidPopunderBridge !== 'undefined' &&
                        AndroidPopunderBridge.onScrollProgress) {
                        AndroidPopunderBridge.onScrollProgress(pct);
                    }
                } catch(e) {}
            };

            // ═══════════════════════════════════════════════════════════
            // انتخاب الگوی اسکرول — [CRASH-FIX] only keep A (reader) and D (deep browse)
            // to reduce JS injection size and prevent native OOM on low-end devices.
            // Removed Pattern B (scanner) and Pattern C (searcher) which were redundant.
            // ═══════════════════════════════════════════════════════════
            var patternA = function() {
                var idx = 0;
                var totalTargets = scrollTargets.length;
                var nextStep = function() {
                    reportProgress(Math.floor((idx / totalTargets) * 100));
                    if (idx >= scrollTargets.length) {
                        reportProgress(100);
                        if (Math.random() < 0.20) {
                            var backTarget = scrollTargets[Math.floor(Math.random() * scrollTargets.length)];
                            scrollGesture(window.scrollY, backTarget,
                                600 + Math.random() * 1200, function() {
                                var pause = pauseMin * 2 + Math.random() * pauseMax * 2;
                                setTimeout(function() {
                                    if (Math.random() < 0.40) {
                                        window.scrollBy(0, (Math.random() - 0.5) * 20);
                                    }
                                }, pause);
                            });
                        }
                        return;
                    }
                    var target = scrollTargets[idx];
                    var currentY = window.scrollY;

                    if (Math.random() < reverseProb && idx > 0) {
                        var prevTarget = scrollTargets[Math.floor(Math.random() * idx)];
                        scrollGesture(currentY, prevTarget,
                            400 + Math.random() * 800, function() {
                            var reReadPause = pauseMin * 1.5 + Math.random() * pauseMax;
                            setTimeout(function() {
                                if (Math.random() < 0.50) {
                                    window.scrollBy(0, (Math.random() - 0.5) * 40);
                                }
                                setTimeout(function() {
                                    nextStep();
                                }, 200 + Math.random() * 600);
                            }, reReadPause);
                        });
                        return;
                    }

                    if (Math.random() < 0.15 && idx > 0 && idx < scrollTargets.length - 1) {
                        var midStop = currentY + (target - currentY) * (0.3 + Math.random() * 0.4);
                        scrollGesture(currentY, midStop,
                            300 + Math.random() * 600, function() {
                            var midPause = pauseMax + Math.random() * 3000;
                            var microAdjustInterval = setInterval(function() {
                                window.scrollBy(0, (Math.random() - 0.5) * 10);
                            }, 800 + Math.random() * 1200);
                            setTimeout(function() {
                                clearInterval(microAdjustInterval);
                                nextStep();
                            }, midPause);
                        });
                        return;
                    }

                    scrollGesture(currentY, target, 400 + Math.random() * 800, function() {
                        var readPause = weibullDelay(pauseMin, pauseMax);
                        if (Math.random() < 0.10) {
                            readPause += 2000 + Math.random() * 4000;
                        }
                        if (Math.random() < 0.20) {
                            var microInterval = setInterval(function() {
                                window.scrollBy(0, (Math.random() - 0.5) * 8);
                            }, 600 + Math.random() * 1000);
                            setTimeout(function() {
                                clearInterval(microInterval);
                                idx++;
                                setTimeout(nextStep, 100 + Math.random() * 300);
                            }, readPause);
                        } else {
                            idx++;
                            setTimeout(nextStep, readPause);
                        }
                    });
                };
                nextStep();
            };

            // ============================================================
            // PATTERN D: مرورگر عمیق
            // ============================================================
            var patternD = function() {
                if (scrollTargets.length < 4) { reportProgress(20); patternA(); return; }
                reportProgress(5);
                var shuffled = [].concat(scrollTargets);
                for (var i = shuffled.length - 1; i > 0; i--) {
                    var j = Math.floor(Math.random() * (i + 1));
                    var tmp = shuffled[i]; shuffled[i] = shuffled[j]; shuffled[j] = tmp;
                }
                var visitCount = Math.min(3 + Math.floor(Math.random() * 3), shuffled.length);
                var visited = 0;
                var visitNext = function() {
                    var pct = Math.floor((visited / visitCount) * 95);
                    reportProgress(pct);
                    if (visited >= visitCount) {
                        reportProgress(100);
                        scrollGesture(window.scrollY, maxScroll * 0.95,
                            500 + Math.random() * 1000, function(){reportProgress(100);});
                        return;
                    }
                    var target = shuffled[visited];
                    var currentY = window.scrollY;
                    var speed = 300 + Math.random() * 1400;
                    scrollGesture(currentY, target, speed, function() {
                        var stopPause = pauseMin * 0.5 + Math.random() * pauseMax * 1.5;
                        if (Math.random() < 0.15) {
                            stopPause += 3000 + Math.random() * 5000;
                        }
                        setTimeout(function() {
                            visited++;
                            if (Math.random() < 0.20) {
                                window.scrollBy(0, (Math.random() - 0.5) * 30);
                            }
                            setTimeout(visitNext, 200 + Math.random() * 500);
                        }, stopPause);
                    });
                };
                visitNext();
            };

            // ═══════════════════════════════════════════════════════════
            // اجرای الگوی انتخاب‌شده
            // ═══════════════════════════════════════════════════════════
            var patternRoll = Math.random();
            if (patternRoll < 0.45) {
                patternA();
            } else if (patternRoll < 0.70) {
                if (scrollTargets.length < 4) { patternA(); return; }
                patternD();
            }
        };
        """.trimIndent()
    }

    // ═══════════════════════════════════════════════════════════════
    // Viewability Tracking
    // ═══════════════════════════════════════════════════════════════

    private fun buildViewabilityJS(behavior: AdNetworkBehavior): String {
        val threshold = behavior.viewabilityThreshold
        val durationMs = behavior.viewabilityDurationMs

        return """
            HBS.trackViewability = function() {
                var threshold = $threshold;
                var durationMs = $durationMs;
                var selectors = ${jsonArray(behavior.adElementSelectors)};
                if (selectors.length === 0) return;
                var adElements = [];
                for (var s = 0; s < selectors.length; s++) {
                    try {
                        var found = document.querySelectorAll(selectors[s]);
                        for (var f = 0; f < found.length; f++) {
                            adElements.push(found[f]);
                        }
                    } catch(e) {}
                }
                if (adElements.length === 0) return;
                for (var i = 0; i < adElements.length; i++) {
                    (function(el) {
                        try {
                            var observer = new IntersectionObserver(function(entries) {
                                entries.forEach(function(entry) {
                                    if (entry.intersectionRatio >= threshold) {
                                        if (!el.dataset.hbsViewable) {
                                            el.dataset.hbsViewable = '1';
                                            el.dataset.hbsViewStart = Date.now();
                                        } else if (el.dataset.hbsViewStart) {
                                            var elapsed = Date.now() - parseInt(el.dataset.hbsViewStart);
                                            if (elapsed >= durationMs) {
                                                el.dataset.hbsViewableConfirmed = '1';
                                                el.scrollIntoView({behavior: 'smooth', block: 'center'});
                                            }
                                        }
                                    } else {
                                        if (el.dataset.hbsViewStart) {
                                            var elapsed = Date.now() - parseInt(el.dataset.hbsViewStart);
                                            if (elapsed < durationMs) {
                                                el.dataset.hbsViewable = '0';
                                                el.dataset.hbsViewStart = '';
                                            }
                                        }
                                    }
                                });
                            }, {threshold: [threshold, 0.75, 1.0]});
                            observer.observe(el);
                        } catch(e) {}
                    })(adElements[i]);
                }
            };
        """.trimIndent()
    }

    // ═══════════════════════════════════════════════════════════════
    // Hover Simulation — با mousemove واقعی
    // ═══════════════════════════════════════════════════════════════
    //
    // == معماری جدید ==
    //
    // کاربر واقعی این hoverها را تولید می‌کند:
    // 1. mousemove روی یک مسیر (از یک عنصر به عنصر دیگر)
    // 2. mouseover روی عنصر جدید
    // 3. mouseenter روی عنصر جدید
    // 4. توقف + حرکت‌های ریز
    // 5. mouseout روی عنصر قدیمی
    // 6. mouseleave روی عنصر قدیمی
    //
    // این نسخه تمام این رویدادها را شبیه‌سازی می‌کند.
    // ═══════════════════════════════════════════════════════════════

    private fun buildHoverSimulationJS(behavior: AdNetworkBehavior): String {
        val hoverProb = behavior.hoverProbability

        return """
            HBS.simulateHover = function() {
                if (Math.random() > $hoverProb) return;

                // ── پیدا کردن عناصر hoverable ──
                var hoverableSelectors = 'a[href], button, input, select, textarea, [onmouseover], [onmouseenter], [tabindex], [role=button], [role=link]';
                var elements = document.querySelectorAll(hoverableSelectors);
                var visibleElements = [];

                for (var i = 0; i < elements.length; i++) {
                    try {
                        var rect = elements[i].getBoundingClientRect();
                        if (rect.width > 0 && rect.height > 0 &&
                            rect.bottom > 0 && rect.top < window.innerHeight &&
                            rect.right > 0 && rect.left < window.innerWidth) {
                            visibleElements.push({
                                el: elements[i],
                                rect: rect,
                                cx: rect.left + rect.width / 2,
                                cy: rect.top + rect.height / 2
                            });
                        }
                    } catch(e) {}
                }

                if (visibleElements.length < 2) return;

                // انتخاب ۲-۴ عنصر تصادفی
                var count = Math.min(visibleElements.length, 2 + Math.floor(Math.random() * 3));
                var shuffled = [].concat(visibleElements);
                for (var i = shuffled.length - 1; i > 0; i--) {
                    var j = Math.floor(Math.random() * (i + 1));
                    var tmp = shuffled[i]; shuffled[i] = shuffled[j]; shuffled[j] = tmp;
                }
                var selected = shuffled.slice(0, count);

                // ── حرکت ماوس بین دو نقطه با mousemove ──
                var moveMouse = function(fromX, fromY, toX, toY, durationMs, callback) {
                    var steps = 5 + Math.floor(Math.random() * 10);
                    var step = 0;
                    var doMove = function() {
                        if (step > steps) {
                            if (callback) callback();
                            return;
                        }
                        var t = step / steps;
                        // easing: smooth step
                        var eased = t * t * (3 - 2 * t);
                        var x = fromX + (toX - fromX) * eased;
                        var y = fromY + (toY - fromY) * eased;

                        // لرزش طبیعی دست
                        x += (Math.random() - 0.5) * 1.5;
                        y += (Math.random() - 0.5) * 1.5;

                        // dispatch mousemove
                        try {
                            var evt = new MouseEvent('mousemove', {
                                clientX: x, clientY: y,
                                screenX: x + (window.screenX || 0),
                                screenY: y + (window.screenY || 0),
                                bubbles: true, cancelable: true, view: window,
                                button: 0, buttons: 0
                            });
                            document.elementFromPoint(x, y).dispatchEvent(evt);
                        } catch(e) {}

                        step++;
                        setTimeout(doMove, durationMs / steps);
                    };
                    doMove();
                };

                // ── Hover روی هر عنصر ──
                var hoverIdx = 0;
                var doHoverNext = function() {
                    if (hoverIdx >= selected.length) return;

                    var item = selected[hoverIdx];
                    var target = item.el;
                    var cx = item.cx + (Math.random() - 0.5) * item.rect.width * 0.2;
                    var cy = item.cy + (Math.random() - 0.5) * item.rect.height * 0.2;

                    // mouseover
                    try {
                        var overEvent = new MouseEvent('mouseover', {
                            clientX: cx, clientY: cy, bubbles: true, cancelable: true,
                            view: window, button: 0, buttons: 0
                        });
                        target.dispatchEvent(overEvent);
                    } catch(e) {}

                    // mouseenter
                    try {
                        var enterEvent = new MouseEvent('mouseenter', {
                            clientX: cx, clientY: cy, bubbles: false, cancelable: true,
                            view: window, button: 0, buttons: 0
                        });
                        target.dispatchEvent(enterEvent);
                    } catch(e) {}

                    // PointerEvent pointerover
                    try {
                        target.dispatchEvent(new PointerEvent('pointerover', {
                            pointerId: 1, pointerType: 'mouse', clientX: cx, clientY: cy,
                            bubbles: true, cancelable: true, isPrimary: true
                        }));
                    } catch(e) {}

                    // حرکت‌های ریز روی عنصر (شبیه خواندن tooltip)
                    var microMoves = 2 + Math.floor(Math.random() * 3);
                    var microIdx = 0;
                    var doMicroMove = function() {
                        if (microIdx >= microMoves) {
                            // مدت hover
                            var hoverDuration = 300 + Math.random() * 1500;
                            setTimeout(function() {
                                // mouseout
                                try {
                                    var outEvent = new MouseEvent('mouseout', {
                                        clientX: cx, clientY: cy, bubbles: true, cancelable: true,
                                        view: window, button: 0, buttons: 0
                                    });
                                    target.dispatchEvent(outEvent);
                                } catch(e) {}

                                // mouseleave
                                try {
                                    var leaveEvent = new MouseEvent('mouseleave', {
                                        clientX: cx, clientY: cy, bubbles: false, cancelable: true,
                                        view: window, button: 0, buttons: 0
                                    });
                                    target.dispatchEvent(leaveEvent);
                                } catch(e) {}

                                // pointerout
                                try {
                                    target.dispatchEvent(new PointerEvent('pointerout', {
                                        pointerId: 1, pointerType: 'mouse', clientX: cx, clientY: cy,
                                        bubbles: true, cancelable: true, isPrimary: true
                                    }));
                                } catch(e) {}

                                hoverIdx++;
                                // حرکت ماوس به عنصر بعدی
                                if (hoverIdx < selected.length) {
                                    var nextItem = selected[hoverIdx];
                                    var nextCx = nextItem.cx + (Math.random() - 0.5) * nextItem.rect.width * 0.2;
                                    var nextCy = nextItem.cy + (Math.random() - 0.5) * nextItem.rect.height * 0.2;
                                    moveMouse(cx, cy, nextCx, nextCy, 200 + Math.random() * 400, doHoverNext);
                                }
                            }, hoverDuration);
                            return;
                        }
                        // حرکت ریز ماوس
                        try {
                            var microEvt = new MouseEvent('mousemove', {
                                clientX: cx + (Math.random() - 0.5) * 5,
                                clientY: cy + (Math.random() - 0.5) * 5,
                                bubbles: true, cancelable: true, view: window,
                                button: 0, buttons: 0
                            });
                            target.dispatchEvent(microEvt);
                        } catch(e) {}
                        microIdx++;
                        setTimeout(doMicroMove, 100 + Math.random() * 300);
                    };
                    doMicroMove();
                };

                // شروع از عنصر اول
                var firstItem = selected[0];
                var fcx = firstItem.cx + (Math.random() - 0.5) * firstItem.rect.width * 0.2;
                var fcy = firstItem.cy + (Math.random() - 0.5) * firstItem.rect.height * 0.2;

                // یک mousemove اولیه برای ورود ماوس به صفحه
                try {
                    document.body.dispatchEvent(new MouseEvent('mousemove', {
                        clientX: 10 + Math.random() * 100,
                        clientY: 10 + Math.random() * 100,
                        bubbles: true, cancelable: true, view: window
                    }));
                } catch(e) {}

                // حرکت به عنصر اول
                setTimeout(function() {
                    moveMouse(
                        10 + Math.random() * 100, 10 + Math.random() * 100,
                        fcx, fcy,
                        300 + Math.random() * 500,
                        doHoverNext
                    );
                }, 200 + Math.random() * 400);
            };
        """.trimIndent()
    }

    // ═══════════════════════════════════════════════════════════════
    // Ad Click Detection — با event chain کامل
    // ═══════════════════════════════════════════════════════════════
    //
    // == مشکل قبلی ==
    // فقط el.click() را صدا می‌زد که بسیاری از ad networks آن را تشخیص
    // نمی‌دهند زیرا فاقد event chain کامل است.
    //
    // == راه‌حل جدید ==
    // از HBS.dispatchFullTap استفاده می‌کند که pointer → touch → mouse → click
    // کامل را اجرا می‌کند. این برای Monetag و Hypelab ضروری است.
    // ═══════════════════════════════════════════════════════════════

    private fun buildAdClickJS(behavior: AdNetworkBehavior): String {
        val clickProb = behavior.clickAdProbability
        val selectors = jsonArray(behavior.adElementSelectors)

        return """
            HBS.tryClickAd = function() {
                if (Math.random() > $clickProb) return;
                var selectors = $selectors;
                for (var s = 0; s < selectors.length; s++) {
                    try {
                        var elements = document.querySelectorAll(selectors[s]);
                        for (var e = 0; e < elements.length; e++) {
                            var el = elements[e];
                            var rect = el.getBoundingClientRect();
                            var viewportHeight = window.innerHeight || document.documentElement.clientHeight;
                            var viewportWidth = window.innerWidth || document.documentElement.clientWidth;
                            if (rect.bottom < 0 || rect.top > viewportHeight ||
                                rect.right < 0 || rect.left > viewportWidth) {
                                continue;
                            }
                            // اسکرول به موقعیت عنصر
                            el.scrollIntoView({behavior: 'smooth', block: 'center'});

                            // مختصات تصادفی داخل عنصر
                            var marginX = rect.width * 0.15;
                            var marginY = rect.height * 0.15;
                            var x = rect.left + marginX + Math.random() * (rect.width - marginX * 2);
                            var y = rect.top + marginY + Math.random() * (rect.height - marginY * 2);

                            // [حیاتی] استفاده از event chain کامل
                            // pointerdown → touchstart → [hold] → pointerup → touchend → mousedown → [release] → mouseup → click
                            setTimeout(function() {
                                HBS.dispatchFullTap(x, y, el);
                            }, 100 + Math.random() * 400);

                            return; // فقط یک تبلیغ
                        }
                    } catch(e) {}
                }

                // Fallback: اگر هیچ عنصر تبلیغاتی با CSS selector پیدا نشد،
                // روی لینک‌های تصادفی کلیک کن (برای Monetag که از selectors
                // پویا استفاده می‌کند)
                if (selectors.length > 0) {
                    try {
                        var allLinks = document.querySelectorAll('a[href]');
                        var adLinks = [];
                        for (var i = 0; i < allLinks.length; i++) {
                            var href = (allLinks[i].getAttribute('href') || '').toLowerCase();
                            if (href.indexOf('click') > -1 || href.indexOf('ad') > -1 ||
                                href.indexOf('promo') > -1 || href.indexOf('sponsor') > -1 ||
                                href.indexOf('offer') > -1 || href.indexOf('go') > -1) {
                                adLinks.push(allLinks[i]);
                            }
                        }
                        if (adLinks.length > 0) {
                            var chosen = adLinks[Math.floor(Math.random() * adLinks.length)];
                            var r = chosen.getBoundingClientRect();
                            var x = r.left + Math.random() * r.width;
                            var y = r.top + Math.random() * r.height;
                            setTimeout(function() {
                                HBS.dispatchFullTap(x, y, chosen);
                            }, 200 + Math.random() * 500);
                        }
                    } catch(e) {}
                }
            };
        """.trimIndent()
    }

    // ═══════════════════════════════════════════════════════════════
    // Internal Link Clicking — با event chain کامل
    // ═══════════════════════════════════════════════════════════════

    private fun buildInternalLinkJS(behavior: AdNetworkBehavior): String {
        val clickProb = behavior.internalLinkClickProbability

        return """
            HBS.clickInternalLink = function() {
                if (Math.random() > $clickProb) return;
                var links = document.querySelectorAll('a[href]:not([href="#"]):not([href=""])');
                var internalLinks = [];
                var currentHost = window.location.host;
                for (var i = 0; i < links.length; i++) {
                    try {
                        var href = links[i].getAttribute('href');
                        if (!href || href.startsWith('#') || href.startsWith('javascript:') ||
                            href.startsWith('mailto:') || href.startsWith('tel:')) continue;
                        if (href.startsWith('/') || href.indexOf(currentHost) > -1 ||
                            href.startsWith(window.location.protocol + '//' + currentHost)) {
                            internalLinks.push(links[i]);
                        }
                    } catch(e) {}
                }
                if (internalLinks.length === 0) return;
                var link = internalLinks[Math.floor(Math.random() * internalLinks.length)];
                try {
                    link.scrollIntoView({behavior: 'smooth', block: 'center'});
                    setTimeout(function() {
                        try {
                            // [حیاتی] استفاده از event chain کامل به جای link.click()
                            var rect = link.getBoundingClientRect();
                            var x = rect.left + rect.width * (0.3 + Math.random() * 0.4);
                            var y = rect.top + rect.height * (0.3 + Math.random() * 0.4);
                            HBS.dispatchFullTap(x, y, link);
                        } catch(e) {}
                    }, 200 + Math.random() * 800);
                } catch(e) {}
            };
        """.trimIndent()
    }

    // ═══════════════════════════════════════════════════════════════
    // Anti-Detection — پیشرفته
    // ═══════════════════════════════════════════════════════════════

    private fun buildAntiDetectionJS(): String {
        return """
            try {
                // ═════════════════════════════════════════════════════
                // ۱. مخفی کردن webdriver
                // ═════════════════════════════════════════════════════
                Object.defineProperty(navigator, 'webdriver', {
                    get: function() { return undefined; }
                });

                // ═════════════════════════════════════════════════════
                // ۲. شبیه‌سازی plugins واقعی
                // ═════════════════════════════════════════════════════
                Object.defineProperty(navigator, 'plugins', {
                    get: function() {
                        return [
                            {name: 'Chrome PDF Plugin', filename: 'internal-pdf-viewer'},
                            {name: 'Chrome PDF Viewer', filename: 'mhjfbmdgcfjbbpaeojofohoefgiehjai'},
                            {name: 'Native Client', filename: 'internal-nacl-plugin'}
                        ];
                    }
                });

                // ═════════════════════════════════════════════════════
                // ۳. شبیه‌سازی languages
                // ═════════════════════════════════════════════════════
                Object.defineProperty(navigator, 'languages', {
                    get: function() { return ['en-US', 'en', 'fa']; }
                });

                // ═════════════════════════════════════════════════════
                // ۴. شبیه‌سازی hardwareConcurrency (تعداد هسته‌های CPU)
                // ═════════════════════════════════════════════════════
                Object.defineProperty(navigator, 'hardwareConcurrency', {
                    get: function() { return 4 + Math.floor(Math.random() * 4); }
                });

                // ═════════════════════════════════════════════════════
                // ۵. شبیه‌سازی deviceMemory (GB)
                // ═════════════════════════════════════════════════════
                Object.defineProperty(navigator, 'deviceMemory', {
                    get: function() { return [4, 8, 12, 16][Math.floor(Math.random() * 4)]; }
                });

                // ═════════════════════════════════════════════════════
                // ۶. شبیه‌سازی maxTouchPoints (حیاتی برای touch detection)
                // ═════════════════════════════════════════════════════
                Object.defineProperty(navigator, 'maxTouchPoints', {
                    get: function() { return 5; }
                });

                // ═════════════════════════════════════════════════════
                // ۷. شبیه‌سازی screen.orientation
                // ═════════════════════════════════════════════════════
                try {
                    Object.defineProperty(screen, 'orientation', {
                        get: function() {
                            return {
                                type: 'portrait-primary',
                                angle: 0,
                                onchange: null
                            };
                        }
                    });
                } catch(e) {}

                // ═════════════════════════════════════════════════════
                // ۸. شبیه‌سازی visualViewport
                // ═════════════════════════════════════════════════════
                try {
                    if (!window.visualViewport) {
                        window.visualViewport = {
                            width: window.innerWidth,
                            height: window.innerHeight,
                            scale: 1,
                            offsetTop: 0,
                            offsetLeft: 0,
                            onresize: null,
                            onscroll: null
                        };
                    }
                } catch(e) {}

                // ═════════════════════════════════════════════════════
                // ۹. اضافه کردن chrome.runtime
                // ═════════════════════════════════════════════════════
                if (!window.chrome) {
                    window.chrome = {runtime: {}};
                }
                if (!window.chrome.runtime) {
                    window.chrome.runtime = {};
                }

                // ═════════════════════════════════════════════════════
                // ۱۰. مخفی کردن automation hints در Function.prototype.toString
                // ═════════════════════════════════════════════════════
                var originalToString = Function.prototype.toString;
                Function.prototype.toString = function() {
                    if (this === navigator.webdriver) {
                        return 'function get webdriver() { [native code] }';
                    }
                    return originalToString.call(this);
                };
            } catch(e) {}
        """.trimIndent()
    }

    // ═══════════════════════════════════════════════════════════════
    // Popunder Trigger — مخصوص Monetag
    // ═══════════════════════════════════════════════════════════════

    fun buildPopunderJS(delayMs: Int): String {
        return """
            (function() {
                HBS.triggerPopunder = function() {
                    try {
                        var iframe = document.createElement('iframe');
                        iframe.style.display = 'none';
                        iframe.src = 'about:blank';
                        document.body.appendChild(iframe);
                        var popup = window.open('about:blank', '_blank');
                        if (popup) {
                            try {
                                popup.document.write('<html><head><meta http-equiv="refresh" content="0;url=' + encodeURI(window.location.href) + '"></head><body></body></html>');
                                popup.document.close();
                            } catch(e) {}
                        }
                        var a = document.createElement('a');
                        a.href = window.location.href;
                        a.target = '_blank';
                        a.style.display = 'none';
                        document.body.appendChild(a);
                        a.click();
                        document.body.removeChild(a);
                        try {
                            window.history.pushState({popunder: true}, '', window.location.href + '#popunder');
                        } catch(e) {}
                    } catch(e) {}
                };
                setTimeout(function() {
                    if (HBS.triggerPopunder) HBS.triggerPopunder();
                }, $delayMs);
            })();
        """.trimIndent()
    }

    fun buildPushNotificationJS(): String {
        return """
            (function() {
                if ('Notification' in window && Notification.permission === 'default') {
                    Notification.requestPermission();
                }
                if ('serviceWorker' in navigator) {
                    try {
                        navigator.serviceWorker.register('/sw.js').catch(function() {});
                    } catch(e) {}
                }
            })();
        """.trimIndent()
    }

    // ═══════════════════════════════════════════════════════════════
    // Dwell Time Distribution
    // ═══════════════════════════════════════════════════════════════

    fun getDwellTime(behavior: AdNetworkBehavior): Long {
        val min = behavior.dwellMinMs.toLong()
        val max = behavior.dwellMaxMs.toLong()
        val range = max - min

        if (range <= 0) return min.coerceAtLeast(30_000L)
        if (min < 30_000L) return getDwellTimeSafe(min, max)

        return when {
            rng.nextDouble() < 0.50 -> {
                val midRange = (range.toDouble() * 0.55).toLong()
                min + (range.toDouble() * 0.15).toLong() + (rng.nextLong().ushr(1) % midRange.coerceAtLeast(1))
            }
            rng.nextDouble() < 0.75 -> {
                val deepRange = (range.toDouble() * 0.30).toLong()
                min + (range.toDouble() * 0.55).toLong() + (rng.nextLong().ushr(1) % deepRange.coerceAtLeast(1))
            }
            rng.nextDouble() < 0.90 -> {
                val fullRange = (range.toDouble() * 0.20).toLong()
                min + (range.toDouble() * 0.75).toLong() + (rng.nextLong().ushr(1) % fullRange.coerceAtLeast(1))
            }
            else -> {
                val bounceRange = (range / 3).coerceAtLeast(1)
                min.coerceAtLeast(30_000L) + (rng.nextLong().ushr(1) % bounceRange)
            }
        }
    }

    private fun getDwellTimeSafe(min: Long, max: Long): Long {
        val safeMin = min.coerceAtLeast(30_000L)
        val safeMax = max.coerceAtLeast(60_000L)
        if (safeMin >= safeMax) return safeMin
        val safeRange = safeMax - safeMin
        return safeMin + (rng.nextLong().ushr(1) % safeRange.coerceAtLeast(1))
    }

    // ═══════════════════════════════════════════════════════════════
    // Helper
    // ═══════════════════════════════════════════════════════════════

    private fun jsonArray(list: List<String>): String {
        val sb = StringBuilder("[")
        for (i in list.indices) {
            if (i > 0) sb.append(",")
            sb.append("'").append(list[i].replace("'", "\\'")).append("'")
        }
        sb.append("]")
        return sb.toString()
    }
}
