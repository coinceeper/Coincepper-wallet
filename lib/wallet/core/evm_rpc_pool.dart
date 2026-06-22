import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../services/backend_proxy_service.dart';
import '../../services/build_secrets.dart';
import '../../di/service_locator.dart';

/// Multi-provider RPC pool for EVM chains with automatic fallback.
///
/// ## استراتژی Hybrid:
/// 1. **Backend Proxy (Primary)**: POST /api/v2/rpc/{chain} — cache دار
/// 2. **Direct (Fallback)**: Pool مستقیم (dRPC → Ankr → ... → PublicNode)
///
/// Priority order for direct:
///   1. dRPC     (50M CU/mo, one key for all chains)
///   2. Ankr     (200M CU/mo Freemium, one key for all chains)
///   3. Chainstack (per-chain token)
///   4. Tenderly   (per-chain gateway)
///   5. Etox       (per-chain endpoint)
///   6. BlockPI    (per-chain endpoint)
///   7. PublicNode (free, always available — last resort)
class EvmRpcPool {
  EvmRpcPool._();

  /// Returns all available direct RPC URLs for [blockchainName], in priority order.
  static List<String> evmRpcUrls(String blockchainName) {
    final n = blockchainName.toLowerCase();
    final urls = <String>[];

    void addIf(String url) {
      if (url.isNotEmpty) urls.add(url);
    }

    // 1. dRPC
    if (BuildSecrets.drpcApiKey.isNotEmpty) {
      final chain = _drpcChain(n);
      addIf('https://lb.drpc.live/$chain/${BuildSecrets.drpcApiKey}');
    }

    // 2. Ankr
    if (BuildSecrets.ankrApiKey.isNotEmpty) {
      final chain = _ankrChain(n);
      addIf('https://rpc.ankr.com/$chain/${BuildSecrets.ankrApiKey}');
    }

    // 3. Chainstack per-chain
    if ((n.contains('ethereum') || n == 'eth') &&
        BuildSecrets.chainstackEthToken.isNotEmpty) {
      addIf(
        'https://ethereum-mainnet.core.chainstack.com/${BuildSecrets.chainstackEthToken}',
      );
    }
    if ((n.contains('bsc') || n.contains('binance')) &&
        BuildSecrets.chainstackBscToken.isNotEmpty) {
      addIf(
        'https://bsc-mainnet.core.chainstack.com/${BuildSecrets.chainstackBscToken}',
      );
    }

    // 4. Tenderly per-chain
    if ((n.contains('ethereum') || n == 'eth') &&
        BuildSecrets.tenderlyEthRpc.isNotEmpty) {
      addIf(BuildSecrets.tenderlyEthRpc);
    }
    if (n.contains('polygon') && BuildSecrets.tenderlyPolygonRpc.isNotEmpty) {
      addIf(BuildSecrets.tenderlyPolygonRpc);
    }
    if (n.contains('arbitrum') && BuildSecrets.tenderlyArbitrumRpc.isNotEmpty) {
      addIf(BuildSecrets.tenderlyArbitrumRpc);
    }
    if (n.contains('avalanche') &&
        BuildSecrets.tenderlyAvalancheRpc.isNotEmpty) {
      addIf(BuildSecrets.tenderlyAvalancheRpc);
    }

    // 5. Etox per-chain
    if ((n.contains('ethereum') || n == 'eth') &&
        BuildSecrets.etoxEthRpc.isNotEmpty) {
      addIf(BuildSecrets.etoxEthRpc);
    }
    if (n.contains('arbitrum') && BuildSecrets.etoxArbRpc.isNotEmpty) {
      addIf(BuildSecrets.etoxArbRpc);
    }
    if (n.contains('polygon') && BuildSecrets.etoxPolygonRpc.isNotEmpty) {
      addIf(BuildSecrets.etoxPolygonRpc);
    }

    // 6. BlockPI per-chain
    if ((n.contains('ethereum') || n == 'eth') &&
        BuildSecrets.blockpiEthRpc.isNotEmpty) {
      addIf(BuildSecrets.blockpiEthRpc);
    }
    if ((n.contains('bsc') || n.contains('binance')) &&
        BuildSecrets.blockpiBscRpc.isNotEmpty) {
      addIf(BuildSecrets.blockpiBscRpc);
    }
    if (n.contains('polygon') && BuildSecrets.blockpiPolygonRpc.isNotEmpty) {
      addIf(BuildSecrets.blockpiPolygonRpc);
    }
    if (n.contains('arbitrum') && BuildSecrets.blockpiArbitrumRpc.isNotEmpty) {
      addIf(BuildSecrets.blockpiArbitrumRpc);
    }
    if (n.contains('avalanche') &&
        BuildSecrets.blockpiAvalancheRpc.isNotEmpty) {
      addIf(BuildSecrets.blockpiAvalancheRpc);
    }

    // 7. PublicNode (last-resort fallback)
    addIf(_publicNodeUrl(n));

    return urls;
  }

  /// Returns the **primary** (highest-priority) RPC URL.
  static String evmRpcForBlockchain(String blockchainName) {
    final urls = evmRpcUrls(blockchainName);
    return urls.isNotEmpty
        ? urls.first
        : _publicNodeUrl(blockchainName.toLowerCase());
  }

  /// Make an RPC call with Hybrid strategy:
  /// 1. Try backend proxy first (POST /api/v2/rpc/{chain})
  /// 2. Fallback to direct RPC pool
  static Future<Map<String, dynamic>> tryPost(
    String blockchainName,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    return ServiceLocator.get<BackendProxyService>().route(
      endpoint: 'rpc/$blockchainName',
      proxyCall: () => _tryPostViaProxy(blockchainName, body),
      directCall: () => _tryPostDirect(blockchainName, body, timeout: timeout),
    );
  }

  /// Try RPC call via backend proxy.
  static Future<Map<String, dynamic>> _tryPostViaProxy(
    String blockchainName,
    Map<String, dynamic> body,
  ) async {
    final response =
        await ServiceLocator.get<BackendProxyService>().proxyPost('rpc/$blockchainName', body: {
      'jsonrpc': body['jsonrpc'] ?? '2.0',
      'method': body['method'],
      'params': body['params'] ?? [],
      'id': body['id'] ?? 1,
    });

    final json = BackendProxyService.parseJson(response);
    if (json == null) throw Exception('Proxy RPC returned no data');
    if (json['error'] != null) {
      throw Exception('Proxy RPC error: ${json['error']}');
    }
    return json;
  }

  /// Direct RPC pool (existing implementation).
  static Future<Map<String, dynamic>> _tryPostDirect(
    String blockchainName,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final urls = evmRpcUrls(blockchainName);
    final errors = <String>[];
    for (final url in urls) {
      try {
        final res = await http
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(timeout);
        final map = jsonDecode(res.body) as Map<String, dynamic>;
        if (map['error'] == null) return map;
        errors.add('$url → ${map['error']}');
      } catch (e) {
        errors.add('$url → $e');
      }
    }
    throw StateError(
      'All ${urls.length} RPC(s) failed for $blockchainName:\n${errors.join('\n')}',
    );
  }

  // ── helpers ────────────────────────────────────────────────

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
