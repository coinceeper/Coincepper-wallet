// =============================================================================
// 📋 NOTIFICATION TYPE ENUMS
// =============================================================================

/// All supported FCM notification types from the backend.
/// Used for deep-linking and routing notifications.
enum NotificationType {
  transactionReceived,
  send,
  receive,
  securityLogin,
  securityChange,
  securitySuspicious,
  priceAlert,
  volatilityAlert,
  portfolioSummary,
  gasAlert,
  networkStatus,
  networkUpgrade,
  newListing,
  reward,
  breakingNews,
  appUpdate,
  unknown;

  String get value {
    switch (this) {
      case NotificationType.transactionReceived:
        return 'transaction_received';
      case NotificationType.send:
        return 'send';
      case NotificationType.receive:
        return 'receive';
      case NotificationType.securityLogin:
        return 'security_login';
      case NotificationType.securityChange:
        return 'security_change';
      case NotificationType.securitySuspicious:
        return 'security_suspicious';
      case NotificationType.priceAlert:
        return 'price_alert';
      case NotificationType.volatilityAlert:
        return 'volatility_alert';
      case NotificationType.portfolioSummary:
        return 'portfolio_summary';
      case NotificationType.gasAlert:
        return 'gas_alert';
      case NotificationType.networkStatus:
        return 'network_status';
      case NotificationType.networkUpgrade:
        return 'network_upgrade';
      case NotificationType.newListing:
        return 'new_listing';
      case NotificationType.reward:
        return 'reward';
      case NotificationType.breakingNews:
        return 'breaking_news';
      case NotificationType.appUpdate:
        return 'app_update';
      case NotificationType.unknown:
        return 'unknown';
    }
  }

  static NotificationType fromString(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'transaction_received':
        return NotificationType.transactionReceived;
      case 'send':
        return NotificationType.send;
      case 'receive':
        return NotificationType.receive;
      case 'security_login':
        return NotificationType.securityLogin;
      case 'security_change':
        return NotificationType.securityChange;
      case 'security_suspicious':
        return NotificationType.securitySuspicious;
      case 'price_alert':
        return NotificationType.priceAlert;
      case 'volatility_alert':
        return NotificationType.volatilityAlert;
      case 'portfolio_summary':
        return NotificationType.portfolioSummary;
      case 'gas_alert':
        return NotificationType.gasAlert;
      case 'network_status':
        return NotificationType.networkStatus;
      case 'network_upgrade':
        return NotificationType.networkUpgrade;
      case 'new_listing':
        return NotificationType.newListing;
      case 'reward':
        return NotificationType.reward;
      case 'breaking_news':
        return NotificationType.breakingNews;
      case 'app_update':
        return NotificationType.appUpdate;
      default:
        return NotificationType.unknown;
    }
  }

  /// Android notification channel ID for this type.
  String get channelId {
    switch (this) {
      case NotificationType.transactionReceived:
      case NotificationType.send:
      case NotificationType.receive:
        return 'transactions';
      case NotificationType.securityLogin:
      case NotificationType.securityChange:
      case NotificationType.securitySuspicious:
        return 'security';
      case NotificationType.priceAlert:
      case NotificationType.volatilityAlert:
      case NotificationType.portfolioSummary:
        return 'price_alerts';
      case NotificationType.gasAlert:
      case NotificationType.networkStatus:
      case NotificationType.networkUpgrade:
        return 'network';
      case NotificationType.newListing:
      case NotificationType.reward:
      case NotificationType.breakingNews:
      case NotificationType.appUpdate:
        return 'engagement';
      case NotificationType.unknown:
        return 'engagement';
    }
  }
}

/// Severity levels for security notifications.
enum SecuritySeverity { info, warning, critical }

/// Alert type for price alerts.
/// - [above] / [below]: exact price triggers
/// - [percentUp] / [percentDown]: percentage-change triggers
enum PriceAlertType { above, below, percentUp, percentDown }

/// Serialization helpers for [PriceAlertType].
extension PriceAlertTypeX on PriceAlertType {
  /// Backend API string value.
  String get apiValue {
    switch (this) {
      case PriceAlertType.above:
        return 'above';
      case PriceAlertType.below:
        return 'below';
      case PriceAlertType.percentUp:
        return 'percent_up';
      case PriceAlertType.percentDown:
        return 'percent_down';
    }
  }

