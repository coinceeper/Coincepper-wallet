import 'dart:async';
import '../di/service_locator.dart';
import '../utils/secure_log.dart';

/// Poller برای نوتیفیکیشن‌های V2 (اعلان تراکنش‌های non-custodial)
///
/// این سرویس به صورت دوره‌ای وضعیت تراکنش‌های در انتظار را از بک‌اند بررسی می‌کند
/// و در صورت تغییر وضعیت، نوتیفیکیشن نمایش می‌دهد.
class V2NotificationPoller {
  V2NotificationPoller._();
  V2NotificationPoller();
  static V2NotificationPoller get instance => ServiceLocator.get<V2NotificationPoller>();

  Timer? _timer;
  bool _isRunning = false;

  /// شروع polling برای یک wallet خاص
  Future<void> start({required String walletId}) async {
    if (_isRunning) return;
    _isRunning = true;
    SecureLog.i('V2NotificationPoller started for wallet: $walletId');
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      _poll(walletId);
    });
  }

  Future<void> _poll(String walletId) async {
    try {
      // TODO: پیاده‌سازی واقعی polling از بک‌اند
      SecureLog.d('V2NotificationPoller polling for wallet: $walletId');
    } catch (e) {
      SecureLog.e('V2NotificationPoller poll error: $e');
    }
  }

  /// توقف polling
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    SecureLog.i('V2NotificationPoller stopped');
  }
}
