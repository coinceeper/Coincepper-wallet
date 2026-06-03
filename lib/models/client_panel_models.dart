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
    return id.substring(0, 8);
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
