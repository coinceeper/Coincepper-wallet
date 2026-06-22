import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../models/transaction.dart';
import '../../../services/backend_proxy_service.dart';
import '../../../services/build_secrets.dart';
import '../../../utils/secure_log.dart';
import '../../../di/service_locator.dart';

class EvmHistoryIndexer {
  static const _explorers = {
    'ethereum': 'https://api.etherscan.io',
    'polygon': 'https://api.polygonscan.com',
    'bsc': 'https://api.bscscan.com',
    'binance': 'https://api.bscscan.com',
    'avalanche': 'https://api.snowtrace.io',
    'arbitrum': 'https://api.arbiscan.io',
  };

  /// Returns the correct explorer API key for [blockchainName].
  static String _apiKeyFor(String blockchainName) {
    return BuildSecrets.explorerApiKeyForBlockchain(blockchainName);
  }

  /// Fetch transaction history with Hybrid strategy:
  /// 1. Try backend proxy first (POST /api/v2/explorer/tx-history)
  /// 2. Fallback to direct explorer API
  Future<List<Transaction>> fetch(
    String blockchainName,
    String address,
  ) async {
    return ServiceLocator.get<BackendProxyService>().route(
      endpoint: 'explorer/tx-history',
      proxyCall: () => _fetchFromProxy(blockchainName, address),
      directCall: () => _fetchDirect(blockchainName, address),
    );
  }

  /// Fetch via backend proxy.
  Future<List<Transaction>> _fetchFromProxy(
    String blockchainName,
    String address,
  ) async {
    final response = await ServiceLocator.get<BackendProxyService>()
        .proxyPost('explorer/tx-history', body: {
      'chain': blockchainName.toLowerCase(),
      'address': address,
      'page': 1,
      'limit': 25,
    });

    final json = BackendProxyService.parseJson(response);
    if (json == null || json['status'] != 'ok') {
      throw Exception('Proxy tx-history failed');
    }

    final rawList = json['data'] as List<dynamic>? ?? [];
    // Proxy returns the same shape as direct response,
    // so we reuse the parsing logic
    return _parseTransactions(rawList, blockchainName, address);
  }

  /// Direct explorer API (existing implementation).
  Future<List<Transaction>> _fetchDirect(
    String blockchainName,
    String address,
  ) async {
    final base = _explorers[blockchainName.toLowerCase()] ??
        _explorers['ethereum']!;
    final apiKey = _apiKeyFor(blockchainName);
    final uri = Uri.parse(
      '$base/api?module=account&action=txlist&address=$address'
      '&startblock=0&endblock=99999999&sort=desc&apikey=$apiKey',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) return [];
    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      SecureLog.w('EvmHistoryIndexer: explorer returned non-JSON response', error: e);
      return [];
    }
    if (body['status'] != '1') return [];
    final list = body['result'] as List<dynamic>? ?? [];
    return _parseTransactions(list, blockchainName, address);
  }

  /// Shared transaction parser.
  List<Transaction> _parseTransactions(
    List<dynamic> rawList,
    String blockchainName,
    String address,
  ) {
    final out = <Transaction>[];
    final addrLower = address.toLowerCase();

    for (final raw in rawList.take(50)) {
      if (raw is! Map) continue;
      final hash = raw['hash']?.toString() ?? '';
      final from = raw['from']?.toString() ?? '';
      final to = raw['to']?.toString() ?? '';
      final valueWei = raw['value']?.toString() ?? '0';
      final success =
          raw['isError'] == '0' || raw['txreceipt_status'] == '1';
      final status = success ? 'completed' : 'failed';
      final ts = int.tryParse(raw['timeStamp']?.toString() ?? '') ?? 0;

      final valueWeiBig = BigInt.tryParse(valueWei) ?? BigInt.zero;
      final amountEth =
          (valueWeiBig / BigInt.from(10).pow(18)).toStringAsFixed(18);
      final formattedAmount =
          double.tryParse(amountEth)?.toString() ?? amountEth;

      String direction;
      if (from.toLowerCase() == addrLower) {
        direction = 'outbound';
      } else {
        direction = 'inbound';
      }

      out.add(Transaction(
        txHash: hash,
        from: from,
        to: to,
        amount: formattedAmount,
        tokenSymbol: 'ETH',
        direction: direction,
        status: status,
        timestamp: DateTime.fromMillisecondsSinceEpoch(ts * 1000)
            .toIso8601String(),
        blockchainName: blockchainName,
      ));
    }
    return out;
  }
}
