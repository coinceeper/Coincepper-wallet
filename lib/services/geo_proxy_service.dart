import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../di/service_locator.dart';
import '../models/geo_models.dart';
import '../utils/secure_log.dart';
import 'build_secrets.dart';

/// سرویس مدیریت Pool پراکسی GEO با توزیع هوشمند ترافیک
///
/// این سرویس وظایف زیر را انجام می‌دهد:
/// 1. نگهداری pool پراکسی از مناطق GEO مختلف
/// 2. توزیع ترافیک بر اساس وزن و CPM هر منطقه
/// 3. چرخش IP در بازه‌های زمانی مشخص (شبیه کاربر واقعی)
/// 4. ارسال تنظیمات پراکسی به WebView از طریق MethodChannel
/// 5. ردیابی عملکرد هر GEO و بهینه‌سازی خودکار توزیع
/// 6. ذخیره و بازیابی پیکربندی از SharedPreferences
class GeoProxyService {
  static GeoProxyService get instance => ServiceLocator.get<GeoProxyService>();

  static const String _kChannel = 'com.coinceeper.app/tsp_agent';
  static const MethodChannel _ch = MethodChannel(_kChannel);

  // ─── Constantes ───────────────────────────────────────────────

  /// بازه چرخش IP (۵-۱۵ دقیقه)
  static const Duration _ipRotationMin = Duration(minutes: 5);
  static const Duration _ipRotationMax = Duration(minutes: 15);

  /// [PERF-FIX] Backoff state: after consecutive rotation failures,
  /// the interval is multiplied up to 3x to avoid hammering the native layer.
  static const int _rotationMaxBackoffFactor = 3;

  /// کلیدهای SharedPreferences
  static const String _kPrefProxyPool = 'geo_proxy_pool';
  static const String _kPrefGeoConfig = 'geo_proxy_config';
  static const String _kPrefActiveGeo = 'geo_active_region';

  // ─── State ────────────────────────────────────────────────────

  final List<GeoProxy> _proxyPool = [];
  final Map<String, List<GeoProxy>> _proxyByRegion = {};
  final Map<String, double> _cpmByGeo = {};

  GeoRegion _currentGeo = GeoRegion.usa;
  int _rotationIndex = 0;
  int _rotationFailCount = 0;
  Timer? _rotationTimer;
  bool _initialized = false;
  bool _isStopped = false;

  // ─── Public API ───────────────────────────────────────────────

  /// آیا سرویس مقداردهی شده است
  bool get isInitialized => _initialized;

  /// منطقه GEO فعلی
  GeoRegion get currentGeo => _currentGeo;

  /// تعداد پراکسی‌های فعال
  int get activeProxyCount => _proxyPool.where((p) => p.isActive).length;

  /// توزیع پراکسی به تفکیک GEO
  Map<String, int> get proxyDistribution {
    final dist = <String, int>{};
    for (final proxy in _proxyPool) {
      dist[proxy.region.code] = (dist[proxy.region.code] ?? 0) + 1;
    }
    return dist;
  }

  /// مقداردهی اولیه: بارگذاری pool از Storage یا مقدار پیش‌فرض
  Future<void> initialize() async {
    if (_initialized) return;
    SecureLog.i('GeoProxyService: initializing');

    await _loadFromPrefs();
    if (_proxyPool.isEmpty) {
      await _buildDefaultPool();
    }

    _rebuildRegionIndex();
    _selectInitialGeo();
    _startIpRotation();

    _initialized = true;
    SecureLog.i('GeoProxyService: initialized with ${_proxyPool.length} proxies across ${_proxyByRegion.length} regions');
  }

  /// دریافت یک پراکسی تصادفی با وزن GEO
  ///
  /// [preferredGeo]: منطقه ترجیحی (اختیاری)
  /// [avoidGeo]: منطقه‌ای که نباید انتخاب شود (مثلاً GEO فعلی دستگاه)
  GeoProxy? getProxy({GeoRegion? preferredGeo, GeoRegion? avoidGeo}) {
    if (_proxyPool.isEmpty) return null;

    // اگر منطقه ترجیحی داده شده و پراکسی دارد
    if (preferredGeo != null) {
      final regionProxies = _proxyByRegion[preferredGeo.code];
      if (regionProxies != null && regionProxies.isNotEmpty) {
        return _weightedPick(regionProxies);
      }
    }

    // انتخاب تصادفی با وزن از کل pool (با در نظر گرفتن CPM)
    final candidates = _proxyPool.where((p) {
      if (!p.isActive) return false;
      if (avoidGeo != null && p.region == avoidGeo) return false;
      return true;
    }).toList();

    if (candidates.isEmpty) return null;
    return _weightedPick(candidates);
  }

