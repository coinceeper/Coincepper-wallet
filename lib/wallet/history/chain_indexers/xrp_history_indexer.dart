import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../models/transaction.dart';

class XrpHistoryIndexer {
  Future<List<Transaction>> fetch(String address) async {
    final res = await http
        .post(
          Uri.parse('https://s1.ripple.com:51234/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'method': 'account_tx',
            'params': [
              {
                'account': address,
                'ledger_index_min': -1,
                'ledger_index_max': -1,
                'limit': 25,
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) return [];
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final txs = map['result']?['transactions'] as List<dynamic>? ?? [];
    final out = <Transaction>[];
    for (final wrapper in txs) {
      if (wrapper is! Map) continue;
      final tx = wrapper['tx'] as Map<String, dynamic>? ?? {};
      final hash = tx['hash']?.toString() ?? '';
      final amountDrops = tx['Amount']?.toString() ?? '0';
      final drops = int.tryParse(amountDrops) ?? 0;
      final date = tx['date'] as int? ?? 0;
      final destination = tx['Destination']?.toString() ?? '';
      final account = tx['Account']?.toString() ?? '';
      if (hash.isEmpty) continue;
      final inbound = destination == address;
      out.add(
        Transaction(
          txHash: hash,
          amount: (drops / 1e6).toString(),
          tokenSymbol: 'XRP',
          blockchainName: 'XRP',
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            (date + 946684800) * 1000,
          ).toIso8601String(),
          direction: inbound ? 'inbound' : 'outbound',
          status: 'completed',
          from: inbound ? account : address,
          to: inbound ? address : destination,
        ),
      );
    }
    return out;
  }
}
