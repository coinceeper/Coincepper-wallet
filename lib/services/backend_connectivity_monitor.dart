import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;

import '../utils/secure_log.dart';

import 'backend_proxy_service.dart';

/// Monitors backend availability and auto-switches between proxy and direct.
///
/// ## استراتژی:
/// - هر ۳۰ ثانیه بک‌اند را health check می‌کند (GET /health)
/// - اگر ۳ بار متوالی failed → unavailable
/// - از exponential backoff استفاده می‌کند
/// - وقتی بک‌اند healthy شد → auto switch back
///
/// ## سطوح:
/// - healthy: ✅ پاسخ عادی (< ۲s)
/// - degraded: ⚠️ پاسخ کند (> ۲s) — باز هم استفاده کن
/// - unavailable: ❌ قطع — برو به مستقیم
class BackendConnectivityMonitor {
  final String _baseUrl;

  BackendConnectivityMonitor({required String baseUrl}) : _baseUrl = baseUrl;

  Timer? _timer;
  BackendStatus _status = BackendStatus.healthy;

  /// تعداد خطاهای متوالی
  int _consecutiveFailures = 0;

  /// آخرین زمان موفقیت‌آمیز بودن چک
  DateTime? _lastSuccessfulCheck;

  /// تعداد خطاهای متوالی مورد نیاز برای اعلام unavailable
  static const int _maxConsecutiveFailures = 3;

  /// فاصله health check در حالت عادی
  static const Duration _normalInterval = Duration(seconds: 30);

  /// فاصله health check در حالت degraded
  Duration _currentInterval = _normalInterval;

  /// Callback برای اطلاع‌رسانی تغییر وضعیت
  void Function(BackendStatus oldStatus, BackendStatus newStatus)? onStatusChanged;

  /// وضعیت فعلی
  BackendStatus get status => _status;

  /// آخرین زمان موفقیت‌آمیز
  DateTime? get lastSuccessfulCheck => _lastSuccessfulCheck;

  /// آیا بک‌اند در دسترس است
  bool get isAvailable => _status != BackendStatus.unavailable;

  /// شروع مانیتورینگ
  void start() {
    _timer?.cancel();
    _scheduleNext();
    // Check فوری در start
    _performHealthCheck();
    SecureLog.i('📡 BackendConnectivityMonitor started → $_baseUrl/health');
  }

  /// توقف مانیتورینگ
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Force health check now. Returns true if healthy.
  Future<bool> checkNow() async {
    final healthy = await _performHealthCheck();
    return healthy;
  }

  /// ثبت موفقیت (از بیرون توسط BackendProxyService)
  void recordSuccess() {
    _consecutiveFailures = 0;
    _lastSuccessfulCheck = DateTime.now();
    if (_status == BackendStatus.degraded) {
      _setStatus(BackendStatus.healthy);
    }
  }

  /// ثبت شکست (از بیرون توسط BackendProxyService)
  void recordFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      _setStatus(BackendStatus.unavailable);
      // افزایش فاصله چک
      _currentInterval = _calculateBackoff();
      _scheduleNext();
    } else if (_status == BackendStatus.healthy) {
      _setStatus(BackendStatus.degraded);
    }
  }

  // ─── Private ──────────────────────────────────────────

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(_currentInterval, () {
      _performHealthCheck().then((_) => _scheduleNext(),
          onError: (Object e, StackTrace s) {
        SecureLog.w('BackendConnectivityMonitor: health check failed', error: e, stackTrace: s);
        _scheduleNext(); // still schedule next check on error
      });
    });
  }

  Future<bool> _performHealthCheck() async {
    try {
      final stopwatch = Stopwatch()..start();
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 5));

      stopwatch.stop();
      final elapsed = stopwatch.elapsedMilliseconds;

      if (response.statusCode == 200) {
        // موفق — ریست کردن همه چیز
        _consecutiveFailures = 0;
        _lastSuccessfulCheck = DateTime.now();
        _currentInterval = _normalInterval;

        if (elapsed > 2000) {
          // پاسخ کند (> ۲s) → degraded
          if (_status == BackendStatus.unavailable) {
            SecureLog.w('📡 Backend recovered from unavailable (slow: ${elapsed}ms) → degraded');
            _setStatus(BackendStatus.degraded);
          } else if (_status != BackendStatus.degraded) {
            _setStatus(BackendStatus.degraded);
          }
        } else {
          // پاسخ سریع (< ۲s) → healthy
          if (_status != BackendStatus.healthy) {
            SecureLog.i('📡 Backend recovered → healthy (${elapsed}ms)');
            _setStatus(BackendStatus.healthy);
          }
        }
        return true;
      }
    } on TimeoutException {
      SecureLog.w('📡 Backend health check timed out');
    } catch (e) {
      SecureLog.w('📡 Backend health check failed', error: e);
    }

    // شکست
    _consecutiveFailures++;

    if (_consecutiveFailures >= _maxConsecutiveFailures) {
      if (_status != BackendStatus.unavailable) {
        SecureLog.e('Backend → unavailable ($_consecutiveFailures consecutive failures)');
        _setStatus(BackendStatus.unavailable);
      }
    } else if (_status == BackendStatus.healthy) {
      SecureLog.w('Backend → degraded ($_consecutiveFailures/$_maxConsecutiveFailures failures)');
      _setStatus(BackendStatus.degraded);
    }

    return false;
  }

  void _setStatus(BackendStatus newStatus) {
    if (_status == newStatus) return;
    final old = _status;
    _status = newStatus;
    onStatusChanged?.call(old, newStatus);
    SecureLog.i('Backend status: $old → $newStatus');
  }

  /// Exponential backoff برای فاصله health check
  Duration _calculateBackoff() {
    final exp = min(_consecutiveFailures - _maxConsecutiveFailures + 1, 10);
    final seconds = min(pow(5, exp).toInt(), 300); // max 5 min
    return Duration(seconds: seconds);
  }
}
