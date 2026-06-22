import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/secure_log.dart';

import 'backend_proxy_service.dart';
import 'build_secrets.dart';
import '../di/service_locator.dart';

/// Broadcasts signed transactions via backend proxy with direct fallback.
///
/// ## Non-custodial:
/// Private key هرگز از دستگاه خارج نمی‌شود. امضای تراکنش روی دستگاه انجام می‌شود.
/// بک‌اند فقط signedTx را می‌بیند که یکبارمصرف است (nonce-based) و
/// حتی اگر بک‌اند آن را ببیند، نمی‌تواند دوباره استفاده کند.
class BroadcastService {
  BroadcastService._();
  BroadcastService();
  static BroadcastService get instance => ServiceLocator.get<BroadcastService>();

  /// Broadcast a signed transaction.
  ///
  /// [chain] - blockchain name (e.g. "ethereum", "bsc", "polygon")
  /// [signedTx] - signed raw transaction hex string (e.g. "0xf86c...")
  ///
  /// Returns the transaction hash on success, or throws on failure.
  Future<String> broadcast({
    required String chain,
    required String signedTx,
  }) async {
    return ServiceLocator.get<BackendProxyService>().route(
      endpoint: 'broadcast/$chain',
      proxyCall: () => _broadcastViaProxy(chain, signedTx),
      directCall: () => _broadcastViaDirectRpc(chain, signedTx),
    );
  }

  Future<String> _broadcastViaProxy(String chain, String signedTx) async {
    final response = await ServiceLocator.get<BackendProxyService>()
        .proxyPost('broadcast', body: {
      'chain': chain.toLowerCase(),
      'signed_tx': signedTx,
    });

    final json = BackendProxyService.parseJson(response);
    if (json == null || json['status'] != 'ok') {
      throw Exception('Proxy broadcast failed');
    }

    final txHash = json['tx_hash'] as String? ?? json['txHash'] as String?;
    if (txHash == null || txHash.isEmpty) {
      throw Exception('Proxy broadcast returned no tx hash');
    }

    SecureLog.i('📡 Broadcast via proxy: $txHash');
    return txHash;
  }

  Future<String> _broadcastViaDirectRpc(String chain, String signedTx) async {
    final rpcBody = {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'eth_sendRawTransaction',
      'params': [signedTx],
    };

    final urls = _getDirectRpcUrls(chain);
    final errors = <String>[];

    for (final url in urls) {
      try {
        final res = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(rpcBody),
            )
            .timeout(const Duration(seconds: 15));

        final map = jsonDecode(res.body) as Map<String, dynamic>;
        if (map['error'] == null) {
          final txHash = map['result'] as String?;
          if (txHash != null && txHash.isNotEmpty) {
            SecureLog.i('📡 Broadcast via direct RPC: $txHash ($url)');
            return txHash;
          }
        }
        errors.add('$url → ${map['error']}');
      } catch (e) {
        errors.add('$url → $e');
      }
    }

    throw StateError(
      'All broadcast RPCs failed for $chain:\n${errors.join('\n')}',
    );
  }

  List<String> _getDirectRpcUrls(String blockchainName) {
    final n = blockchainName.toLowerCase();
    final urls = <String>[];

    void addIf(String url) {
      if (url.isNotEmpty) urls.add(url);
    }

    if (BuildSecrets.drpcApiKey.isNotEmpty) {
      addIf(
          'https://lb.drpc.live/${_drpcChain(n)}/${BuildSecrets.drpcApiKey}');
    }
    if (BuildSecrets.ankrApiKey.isNotEmpty) {
      addIf(
          'https://rpc.ankr.com/${_ankrChain(n)}/${BuildSecrets.ankrApiKey}');
    }
    addIf(_publicNodeUrl(n));

    return urls;
  }

  static String _drpcChain(String n) {
    if (n.contains('ethereum') || n == 'eth') return 'ethereum';
    if (n.contains('bsc') || n.contains('binance')) return 'bsc';
    if (n.contains('polygon')) return 'polygon';
    if (n.contains('avalanche')) return 'avalanche';
    if (n.contains('arbitrum')) return 'arbitrum';
    return 'ethereum';
  }

  static String _ankrChain(String n) {
    if (n.contains('ethereum') || n == 'eth') return 'eth';
    if (n.contains('bsc') || n.contains('binance')) return 'bsc';
    if (n.contains('polygon')) return 'polygon';
    if (n.contains('avalanche')) return 'avalanche';
    if (n.contains('arbitrum')) return 'arbitrum';
    return 'eth';
  }

  static String _publicNodeUrl(String n) {
    if (n.contains('bsc') || n.contains('binance')) {
      return 'https://bsc.publicnode.com';
    }
    if (n.contains('polygon')) return 'https://polygon-bor.publicnode.com';
    if (n.contains('avalanche')) {
      return 'https://avalanche-c-chain.publicnode.com';
    }
    if (n.contains('arbitrum')) return 'https://arbitrum-one.publicnode.com';
    return 'https://ethereum.publicnode.com';
  }
}
