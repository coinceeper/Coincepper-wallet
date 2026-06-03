import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../models/notification_models.dart';
import 'notification_helper.dart';

/// Maps FCM [RemoteMessage] payloads to local notifications & deep links.
///
/// Handles all 5 priority levels (P1–P5) with proper:
/// - Channel routing (5 standard Android channels)
/// - Notification display with appropriate formatting
/// - Deep linking via [GoRouter] for navigation
/// - FCM data payload parsing via [FcmDataPayload]
class PushNotificationRouter {
  /// Route an incoming FCM message to local notification.
  static Future<void> route(RemoteMessage message) async {
    final data = message.data;
    final payload = FcmDataPayload.fromMap(data);
    final title = message.notification?.title ??
        (data['title']?.toString().trim().isNotEmpty == true
            ? data['title'].toString()
            : 'CoinCeeper');
    final body = message.notification?.body ??
        data['body']?.toString() ??
        data['message']?.toString() ??
        '';

    debugPrint('🔔 Routing notification: type=${payload.type.value}');

    switch (payload.type) {
      // ── P1: Financial Transactions ────────────────────────────────────
      case NotificationType.transactionReceived:
      case NotificationType.send:
      case NotificationType.receive:
        await _routeTransaction(payload, title, body);
        return;

      // ── P2: Security & Account ────────────────────────────────────────
      case NotificationType.securityLogin:
        await NotificationHelper.showSecurityLoginNotification(
          deviceName: payload.body ?? 'New device',
          location: data['location']?.toString(),
        );
        return;
      case NotificationType.securityChange:
        await NotificationHelper.showSecurityChangeNotification(
          data['change_type']?.toString() ?? 'setting',
        );
        return;
      case NotificationType.securitySuspicious:
        await NotificationHelper.showSecuritySuspiciousNotification(
          description: payload.body ?? body,
          severity: payload.severity ?? 'info',
        );
        return;

      // ── P3: Price Alerts & Portfolio ─────────────────────────────────
      case NotificationType.priceAlert:
        await NotificationHelper.showPriceAlertNotification(
          currentPrice: payload.price ?? 0,
          symbol: payload.symbol ?? '',
          targetPrice: double.tryParse(data['target_price']?.toString() ?? '') ?? 0,
          alertType: data['alert_type']?.toString() ?? '',
          customTitle: title,
          customBody: body,
        );
        return;
      case NotificationType.volatilityAlert:
        await NotificationHelper.showNotification(
          channelId: NotificationHelper.channelPriceAlerts,
          title: '📊 Volatility Alert',
          body: body.isNotEmpty ? body : 'High volatility detected',
          largeIconAsset: 'logo',
        );
        return;
      case NotificationType.portfolioSummary:
        await NotificationHelper.showNotification(
          channelId: NotificationHelper.channelPriceAlerts,
          title: '📈 Portfolio Summary',
          body: body.isNotEmpty ? body : 'Your daily portfolio summary',
          largeIconAsset: 'logo',
        );
        return;

      // ── P4: Network & Gas ────────────────────────────────────────────
      case NotificationType.gasAlert:
        final blockchain = data['blockchain']?.toString() ?? 'Network';
        final gasPrice = (data['gas_price'] as num?)?.toDouble() ?? 0;
        final level = data['level']?.toString() ?? 'high';
        await NotificationHelper.showGasAlertNotification(
          blockchain: blockchain,
          gasPrice: gasPrice,
          level: level,
        );
        return;
      case NotificationType.networkStatus:
        await NotificationHelper.showNetworkStatusNotification(
          blockchain: data['blockchain']?.toString() ?? 'Network',
          status: data['status']?.toString() ?? 'unknown',
          message: body,
        );
        return;
      case NotificationType.networkUpgrade:
        await NotificationHelper.showNetworkUpgradeNotification(
          blockchain: data['blockchain']?.toString() ?? 'Network',
          upgradeName: data['upgrade_name']?.toString() ?? 'Upgrade',
        );
        return;

      // ── P5: Engagement & Features ────────────────────────────────────
      case NotificationType.newListing:
        await NotificationHelper.showNewListingNotification(
          symbol: data['symbol']?.toString() ?? '',
          name: data['name']?.toString() ?? '',
        );
        return;
      case NotificationType.breakingNews:
        await NotificationHelper.showBreakingNewsNotification(
          title: title,
          body: body,
        );
        return;
      case NotificationType.appUpdate:
        await NotificationHelper.showAppUpdateNotification(
          version: payload.version ?? 'unknown',
          forceUpdate: data['force_update']?.toString() == 'true',
        );
        return;
      case NotificationType.reward:
        await NotificationHelper.showRewardNotification(
          amount: payload.rewardAmount ?? data['amount']?.toString() ?? '0',
          symbol: payload.rewardSymbol ?? data['symbol']?.toString() ?? '',
          rewardType: payload.rewardType ?? data['reward_type']?.toString() ?? 'reward',
        );
        return;

      // ── Legacy / Unknown / Fallback ──────────────────────────────────
      case NotificationType.unknown:
        // Try legacy panel types
        final legacyType = (data['type'] ?? '').toString().toLowerCase().trim();
        if (legacyType == 'panel_alert' || legacyType == 'panel_notification' || legacyType == 'client_notification') {
          await NotificationHelper.showPanelAlert(
            title: title,
            body: body.isEmpty ? 'Panel alert' : body,
            payload: data['notification_id']?.toString(),
          );
          return;
        }
        if (legacyType == 'transaction' || legacyType == 'crypto') {
          await _routeTransaction(payload, title, body);
          return;
        }
        if (legacyType == 'security') {
          await NotificationHelper.showNotification(
            channelId: NotificationHelper.channelSecurity,
            title: title,
            body: body.isEmpty ? 'Security alert' : body,
            payload: data['action']?.toString(),
          );
          return;
        }
        // Fallback: show generic notification
        if (message.notification != null || body.isNotEmpty || (data.isNotEmpty && title != 'CoinCeeper')) {
          await NotificationHelper.showNotification(
            channelId: NotificationHelper.channelEngagement,
            title: title,
            body: body.isEmpty ? 'New message' : body,
          );
        }
        return;
    }
  }

