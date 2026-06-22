/// Full Hybrid Integration Test
///
/// Tests the complete proxy → cache → direct fallback architecture.
///
/// ## Architecture verified:
/// 1. **Proxy available** → all traffic routes through the cache proxy
/// 2. **Proxy failing** → degrades health, still tries proxy then falls back
/// 3. **Proxy unavailable** → after 3 failures, all traffic skips proxy
///    and goes direct immediately
/// 4. **Proxy recovery** → health check succeeds, traffic routes back to proxy
///
/// ## Non-custodial verification:
/// All calls use public addresses or signed transactions (one-time-use).
/// Private keys never leave the device.
library;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/services/backend_connectivity_monitor.dart';
import 'package:my_flutter_app/services/backend_proxy_service.dart';

/// Test harness that simulates proxy calls using closures.
///
/// This tests the routing logic of [BackendProxyService.route()] without
/// making real network calls. The `proxyCall` and `directCall` closures are
/// the actual code paths used by all services in production.
class TestHybridHarness {
  final BackendProxyService proxy = BackendProxyService.instance;

  int proxyCallCount = 0;
  int directCallCount = 0;
  String? lastEndpoint;

  /// Reset all counters.
  void reset() {
    proxyCallCount = 0;
    directCallCount = 0;
    lastEndpoint = null;
  }

  /// Initialize the harness.
  Future<void> init() async {
    proxy.initialize(baseUrl: 'https://0.0.0.0:0');
    await Future<void>.delayed(Duration.zero);
  }

  /// Shut down.
  void dispose() {
    proxy.dispose();
  }

  /// Simulate a route call with controlled closures.
  Future<T> simulateRoute<T>({
    required String endpoint,
    T? proxyData,
    T? directData,
    Duration proxyDelay = Duration.zero,
    bool proxyThrows = false,
  }) async {
    return proxy.route<T>(
      endpoint: endpoint,
      proxyCall: () async {
        proxyCallCount++;
        lastEndpoint = endpoint;
        if (proxyDelay > Duration.zero) {
          await Future<void>.delayed(proxyDelay);
        }
        if (proxyThrows) {
          throw Exception('Simulated proxy failure for $endpoint');
        }
        if (proxyData != null) return proxyData;
        return 'proxy-ok' as T;
      },
      directCall: () async {
        directCallCount++;
        if (directData != null) return directData;
        return 'direct-ok' as T;
      },
    );
  }
}

/// A minimal HTTP server for testing health check recovery.
///
/// Serves a 200 OK with `{"status":"ok"}` on `GET /health`.
class TestHealthServer {
  HttpServer? _server;
  int _requestCount = 0;
  int _responseDelayMs = 0;

  int get requestCount => _requestCount;

  /// Start the server on a random port.
  Future<int> start({int responseDelayMs = 0}) async {
    _responseDelayMs = responseDelayMs;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleRequest);
    return _server!.port;
  }

  void _handleRequest(HttpRequest request) {
    _requestCount++;
    if (_responseDelayMs > 0) {
      Future<void>.delayed(Duration(milliseconds: _responseDelayMs), () {
        _respondOk(request);
      });
    } else {
      _respondOk(request);
    }
  }

  void _respondOk(HttpRequest request) {
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write('{"status":"ok"}')
      ..close();
  }

  Future<void> stop() async {
    await _server?.close();
  }
}

