import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'push_notification_router.dart';
import 'secure_storage.dart';
import 'service_provider.dart';
import '../navigation/app_router.dart';

/// Firebase Cloud Messaging (FCM) Service.
///
/// Responsibilities:
/// - Receive FCM tokens and register device with backend
/// - Listen for incoming messages (foreground + background)
/// - Handle notification taps for deep linking
/// - Forward messages to [PushNotificationRouter] for display
class FirebaseMessagingService {
  FirebaseMessagingService._();
  static final FirebaseMessagingService instance = FirebaseMessagingService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  String? _fcmToken;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;
  StreamSubscription<String>? _onTokenRefreshSub;

  /// Current FCM token.
  String? get fcmToken => _fcmToken;

  /// Initialize FCM service.
  Future<void> initialize() async {
    try {
      // Request permission (iOS + Android 13+)
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('🔔 FCM permission: ${settings.authorizationStatus}');

      // Get FCM token
      _fcmToken = await _messaging.getToken();
      debugPrint('🔔 FCM token: $_fcmToken');

      // Register device on every app start (token freshness)
      if (_fcmToken != null) {
        await _registerDeviceWithBackend(_fcmToken!);
      }

      // Listen for token refresh and re-register
      _onTokenRefreshSub = _messaging.onTokenRefresh.listen((token) async {
        _fcmToken = token;
        debugPrint('🔔 FCM token refreshed: $token');
        await _registerDeviceWithBackend(token);
      });

      // Handle messages in foreground
      _onMessageSub = FirebaseMessaging.onMessage.listen(_handleMessage);

      // Handle notification tap (app opened from background via notification)
      _onMessageOpenedAppSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Handle app opened from terminated state via notification
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        Future.delayed(const Duration(milliseconds: 800), () {
          _handleNotificationTap(initialMessage);
        });
      }

      // Set background message handler (static, can't use instance methods)
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      debugPrint('🔔 FirebaseMessagingService initialized');
    } catch (e, st) {
      debugPrint('❌ FirebaseMessagingService init error: $e');
      debugPrint('$st');
    }
  }

  /// Register device with backend for push notifications.
  Future<void> _registerDeviceWithBackend(String token) async {
    try {
      // Get UserID and WalletID
      final userId = await SecureStorage.instance.getUserIdForSelectedWallet();
      if (userId == null || userId.isEmpty) {
        debugPrint('⚠️ FCM register: No UserID found — skipping');
        return;
      }
      final walletId = await SecureStorage.instance.getWalletIdForSelectedWallet();
      if (walletId == null || walletId.isEmpty) {
        debugPrint('⚠️ FCM register: No WalletID found — skipping');
        return;
      }

      // Detect platform
      final String platform;
      if (Platform.isAndroid) {
        platform = 'android';
      } else if (Platform.isIOS) {
        platform = 'ios';
      } else {
        platform = 'android';
      }

      // Get device name
      String deviceName = platform;
      try {
        if (Platform.isAndroid) {
          final androidInfo = await _deviceInfo.androidInfo;
          deviceName =
              '${androidInfo.brand} ${androidInfo.model} (${androidInfo.version.release})';
        } else if (Platform.isIOS) {
          final iosInfo = await _deviceInfo.iosInfo;
          deviceName =
              '${iosInfo.name} ${iosInfo.model} (iOS ${iosInfo.systemVersion})';
        }
      } catch (_) {
        deviceName = platform;
      }

      // Use the V2 register method from API service
      final response = await ServiceProvider.instance.apiService.registerDeviceV2(
        deviceToken: token,
        platform: platform,
        walletId: walletId,
        userId: userId,
        deviceName: deviceName,
      );

      if (response.success) {
        debugPrint('🔔 Device registered successfully');
      } else {
        debugPrint('⚠️ Device registration failed: ${response.message}');
      }
    } catch (e) {
      debugPrint('⚠️ FCM register error: $e');
    }
  }

  /// Handle incoming FCM message (foreground).
  Future<void> _handleMessage(RemoteMessage message) async {
    try {
      debugPrint('🔔 FCM message received: ${message.messageId}');
      debugPrint('🔔 FCM data: ${message.data}');

      await PushNotificationRouter.route(message);
    } catch (e, st) {
      debugPrint('❌ FCM handleMessage error: $e');
      debugPrint('$st');
    }
  }

  /// Handle notification tap for deep linking.
  void _handleNotificationTap(RemoteMessage message) {
    try {
      debugPrint('🔔 FCM notification tapped: ${message.messageId}');
      final route = PushNotificationRouter.handleNotificationTap(message);

      if (route != null && route.isNotEmpty) {
        debugPrint('🔔 Navigating to deep link: $route');
        // Use a short delay to ensure app is ready
        Future.delayed(const Duration(milliseconds: 300), () {
          try {
            AppRouter.router.go(route);
          } catch (e) {
            debugPrint('⚠️ Deep link navigation failed: $e');
          }
        });
      }
    } catch (e, st) {
      debugPrint('❌ handleNotificationTap error: $e');
      debugPrint('$st');
    }
  }

  /// Dispose subscriptions.
  void dispose() {
    _onMessageSub?.cancel();
    _onMessageOpenedAppSub?.cancel();
    _onTokenRefreshSub?.cancel();
  }
}

/// Top-level background message handler (required by FCM).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('🔔 FCM background message: ${message.messageId}');
  debugPrint('🔔 FCM background data: ${message.data}');

  // In background, we can only show local notifications (no UI navigation)
  await PushNotificationRouter.route(message);
}