  /// دریافت بهترین GEO برای یک وب‌سایت خاص بر اساس CPM ثبت شده
  GeoRegion getBestGeoForWebsite(String website) {
    // اگر برای این وب‌سایت CPM داریم، بهترین GEO را انتخاب کن
    if (_cpmByGeo.isNotEmpty) {
      final bestEntry = _cpmByGeo.entries
          .where((e) => e.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (bestEntry.isNotEmpty) {
        return GeoRegion.fromCode(bestEntry.first.key);
      }
    }

    // پیش‌فرض: توزیع وزن‌دار Tier 1
    return _weightedGeoSelection();
  }

  /// انتخاب یک GEO تصادفی با وزن CPM
  GeoRegion _weightedGeoSelection() {
    final tier1 = GeoRegion.tier1Regions;
    final tier2 = GeoRegion.tier2Regions;

    // ۷۰٪ شانس Tier 1, ۲۰٪ Tier 2, ۱۰٪ بقیه
    final roll = Random().nextDouble();
    List<GeoRegion> candidates;
    if (roll < 0.70) {
      candidates = tier1;
    } else if (roll < 0.90) {
      candidates = tier2;
    } else {
      candidates = GeoRegion.values
          .where((r) => r.tier == GeoRevenueTier.tier3 && r != GeoRegion.other)
          .toList();
    }

    if (candidates.isEmpty) {
      candidates = [GeoRegion.usa];
    }

    // وزن‌دار: هر چه CPM بالاتر، شانس بیشتر
    final totalWeight = candidates.fold<double>(
      0,
      (sum, r) => sum + r.trafficWeight * r.cpmAvg,
    );
    if (totalWeight <= 0) return candidates.first;

    var r = Random().nextDouble() * totalWeight;
    for (final region in candidates) {
      r -= region.trafficWeight * region.cpmAvg;
      if (r <= 0) return region;
    }
    return candidates.last;
  }

  /// دریافت لیست کامل پراکسی‌های یک منطقه
  List<GeoProxy> getProxiesForRegion(GeoRegion region) {
    return _proxyByRegion[region.code]?.where((p) => p.isActive).toList() ?? [];
  }

  /// تنظیم منطقه GEO فعلی و اعمال پراکسی متناظر
  Future<void> setGeo(GeoRegion region) async {
    if (region == _currentGeo) return;

    _currentGeo = region;
    await _saveActiveGeo();

    // ارسال به WebView از طریق MethodChannel (برای اعمال پراکسی)
    await _applyProxyToWebView();

    SecureLog.d('GeoProxyService: switched to ${region.code}');
  }

  /// تغییر اجباری GEO (چرخش IP)
  Future<void> rotateGeo() async {
    final newGeo = _weightedGeoSelection();
    await setGeo(newGeo);
    SecureLog.d('GeoProxyService: rotated to ${newGeo.code} (IP rotation)');
  }

  /// ثبت CPM مشاهده شده برای یک GEO (برای بهبود انتخاب‌های بعدی)
  void recordCpm(String geoCode, double cpm) {
    _cpmByGeo[geoCode] = cpm;
    // میانگین متحرک با وزن ۰.۳
    if (_cpmByGeo.containsKey(geoCode)) {
      _cpmByGeo[geoCode] = _cpmByGeo[geoCode]! * 0.7 + cpm * 0.3;
    }
  }

  /// توقف سرویس و پاکسازی
  void dispose() {
    _isStopped = true;
    _rotationTimer?.cancel();
    _rotationTimer = null;
    _proxyPool.clear();
    _proxyByRegion.clear();
    _cpmByGeo.clear();
    _initialized = false;
    SecureLog.i('GeoProxyService: disposed');
  }

  // ─── Management ──────────────────────────────────────────────

  /// افزودن پراکسی جدید به pool
  Future<void> addProxy(GeoProxy proxy) async {
    _proxyPool.add(proxy);
    _proxyByRegion
        .putIfAbsent(proxy.region.code, () => [])
        .add(proxy);
    await _savePool();
  }

  /// حذف پراکسی از pool
  Future<void> removeProxy(String proxyId) async {
    _proxyPool.removeWhere((p) => p.id == proxyId);
    _rebuildRegionIndex();
    await _savePool();
  }

  /// به‌روزرسانی پیکربندی از سرور (Pool دریافت شده از API)
  Future<void> updateFromRemote(List<GeoProxy> proxies) async {
    _proxyPool.clear();
    _proxyPool.addAll(proxies);
    _rebuildRegionIndex();
    await _savePool();
    SecureLog.i('GeoProxyService: updated pool from remote (${proxies.length} proxies)');
  }

  /// گرفتن آمار GEO برای Dashboard
  GeoStats computeGeoStats(List<PerGeoRevenue> analytics) {
    if (analytics.isEmpty) {
      return GeoStats(
        byGeo: [],
        totalRevenueUsd: 0,
        avgCpmOverall: 0,
        potentialRevenueAtTier1Cpm: 0,
        revenueGap: 0,
        topGeoCode: _currentGeo.code,
        geoDiversityScore: 0,
        activeProxyCount: activeProxyCount,
        proxyDistribution: proxyDistribution,
      );
    }

    final totalRev = analytics.fold<double>(0, (s, g) => s + g.totalRevenueUsd);
    final totalClicks = analytics.fold<int>(0, (s, g) => s + g.clickCount);
    final avgCpm = totalClicks > 0
        ? analytics.fold<double>(
            0, (s, g) => s + g.avgCpm * g.clickCount) /
            totalClicks
        : 0;

    // CPM میانگین Tier 1: ۶.۰
    const tier1AvgCpm = 6.0;
    final totalImpressions = analytics.fold<int>(0, (s, g) => s + g.impressionCount);
    final potentialRevenue = totalImpressions / 1000 * tier1AvgCpm;

    final topGeo = analytics.isNotEmpty
        ? analytics.reduce((a, b) =>
            a.totalRevenueUsd >= b.totalRevenueUsd ? a : b)
        : null;

    // شاخص تنوع GEO (0-1): هر چه تعداد GEOهای فعال بیشتر باشد، بالاتر
    final activeGeos = analytics.where((g) => g.totalRevenueUsd > 0).length;
    final diversityScore = (activeGeos / GeoRegion.values.length).clamp(0.0, 1.0);

    return GeoStats(
      byGeo: analytics,
      totalRevenueUsd: totalRev,
      avgCpmOverall: avgCpm.toDouble(),
      potentialRevenueAtTier1Cpm: potentialRevenue,
      revenueGap: potentialRevenue - totalRev,
      topGeoCode: topGeo?.geoCode ?? _currentGeo.code,
      geoDiversityScore: diversityScore,
      activeProxyCount: activeProxyCount,
      proxyDistribution: proxyDistribution,
    );
  }

  // ─── Private Methods ──────────────────────────────────────────

  /// بارگذاری pool از SharedPreferences
  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefProxyPool);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        _proxyPool.addAll(
          list.map((e) => GeoProxy.fromJson(e as Map<String, dynamic>)),
        );
      }

      final activeGeoRaw = prefs.getString(_kPrefActiveGeo);
      if (activeGeoRaw != null && activeGeoRaw.isNotEmpty) {
        _currentGeo = GeoRegion.fromCode(activeGeoRaw);
      }
    } catch (e) {
      SecureLog.w('GeoProxyService: load from prefs failed', error: e);
    }
  }

  /// ساختن pool پیش‌فرض از BuildSecrets
  Future<void> _buildDefaultPool() async {
    // پراکسی‌های پیش‌فرض از طریق BuildSecrets
    final geoConfigRaw = BuildSecrets.geoProxyConfig;
    if (geoConfigRaw.isNotEmpty) {
      try {
        final config = jsonDecode(geoConfigRaw) as Map<String, dynamic>;
        final proxies = config['proxies'] as List<dynamic>? ?? [];
        _proxyPool.addAll(
          proxies
              .map((e) => GeoProxy.fromJson(e as Map<String, dynamic>))
              .where((p) => p.host.isNotEmpty),
        );
        SecureLog.d('GeoProxyService: built pool from build secrets (${_proxyPool.length} proxies)');
      } catch (e) {
        SecureLog.w('GeoProxyService: build secrets parse failed', error: e);
      }
    }

    // اگر BuildSecrets خالی بود، pool پیش‌فرض برای نمایش ایجاد کن
    if (_proxyPool.isEmpty) {
      _proxyPool.addAll(_createDefaultPool());
      SecureLog.d('GeoProxyService: created default demo pool (${_proxyPool.length} proxies)');
    }
  }

  /// ایجاد pool پیش‌فرض برای GEOهای Tier 1
  /// این پراکسی‌ها placeholder هستند و باید توسط Backend جایگزین شوند
  List<GeoProxy> _createDefaultPool() {
    final proxies = <GeoProxy>[];
    var id = 0;

    for (final region in GeoRegion.tier1Regions) {
      // ۲-۴ پراکسی برای هر Tier 1
      final count = region == GeoRegion.usa ? 4 : 2;
      for (var i = 0; i < count; i++) {
        id++;
        // مقدار host و port placeholder — در عمل از Backend می‌آید
        proxies.add(GeoProxy(
          id: 'geo-default-${region.code.toLowerCase()}-$id',
          region: region,
          host: 'proxy-${region.code.toLowerCase()}-$id.example.com',
          port: 3128 + i,
          protocol: 'http',
          isActive: true,
        ));
      }
    }

    // تعدادی برای Tier 2
    for (final region in GeoRegion.tier2Regions) {
      id++;
      proxies.add(GeoProxy(
        id: 'geo-default-${region.code.toLowerCase()}-$id',
        region: region,
        host: 'proxy-${region.code.toLowerCase()}-$id.example.com',
        port: 3128,
        protocol: 'http',
        isActive: true,
      ));
    }

    return proxies;
  }

  /// بازسازی ایندکس منطقه‌ای
  void _rebuildRegionIndex() {
    _proxyByRegion.clear();
    for (final proxy in _proxyPool) {
      _proxyByRegion
          .putIfAbsent(proxy.region.code, () => [])
          .add(proxy);
    }
  }

  /// انتخاب GEO اولیه با وزن
  void _selectInitialGeo() {
    // ۸۰٪ شانس شروع با Tier 1
    if (Random().nextDouble() < 0.8) {
      final tier1 = GeoRegion.tier1Regions;
      _currentGeo = tier1[Random().nextInt(tier1.length)];
    } else {
      _currentGeo = _weightedGeoSelection();
    }
    SecureLog.d('GeoProxyService: initial geo = ${_currentGeo.code}');
  }

  /// شروع تایمر چرخش IP
  /// [PERF-FIX] Incorporates exponential backoff after consecutive failures
  /// to avoid hammering the native layer when it's unresponsive.
  void _startIpRotation() {
    _rotationTimer?.cancel();
    _scheduleNextRotation();
  }

  void _scheduleNextRotation() {
    _rotationTimer?.cancel();
    final baseInterval = _ipRotationMin +
        Duration(
          milliseconds: Random().nextInt(
            _ipRotationMax.inMilliseconds - _ipRotationMin.inMilliseconds,
          ),
        );
    // [PERF-FIX] Backoff: multiply interval by failCount (capped at 3x)
    final factor = (_rotationFailCount + 1).clamp(1, _rotationMaxBackoffFactor);
    final interval = Duration(milliseconds: baseInterval.inMilliseconds * factor);

    _rotationTimer = Timer.periodic(interval, (_) async {
      if (_isStopped) return;
      try {
        await rotateGeo();
        // [PERF-FIX] Reset backoff on success
        _rotationFailCount = 0;
      } catch (e) {
        _rotationFailCount++;
        SecureLog.w('GeoProxyService: IP rotation failed (fail #$_rotationFailCount)', error: e);
      }
      // [PERF-FIX] Reschedule with updated backoff
      _scheduleNextRotation();
    });
    SecureLog.d('GeoProxyService: IP rotation every ${interval.inMinutes} min (backoff=$factor)');
  }

  /// انتخاب وزن‌دار از لیست پراکسی‌ها
  GeoProxy _weightedPick(List<GeoProxy> proxies) {
    if (proxies.length == 1) return proxies.first;

    // وزن‌دهی بر اساس CPM منطقه
    final weights = proxies.map((p) {
      final cpm = _cpmByGeo[p.region.code];
      return cpm != null ? cpm : p.region.cpmAvg;
    }).toList();

    final totalWeight = weights.fold<double>(0, (s, w) => s + w);
    if (totalWeight <= 0) return proxies[Random().nextInt(proxies.length)];

    var r = Random().nextDouble() * totalWeight;
    for (var i = 0; i < proxies.length; i++) {
      r -= weights[i];
      if (r <= 0) return proxies[i];
    }
    return proxies.last;
  }

  /// اعمال پراکسی فعلی به WebView از طریق MethodChannel
  Future<void> _applyProxyToWebView() async {
    final proxy = getProxy(preferredGeo: _currentGeo);
    if (proxy == null) return;

    try {
      await _ch.invokeMethod<void>('tspSetGeoProxy', {
        'geo': _currentGeo.code,
        'proxy_url': proxy.proxyUrl,
        'host': proxy.host,
        'port': proxy.port,
        'protocol': proxy.protocol,
        'username': proxy.username ?? '',
        'password': proxy.password ?? '',
        'rotation_minutes': _ipRotationMin.inMinutes,
      });
    } catch (e) {
      SecureLog.w('GeoProxyService: _applyProxyToWebView failed (native not ready)', error: e);
    }
  }

  /// ذخیره pool در SharedPreferences
  Future<void> _savePool() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_proxyPool.map((p) => p.toJson()).toList());
      await prefs.setString(_kPrefProxyPool, raw);
    } catch (e) {
      SecureLog.w('GeoProxyService: save pool failed', error: e);
    }
  }

  /// ذخیره GEO فعال
  Future<void> _saveActiveGeo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefActiveGeo, _currentGeo.code);
    } catch (e) {
      SecureLog.w('GeoProxyService: save active geo failed', error: e);
    }
  }
}
