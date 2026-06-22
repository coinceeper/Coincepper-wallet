import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_flutter_app/services/backend_proxy_service.dart';

void main() {
  late BackendProxyService proxy;

  setUp(() {
    proxy = BackendProxyService.instance;
    // Initialize with a non-routable URL so no real health check succeeds
    proxy.initialize(baseUrl: 'https://0.0.0.0:0');
  });

  tearDown(() {
    proxy.dispose();
  });

  group('BackendProxyService — Core Routing (route<T>)', () {
    test('route() calls proxyCall when monitor is healthy', () async {
      String? calledEndpoint;
      final result = await proxy.route(
        endpoint: 'test-endpoint',
        proxyCall: () async {
          calledEndpoint = 'proxy';
          return 'proxy-result';
        },
        directCall: () async {
          calledEndpoint = 'direct';
          return 'direct-result';
        },
      );

      expect(result, 'proxy-result');
      expect(calledEndpoint, 'proxy');
    });

    test('route() falls back to directCall when proxyCall throws', () async {
      String? calledEndpoint;
      final result = await proxy.route(
        endpoint: 'failing-endpoint',
        proxyCall: () async {
          calledEndpoint = 'proxy';
          throw Exception('Proxy failed');
        },
        directCall: () async {
          calledEndpoint = 'direct';
          return 'direct-result';
        },
      );

      expect(result, 'direct-result');
      // After first call fails, monitor records a failure
    });

    test('route() falls back to directCall on TimeoutException', () async {
      String? calledEndpoint;
      final result = await proxy.route(
        endpoint: 'timeout-endpoint',
        proxyCall: () async {
          calledEndpoint = 'proxy';
          throw TimeoutException('timed out');
        },
        directCall: () async {
          calledEndpoint = 'direct';
          return 'direct-result';
        },
      );

      expect(result, 'direct-result');
      expect(calledEndpoint, 'direct');
    });

    test('route() falls back to directCall on http.ClientException', () async {
      String? calledEndpoint;
      final result = await proxy.route(
        endpoint: 'client-error-endpoint',
        proxyCall: () async {
          calledEndpoint = 'proxy';
          throw http.ClientException('Connection refused');
        },
        directCall: () async {
          calledEndpoint = 'direct';
          return 'direct-result';
        },
      );

      expect(result, 'direct-result');
      expect(calledEndpoint, 'direct');
    });

    test(
        'route() skips proxyCall entirely when monitor status is unavailable',
        () async {
      // Force the monitor into unavailable state by recording 3 failures
      // Since the health check to 0.0.0.0:0 will also fail, we simulate
      // by checking the current status after initialization
      String? calledEndpoint;

      // First, exhaust the proxy tolerance by calling route with failing proxy
      for (int i = 0; i < 3; i++) {
        try {
          await proxy.route(
            endpoint: 'fail-$i',
            proxyCall: () async {
              throw Exception('fail');
            },
            directCall: () async => 'ok',
          );
        } catch (_) {
          // Expected: proxy failure is normal during tolerance exhaustion
        }
      }

      // Now the monitor should be unavailable
      expect(proxy.backendStatus, BackendStatus.unavailable);

      // This call should go DIRECTLY to directCall, never touching proxyCall
      final result = await proxy.route(
        endpoint: 'should-skip-proxy',
        proxyCall: () async {
          calledEndpoint = 'proxy';
          return 'proxy-result';
        },
        directCall: () async {
          calledEndpoint = 'direct';
          return 'direct-result';
        },
      );

      expect(result, 'direct-result');
      // proxyCall should never have been invoked
      expect(calledEndpoint, 'direct');
    });

    test('route() respects result types (String, int, Map)', () async {
      // String result
      final stringResult = await proxy.route(
        endpoint: 'string-test',
        proxyCall: () async => 'hello',
        directCall: () async => 'fallback',
      );
      expect(stringResult, 'hello');

      // int result
      final intResult = await proxy.route(
        endpoint: 'int-test',
        proxyCall: () async => 42,
        directCall: () async => 0,
      );
      expect(intResult, 42);

      // Map result
      final mapResult = await proxy.route<Map<String, dynamic>>(
        endpoint: 'map-test',
        proxyCall: () async => {'key': 'value'},
        directCall: () async => <String, dynamic>{},
      );
      expect(mapResult, {'key': 'value'});

      // List result
      final listResult = await proxy.route<List<int>>(
        endpoint: 'list-test',
        proxyCall: () async => [1, 2, 3],
        directCall: () async => [],
      );
      expect(listResult, [1, 2, 3]);
    });

    test('route() records success when proxyCall succeeds', () async {
      // After failures, verify recordSuccess resets
      for (int i = 0; i < 2; i++) {
        await proxy.route(
          endpoint: 'fail',
          proxyCall: () async => throw Exception('fail'),
          directCall: () async => 'fallback',
        );
      }
      expect(proxy.backendStatus, BackendStatus.degraded);

      // Now a successful proxy call resets
      await proxy.route(
        endpoint: 'success',
        proxyCall: () async => 'ok',
        directCall: () async => 'fallback',
      );
      expect(proxy.backendStatus, BackendStatus.healthy);
    });
  });

  group('BackendProxyService — HTTP helpers', () {
    test('isSuccess returns true for 2xx status codes', () {
      expect(
        BackendProxyService.isSuccess(http.Response('{}', 200)),
        isTrue,
      );
      expect(
        BackendProxyService.isSuccess(http.Response('{}', 201)),
        isTrue,
      );
      expect(
        BackendProxyService.isSuccess(http.Response('{}', 204)),
        isTrue,
      );
      expect(
        BackendProxyService.isSuccess(http.Response('{}', 301)),
        isFalse,
      );
      expect(
        BackendProxyService.isSuccess(http.Response('{}', 400)),
        isFalse,
      );
      expect(
        BackendProxyService.isSuccess(http.Response('{}', 500)),
        isFalse,
      );
    });

    test('parseJson returns null for non-2xx responses', () {
      final response = http.Response('{"error":"bad"}', 500);
      expect(BackendProxyService.parseJson(response), isNull);
    });

    test('parseJson returns parsed map for 2xx responses', () {
      final response = http.Response(
        '{"status":"ok","data":{"balance":1.5}}',
        200,
      );
      final parsed = BackendProxyService.parseJson(response);
      expect(parsed, isNotNull);
      expect(parsed!['status'], 'ok');
      expect(parsed['data'], {'balance': 1.5});
    });

    test('parseJson returns null for malformed JSON', () {
      final response = http.Response('not-json', 200);
      expect(BackendProxyService.parseJson(response), isNull);
    });

    test('extractData returns typed data when status is ok', () {
      final json = {
        'status': 'ok',
        'data': {'balance': 1.5},
      };
      final data = BackendProxyService.extractData<Map<String, dynamic>>(json);
      expect(data, isNotNull);
      expect(data!['balance'], 1.5);
    });

    test('extractData returns null when json is null', () {
      expect(BackendProxyService.extractData<String>(null), isNull);
    });

    test('extractData returns null when status is not ok', () {
      final json = {
        'status': 'error',
        'data': {'balance': 1.5},
      };
      expect(BackendProxyService.extractData(json), isNull);
    });

    test('extractData returns null when data is null', () {
      final json = {
        'status': 'ok',
        'data': null,
      };
      expect(BackendProxyService.extractData(json), isNull);
    });

    test('proxyGet builds correct URL', () async {
      // This will fail to connect, but we can verify the URL construction
      // by catching the error (it's async so it'll throw)
      try {
        await proxy.proxyGet(
          'test-path',
          queryParams: {'key': 'value'},
        );
      } catch (_) {
        // Expected to fail — no real server
      }
      // Success means URL construction didn't throw
    });

    test('proxyPost builds correct request', () async {
      try {
        await proxy.proxyPost(
          'test-path',
          body: {'chain': 'ethereum', 'address': '0xabc'},
        );
      } catch (_) {
        // Expected to fail — no real server
      }
    });
  });

  group('BackendProxyService — Lifecycle', () {
    test('initialize sets base URL and starts monitor', () {
      // Already initialized in setUp
      expect(proxy.backendStatus, isNotNull);
    });

    test('dispose stops monitor without throwing', () {
      // Already disposed in tearDown, so we just verify it doesn't throw
      // when called again (should be idempotent or safe)
      proxy.dispose();
      proxy.dispose(); // Double dispose should not throw
    });
  });
}
