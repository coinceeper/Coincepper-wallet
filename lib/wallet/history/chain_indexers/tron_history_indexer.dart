import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../models/transaction.dart';
import '../../../services/build_secrets.dart';

class TronHistoryIndexer {
  Map<String, String> _headers() {
    final keys = BuildSecrets.trongridApiKeys;
    final key = keys.isNotEmpty ? keys.first : '';
    return key.isNotEmpty
        ? {'TRON-PRO-API-KEY': key}
        : {};
  }

  Future<List<Transaction>> fetch(String address) async {
    final uri = Uri.parse(
      'https://api.trongrid.io/v1/accounts/$address/transactions?limit=40',
    );
    final res = await http
        .get(uri, headers: _headers())
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>? ?? [];
    final out = <Transaction>[];
    for (final item in data) {
      if (item is! Map) continue;
      final raw = item['raw_data'] as Map<String, dynamic>?;
      final contract = raw?['contract'] as List<dynamic>?;
      if (contract == null || contract.isEmpty) continue;
      final first = contract.first;
      if (first is! Map) continue;
      final param = first['parameter'] as Map<String, dynamic>?;
      final value = param?['value'] as Map<String, dynamic>?;
      if (value == null) continue;
      final amountSun = value['amount'] as num? ?? 0;
      final to = value['to_address']?.toString() ?? '';
      final from = value['owner_address']?.toString() ?? '';
      final hash = item['txID']?.toString() ?? '';
      final ts = raw?['timestamp'] as num? ?? 0;
      out.add(Transaction(
        txHash: hash,
        from: from,
        to: to,
        amount: (amountSun / 1e6).toStringAsFixed(6),
        tokenSymbol: 'TRX',
        direction: from.toLowerCase().contains(address.toLowerCase().substring(1))
            ? 'outbound'
            : 'inbound',
        status: 'completed',
        timestamp: DateTime.fromMillisecondsSinceEpoch(ts.toInt())
            .toIso8601String(),
        blockchainName: 'Tron',
      ));
    }
    return out;
  }
}
