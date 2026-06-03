import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../models/transaction.dart';

class BtcHistoryIndexer {
  Future<List<Transaction>> fetch(String address) async {
    final uri = Uri.parse('https://blockstream.info/api/address/$address/txs');
    final res = await http.get(uri).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) return [];
    final list = jsonDecode(res.body) as List<dynamic>;
    final out = <Transaction>[];
    final addrLower = address.toLowerCase();

    for (final raw in list.take(50)) {
      if (raw is! Map) continue;
      final txid = raw['txid']?.toString() ?? '';
      final status = raw['status'] is Map
          ? (raw['status']['confirmed'] == true ? 'completed' : 'pending')
          : 'completed';
      final ts = raw['status'] is Map && raw['status']['block_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (raw['status']['block_time'] as int) * 1000,
            ).toIso8601String()
          : DateTime.now().toIso8601String();

      var received = 0.0;
      var sent = 0.0;
      String? counterparty;
      final vouts = raw['vout'] as List<dynamic>? ?? [];
      final vins = raw['vin'] as List<dynamic>? ?? [];
      for (final v in vouts) {
        if (v is! Map) continue;
        final spk = v['scriptpubkey_address']?.toString() ?? '';
        final val = (v['value'] as num?)?.toDouble() ?? 0.0;
        if (spk.toLowerCase() == addrLower) {
          received += val;
        } else if (received > 0 || sent == 0) {
          counterparty ??= spk;
        }
      }
      for (final v in vins) {
        if (v is! Map) continue;
        final prevout = v['prevout'];
        if (prevout is Map) {
          final spk = prevout['scriptpubkey_address']?.toString() ?? '';
          if (spk.toLowerCase() == addrLower) {
            final val = (prevout['value'] as num?)?.toDouble() ?? 0.0;
            sent += val;
          }
        }
      }
      final net = received - sent;
      final direction = net >= 0 ? 'inbound' : 'outbound';
      final amountBtc = (net.abs() / 1e8).toStringAsFixed(8);

      out.add(Transaction(
        txHash: txid,
        from: direction == 'outbound' ? address : (counterparty ?? ''),
        to: direction == 'inbound' ? address : (counterparty ?? ''),
        amount: amountBtc,
        tokenSymbol: 'BTC',
        direction: direction,
        status: status,
        timestamp: ts,
        blockchainName: 'Bitcoin',
      ));
    }
    return out;
  }
}