  /// Route a transaction notification (legacy + new format).
  static Future<void> _routeTransaction(
    FcmDataPayload payload,
    String title,
    String body,
  ) async {
    final direction =
        (payload.direction ?? payload.raw['tx_direction'] ?? '').toString().toLowerCase();
    final amount = payload.amount ?? payload.raw['value']?.toString() ?? '0';
    final symbol = payload.symbol ?? payload.raw['token'] ?? payload.raw['currency'] ?? '';

    if (direction.contains('in') || direction == 'receive' || direction == 'deposit') {
      final parsed = double.tryParse(amount);
      await NotificationHelper.showReceiveNotification(
        parsed ?? 0,
        symbol.isEmpty ? 'crypto' : symbol,
      );
    } else {
      final parsed = double.tryParse(amount);
      await NotificationHelper.showSendNotification(
        parsed ?? 0,
        symbol.isEmpty ? 'crypto' : symbol,
      );
    }
  }

  /// Handle notification tap for deep linking.
  ///
  /// Call this when user taps a notification (foreground or background).
  /// Returns the route path to navigate to, or null for no navigation.
  static String? handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final payload = FcmDataPayload.fromMap(data);
    final type = payload.type;

    debugPrint('🔔 Notification tapped: type=$type');

    switch (type) {
      case NotificationType.transactionReceived:
      case NotificationType.send:
      case NotificationType.receive:
        if (payload.transactionId != null) {
          return '/transaction_detail/${payload.transactionId}';
        } else if (payload.txHash != null) {
          return '/transaction_detail/${payload.txHash}';
        }
        return '/history';

      case NotificationType.securityLogin:
      case NotificationType.securityChange:
      case NotificationType.securitySuspicious:
        return '/security';

      case NotificationType.priceAlert:
      case NotificationType.volatilityAlert:
        // Navigate to price chart or alerts page
        if (payload.symbol != null) {
          return '/crypto-details/${payload.symbol}';
        }
        return '/notificationmanagement';

      case NotificationType.portfolioSummary:
        return '/history';

      case NotificationType.gasAlert:
        return '/notificationmanagement';

      case NotificationType.networkStatus:
      case NotificationType.networkUpgrade:
        return '/notificationmanagement';

      case NotificationType.newListing:
        if (payload.symbol != null) {
          return '/crypto-details/${payload.symbol}';
        }
        return null;

      case NotificationType.breakingNews:
        if (payload.url != null && payload.url!.isNotEmpty) {
          return '/webview?url=${Uri.encodeComponent(payload.url!)}';
        }
        return null;

      case NotificationType.appUpdate:
        // Open app store — handled in FCM handler
        return null;

      case NotificationType.reward:
        return '/panel';

      case NotificationType.unknown:
        // Legacy: try payload-based navigation
        final payloadStr = message.data['payload']?.toString() ??
            data['notification_id']?.toString() ??
            data['action']?.toString();
        if (payloadStr != null && payloadStr.startsWith('/')) {
          return payloadStr;
        }
        return null;
    }
  }
}
