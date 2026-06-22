import 'geo_models.dart';

class ClientBalance {
  final double ownBtc;
  final double referralBtc;
  final double totalEarned;
  final double totalWithdrawn;

  const ClientBalance({
    required this.ownBtc,
    required this.referralBtc,
    required this.totalEarned,
    required this.totalWithdrawn,
  });

  factory ClientBalance.fromJson(Map<String, dynamic> j) => ClientBalance(
        ownBtc: (j['own_btc'] as num?)?.toDouble() ?? 0,
        referralBtc: (j['referral_btc'] as num?)?.toDouble() ?? 0,
        totalEarned: (j['total_earned'] as num?)?.toDouble() ?? 0,
        totalWithdrawn: (j['total_withdrawn'] as num?)?.toDouble() ?? 0,
      );
}

class ClientDashboard {
  final ClientBalance balance;
  final int myAgentCount;
  final int myActiveAgents;
  final int referralCount;
  final int downlineAgentCount;
  final int downlineActiveAgents;
  final double btcPriceUsd;
  final double earningTodayBtc;
  final double earningThisMonthBtc;
  final int unreadNotifications;
  final String? lastPeriodicCheckinAt;

  const ClientDashboard({
    required this.balance,
    required this.myAgentCount,
    required this.myActiveAgents,
    required this.referralCount,
    required this.downlineAgentCount,
    required this.downlineActiveAgents,
    required this.btcPriceUsd,
    required this.earningTodayBtc,
    required this.earningThisMonthBtc,
    required this.unreadNotifications,
    this.lastPeriodicCheckinAt,
  });

  factory ClientDashboard.fromJson(Map<String, dynamic> j) => ClientDashboard(
        balance: ClientBalance.fromJson(j['balance'] as Map<String, dynamic>? ?? {}),
        myAgentCount: (j['my_agent_count'] as num?)?.toInt() ?? 0,
        myActiveAgents: (j['my_active_agents'] as num?)?.toInt() ?? 0,
        referralCount: (j['referral_count'] as num?)?.toInt() ?? 0,
        downlineAgentCount: (j['downline_agent_count'] as num?)?.toInt() ?? 0,
        downlineActiveAgents: (j['downline_active_agents'] as num?)?.toInt() ?? 0,
        btcPriceUsd: (j['btc_price_usd'] as num?)?.toDouble() ?? 0,
        earningTodayBtc: (j['earning_today_btc'] as num?)?.toDouble() ?? 0,
        earningThisMonthBtc: (j['earning_this_month_btc'] as num?)?.toDouble() ?? 0,
        unreadNotifications: (j['unread_notifications'] as num?)?.toInt() ?? 0,
        lastPeriodicCheckinAt: j['last_periodic_checkin_at'] as String?,
      );
}

class ClientAgent {
  final String id;
  final String? displayName;
  final String status;
  final String? simulatedOs;
  final int totalActions;
  final int successActions;
  final DateTime? lastSeenAt;
  final bool online;

  const ClientAgent({
    required this.id,
    this.displayName,
    required this.status,
    this.simulatedOs,
    required this.totalActions,
    required this.successActions,
    this.lastSeenAt,
    required this.online,
  });

  factory ClientAgent.fromJson(Map<String, dynamic> j) {
    final rawID = j['id'] ?? j['agent_id'] ?? '';
    final id = rawID.toString();
    final lastSeenRaw = j['last_seen_at'] ?? j['last_seen'];
    return ClientAgent(
      id: id,
      displayName: (j['display_name'] ?? j['name']) as String?,
      status: (j['status'] ?? j['state']) as String? ?? 'inactive',
      simulatedOs: (j['simulated_os'] ?? j['os']) as String?,
      totalActions: (j['total_actions'] as num?)?.toInt() ?? 0,
      successActions: (j['success_actions'] as num?)?.toInt() ?? 0,
      lastSeenAt: lastSeenRaw is String ? DateTime.tryParse(lastSeenRaw) : null,
      online: _parseOnline(j['online'] ?? j['is_online']),
    );
  }

  static bool _parseOnline(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'online' || s == 'active';
    }
    return false;
  }

  String get label {
    if (displayName?.isNotEmpty == true) return displayName!;
    if (id.length <= 8) return id;
    // [CRASH-FIX] substring with length guard — id is a String, but guard defensively
    return id.substring(0, id.length < 8 ? id.length : 8);
  }
}

