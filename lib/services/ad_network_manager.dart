import 'package:flutter/services.dart';

import '../models/geo_models.dart';

/// AdNetwork — شبکه‌های تبلیغاتی پشتیبانی‌شده.
///
/// این enum با [AdNetworkConfig.kt] در سمت Android هماهنگ است.
/// هر شبکه الگوی رفتاری اختصاصی در WebView دارد:
/// - Coinzilla: بنر + مدال → viewability + scroll to banner
/// - Monetag: پاپ‌آندر → popunder + push notification
/// - Hypelab: نیتیو → مرور طبیعی + session depth
enum AdNetwork {
  coinzilla('coinzilla'),
  monetag('monetag'),
  hypelab('hypelab'),
  generic('generic');

  final String key;
  const AdNetwork(this.key);

  static AdNetwork fromKey(String key) {
    return AdNetwork.values.firstWhere(
      (n) => n.key == key.toLowerCase(),
      orElse: () => AdNetwork.generic,
    );
  }
}

/// AdNetworkOverrides — overrideهای پویا برای تنظیمات شبکه تبلیغاتی.
///
/// این کلاس به پنل اجازه می‌دهد تنظیمات را برای هر شبکه یا یک URL خاص
/// override کند. تمام فیلدها nullable هستند — مقدار null یعنی استفاده از
/// مقدار پیش‌فرض پروفایل شبکه.
class AdNetworkOverrides {
  final int? dwellMinSec;
  final int? dwellMaxSec;
  final double? clickAdProbability;
  final bool? triggerPopunder;
  final int? popunderDelayMs;
  final bool? pushOptIn;
  final int? sessionDepth;
  final bool? browseNatural;
  final double? internalLinkClickProbability;
  final int? scrollSections;
  final double? scrollReverseProbability;

  const AdNetworkOverrides({
    this.dwellMinSec,
    this.dwellMaxSec,
    this.clickAdProbability,
    this.triggerPopunder,
    this.popunderDelayMs,
    this.pushOptIn,
    this.sessionDepth,
    this.browseNatural,
    this.internalLinkClickProbability,
    this.scrollSections,
    this.scrollReverseProbability,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (dwellMinSec != null) map['dwell_min_sec'] = dwellMinSec;
    if (dwellMaxSec != null) map['dwell_max_sec'] = dwellMaxSec;
    if (clickAdProbability != null) map['click_ad_prob'] = clickAdProbability;
    if (triggerPopunder != null) map['trigger_popunder'] = triggerPopunder;
    if (popunderDelayMs != null) map['popunder_delay_ms'] = popunderDelayMs;
    if (pushOptIn != null) map['push_optin'] = pushOptIn;
    if (sessionDepth != null) map['session_depth'] = sessionDepth;
    if (browseNatural != null) map['browse_natural'] = browseNatural;
    if (internalLinkClickProbability != null) {
      map['internal_link_click_prob'] = internalLinkClickProbability;
    }
    if (scrollSections != null) map['scroll_sections'] = scrollSections;
    if (scrollReverseProbability != null) {
      map['scroll_reverse_prob'] = scrollReverseProbability;
    }
    return map;
  }

  /// اعمال تنظیمات GEO-aware بر اساس منطقه جغرافیایی فعلی
  static AdNetworkOverrides geoAdjusted({
    required AdNetworkOverrides base,
    required GeoRegion region,
  }) {
    final cpmRatio = region.cpmAvg / 8.5; // نسبت به USA CPM
    final dwellMultiplier = 1.0 + (1.0 - cpmRatio) * 0.5;

    return AdNetworkOverrides(
      dwellMinSec: base.dwellMinSec != null
          ? (base.dwellMinSec! * dwellMultiplier).round()
          : null,
      dwellMaxSec: base.dwellMaxSec != null
          ? (base.dwellMaxSec! * dwellMultiplier).round()
          : null,
      clickAdProbability: base.clickAdProbability,
      triggerPopunder: base.triggerPopunder,
      popunderDelayMs: base.popunderDelayMs,
      pushOptIn: base.pushOptIn,
      sessionDepth: base.sessionDepth,
      browseNatural: base.browseNatural,
      internalLinkClickProbability: base.internalLinkClickProbability,
      scrollSections: base.scrollSections,
      scrollReverseProbability: base.scrollReverseProbability,
    );
  }
}

/// AdNetworkManager — مدیریت شبکه‌های تبلیغاتی در سمت Flutter.
///
/// این کلاس امکانات زیر را فراهم می‌کند:
/// 1. ارسال دستور تنظیم شبکه تبلیغاتی به سمت Android از طریق MethodChannel
/// 2. نگهداشتن تنظیمات global ad network برای تمام بازدیدهای WebView
/// 3. امکان override تنظیمات برای URLهای خاص
/// 4. log و مانیتورینگ عملکرد هر شبکه
class AdNetworkManager {
  static const _channel = MethodChannel('com.coinceeper.app/tsp_agent');

