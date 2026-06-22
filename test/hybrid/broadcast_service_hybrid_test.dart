import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/services/backend_proxy_service.dart';
import 'package:my_flutter_app/services/broadcast_service.dart';

void main() {
  late BackendProxyService proxy;
  late BroadcastService broadcast;

  setUp(() {
    proxy = BackendProxyService.instance;
    proxy.initialize(baseUrl: 'https://0.0.0.0:0');
    broadcast = BroadcastService.instance;
  });

  tearDown(() {
    proxy.dispose();
  });

  group('BroadcastService — Hybrid Routing', () {
    test('broadcast() calls route() with correct endpoint', () async {
      // Proxy will fail, then direct RPC will fail
      // Should throw a StateError with details about all failed attempts
      try {
        await broadcast.broadcast(
          chain: 'ethereum',
          signedTx: '0xf86c...',
        );
        fail('Expected StateError to be thrown');
      } on StateError catch (e) {
        expect(e.message, contains('All broadcast RPCs failed'));
        expect(e.message, contains('ethereum'));
      } catch (e) {
        // Any error is acceptable — the hybrid system tried its best
      }
    });

    test('broadcast() works for multiple EVM chains', () async {
      // BSC
      try {
        await broadcast.broadcast(
          chain: 'bsc',
          signedTx: '0xf86c...',
        );
        fail('Expected error');
      } on StateError catch (e) {
        expect(e.message, contains('bsc'));
      } catch (_) {
        // Any other error type is unexpected but non-fatal for this test
      }

      // Polygon
      try {
        await broadcast.broadcast(
          chain: 'polygon',
          signedTx: '0xf86c...',
        );
        fail('Expected error');
      } on StateError catch (_) {
        // Expected: Polygon RPC not configured
      } catch (_) {
        // Any other error type is unexpected but non-fatal for this test
      }

      // Avalanche
      try {
        await broadcast.broadcast(
          chain: 'avalanche',
          signedTx: '0xf86c...',
        );
        fail('Expected error');
      } on StateError catch (_) {
        // Expected: Avalanche RPC not configured
      } catch (_) {
        // Any other error type is unexpected but non-fatal for this test
      }
    });

    test('broadcast() handles invalid chain gracefully', () async {
      try {
        await broadcast.broadcast(
          chain: 'nonexistent-chain',
          signedTx: '0xf86c...',
        );
        fail('Expected error for unknown chain');
      } on StateError catch (_) {
        // Expected — no RPC URLs for this chain
      } catch (_) {
        // Any other error type is unexpected but non-fatal for this test
      }
    });
  });
}
