import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/services/backend_connectivity_monitor.dart';
import 'package:my_flutter_app/services/backend_proxy_service.dart';

void main() {
  group('BackendConnectivityMonitor — State Machine', () {
    late BackendConnectivityMonitor monitor;

    setUp(() {
      monitor = BackendConnectivityMonitor(
        baseUrl: 'https://test.proxy.local',
      );
    });

    tearDown(() {
      monitor.stop();
    });

    // ── Initial state ───────────────────────────────────────

    test('initial status is healthy', () {
      expect(monitor.status, BackendStatus.healthy);
      expect(monitor.isAvailable, isTrue);
      expect(monitor.lastSuccessfulCheck, isNull);
    });

    // ── recordSuccess when already healthy ───────────────────

    test('recordSuccess keeps status healthy when already healthy', () {
      monitor.recordSuccess();
      expect(monitor.status, BackendStatus.healthy);
      expect(monitor.lastSuccessfulCheck, isNotNull);
    });

    // ── Failure transitions ─────────────────────────────────

    test('one failure transitions from healthy to degraded', () {
      monitor.recordFailure();
      expect(monitor.status, BackendStatus.degraded);
      expect(monitor.isAvailable, isTrue);
    });

    test('two failures stays degraded (no change)', () {
      monitor.recordFailure(); // healthy → degraded
      monitor.recordFailure(); // stays degraded (already degraded)
      expect(monitor.status, BackendStatus.degraded);
      expect(monitor.isAvailable, isTrue);
    });

    test('three consecutive failures transitions to unavailable', () {
      monitor.recordFailure(); // healthy → degraded
      monitor.recordFailure(); // already degraded
      monitor.recordFailure(); // degraded → unavailable
      expect(monitor.status, BackendStatus.unavailable);
      expect(monitor.isAvailable, isFalse);
    });

    // ── recordSuccess recovery ──────────────────────────────

    test('recordSuccess recovers from degraded to healthy', () {
      monitor.recordFailure(); // healthy → degraded
      expect(monitor.status, BackendStatus.degraded);

      monitor.recordSuccess();
      expect(monitor.status, BackendStatus.healthy);
    });

    test('recordSuccess does NOT recover from unavailable (health check only)', () {
      // Drive to unavailable
      monitor.recordFailure();
      monitor.recordFailure();
      monitor.recordFailure();
      expect(monitor.status, BackendStatus.unavailable);

      // recordSuccess only handles degraded → healthy
      // Recovery from unavailable requires _performHealthCheck()
      monitor.recordSuccess();
      expect(monitor.status, BackendStatus.unavailable,
          reason: 'Only health check can recover from unavailable');
    });

    test('non-consecutive failures do not escalate beyond degraded', () {
      monitor.recordFailure(); // healthy → degraded (1 failure)

      // Success resets the counter
      monitor.recordSuccess();
      expect(monitor.status, BackendStatus.healthy);

      // Another failure starts fresh
      monitor.recordFailure(); // healthy → degraded (1 failure again)
      expect(monitor.status, BackendStatus.degraded);

      // Two more failures would be needed for unavailable
      monitor.recordFailure(); // stays degraded (2nd total, but non-consecutive)
      expect(monitor.status, BackendStatus.degraded);
    });

    // ── recordFailure bookkeeping ───────────────────────────

    test('recordSuccess resets consecutive failure counter', () {
      monitor.recordFailure(); // 1 failure
      monitor.recordSuccess(); // resets counter to 0

      // Now one more failure only goes to degraded (not unavailable)
      monitor.recordFailure(); // 1 failure again
      expect(monitor.status, BackendStatus.degraded);
    });

    // ── Status change callback ──────────────────────────────

    test('status change callback fires on all transitions (recordFailure only)', () {
      final transitions = <String>[];
      monitor.onStatusChanged = (oldStatus, newStatus) {
        transitions.add('$oldStatus → $newStatus');
      };

      monitor.recordFailure(); // healthy → degraded
      monitor.recordFailure(); // stays degraded — no transition
      monitor.recordFailure(); // degraded → unavailable
      // recordSuccess from unavailable does NOT transition
      monitor.recordSuccess(); // stays unavailable — no transition

      // Only actual transitions fire the callback
      expect(transitions, [
        'BackendStatus.healthy → BackendStatus.degraded',
        'BackendStatus.degraded → BackendStatus.unavailable',
      ]);
    });

    test('status change callback fires for degraded → healthy via recordSuccess', () {
      final transitions = <String>[];
      monitor.onStatusChanged = (oldStatus, newStatus) {
        transitions.add('$oldStatus → $newStatus');
      };

      monitor.recordFailure(); // healthy → degraded
      monitor.recordSuccess(); // degraded → healthy

      expect(transitions, [
        'BackendStatus.healthy → BackendStatus.degraded',
        'BackendStatus.degraded → BackendStatus.healthy',
      ]);
    });

    // ── Lifecycle ──────────────────────────────────────────

    test('start and stop do not throw', () {
      monitor.start();
      monitor.stop();
      // No assertion needed — checking it doesn't throw
    });

    test('checkNow returns false when server is unreachable (no crash)', () async {
      // This makes a real HTTP call to test.proxy.local which doesn't exist.
      // The method should handle the timeout/error gracefully.
      final result = await monitor.checkNow();
      expect(result, isFalse);
      // After a failed health check, status should degrade
      expect(monitor.status, BackendStatus.degraded);
    });

    // ── lastSuccessfulCheck ─────────────────────────────────

    test('lastSuccessfulCheck is null before any success', () {
      expect(monitor.lastSuccessfulCheck, isNull);
    });

    test('lastSuccessfulCheck is set after recordSuccess', () {
      monitor.recordSuccess();
      expect(monitor.lastSuccessfulCheck, isNotNull);
      // Should be set to the current time (within 1 second)
      final now = DateTime.now();
      final diff = now.difference(monitor.lastSuccessfulCheck!).inMilliseconds.abs();
      expect(diff, lessThan(1000));
    });
  });
}