void main() {
  group('Full Hybrid Integration — Complete Lifecycle', () {
    late TestHybridHarness harness;

    setUp(() async {
      harness = TestHybridHarness();
      await harness.init();
    });

    tearDown(() {
      harness.dispose();
    });

    test('1. Proxy available → all traffic goes through proxy', () async {
      const numRequests = 5;
      for (int i = 0; i < numRequests; i++) {
        final result = await harness.simulateRoute<String>(
          endpoint: 'prices',
          proxyData: 'proxy-data-$i',
        );
        expect(result, startsWith('proxy-data'));
      }

      expect(harness.proxyCallCount, numRequests);
      expect(harness.directCallCount, 0);
      expect(harness.proxy.backendStatus, BackendStatus.healthy);
    });

    test('2. Proxy fails → falls back to direct, degrades health', () async {
      final result = await harness.simulateRoute<String>(
        endpoint: 'balance',
        proxyThrows: true,
        directData: 'direct-balance',
      );

      expect(result, 'direct-balance');
      expect(harness.proxyCallCount, 1);
      expect(harness.directCallCount, 1);
      // After 1 failure: healthy → degraded
      expect(harness.proxy.backendStatus, BackendStatus.degraded);
    });

    test('3. Three failures → unavailable; all traffic skips proxy', () async {
      // First failure → degraded
      await harness.simulateRoute<String>(
        endpoint: 'gas',
        proxyThrows: true,
        directData: 'direct-gas-1',
      );
      expect(harness.proxy.backendStatus, BackendStatus.degraded);

      // Second failure → still degraded
      await harness.simulateRoute<String>(
        endpoint: 'gas',
        proxyThrows: true,
        directData: 'direct-gas-2',
      );
      expect(harness.proxy.backendStatus, BackendStatus.degraded);

      // Third failure → unavailable!
      await harness.simulateRoute<String>(
        endpoint: 'gas',
        proxyThrows: true,
        directData: 'direct-gas-3',
      );
      expect(harness.proxy.backendStatus, BackendStatus.unavailable);

      // Reset counters
      harness.reset();

      // When unavailable, route() skips proxyCall entirely and goes direct
      final result = await harness.simulateRoute<String>(
        endpoint: 'prices',
        proxyData: 'should-not-be-called',
        directData: 'direct-after-unavailable',
      );

      expect(result, 'direct-after-unavailable');
      expect(
        harness.proxyCallCount, 0,
        reason: 'Proxy was unavailable — route() skips proxyCall entirely',
      );
      expect(harness.directCallCount, 1);
    });

    test('4. Mixed traffic: proxy recovers from degraded after success', () async {
      // Simulate: success → fail → fail → success → success

      // Success
      await harness.simulateRoute<String>(
        endpoint: 'prices', proxyData: 'ok',
      );
      expect(harness.proxy.backendStatus, BackendStatus.healthy);

      // Fail
      await harness.simulateRoute<String>(
        endpoint: 'chart', proxyThrows: true, directData: 'direct',
      );
      expect(harness.proxy.backendStatus, BackendStatus.degraded);

      // Fail again
      await harness.simulateRoute<String>(
        endpoint: 'coins', proxyThrows: true, directData: 'direct',
      );
      expect(harness.proxy.backendStatus, BackendStatus.degraded);

      // Success — recordSuccess() recovers degraded → healthy
      await harness.simulateRoute<String>(
        endpoint: 'prices', proxyData: 'recovered',
      );
      expect(harness.proxy.backendStatus, BackendStatus.healthy);

      // Next request goes to proxy
      final result = await harness.simulateRoute<String>(
        endpoint: 'prices', proxyData: 'proxy-again',
      );
      expect(result, 'proxy-again');
    });

    test('5. Sequence: 20 mixed requests simulate real-world usage', () async {
      harness.reset();
      final results = <String>[];

      for (int i = 0; i < 20; i++) {
        String result;
        if (i < 10) {
          // First 10: proxy works fine
          result = await harness.simulateRoute<String>(
            endpoint: 'api-call-$i',
            proxyData: 'proxy-$i',
          );
        } else if (i < 13) {
          // Next 3: proxy fails → fallback to direct
          result = await harness.simulateRoute<String>(
            endpoint: 'api-call-$i',
            proxyThrows: true,
            directData: 'direct-$i',
          );
        } else {
          // Last 7: proxy unavailable → all direct
          result = await harness.simulateRoute<String>(
            endpoint: 'api-call-$i',
            proxyData: 'proxy-$i', // won't be called
            directData: 'direct-$i',
          );
        }
        results.add(result);
      }

      // First 10: proxy
      for (int i = 0; i < 10; i++) {
        expect(results[i], 'proxy-$i');
      }
      // Next 3: direct (proxy failed)
      for (int i = 10; i < 13; i++) {
        expect(results[i], 'direct-$i');
      }
      // After 3rd consecutive failure (i=12), proxy went unavailable
      // Last 7: direct (proxy skipped entirely)
      for (int i = 13; i < 20; i++) {
        expect(results[i], 'direct-$i');
      }

      expect(harness.proxy.backendStatus, BackendStatus.unavailable);
    });
  });

  group('Health Check Recovery — Real HTTP Server', () {
    /// This group starts a real local HTTP server to test health check
    /// recovery. The monitor pings the server for health checks, allowing
    /// us to verify the full unavailable → healthy transition.

    test('Health check recovers proxy from unavailable', () async {
      final server = TestHealthServer();
      final port = await server.start();

      // Create a monitor pointing to our local test server
      final monitor = BackendConnectivityMonitor(
        baseUrl: 'http://127.0.0.1:$port',
      );

      try {
        // Initial state: healthy
        expect(monitor.status, BackendStatus.healthy);

        // Drive to unavailable via 3 consecutive failures
        monitor.recordFailure(); // healthy → degraded
        monitor.recordFailure(); // stays degraded
        monitor.recordFailure(); // degraded → unavailable
        expect(monitor.status, BackendStatus.unavailable);

        // Now run health check — server returns 200 → recovers to healthy
        final healthy = await monitor.checkNow();
        expect(healthy, isTrue);
        expect(monitor.status, BackendStatus.healthy);
        expect(server.requestCount, greaterThanOrEqualTo(1));
      } finally {
        monitor.stop();
        await server.stop();
      }
    });

    test('Health check detects slow response → degraded', () async {
      final server = TestHealthServer();
      final port = await server.start(responseDelayMs: 2500); // > 2s

      final monitor = BackendConnectivityMonitor(
        baseUrl: 'http://127.0.0.1:$port',
      );

      try {
        // Drive to unavailable
        monitor.recordFailure();
        monitor.recordFailure();
        monitor.recordFailure();
        expect(monitor.status, BackendStatus.unavailable);

        // Health check succeeds but slow → recovers to degraded
        final healthy = await monitor.checkNow();
        expect(healthy, isTrue);
        expect(
          monitor.status,
          BackendStatus.degraded,
          reason: 'Response > 2s should set degraded',
        );
      } finally {
        monitor.stop();
        await server.stop();
      }
    });

    test('Health check fails → stays unavailable', () async {
      final server = TestHealthServer();
      final port = await server.start();

      final monitor = BackendConnectivityMonitor(
        baseUrl: 'http://127.0.0.1:$port',
      );

      try {
        // Drive to unavailable
        monitor.recordFailure();
        monitor.recordFailure();
        monitor.recordFailure();
        expect(monitor.status, BackendStatus.unavailable);

        // Stop the server so health check fails
        await server.stop();

        // Health check fails → stays unavailable
        final healthy = await monitor.checkNow();
        expect(healthy, isFalse);
        expect(monitor.status, BackendStatus.unavailable);
      } finally {
        monitor.stop();
      }
    });
  });

  group('Edge Cases & Error Handling', () {
    late TestHybridHarness harness;

    setUp(() async {
      harness = TestHybridHarness();
      await harness.init();
    });

    tearDown(() {
      harness.dispose();
    });

    test('Both proxy and direct fail → exception from direct propagates', () async {
      // route() catches proxyCall error and falls back to directCall
      // The error from directCall propagates to the caller
      try {
        await harness.proxy.route<String>(
          endpoint: 'both-fail',
          proxyCall: () async => throw Exception('Proxy error'),
          directCall: () async => throw Exception('Direct error'),
        );
        fail('Expected exception when both routes fail');
      } on Exception catch (e) {
        // proxy error is caught by route(), direct error propagates
        expect(e.toString(), contains('Direct error'));
      }
    });

    test('Quick proxy → no direct call, fast response', () async {
      final sw = Stopwatch()..start();
      await harness.simulateRoute<String>(
        endpoint: 'fast',
        proxyData: 'instant',
      );
      sw.stop();
      // Should be very fast since no real network I/O
      expect(sw.elapsedMilliseconds, lessThan(100));
    });

    test('Multiple endpoints share the same monitor state', () async {
      // Different endpoints all use the same BackendConnectivityMonitor
      await harness.simulateRoute<String>(
        endpoint: 'prices', proxyThrows: true, directData: 'prices-direct',
      );
      await harness.simulateRoute<String>(
        endpoint: 'balance', proxyThrows: true, directData: 'balance-direct',
      );
      await harness.simulateRoute<String>(
        endpoint: 'gas', proxyThrows: true, directData: 'gas-direct',
      );

      // After 3 failures across different endpoints → monitor unavailable
      expect(harness.proxy.backendStatus, BackendStatus.unavailable);

      // Reset counters — next call should skip proxy entirely
      harness.reset();

      final result = await harness.simulateRoute<String>(
        endpoint: 'broadcast',
        proxyData: 'should-skip',
        directData: 'direct-broadcast',
      );
      expect(result, 'direct-broadcast');
      expect(harness.proxyCallCount, 0, reason: 'Proxy was skipped when unavailable');
      expect(harness.directCallCount, 1);
    });

    test('Proxy timeout triggers fallback to direct', () async {
      final result = await harness.simulateRoute<String>(
        endpoint: 'slow',
        proxyThrows: true, // Simulates timeout
        directData: 'direct-fast',
      );
      expect(result, 'direct-fast');
      expect(harness.proxy.backendStatus, BackendStatus.degraded);
    });
  });
}
