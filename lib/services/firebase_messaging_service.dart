import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../utils/secure_log.dart';
import 'notification_helper.dart';
import 'push_notification_router.dart';
import 'secure_storage.dart';
import 'service_provider.dart';
import '../navigation/app_router.dart';
import '../di/service_locator.dart';

/// Firebase Cloud Messaging (FCM) Service.
///
/// Responsibilities:
/// - Receive FCM tokens and register device with backend
/// - Listen for incoming messages (foreground + background)
/// - Handle notification taps for deep linking
/// - Forward messages to [PushNotificationRouter] for display
///
/// 🛡️ Privacy: Uses an anonymous device ID (UUID v4) instead of [userId]
/// so the proxy server never learns the actual user identity.
class FirebaseMessagingService {
  FirebaseMessagingService._();
  FirebaseMessagingService();
  static FirebaseMessagingService get instance => ServiceLocator.get<FirebaseMessagingService>();

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
      SecureLog.d('FCM permission: ${settings.authorizationStatus}');

      // Get FCM token
      _fcmToken = await _messaging.getToken();
      SecureLog.d('FCM token: $_fcmToken');

      // Register device on every app start (token freshness)
      if (_fcmToken != null) {
        await _registerDeviceWithBackend(_fcmToken!);
      }

      // Listen for token refresh and re-register
      _onTokenRefreshSub = _messaging.onTokenRefresh.listen((token) async {
        _fcmToken = token;
        SecureLog.d('FCM token refreshed: $token');
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

      // ── Local notification tap → navigation ─────────────────────────
      // When the user taps a local notification shown by [NotificationHelper],
      // this callback navigates to the deep-link route stored in
      // [PushNotificationRouter].
      NotificationHelper.navigateToRoute = (route) {
        try {
          AppRouter.router.go(route);
        } catch (e) {
          SecureLog.w('Notification tap navigation failed: $e');
        }
      };

      // Set background message handler (static, can't use instance methods)
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      SecureLog.d('FirebaseMessagingService initialized');
    } catch (e, st) {
      SecureLog.e('FirebaseMessagingService init error: $e', error: e, stackTrace: st);
    }
  }

  /// Register device with backend for push notifications.
  ///
  /// Uses an anonymous device ID instead of [userId] so the proxy server
  /// cannot link the FCM token to any specific user identity.
  Future<void> _registerDeviceWithBackend(String token) async {
    try {
      // Get anonymous device ID (locally generated UUID v4)
      final anonymousId =
          await ServiceLocator.get<SecureStorage>().getAnonymousDeviceId();
      if (anonymousId.isEmpty) {
        SecureLog.w('FCM register: No anonymous device ID — skipping');
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
      } catch (e) {
        SecureLog.w('FirebaseMessaging: failed to get device info, using platform fallback', error: e);
        deviceName = platform;
      }

      // Use anonymous ID instead of UserID/WalletID
      final response = await ServiceLocator.get<ServiceProvider>().apiService.registerDeviceV2(
        deviceToken: token,
        platform: platform,
        anonymousId: anonymousId,
        deviceName: deviceName,
      );

      if (response.success) {
        SecureLog.d('Device registered successfully (anonymous ID: $anonymousId)');
      } else {
        SecureLog.w('Device registration failed: ${response.message}');
      }
    } catch (e) {
      SecureLog.w('FCM register error: $e');
    }
  }

  /// Handle incoming FCM message (foreground).
  Future<void> _handleMessage(RemoteMessage message) async {
    try {
      SecureLog.d('FCM message received: ${message.messageId}');
      SecureLog.d('FCM data: ${message.data}');

      await PushNotificationRouter.route(message);
    } catch (e, st) {
      SecureLog.e('FCM handleMessage error: $e', error: e, stackTrace: st);
    }
  }

  /// Handle notification tap for deep linking.
  void _handleNotificationTap(RemoteMessage message) {
    try {
      SecureLog.d('FCM notification tapped: ${message.messageId}');
      final route = PushNotificationRouter.handleNotificationTap(message);

      if (route != null && route.isNotEmpty) {
        SecureLog.d('Navigating to deep link: $route');
        // Use a short delay to ensure app is ready
        Future.delayed(const Duration(milliseconds: 300), () {
          try {
            AppRouter.router.go(route);
          } catch (e) {
            SecureLog.w('Deep link navigation failed: $e');
          }
        });
      }
    } catch (e, st) {
      SecureLog.e('handleNotificationTap error: $e', error: e, stackTrace: st);
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
///
/// Runs in a **separate isolate** from the main app. This means:
/// - [Firebase] must be re-initialized here
/// - [NotificationHelper] (which wraps [FlutterLocalNotificationsPlugin])
///   must be re-initialized here because the static instance is fresh
///   in this isolate
/// - Only local notifications can be shown (no UI navigation possible)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  SecureLog.d('FCM background message: ${message.messageId}');
  SecureLog.d('FCM background data: ${message.data}');

  try {
    // 1. Re-initialize Firebase in the background isolate
    //    (fresh isolate = no inherited state from main)
    await Firebase.initializeApp();

    // 2. Re-initialize FlutterLocalNotificationsPlugin in this isolate
    //    (its static `_notifications` instance is fresh here)
    await NotificationHelper.initialize();

    // 3. Show the local notification (only display, no navigation)
    await PushNotificationRouter.route(message);
  } catch (e, st) {
    SecureLog.e('FCM background handler error: $e', error: e, stackTrace: st);
  }
}
