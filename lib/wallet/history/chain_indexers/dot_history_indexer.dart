import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../models/transaction.dart';
import '../../../services/build_secrets.dart';

class DotHistoryIndexer {
  Map<String, String> _headers() {
    final keys = BuildSecrets.subscanApiKeys;
    return {
      'Content-Type': 'application/json',
      if (keys.isNotEmpty) 'X-API-Key': keys.first,
    };
  }

  Future<List<Transaction>> fetch(String address) async {
    final res = await http
        .post(
          Uri.parse('https://polkadot.api.subscan.io/api/v2/scan/transfers'),
          headers: _headers(),
          body: jsonEncode({
            'address': address,
            'row': 25,
            'page': 0,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) return [];
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>?;
    final transfers = data?['transfers'] as List<dynamic>? ?? [];
    final out = <Transaction>[];
    for (final t in transfers) {
      if (t is! Map) continue;
      final hash = t['hash']?.toString() ?? '';
      final amount = t['amount']?.toString() ?? '0';
      final from = t['from']?.toString() ?? '';
      final to = t['to']?.toString() ?? '';
      final ts = t['block_timestamp'] as int? ?? 0;
      if (hash.isEmpty) continue;
      final inbound = to == address;
      out.add(
        Transaction(
          txHash: hash,
          amount: amount,
          tokenSymbol: 'DOT',
          blockchainName: 'Polkadot',
          timestamp: DateTime.fromMillisecondsSinceEpoch(ts * 1000)
              .toIso8601String(),
          direction: inbound ? 'inbound' : 'outbound',
          status: 'completed',
          from: inbound ? from : address,
          to: inbound ? address : to,
        ),
      );
    }
    return out;
  }
}
