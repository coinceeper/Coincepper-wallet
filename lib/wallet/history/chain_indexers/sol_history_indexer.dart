import '../../../models/transaction.dart';
import 'solana_rpc_client.dart';

class SolHistoryIndexer {
  final _rpc = SolanaRpcClient();

  Future<List<Transaction>> fetch(String address) async {
    final sigs = await _rpc.call('getSignaturesForAddress', [
      address,
      {'limit': 20},
    ]);
    if (sigs is! List) return [];
    final signatures = <String>[];
    for (final item in sigs) {
      if (item is Map && item['signature'] != null) {
        signatures.add(item['signature'].toString());
      }
    }

    final out = <Transaction>[];
    const chunk = 4;
    for (var i = 0; i < signatures.length; i += chunk) {
      final batch = signatures.skip(i).take(chunk).toList();
      final txs = await Future.wait(
        batch.map((sig) => _txForSignature(address, sig)),
      );
      out.addAll(txs.whereType<Transaction>());
    }
    return out;
  }

  Future<Transaction?> _txForSignature(String address, String signature) async {
    try {
      final result = await _rpc.call('getTransaction', [
        signature,
        {
          'encoding': 'jsonParsed',
          'maxSupportedTransactionVersion': 0,
        },
      ]);
      if (result is! Map) return null;
      final meta = result['meta'] as Map<String, dynamic>?;
      final transaction = result['transaction'] as Map<String, dynamic>?;
      if (meta == null || transaction == null) return null;

      final message = transaction['message'] as Map<String, dynamic>?;
      final accountKeys = message?['accountKeys'] as List<dynamic>? ?? [];
      var accountIndex = -1;
      for (var i = 0; i < accountKeys.length; i++) {
        final key = accountKeys[i];
        final pubkey = key is Map
            ? key['pubkey']?.toString()
            : key?.toString();
        if (pubkey == address) {
          accountIndex = i;
          break;
        }
      }
      if (accountIndex < 0) return null;

      final pre = (meta['preBalances'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .toList();
      final post = (meta['postBalances'] as List<dynamic>? ?? [])
          .map((e) => (e as num).toInt())
          .toList();
      if (accountIndex >= pre.length || accountIndex >= post.length) {
        return null;
      }
      final delta = post[accountIndex] - pre[accountIndex];
      if (delta == 0) return null;

      final blockTime = result['blockTime'] as int? ?? 0;
      final inbound = delta > 0;
      final lamports = delta.abs();

      return Transaction(
        txHash: signature,
        from: inbound ? '' : address,
        to: inbound ? address : '',
        amount: (lamports / 1e9).toString(),
        tokenSymbol: 'SOL',
        direction: inbound ? 'inbound' : 'outbound',
        status: meta['err'] == null ? 'completed' : 'failed',
        timestamp: DateTime.fromMillisecondsSinceEpoch(blockTime * 1000)
            .toIso8601String(),
        blockchainName: 'Solana',
      );
    } catch (_) {
      return null;
    }
  }
}