  // ── نهاد جاری ───────────────────────────────────────────
  static AdNetwork _defaultNetwork = AdNetwork.generic;
  static final Map<String, AdNetwork> _urlOverrides = {};
  static AdNetworkOverrides? _globalOverrides;
  static final Map<String, AdNetworkOverrides> _urlOverridesConfig = {};

  /// شبکه تبلیغاتی پیش‌فرض.
  static AdNetwork get defaultNetwork => _defaultNetwork;

  /// تنظیم شبکه تبلیغاتی پیش‌فرض.
  static Future<void> setDefaultNetwork(AdNetwork network) async {
    _defaultNetwork = network;
    try {
      await _channel.invokeMethod<void>('tspSetAdNetwork', network.key);
    } catch (e) {
      // ignore on platforms where not supported
    }
  }

  /// تنظیم override شبکه تبلیغاتی برای یک URL خاص.
  static void setUrlOverride(String url, AdNetwork network) {
    _urlOverrides[url] = network;
  }

  /// حذف override برای یک URL.
  static void removeUrlOverride(String url) {
    _urlOverrides.remove(url);
  }

  /// دریافت شبکه تبلیغاتی مناسب برای یک URL.
  static AdNetwork getNetworkForUrl(String url) {
    if (_urlOverrides.containsKey(url)) {
      return _urlOverrides[url]!;
    }
    // تشخیص خودکار از روی domain
    return _detectNetworkFromUrl(url);
  }

  /// تنظیم overrideهای سراسری (از پنل).
  static void setGlobalOverrides(AdNetworkOverrides? overrides) {
    _globalOverrides = overrides;
  }

  /// دریافت overrideهای یک URL خاص.
  static AdNetworkOverrides? getOverridesForUrl(String url) {
    return _urlOverridesConfig[url] ?? _globalOverrides;
  }

  /// تشخیص خودکار شبکه تبلیغاتی از روی URL.
  static AdNetwork _detectNetworkFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('coinzilla') || lower.contains('coinzilla')) {
      return AdNetwork.coinzilla;
    }
    if (lower.contains('monetag') || lower.contains('popunder') || lower.contains('pop.js')) {
      return AdNetwork.monetag;
    }
    if (lower.contains('hypelab') || lower.contains('native-ad')) {
      return AdNetwork.hypelab;
    }
    return _defaultNetwork;
  }

  // ═══════════════════════════════════════════════════════════════
  // GEO-Aware Ad Network Configuration
  // ═══════════════════════════════════════════════════════════════

  /// تنظیم GEO برای Ad Network Manager
  ///
  /// این متد تنظیمات شبکه تبلیغاتی را بر اساس GEO تنظیم می‌کند:
  /// - Tier 1 (USA, UK, DE, ...): dwell طولانی‌تر، رفتار طبیعی‌تر
  /// - Tier 2 (JP, KR, SG, ...): dwell متوسط
  /// - Tier 3 (BR, IN, ...): dwell کوتاه‌تر، کلیک سریع‌تر
  static Future<void> setGeo(GeoRegion region) async {
    // تنظیم dwell time بر اساس GEO
    int minDwell, maxDwell;
    double clickProb;
    bool browseNatural;

    switch (region.tier) {
      case GeoRevenueTier.tier1:
        // Tier 1: dwell طولانی (۳-۱۰ دقیقه) + مرور طبیعی
        minDwell = 180;
        maxDwell = 600;
        clickProb = 0.15;
        browseNatural = true;
        break;
      case GeoRevenueTier.tier2:
        // Tier 2: dwell متوسط (۲-۵ دقیقه)
        minDwell = 120;
        maxDwell = 300;
        clickProb = 0.20;
        browseNatural = true;
        break;
      case GeoRevenueTier.tier3:
        // Tier 3: dwell کوتاه‌تر (۱-۳ دقیقه) + کلیک سریع‌تر
        minDwell = 60;
        maxDwell = 180;
        clickProb = 0.30;
        browseNatural = false;
        break;
    }

    _globalOverrides = AdNetworkOverrides(
      dwellMinSec: minDwell,
      dwellMaxSec: maxDwell,
      clickAdProbability: clickProb,
      browseNatural: browseNatural,
      sessionDepth: region.tier == GeoRevenueTier.tier1 ? 5 : 3,
      scrollReverseProbability: 0.3,
    );

    try {
      await _channel.invokeMethod<void>('tspSetGeo', <String, dynamic>{
        'geo_code': region.code,
        'geo_tier': region.tier.name,
        'cpm_min': region.cpmMin,
        'cpm_max': region.cpmMax,
        'dwell_min_sec': minDwell,
        'dwell_max_sec': maxDwell,
        'click_ad_prob': clickProb,
        'browse_natural': browseNatural,
      });
    } catch (e) {
      // ignore on platforms where not supported
    }
  }
}
