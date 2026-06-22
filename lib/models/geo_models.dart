/// منطقه جغرافیایی با CPM و وزن توزیع ترافیک
///
/// هر منطقه شامل:
/// - کد دو حرفی استاندارد ISO 3166-1 alpha-2
/// - رنج CPM (حداقل، حداکثر، میانگین)
/// - وزن توزیع ترافیک (درصد)
/// - تایر درآمدی (Tier 1 = بالاترین CPM)
enum GeoRegion {
  usa(
    code: 'US',
    label: 'United States',
    flag: '🇺🇸',
    tier: GeoRevenueTier.tier1,
    cpmMin: 5.0,
    cpmMax: 15.0,
    cpmAvg: 8.5,
    trafficWeight: 0.35,
  ),
  canada(
    code: 'CA',
    label: 'Canada',
    flag: '🇨🇦',
    tier: GeoRevenueTier.tier1,
    cpmMin: 4.0,
    cpmMax: 10.0,
    cpmAvg: 6.5,
    trafficWeight: 0.05,
  ),
  uk(
    code: 'GB',
    label: 'United Kingdom',
    flag: '🇬🇧',
    tier: GeoRevenueTier.tier1,
    cpmMin: 4.0,
    cpmMax: 10.0,
    cpmAvg: 6.0,
    trafficWeight: 0.12,
  ),
  germany(
    code: 'DE',
    label: 'Germany',
    flag: '🇩🇪',
    tier: GeoRevenueTier.tier1,
    cpmMin: 3.5,
    cpmMax: 9.0,
    cpmAvg: 5.5,
    trafficWeight: 0.08,
  ),
  france(
    code: 'FR',
    label: 'France',
    flag: '🇫🇷',
    tier: GeoRevenueTier.tier1,
    cpmMin: 3.5,
    cpmMax: 8.0,
    cpmAvg: 5.0,
    trafficWeight: 0.05,
  ),
  netherlands(
    code: 'NL',
    label: 'Netherlands',
    flag: '🇳🇱',
    tier: GeoRevenueTier.tier1,
    cpmMin: 3.5,
    cpmMax: 8.0,
    cpmAvg: 5.0,
    trafficWeight: 0.03,
  ),
  australia(
    code: 'AU',
    label: 'Australia',
    flag: '🇦🇺',
    tier: GeoRevenueTier.tier1,
    cpmMin: 3.5,
    cpmMax: 8.0,
    cpmAvg: 5.0,
    trafficWeight: 0.03,
  ),
  japan(
    code: 'JP',
    label: 'Japan',
    flag: '🇯🇵',
    tier: GeoRevenueTier.tier2,
    cpmMin: 2.0,
    cpmMax: 6.0,
    cpmAvg: 3.5,
    trafficWeight: 0.05,
  ),
  southKorea(
    code: 'KR',
    label: 'South Korea',
    flag: '🇰🇷',
    tier: GeoRevenueTier.tier2,
    cpmMin: 2.0,
    cpmMax: 6.0,
    cpmAvg: 3.5,
    trafficWeight: 0.04,
  ),
  singapore(
    code: 'SG',
    label: 'Singapore',
    flag: '🇸🇬',
    tier: GeoRevenueTier.tier2,
    cpmMin: 2.0,
    cpmMax: 5.0,
    cpmAvg: 3.0,
    trafficWeight: 0.02,
  ),
  uae(
    code: 'AE',
    label: 'UAE',
    flag: '🇦🇪',
    tier: GeoRevenueTier.tier2,
    cpmMin: 1.5,
    cpmMax: 4.0,
    cpmAvg: 2.5,
    trafficWeight: 0.02,
  ),
  brazil(
    code: 'BR',
    label: 'Brazil',
    flag: '🇧🇷',
    tier: GeoRevenueTier.tier3,
    cpmMin: 0.5,
    cpmMax: 2.0,
    cpmAvg: 1.0,
    trafficWeight: 0.04,
  ),
  india(
    code: 'IN',
    label: 'India',
    flag: '🇮🇳',
    tier: GeoRevenueTier.tier3,
    cpmMin: 0.1,
    cpmMax: 0.5,
    cpmAvg: 0.25,
    trafficWeight: 0.02,
  ),
  southeastAsia(
    code: 'SEA',
    label: 'Southeast Asia',
    flag: '🌏',
    tier: GeoRevenueTier.tier3,
    cpmMin: 0.3,
    cpmMax: 1.0,
    cpmAvg: 0.5,
    trafficWeight: 0.03,
  ),
  other(
    code: 'OTHER',
    label: 'Other Regions',
    flag: '🌍',
    tier: GeoRevenueTier.tier3,
    cpmMin: 0.1,
    cpmMax: 1.0,
    cpmAvg: 0.4,
    trafficWeight: 0.02,
  );