  /// Human-readable label key (for localization).
  String get labelKey {
    switch (this) {
      case PriceAlertType.above:
        return 'price_alerts_screen.above';
      case PriceAlertType.below:
        return 'price_alerts_screen.below';
      case PriceAlertType.percentUp:
        return 'price_alerts_screen.percent_up';
      case PriceAlertType.percentDown:
        return 'price_alerts_screen.percent_down';
    }
  }

  /// Parse from backend string.
  static PriceAlertType fromApi(String value) {
    switch (value) {
      case 'above':
        return PriceAlertType.above;
      case 'below':
        return PriceAlertType.below;
      case 'percent_up':
        return PriceAlertType.percentUp;
      case 'percent_down':
        return PriceAlertType.percentDown;
      default:
        return PriceAlertType.above;
    }
  }
}

// =============================================================================
// 📋 REQUEST MODELS
// =============================================================================

/// Device registration request body.
///
/// Matches the backend API spec:
/// ```json
/// {
///   "UserID": "...",
///   "WalletID": "...",
///   "DeviceToken": "...",
///   "DeviceName": "iPhone 15 Pro",
///   "DeviceType": "ios"
/// }
/// ```
class RegisterDeviceRequest {
  final String deviceToken;
  final String deviceType; // "android", "ios", "web"
  final String walletId;
  final String userId;
  final String deviceName;

  const RegisterDeviceRequest({
    required this.deviceToken,
    required this.deviceType,
    required this.walletId,
    required this.userId,
    this.deviceName = '',
  });

  Map<String, dynamic> toJson() => {
        'UserID': userId,
        'WalletID': walletId,
        'DeviceToken': deviceToken,
        'DeviceName': deviceName,
        'DeviceType': deviceType,
      };
}

/// New login detected request (P2 — Security).
class SecurityLoginRequest {
  final String userId;
  final String deviceName;
  final String deviceType; // "android", "ios", "web"
  final String ipAddress;
  final String? location;

  const SecurityLoginRequest({
    required this.userId,
    required this.deviceName,
    required this.deviceType,
    required this.ipAddress,
    this.location,
  });

  Map<String, dynamic> toJson() => {
        'UserID': userId,
        'DeviceName': deviceName,
        'DeviceType': deviceType,
        'IPAddress': ipAddress,
        if (location != null) 'Location': location,
      };
}

/// Security setting changed request (P2 — Security).
class SecurityChangeRequest {
  final String userId;
  final String changeType; // "password_changed", "pin_changed", "2fa_enabled", "2fa_disabled"
  final String deviceName;

  const SecurityChangeRequest({
    required this.userId,
    required this.changeType,
    required this.deviceName,
  });

  Map<String, dynamic> toJson() => {
        'UserID': userId,
        'ChangeType': changeType,
        'DeviceName': deviceName,
      };
}

/// Suspicious activity request (P2 — Security).
class SecuritySuspiciousRequest {
  final String userId;
  final String activityType; // "failed_login", "unusual_transaction", "new_ip"
  final String description;
  final String severity; // "info", "warning", "critical"

  const SecuritySuspiciousRequest({
    required this.userId,
    required this.activityType,
    required this.description,
    required this.severity,
  });

  Map<String, dynamic> toJson() => {
        'UserID': userId,
        'ActivityType': activityType,
        'Description': description,
        'Severity': severity,
      };
}

/// Price alert request (P3) — supports both exact-price and percentage-based alerts.
class PriceAlertRequest {
  final String userId;
  final String symbol;
  final double? targetPrice;
  final String alertType; // "above", "below", "percent_up", "percent_down"
  final double? targetPercent;

  const PriceAlertRequest({
    required this.userId,
    required this.symbol,
    this.targetPrice,
    required this.alertType,
    this.targetPercent,
  });

  Map<String, dynamic> toJson() => {
        'UserID': userId,
        'Symbol': symbol,
        'AlertType': alertType,
        if (targetPrice != null) 'TargetPrice': targetPrice,
        if (targetPercent != null) 'TargetPercent': targetPercent,
      };
}

/// Delete price alert request — deletes by ID or by Symbol+AlertType.
class DeletePriceAlertRequest {
  final String userId;
  final int? alertId;
  final String? symbol;
  final String? alertType;

  const DeletePriceAlertRequest({
    required this.userId,
    this.alertId,
    this.symbol,
    this.alertType,
  });

