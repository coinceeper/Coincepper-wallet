import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

/// Central notification helper for Coinceeper Push Notification System.
///
/// Manages:
/// - 5 standard Android notification channels (per documentation)
/// - Legacy channels for backward compatibility
/// - Local notification display
/// - Permission requests
class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  // ─── LEGACY CHANNEL IDs (backward compat) ──────────────────────────────
  static const String receiveChannelId = 'receive_channel';
  static const String sendChannelId = 'send_channel';
  static const String welcomeChannelId = 'welcome_channel';
  static const String priceAlertChannelId = 'price_alert_channel';
  static const String loginChannelId = 'login_channel_id';
  static const String panelAlertChannelId = 'panel_alert_channel';

  // ─── STANDARD CHANNEL IDs (from documentation — Section 7) ─────────────
  static const String channelTransactions = 'transactions';
  static const String channelSecurity = 'security';
  static const String channelPriceAlerts = 'price_alerts';
  static const String channelNetwork = 'network';
  static const String channelEngagement = 'engagement';

  /// Maps a channel ID to its user-facing name.
  static String _channelName(String id) {
    switch (id) {
      case channelTransactions:
        return 'Transactions';
      case channelSecurity:
        return 'Security';
      case channelPriceAlerts:
        return 'Price Alerts';
      case channelNetwork:
        return 'Network';
      case channelEngagement:
        return 'CoinCeeper News';
      case receiveChannelId:
        return 'Receive Notifications';
      case sendChannelId:
        return 'Send Notifications';
      case welcomeChannelId:
        return 'Welcome Notifications';
      case priceAlertChannelId:
        return 'Price Alert Notifications';
      case loginChannelId:
        return 'Login Notifications';
      case panelAlertChannelId:
        return 'Panel alerts';
      default:
        return id;
    }
  }

  /// Maps a channel ID to its user-facing description.
  static String _channelDesc(String id) {
    switch (id) {
      case channelTransactions:
        return 'Send/Receive notifications';
      case channelSecurity:
        return 'Login alerts, suspicious activity';
      case channelPriceAlerts:
        return 'Price targets reached';
      case channelNetwork:
        return 'Gas fees, network status';
      case channelEngagement:
        return 'New listings, updates, rewards';
      case receiveChannelId:
        return 'Channel for receive notifications';
      case sendChannelId:
        return 'Channel for send notifications';
      case welcomeChannelId:
        return 'Channel for welcome notifications';
      case priceAlertChannelId:
        return 'Channel for price alert notifications';
      case loginChannelId:
        return 'Channel for login notifications';
      case panelAlertChannelId:
        return 'Coinceeper panel and account alerts';
      default:
        return id;
    }
  }

  /// Importance for each channel (Section 7).
  static Importance _channelImportance(String id) {
    switch (id) {
      case channelTransactions:
        return Importance.high;
      case channelSecurity:
        return Importance.max; // Critical
      case channelPriceAlerts:
        return Importance.defaultImportance;
      case channelNetwork:
        return Importance.defaultImportance;
      case channelEngagement:
        return Importance.defaultImportance;
      case receiveChannelId:
      case sendChannelId:
      case panelAlertChannelId:
        return Importance.high;
      case priceAlertChannelId:
        return Importance.high;
      case welcomeChannelId:
      case loginChannelId:
        return Importance.defaultImportance;
      default:
        return Importance.defaultImportance;
    }
  }

  /// Initialize notification plugin and create all channels.
  static Future<void> initialize() async {
    try {
      const AndroidInitializationSettings androidInit = AndroidInitializationSettings('notifsmall');
      const DarwinInitializationSettings iosInit = DarwinInitializationSettings();

      if (Platform.isWindows) {
        const InitializationSettings initSettings = InitializationSettings(
          android: androidInit,
          iOS: iosInit,
          windows: WindowsInitializationSettings(
            appName: 'CoinCeeper',
            appUserModelId: 'Com.CoinCeeper.ADL.Wallet',
            guid: '3fa85f64-5717-4562-b3fc-2c963f66afa6',
          ),
        );
        await _notifications.initialize(initSettings);
      } else if (Platform.isMacOS) {
        const InitializationSettings initSettings = InitializationSettings(
          android: androidInit,
          iOS: iosInit,
          macOS: DarwinInitializationSettings(),
        );
        await _notifications.initialize(initSettings);
      } else {
        const InitializationSettings initSettings =
            InitializationSettings(android: androidInit, iOS: iosInit);
        await _notifications.initialize(initSettings);
      }
      await _createNotificationChannels();
    } catch (e, st) {
      debugPrint('NotificationHelper.initialize skipped: $e');
      debugPrint('$st');
    }
  }

  /// Create all notification channels (standard + legacy).
  static Future<void> _createNotificationChannels() async {
    if (Platform.isAndroid) {
      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        // ── Standard Channels (from documentation Section 7) ──
        await android.createNotificationChannel(AndroidNotificationChannel(
          channelTransactions,
          _channelName(channelTransactions),
          description: _channelDesc(channelTransactions),
          importance: _channelImportance(channelTransactions),
        ));
        await android.createNotificationChannel(AndroidNotificationChannel(
          channelSecurity,
          _channelName(channelSecurity),
          description: _channelDesc(channelSecurity),
          importance: _channelImportance(channelSecurity),
          sound: null, // Security uses default sound for critical alerts
        ));
        await android.createNotificationChannel(AndroidNotificationChannel(
          channelPriceAlerts,
          _channelName(channelPriceAlerts),
          description: _channelDesc(channelPriceAlerts),
          importance: _channelImportance(channelPriceAlerts),
        ));
        await android.createNotificationChannel(AndroidNotificationChannel(
          channelNetwork,
          _channelName(channelNetwork),
          description: _channelDesc(channelNetwork),
          importance: _channelImportance(channelNetwork),
        ));
        await android.createNotificationChannel(AndroidNotificationChannel(
          channelEngagement,
          _channelName(channelEngagement),
          description: _channelDesc(channelEngagement),
          importance: _channelImportance(channelEngagement),
        ));

        // ── Legacy Channels (backward compatibility) ──
        await android.createNotificationChannel(AndroidNotificationChannel(
          receiveChannelId,
          _channelName(receiveChannelId),
          description: _channelDesc(receiveChannelId),
          importance: Importance.high,
          sound: RawResourceAndroidNotificationSound('receive_sound'),
        ));
        await android.createNotificationChannel(AndroidNotificationChannel(
          sendChannelId,
          _channelName(sendChannelId),
          description: _channelDesc(sendChannelId),
          importance: Importance.high,
          sound: RawResourceAndroidNotificationSound('send_sound'),
        ));
        await android.createNotificationChannel(AndroidNotificationChannel(
          welcomeChannelId,
          _channelName(welcomeChannelId),
          description: _channelDesc(welcomeChannelId),
          importance: Importance.defaultImportance,
          sound: RawResourceAndroidNotificationSound('welcome_sound'),
        ));
        await android.createNotificationChannel(AndroidNotificationChannel(
          priceAlertChannelId,
          _channelName(priceAlertChannelId),
          description: _channelDesc(priceAlertChannelId),
          importance: Importance.high,
          sound: RawResourceAndroidNotificationSound('price_alert_sound'),
        ));
        await android.createNotificationChannel(AndroidNotificationChannel(
          loginChannelId,
          _channelName(loginChannelId),
          description: _channelDesc(loginChannelId),
          importance: Importance.defaultImportance,
        ));
        await android.createNotificationChannel(AndroidNotificationChannel(
          panelAlertChannelId,
          _channelName(panelAlertChannelId),
          description: _channelDesc(panelAlertChannelId),
          importance: Importance.high,
        ));
      }
    }
  }

  /// Request notification permission (Android 13+ and iOS).
  static Future<void> requestNotificationPermission(BuildContext context) async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    } else if (Platform.isIOS) {
      // iOS permission is requested during FCM initialization
    }
  }

  /// Show a local notification on the given channel.
  static Future<void> showNotification({
    required String channelId,
    required String title,
    required String body,
    String? payload,
    String? largeIconAsset,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      _channelName(channelId),
      channelDescription: _channelDesc(channelId),
      importance: _channelImportance(channelId),
      priority: Priority.high,
      largeIcon:
          largeIconAsset != null ? DrawableResourceAndroidBitmap(largeIconAsset) : null,
    );
    const iosDetails = DarwinNotificationDetails();
    final NotificationDetails details = Platform.isWindows
        ? NotificationDetails(
            android: androidDetails,
            iOS: iosDetails,
            windows: const WindowsNotificationDetails(),
          )
        : NotificationDetails(
            android: androidDetails,
            iOS: iosDetails,
          );
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  // ─── Convenience Methods ────────────────────────────────────────────────

  /// Show a welcome notification.
  static Future<void> showWelcomeNotification() async {
    await showNotification(
      channelId: welcomeChannelId,
      title: 'Welcome',
      body: 'Welcome to CoinCeeper',
      largeIconAsset: 'logo',
    );
  }

  /// Show a receive notification.
  static Future<void> showReceiveNotification(double amount, String currency) async {
    await showNotification(
      channelId: receiveChannelId,
      title: 'Receive',
      body: 'You received $amount $currency',
      largeIconAsset: 'logo',
    );
  }

  /// Show a send notification.
  static Future<void> showSendNotification(double amount, String currency) async {
    await showNotification(
      channelId: sendChannelId,
      title: 'Send',
      body: 'You sent $amount $currency',
      largeIconAsset: 'logo',
    );
  }

  /// Show a price alert notification with rich details.
  ///
  /// [symbol] — e.g. "BTC"
  /// [currentPrice] — e.g. 75200.0
  /// [targetPrice] — e.g. 75000.0
  /// [alertType] — "above" or "below"
  static Future<void> showPriceAlertNotification({
    double currentPrice = 0,
    String symbol = '',
    double targetPrice = 0,
    String alertType = '',
    String? customTitle,
    String? customBody,
  }) async {
    final title = customTitle ?? _buildPriceAlertTitle(symbol, alertType);
    final body = customBody ??
        _buildPriceAlertBody(symbol, currentPrice, targetPrice, alertType);
    await showNotification(
      channelId: channelPriceAlerts,
      title: title,
      body: body,
      largeIconAsset: 'logo',
    );
  }

  static String _buildPriceAlertTitle(String symbol, String alertType) {
    if (symbol.isEmpty) return '📈 Price Alert!';
    final direction = alertType == 'above' ? 'Target' : 'Low';
    return '📈 $symbol Hit Your $direction!';
  }

  static String _buildPriceAlertBody(
      String symbol, double currentPrice, double targetPrice, String alertType) {
    if (symbol.isEmpty) {
      return currentPrice > 0
          ? 'Price reached \$${_formatPrice(currentPrice)}'
          : 'Price alert triggered';
    }
    final current = _formatPrice(currentPrice);
    final target = _formatPrice(targetPrice);
    return '$symbol is now \$$current (target: \$$target)';
  }

  static String _formatPrice(double price) {
    if (price >= 1e12) {
      return '${(price / 1e12).toStringAsFixed(2)}T';
    } else if (price >= 1e9) {
      return '${(price / 1e9).toStringAsFixed(2)}B';
    } else if (price >= 1e6) {
      return '${(price / 1e6).toStringAsFixed(2)}M';
    } else if (price >= 1e3) {
      return price.toStringAsFixed(price >= 10000 ? 0 : 1);
    } else if (price >= 1) {
      return price.toStringAsFixed(2);
    } else if (price >= 0.01) {
      return price.toStringAsFixed(4);
    } else {
      return price.toStringAsFixed(6);
    }
  }

  /// Panel tab alerts (also used when FCM sends `type=panel_alert`).
  static Future<void> showPanelAlert({
    required String title,
    required String body,
    String? payload,
  }) async {
    await showNotification(
      channelId: panelAlertChannelId,
      title: title,
      body: body,
      payload: payload,
      largeIconAsset: 'logo',
    );
  }

  // ─── Security Notification Methods ──────────────────────────────────────

  /// Show security login alert notification.
  static Future<void> showSecurityLoginNotification({
    required String deviceName,
    String? location,
  }) async {
    await showNotification(
      channelId: channelSecurity,
      title: 'New Login Detected',
      body: location != null
          ? 'Login from $deviceName ($location)'
          : 'Login from $deviceName',
      largeIconAsset: 'logo',
    );
  }

  /// Show security setting change notification.
  static Future<void> showSecurityChangeNotification(String changeType) async {
    final label = changeType.replaceAll('_', ' ');
    await showNotification(
      channelId: channelSecurity,
      title: 'Security Setting Changed',
      body: 'Your $label has been changed',
      largeIconAsset: 'logo',
    );
  }

  /// Show suspicious activity notification.
  static Future<void> showSecuritySuspiciousNotification({
    required String description,
    required String severity,
  }) async {
    final title = severity == 'critical'
        ? '⚠️ Critical Security Alert'
        : severity == 'warning'
            ? '⚡ Security Warning'
            : '🔍 Security Info';
    await showNotification(
      channelId: channelSecurity,
      title: title,
      body: description,
      largeIconAsset: 'logo',
    );
  }

  // ─── Network & Gas Notification Methods ─────────────────────────────────

  /// Show gas fee alert notification.
  static Future<void> showGasAlertNotification({
    required String blockchain,
    required double gasPrice,
    required String level,
  }) async {
    await showNotification(
      channelId: channelNetwork,
      title: 'Gas Fee Alert',
      body: '$blockchain gas is $level: $gasPrice Gwei',
      largeIconAsset: 'logo',
    );
  }

  /// Show network status notification.
  static Future<void> showNetworkStatusNotification({
    required String blockchain,
    required String status,
    required String message,
  }) async {
    final emoji = status == 'maintenance'
        ? '🔧'
        : status == 'outage'
            ? '🚫'
            : status == 'degraded'
                ? '⚠️'
                : '✅';
    await showNotification(
      channelId: channelNetwork,
      title: '$emoji $blockchain: ${status.toUpperCase()}',
      body: message,
      largeIconAsset: 'logo',
    );
  }

  /// Show network upgrade notification.
  static Future<void> showNetworkUpgradeNotification({
    required String blockchain,
    required String upgradeName,
  }) async {
    await showNotification(
      channelId: channelNetwork,
      title: '🔧 $blockchain Upgrade',
      body: '$upgradeName upgrade scheduled',
      largeIconAsset: 'logo',
    );
  }

  // ─── Engagement Notification Methods ────────────────────────────────────

  /// Show new coin listing notification.
  static Future<void> showNewListingNotification({
    required String symbol,
    required String name,
  }) async {
    await showNotification(
      channelId: channelEngagement,
      title: '🪙 New Listing: $symbol',
      body: '$name is now available on CoinCeeper',
      largeIconAsset: 'logo',
    );
  }

  /// Show breaking news notification.
  static Future<void> showBreakingNewsNotification({
    required String title,
    required String body,
  }) async {
    await showNotification(
      channelId: channelEngagement,
      title: '📰 $title',
      body: body,
      largeIconAsset: 'logo',
    );
  }

  /// Show app update notification.
  static Future<void> showAppUpdateNotification({
    required String version,
    bool forceUpdate = false,
  }) async {
    final title = forceUpdate
        ? '⚠️ Mandatory Update v$version'
        : '📲 Update Available v$version';
    await showNotification(
      channelId: channelEngagement,
      title: title,
      body: forceUpdate
          ? 'Please update to continue using CoinCeeper'
          : 'New version $version is available',
      largeIconAsset: 'logo',
    );
  }

  /// Show reward notification.
  static Future<void> showRewardNotification({
    required String amount,
    required String symbol,
    required String rewardType,
  }) async {
    final emoji = rewardType == 'staking'
        ? '🥩'
        : rewardType == 'airdrop'
            ? '🎁'
            : rewardType == 'cashback'
                ? '💵'
                : '🎯';
    await showNotification(
      channelId: channelEngagement,
      title: '$emoji $rewardType Reward',
      body: 'You received $amount $symbol',
      largeIconAsset: 'logo',
    );
  }

  // ─── Manage Notifications ───────────────────────────────────────────────

  /// Cancel all pending notifications.
  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  /// Delete all notification channels (Android only).
  static Future<void> deleteNotificationChannels() async {
    if (Platform.isAndroid) {
      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        // Delete standard channels
        await android.deleteNotificationChannel(channelTransactions);
        await android.deleteNotificationChannel(channelSecurity);
        await android.deleteNotificationChannel(channelPriceAlerts);
        await android.deleteNotificationChannel(channelNetwork);
        await android.deleteNotificationChannel(channelEngagement);
        // Delete legacy channels
        await android.deleteNotificationChannel(receiveChannelId);
        await android.deleteNotificationChannel(sendChannelId);
        await android.deleteNotificationChannel(welcomeChannelId);
        await android.deleteNotificationChannel(priceAlertChannelId);
        await android.deleteNotificationChannel(loginChannelId);
        await android.deleteNotificationChannel(panelAlertChannelId);
      }
    }
  }

  /// Initialize notification settings (stub for compatibility).
  static Future<void> initializeNotificationSettings() async {
    try {
      print('📱 Initializing notification settings...');
      if (Platform.isIOS || Platform.isAndroid) {
        final permission = await Permission.notification.request();
        if (permission.isGranted) {
          print('✅ Notification permission granted');
        } else {
          print('❌ Notification permission denied');
        }
      }
      print('✅ Notification settings initialized');
    } catch (e) {
      print('❌ Error initializing notification settings: $e');
    }
  }
}