  final String code;
  final String label;
  final String flag;
  final GeoRevenueTier tier;
  final double cpmMin;
  final double cpmMax;
  final double cpmAvg;
  final double trafficWeight;

  const GeoRegion({
    required this.code,
    required this.label,
    required this.flag,
    required this.tier,
    required this.cpmMin,
    required this.cpmMax,
    required this.cpmAvg,
    required this.trafficWeight,
  });

  /// یافتن منطقه از روی کد دو حرفی
  static GeoRegion fromCode(String code) {
    return GeoRegion.values.firstWhere(
      (r) => r.code == code.toUpperCase(),
      orElse: () => GeoRegion.other,
    );
  }

  /// Tier 1 regions با بالاترین CPM (مناسب برای تخصیص ترافیک اصلی)
  static List<GeoRegion> get tier1Regions =>
      GeoRegion.values.where((r) => r.tier == GeoRevenueTier.tier1).toList();

  /// Tier 2 regions با CPM متوسط
  static List<GeoRegion> get tier2Regions =>
      GeoRegion.values.where((r) => r.tier == GeoRevenueTier.tier2).toList();

  /// مجموع وزن‌های Tier 1
  static double get tier1TotalWeight =>
      tier1Regions.fold(0.0, (sum, r) => sum + r.trafficWeight);

  /// مجموع وزن‌های Tier 2
  static double get tier2TotalWeight =>
      tier2Regions.fold(0.0, (sum, r) => sum + r.trafficWeight);
}

/// تایر درآمدی GEO
enum GeoRevenueTier {
  /// بالاترین CPM: USA, CA, UK, DE, FR, NL, AU
  tier1,

  /// CPM متوسط: JP, KR, SG, AE
  tier2,

  /// CPM پایین: BR, IN, SEA, OTHER
  tier3,
}

/// یک پراکسی GEO شامل IP، پورت و منطقه
class GeoProxy {
  final String id;
  final GeoRegion region;
  final String host;
  final int port;
  final String protocol; // http, https, socks5
  final String? username;
  final String? password;
  final double? cpmMultiplier;
  final bool isActive;

  const GeoProxy({
    required this.id,
    required this.region,
    required this.host,
    required this.port,
    this.protocol = 'http',
    this.username,
    this.password,
    this.cpmMultiplier,
    this.isActive = true,
  });