  Map<String, dynamic> toJson() => {
        'UserID': userId,
        if (alertId != null) 'AlertID': alertId,
        if (symbol != null) 'Symbol': symbol,
        if (alertType != null) 'AlertType': alertType,
      };
}

// =============================================================================
// 📋 RESPONSE MODELS
// =============================================================================

/// Generic API response wrapper used by notification endpoints.
class NotificationApiResponse {
  final bool success;
  final String? message;

  const NotificationApiResponse({
    required this.success,
    this.message,
  });

  factory NotificationApiResponse.fromJson(Map<String, dynamic> json) {
    return NotificationApiResponse(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String?,
    );
  }
}

/// Price alert item returned from GET /api/notifications/price-alerts/{UserID}.
class PriceAlertItem {
  final int? id;
  final String symbol;
  final double? targetPrice;
  final String alertType;
  final double? targetPercent;
  final double? referencePrice;
  final bool isActive;
  final String? createdAt;

  const PriceAlertItem({
    this.id,
    required this.symbol,
    this.targetPrice,
    required this.alertType,
    this.targetPercent,
    this.referencePrice,
    this.isActive = true,
    this.createdAt,
  });

  /// Whether this is a percentage-based alert.
  bool get isPercentAlert =>
      alertType == 'percent_up' || alertType == 'percent_down';

  /// Whether this is a price-based alert.
  bool get isPriceAlert => !isPercentAlert;

  /// Parsed [PriceAlertType] for convenience.
  PriceAlertType get typeEnum => PriceAlertTypeX.fromApi(alertType);

  factory PriceAlertItem.fromJson(Map<String, dynamic> json) {
    return PriceAlertItem(
      id: json['id'] as int?,
      symbol: json['symbol'] as String? ?? '',
      targetPrice: (json['target_price'] as num?)?.toDouble(),
      alertType: json['alert_type'] as String? ?? 'above',
      targetPercent: (json['target_percent'] as num?)?.toDouble(),
      referencePrice: (json['reference_price'] as num?)?.toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'symbol': symbol,
        'alert_type': alertType,
        if (targetPrice != null) 'target_price': targetPrice,
        if (targetPercent != null) 'target_percent': targetPercent,
        if (referencePrice != null) 'reference_price': referencePrice,
        'is_active': isActive,
        if (createdAt != null) 'created_at': createdAt,
      };
}

/// Bulk prices response from GET /api/notifications/price-alerts/prices.
class BulkPricesResponse {
  final bool success;
  final Map<String, double> prices;

  const BulkPricesResponse({
    required this.success,
    this.prices = const {},
  });

  factory BulkPricesResponse.fromJson(Map<String, dynamic> json) {
    final rawPrices = json['prices'] as Map<String, dynamic>? ?? {};
    return BulkPricesResponse(
      success: json['success'] as bool? ?? false,
      prices: rawPrices.map((k, v) => MapEntry(k.toUpperCase(), (v as num).toDouble())),
    );
  }
}

/// Response for GET /api/notifications/price-alerts/{UserID}.
class PriceAlertsResponse {
  final bool success;
  final List<PriceAlertItem> alerts;

  const PriceAlertsResponse({
    required this.success,
    this.alerts = const [],
  });