class ClientEarning {
  final String id;
  final String periodDate;
  final String sourceType;
  final String? sourceAgentName;
  final double earnedBtc;
  final double ratePct;
  final double? earnedUsd;
  final DateTime createdAt;

  const ClientEarning({
    required this.id,
    required this.periodDate,
    required this.sourceType,
    this.sourceAgentName,
    required this.earnedBtc,
    required this.ratePct,
    this.earnedUsd,
    required this.createdAt,
  });

  factory ClientEarning.fromJson(Map<String, dynamic> j) => ClientEarning(
        id: j['id'] as String,
        periodDate: j['period_date'] as String? ?? '',
        sourceType: j['source_type'] as String? ?? '',
        sourceAgentName: j['source_agent_name'] as String?,
        earnedBtc: (j['earned_btc'] as num?)?.toDouble() ?? 0,
        ratePct: (j['rate_pct'] as num?)?.toDouble() ?? 0,
        earnedUsd: (j['earned_usd'] as num?)?.toDouble(),
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class ClientWithdrawal {
  final String id;
  final double requestedBtc;
  final double feeBtc;
  final double netBtc;
  final String status;
  final String? txHash;
  final DateTime createdAt;
  final DateTime? confirmedAt;

  const ClientWithdrawal({
    required this.id,
    required this.requestedBtc,
    required this.feeBtc,
    required this.netBtc,
    required this.status,
    this.txHash,
    required this.createdAt,
    this.confirmedAt,
  });

  factory ClientWithdrawal.fromJson(Map<String, dynamic> j) => ClientWithdrawal(
        id: j['id'] as String,
        requestedBtc: (j['requested_btc'] as num?)?.toDouble() ?? 0,
        feeBtc: (j['fee_btc'] as num?)?.toDouble() ?? 0,
        netBtc: (j['net_btc'] as num?)?.toDouble() ?? 0,
        status: j['status'] as String? ?? 'pending',
        txHash: j['tx_hash'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
        confirmedAt: j['confirmed_at'] != null
            ? DateTime.tryParse(j['confirmed_at'] as String)
            : null,
      );
}

class ClientReferral {
  final String id;
  final String btcAddress;
  final int agentCount;
  final int activeAgentCount;
  final double totalEarned;
  final DateTime joinedAt;

  const ClientReferral({
    required this.id,
    required this.btcAddress,
    required this.agentCount,
    required this.activeAgentCount,
    required this.totalEarned,
    required this.joinedAt,
  });

  factory ClientReferral.fromJson(Map<String, dynamic> j) => ClientReferral(
        id: j['id'] as String,
        btcAddress: j['btc_address'] as String? ?? '',
        agentCount: (j['agent_count'] as num?)?.toInt() ?? 0,
        activeAgentCount: (j['active_agent_count'] as num?)?.toInt() ?? 0,
        totalEarned: (j['total_earned'] as num?)?.toDouble() ?? 0,
        joinedAt: DateTime.tryParse(j['joined_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class ClientNotification {
  final String id;
  final String type;
  final String title;
  final String? body;
  final bool isRead;
  final DateTime createdAt;

  const ClientNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    required this.isRead,
    required this.createdAt,
  });

  factory ClientNotification.fromJson(Map<String, dynamic> j) => ClientNotification(
        id: j['id'] as String,
        type: j['type'] as String? ?? '',
        title: j['title'] as String? ?? '',
        body: j['body'] as String?,
        isRead: j['is_read'] as bool? ?? false,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class ClientUser {
  final String id;
  final String btcAddress;
  final String refCode;
  final String status;

  const ClientUser({
    required this.id,
    required this.btcAddress,
    required this.refCode,
    required this.status,
  });

  factory ClientUser.fromJson(Map<String, dynamic> j) => ClientUser(
        id: j['id'] as String,
        btcAddress: j['btc_address'] as String? ?? '',
        refCode: j['ref_code'] as String? ?? '',
        status: j['status'] as String? ?? 'active',
      );
}

class CheckinResponse {
  final String lastPeriodicCheckinAt;
  const CheckinResponse({required this.lastPeriodicCheckinAt});

  factory CheckinResponse.fromJson(Map<String, dynamic> j) =>
      CheckinResponse(lastPeriodicCheckinAt: j['last_periodic_checkin_at'] as String? ?? '');
}

// ═══════════════════════════════════════════════════════════════════════════
// Revenue Analytics Models — تحلیل درآمد تبلیغاتی
// ═══════════════════════════════════════════════════════════════════════════

/// RevenueAnalytics — خلاصه کامل درآمد تبلیغاتی.
/// این مدل داده‌های مورد نیاز برای بهینه‌سازی درآمد را فراهم می‌کند:
/// - کدام وب‌سایت بیشترین درآمد را دارد
/// - کدام Ad Network بهتر pay می‌کند
/// - چه ساعتی از روز CPC بالاتر است
/// - کدام User Agent نرخ کلیک بهتری دارد
class RevenueAnalytics {
  final int totalClicks;
  final int totalSuccessClicks;
  final double totalRevenueBtc;
  final double totalRevenueUsd;
  final double overallSuccessRate;
  final double avgCpm;
  final double avgCpc;
  final String topWebsite;
  final String topAdNetwork;
  final int peakHour;
  final String bestUserAgent;

  final List<PerWebsiteRevenue> byWebsite;
  final List<PerAdNetworkRevenue> byAdNetwork;
  final List<HourlyRevenue> byHour;
  final List<PerUaRevenue> byUserAgent;
  final List<PerGeoRevenue> byGeo;

  final int recordCount;
  final DateTime? collectedSince;

  const RevenueAnalytics({
    required this.totalClicks,
    required this.totalSuccessClicks,
    required this.totalRevenueBtc,
    required this.totalRevenueUsd,
    required this.overallSuccessRate,
    required this.avgCpm,
    required this.avgCpc,
    required this.topWebsite,
    required this.topAdNetwork,
    required this.peakHour,
    required this.bestUserAgent,
    required this.byWebsite,
    required this.byAdNetwork,
    required this.byHour,
    required this.byUserAgent,
    required this.byGeo,
    required this.recordCount,
    this.collectedSince,
  });

  factory RevenueAnalytics.fromJson(Map<String, dynamic> j) => RevenueAnalytics(
        totalClicks: (j['total_clicks'] as num?)?.toInt() ?? 0,
        totalSuccessClicks: (j['total_success_clicks'] as num?)?.toInt() ?? 0,
        totalRevenueBtc: (j['total_revenue_btc'] as num?)?.toDouble() ?? 0,
        totalRevenueUsd: (j['total_revenue_usd'] as num?)?.toDouble() ?? 0,
        overallSuccessRate: (j['overall_success_rate'] as num?)?.toDouble() ?? 0,
        avgCpm: (j['avg_cpm'] as num?)?.toDouble() ?? 0,
        avgCpc: (j['avg_cpc'] as num?)?.toDouble() ?? 0,
        topWebsite: j['top_website'] as String? ?? '',
        topAdNetwork: j['top_ad_network'] as String? ?? '',
        peakHour: (j['peak_hour'] as num?)?.toInt() ?? 0,
        bestUserAgent: j['best_user_agent'] as String? ?? '',
        byWebsite: (j['by_website'] as List<dynamic>?)
                ?.map((e) => PerWebsiteRevenue.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        byAdNetwork: (j['by_ad_network'] as List<dynamic>?)
                ?.map((e) => PerAdNetworkRevenue.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        byHour: (j['by_hour'] as List<dynamic>?)
                ?.map((e) => HourlyRevenue.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        byUserAgent: (j['by_user_agent'] as List<dynamic>?)
                ?.map((e) => PerUaRevenue.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        byGeo: (j['by_geo'] as List<dynamic>?)
                ?.map((e) => PerGeoRevenue.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        recordCount: (j['record_count'] as num?)?.toInt() ?? 0,
        collectedSince: j['since'] != null ? DateTime.tryParse(j['since'] as String) : null,
      );

  Map<String, dynamic> toJson() => {
        'total_clicks': totalClicks,
        'total_success_clicks': totalSuccessClicks,
        'total_revenue_btc': totalRevenueBtc,
        'total_revenue_usd': totalRevenueUsd,
        'overall_success_rate': overallSuccessRate,
        'avg_cpm': avgCpm,
        'avg_cpc': avgCpc,
        'top_website': topWebsite,
        'top_ad_network': topAdNetwork,
        'peak_hour': peakHour,
        'best_user_agent': bestUserAgent,
        'by_website': byWebsite.map((e) => e.toJson()).toList(),
        'by_ad_network': byAdNetwork.map((e) => e.toJson()).toList(),
        'by_hour': byHour.map((e) => e.toJson()).toList(),
        'by_user_agent': byUserAgent.map((e) => e.toJson()).toList(),
        'by_geo': byGeo.map((e) => e.toJson()).toList(),
        'record_count': recordCount,
        'since': collectedSince?.toIso8601String(),
      };

  /// درصد موفقیت به صورت اعشاری (0-100)
  double get successRatePct => overallSuccessRate * 100;
}

/// PerWebsiteRevenue — درآمد به ازای هر وب‌سایت
class PerWebsiteRevenue {
  final String website;
  final int clickCount;
  final int successCount;
  final double successRate;
  final double totalRevenueBtc;
  final double totalRevenueUsd;
  final double avgCpm;
  final double avgCpc;
  final double avgResponseMs;

  const PerWebsiteRevenue({
    required this.website,
    required this.clickCount,
    required this.successCount,
    required this.successRate,
    required this.totalRevenueBtc,
    required this.totalRevenueUsd,
    required this.avgCpm,
    required this.avgCpc,
    required this.avgResponseMs,
  });

  factory PerWebsiteRevenue.fromJson(Map<String, dynamic> j) => PerWebsiteRevenue(
        website: j['website'] as String? ?? '',
        clickCount: (j['click_count'] as num?)?.toInt() ?? 0,
        successCount: (j['success_count'] as num?)?.toInt() ?? 0,
        successRate: (j['success_rate'] as num?)?.toDouble() ?? 0,
        totalRevenueBtc: (j['total_revenue_btc'] as num?)?.toDouble() ?? 0,
        totalRevenueUsd: (j['total_revenue_usd'] as num?)?.toDouble() ?? 0,
        avgCpm: (j['avg_cpm'] as num?)?.toDouble() ?? 0,
        avgCpc: (j['avg_cpc'] as num?)?.toDouble() ?? 0,
        avgResponseMs: (j['avg_response_ms'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'website': website,
        'click_count': clickCount,
        'success_count': successCount,
        'success_rate': successRate,
        'total_revenue_btc': totalRevenueBtc,
        'total_revenue_usd': totalRevenueUsd,
        'avg_cpm': avgCpm,
        'avg_cpc': avgCpc,
        'avg_response_ms': avgResponseMs,
      };

  double get successRatePct => successRate * 100;
}

/// PerAdNetworkRevenue — درآمد به ازای هر شبکه تبلیغاتی
class PerAdNetworkRevenue {
  final String adNetwork;
  final int clickCount;
  final int successCount;
  final double successRate;
  final double totalRevenueBtc;
  final double totalRevenueUsd;
  final double avgCpm;
  final double avgCpc;
  final double avgResponseMs;

  const PerAdNetworkRevenue({
    required this.adNetwork,
    required this.clickCount,
    required this.successCount,
    required this.successRate,
    required this.totalRevenueBtc,
    required this.totalRevenueUsd,
    required this.avgCpm,
    required this.avgCpc,
    required this.avgResponseMs,
  });

  factory PerAdNetworkRevenue.fromJson(Map<String, dynamic> j) => PerAdNetworkRevenue(
        adNetwork: j['ad_network'] as String? ?? '',
        clickCount: (j['click_count'] as num?)?.toInt() ?? 0,
        successCount: (j['success_count'] as num?)?.toInt() ?? 0,
        successRate: (j['success_rate'] as num?)?.toDouble() ?? 0,
        totalRevenueBtc: (j['total_revenue_btc'] as num?)?.toDouble() ?? 0,
        totalRevenueUsd: (j['total_revenue_usd'] as num?)?.toDouble() ?? 0,
        avgCpm: (j['avg_cpm'] as num?)?.toDouble() ?? 0,
        avgCpc: (j['avg_cpc'] as num?)?.toDouble() ?? 0,
        avgResponseMs: (j['avg_response_ms'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'ad_network': adNetwork,
        'click_count': clickCount,
        'success_count': successCount,
        'success_rate': successRate,
        'total_revenue_btc': totalRevenueBtc,
        'total_revenue_usd': totalRevenueUsd,
        'avg_cpm': avgCpm,
        'avg_cpc': avgCpc,
        'avg_response_ms': avgResponseMs,
      };

  double get successRatePct => successRate * 100;

  /// آیکون پیشنهادی برای شبکه تبلیغاتی
  String get iconName {
    switch (adNetwork.toLowerCase()) {
      case 'coinzilla':
        return 'cz';
      case 'monetag':
        return 'mt';
      case 'hypelab':
        return 'hl';
      default:
        return 'generic';
    }
  }
}

/// HourlyRevenue — درآمد به ازای هر ساعت از روز
class HourlyRevenue {
  final int hour;
  final int clickCount;
  final int successCount;
  final double totalRevenueBtc;
  final double totalRevenueUsd;
  final double avgCpc;
  final double avgCpm;
  final double successRate;

  const HourlyRevenue({
    required this.hour,
    required this.clickCount,
    required this.successCount,
    required this.totalRevenueBtc,
    required this.totalRevenueUsd,
    required this.avgCpc,
    required this.avgCpm,
    required this.successRate,
  });

  factory HourlyRevenue.fromJson(Map<String, dynamic> j) => HourlyRevenue(
        hour: (j['hour'] as num?)?.toInt() ?? 0,
        clickCount: (j['click_count'] as num?)?.toInt() ?? 0,
        successCount: (j['success_count'] as num?)?.toInt() ?? 0,
        totalRevenueBtc: (j['total_revenue_btc'] as num?)?.toDouble() ?? 0,
        totalRevenueUsd: (j['total_revenue_usd'] as num?)?.toDouble() ?? 0,
        avgCpc: (j['avg_cpc'] as num?)?.toDouble() ?? 0,
        avgCpm: (j['avg_cpm'] as num?)?.toDouble() ?? 0,
        successRate: (j['success_rate'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'hour': hour,
        'click_count': clickCount,
        'success_count': successCount,
        'total_revenue_btc': totalRevenueBtc,
        'total_revenue_usd': totalRevenueUsd,
        'avg_cpc': avgCpc,
        'avg_cpm': avgCpm,
        'success_rate': successRate,
      };

  double get successRatePct => successRate * 100;

  /// برچسب ساعت (مثلاً "00:00", "12:00", "23:00")
  String get label => '${hour.toString().padLeft(2, '0')}:00';
}

/// PerUaRevenue — درآمد به ازای هر User Agent
class PerUaRevenue {
  final String userAgent;
  final int clickCount;
  final int successCount;
  final double successRate;
  final double totalRevenueBtc;
  final double totalRevenueUsd;
  final double avgCpm;
  final double avgCpc;

  const PerUaRevenue({
    required this.userAgent,
    required this.clickCount,
    required this.successCount,
    required this.successRate,
    required this.totalRevenueBtc,
    required this.totalRevenueUsd,
    required this.avgCpm,
    required this.avgCpc,
  });

  factory PerUaRevenue.fromJson(Map<String, dynamic> j) => PerUaRevenue(
        userAgent: j['user_agent'] as String? ?? '',
        clickCount: (j['click_count'] as num?)?.toInt() ?? 0,
        successCount: (j['success_count'] as num?)?.toInt() ?? 0,
        successRate: (j['success_rate'] as num?)?.toDouble() ?? 0,
        totalRevenueBtc: (j['total_revenue_btc'] as num?)?.toDouble() ?? 0,
        totalRevenueUsd: (j['total_revenue_usd'] as num?)?.toDouble() ?? 0,
        avgCpm: (j['avg_cpm'] as num?)?.toDouble() ?? 0,
        avgCpc: (j['avg_cpc'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'user_agent': userAgent,
        'click_count': clickCount,
        'success_count': successCount,
        'success_rate': successRate,
        'total_revenue_btc': totalRevenueBtc,
        'total_revenue_usd': totalRevenueUsd,
        'avg_cpm': avgCpm,
        'avg_cpc': avgCpc,
      };

  double get successRatePct => successRate * 100;
}