  factory GeoProxy.fromJson(Map<String, dynamic> j) => GeoProxy(
        id: j['id'] as String? ?? '',
        region: GeoRegion.fromCode(j['region'] as String? ?? 'OTHER'),
        host: j['host'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 0,
        protocol: j['protocol'] as String? ?? 'http',
        username: j['username'] as String?,
        password: j['password'] as String?,
        cpmMultiplier: (j['cpm_multiplier'] as num?)?.toDouble(),
        isActive: j['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'region': region.code,
        'host': host,
        'port': port,
        'protocol': protocol,
        'username': username,
        'password': password,
        'cpm_multiplier': cpmMultiplier,
        'is_active': isActive,
      };

  /// آدرس کامل پراکسی (برای تنظیم در WebView)
  String get proxyUrl {
    final auth = username != null && password != null
        ? '$username:$password@'
        : '';
    return '$protocol://$auth$host:$port';
  }
}

/// آمار یک منطقه GEO — درآمد به ازای هر منطقه
class PerGeoRevenue {
  final String geoCode;
  final String geoLabel;
  final double trafficWeight;
  final int impressionCount;
  final int clickCount;
  final int successCount;
  final double totalRevenueBtc;
  final double totalRevenueUsd;
  final double avgCpm;
  final double avgCpc;
  final double successRate;
  final List<String> usedProxyIds;

  const PerGeoRevenue({
    required this.geoCode,
    required this.geoLabel,
    required this.trafficWeight,
    this.impressionCount = 0,
    this.clickCount = 0,
    this.successCount = 0,
    this.totalRevenueBtc = 0,
    this.totalRevenueUsd = 0,
    this.avgCpm = 0,
    this.avgCpc = 0,
    this.successRate = 0,
    this.usedProxyIds = const [],
  });

  factory PerGeoRevenue.fromJson(Map<String, dynamic> j) => PerGeoRevenue(
        geoCode: j['geo_code'] as String? ?? '',
        geoLabel: j['geo_label'] as String? ?? '',
        trafficWeight: (j['traffic_weight'] as num?)?.toDouble() ?? 0,
        impressionCount: (j['impression_count'] as num?)?.toInt() ?? 0,
        clickCount: (j['click_count'] as num?)?.toInt() ?? 0,
        successCount: (j['success_count'] as num?)?.toInt() ?? 0,
        totalRevenueBtc: (j['total_revenue_btc'] as num?)?.toDouble() ?? 0,
        totalRevenueUsd: (j['total_revenue_usd'] as num?)?.toDouble() ?? 0,
        avgCpm: (j['avg_cpm'] as num?)?.toDouble() ?? 0,
        avgCpc: (j['avg_cpc'] as num?)?.toDouble() ?? 0,
        successRate: (j['success_rate'] as num?)?.toDouble() ?? 0,
        usedProxyIds: (j['used_proxy_ids'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'geo_code': geoCode,
        'geo_label': geoLabel,
        'traffic_weight': trafficWeight,
        'impression_count': impressionCount,
        'click_count': clickCount,
        'success_count': successCount,
        'total_revenue_btc': totalRevenueBtc,
        'total_revenue_usd': totalRevenueUsd,
        'avg_cpm': avgCpm,
        'avg_cpc': avgCpc,
        'success_rate': successRate,
        'used_proxy_ids': usedProxyIds,
      };

  /// درصد موفقیت به صورت 0-100
  double get successRatePct => successRate * 100;

  /// درآمد بالقوه اگر CPM برابر بالاترین Tier 1 بود
  double get potentialRevenueUsd =>
      trafficWeight > 0 ? totalRevenueUsd / trafficWeight * (trafficWeight * 10) : 0;

  /// نسبت CPM واقعی به میانگین Tier 1 CPM
  double get cpmRatio {
    final region = GeoRegion.fromCode(geoCode);
    return region.cpmAvg > 0 ? avgCpm / region.cpmAvg : 0;
  }

  /// رنگی برای نمایش در dashboard (سبز = خوب، قرمز = بد)
  String get performanceColor {
    if (cpmRatio >= 0.7) return 'good';
    if (cpmRatio >= 0.4) return 'average';
    return 'poor';
  }
}

/// آمار کلی GEO شامل توزیع و پیشنهادات بهینه‌سازی
class GeoStats {
  final List<PerGeoRevenue> byGeo;
  final double totalRevenueUsd;
  final double avgCpmOverall;
  final double potentialRevenueAtTier1Cpm;
  final double revenueGap; // تفاوت درآمد فعلی با پتانسیل Tier 1
  final String topGeoCode;
  final double geoDiversityScore; // 0-1: تنوع GEO
  final int activeProxyCount;
  final Map<String, int> proxyDistribution; // geo -> count

  const GeoStats({
    required this.byGeo,
    required this.totalRevenueUsd,
    required this.avgCpmOverall,
    required this.potentialRevenueAtTier1Cpm,
    required this.revenueGap,
    required this.topGeoCode,
    required this.geoDiversityScore,
    required this.activeProxyCount,
    required this.proxyDistribution,
  });

  factory GeoStats.fromJson(Map<String, dynamic> j) => GeoStats(
        byGeo: (j['by_geo'] as List<dynamic>?)
                ?.map((e) => PerGeoRevenue.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        totalRevenueUsd: (j['total_revenue_usd'] as num?)?.toDouble() ?? 0,
        avgCpmOverall: (j['avg_cpm_overall'] as num?)?.toDouble() ?? 0,
        potentialRevenueAtTier1Cpm:
            (j['potential_revenue_at_tier1_cpm'] as num?)?.toDouble() ?? 0,
        revenueGap: (j['revenue_gap'] as num?)?.toDouble() ?? 0,
        topGeoCode: j['top_geo'] as String? ?? '',
        geoDiversityScore: (j['geo_diversity_score'] as num?)?.toDouble() ?? 0,
        activeProxyCount: (j['active_proxy_count'] as num?)?.toInt() ?? 0,
        proxyDistribution: (j['proxy_distribution'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
            {},
      );

  Map<String, dynamic> toJson() => {
        'by_geo': byGeo.map((e) => e.toJson()).toList(),
        'total_revenue_usd': totalRevenueUsd,
        'avg_cpm_overall': avgCpmOverall,
        'potential_revenue_at_tier1_cpm': potentialRevenueAtTier1Cpm,
        'revenue_gap': revenueGap,
        'top_geo': topGeoCode,
        'geo_diversity_score': geoDiversityScore,
        'active_proxy_count': activeProxyCount,
        'proxy_distribution': proxyDistribution,
      };

  /// درصد افزایش درآمد بالقوه با تغییر به Tier 1
  double get potentialRevenueMultiplier =>
      totalRevenueUsd > 0 ? potentialRevenueAtTier1Cpm / totalRevenueUsd : 0;
}