  factory PriceAlertsResponse.fromJson(Map<String, dynamic> json) {
    final rawList = json['alerts'] as List<dynamic>? ?? [];
    return PriceAlertsResponse(
      success: json['success'] as bool? ?? false,
      alerts: rawList
          .map((e) => PriceAlertItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

// =============================================================================
// 📋 ADMIN REQUEST MODELS (P4 — Network & Gas)
// =============================================================================

class NetworkStatusRequest {
  final String blockchain;
  final String status; // "maintenance", "outage", "degraded", "restored"
  final String message;

  const NetworkStatusRequest({
    required this.blockchain,
    required this.status,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
        'Blockchain': blockchain,
        'Status': status,
        'Message': message,
      };
}

class NetworkUpgradeRequest {
  final String blockchain;
  final String upgradeName;
  final String description;
  final String estimatedTime;

  const NetworkUpgradeRequest({
    required this.blockchain,
    required this.upgradeName,
    required this.description,
    required this.estimatedTime,
  });

  Map<String, dynamic> toJson() => {
        'Blockchain': blockchain,
        'UpgradeName': upgradeName,
        'Description': description,
        'EstimatedTime': estimatedTime,
      };
}

// =============================================================================
// 📋 ADMIN REQUEST MODELS (P5 — Engagement & Features)
// =============================================================================

class NewListingRequest {
  final String symbol;
  final String name;
  final String blockchain;
  final String description;

  const NewListingRequest({
    required this.symbol,
    required this.name,
    required this.blockchain,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
        'Symbol': symbol,
        'Name': name,
        'Blockchain': blockchain,
        'Description': description,
      };
}

class BreakingNewsRequest {
  final String title;
  final String body;
  final String? url;

  const BreakingNewsRequest({
    required this.title,
    required this.body,
    this.url,
  });

  Map<String, dynamic> toJson() => {
        'Title': title,
        'Body': body,
        if (url != null) 'URL': url,
      };
}

class AppUpdateRequest {
  final String version;
  final List<String> changes;
  final bool forceUpdate;

  const AppUpdateRequest({
    required this.version,
    required this.changes,
    this.forceUpdate = false,
  });

  Map<String, dynamic> toJson() => {
        'Version': version,
        'Changes': changes,
        'ForceUpdate': forceUpdate,
      };
}

class RewardRequest {
  final String userId;
  final String rewardType; // "staking", "airdrop", "cashback", "referral"
  final String amount;
  final String symbol;
  final String description;

  const RewardRequest({
    required this.userId,
    required this.rewardType,
    required this.amount,
    required this.symbol,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
        'UserID': userId,
        'RewardType': rewardType,
        'Amount': amount,
        'Symbol': symbol,
        'Description': description,
      };
}

class BroadcastRequest {
  final String title;
  final String body;
  final String type; // "general"

  const BroadcastRequest({
    required this.title,
    required this.body,
    this.type = 'general',
  });

  Map<String, dynamic> toJson() => {
        'Title': title,
        'Body': body,
        'Type': type,
      };
}

// =============================================================================
// 📋 FCM DATA PAYLOAD PARSER
// =============================================================================

/// Parsed FCM data payload for structured routing.
class FcmDataPayload {
  final NotificationType type;
  final String? transactionId;
  final String? txHash;
  final String? amount;
  final String? symbol;
  final String? direction;
  final String? fromAddress;
  final String? toAddress;
  final String? blockchain;
  final double? price;
  final double? targetPrice;
  final String? alertType;
  final String? title;
  final String? body;
  final String? url;
  final String? version;
  final String? rewardType;
  final String? rewardAmount;
  final String? rewardSymbol;
  final String? severity;
  final Map<String, dynamic> raw;

  const FcmDataPayload({
    required this.type,
    this.transactionId,
    this.txHash,
    this.amount,
    this.symbol,
    this.direction,
    this.fromAddress,
    this.toAddress,
    this.blockchain,
    this.price,
    this.targetPrice,
    this.alertType,
    this.title,
    this.body,
    this.url,
    this.version,
    this.rewardType,
    this.rewardAmount,
    this.rewardSymbol,
    this.severity,
    required this.raw,
  });

  factory FcmDataPayload.fromMap(Map<String, dynamic> data) {
    return FcmDataPayload(
      type: NotificationType.fromString(
          (data['type'] ?? '').toString()),
      transactionId: data['transaction_id']?.toString(),
      txHash: data['tx_hash']?.toString() ?? data['hash']?.toString(),
      amount: data['amount']?.toString(),
      symbol: data['symbol']?.toString() ?? data['token']?.toString(),
      direction: data['direction']?.toString(),
      fromAddress: data['from_address']?.toString(),
      toAddress: data['to_address']?.toString(),
      blockchain: data['blockchain']?.toString(),
      price: (data['price'] as num?)?.toDouble(),
      targetPrice: (data['target_price'] as num?)?.toDouble(),
      alertType: data['alert_type']?.toString(),
      title: data['title']?.toString(),
      body: data['body']?.toString() ?? data['message']?.toString(),
      url: data['url']?.toString(),
      version: data['version']?.toString(),
      rewardType: data['reward_type']?.toString(),
      rewardAmount: data['reward_amount']?.toString(),
      rewardSymbol: data['reward_symbol']?.toString(),
      severity: data['severity']?.toString(),
      raw: Map<String, dynamic>.from(data),
    );
  }
}
