import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../models/transaction.dart';
import '../../../services/build_secrets.dart';

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
    final n = blockchainName.toLowerCase();
    if (n.contains('bsc') || n.contains('binance')) {
      return BuildSecrets.bscscanApiKey;
    }
    if (n.contains('polygon')) return BuildSecrets.polygonscanApiKey;
    if (n.contains('avalanche')) return BuildSecrets.avalancheApiKey;
    if (n.contains('arbitrum')) return BuildSecrets.arbitrumscanApiKey;
    return BuildSecrets.etherscanApiKey; // default / Ethereum
  }

  Future<List<Transaction>> fetch(
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
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['status'] != '1') return [];
    final list = body['result'] as List<dynamic>? ?? [];
    final out = <Transaction>[];
    final addrLower = address.toLowerCase();

    for (final raw in list.take(50)) {
      if (raw is! Map) continue;
      final hash = raw['hash']?.toString() ?? '';
      final from = raw['from']?.toString() ?? '';
      final to = raw['to']?.toString() ?? '';
      final valueWei = raw['value']?.toString() ?? '0';
      final confirmations =
          int.tryParse(raw['confirmations']?.toString() ?? '0') ?? 0;
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
