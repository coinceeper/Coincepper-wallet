import '../../models/transaction.dart';
import '../address_registry.dart';
import 'chain_indexers/btc_history_indexer.dart';
import 'chain_indexers/dot_history_indexer.dart';
import 'chain_indexers/evm_history_indexer.dart';
import 'chain_indexers/sol_history_indexer.dart';
import 'chain_indexers/tron_history_indexer.dart';
import 'chain_indexers/xrp_history_indexer.dart';
import 'history_db.dart';

/// Fetches on-chain history from public indexers and caches locally.
class HistoryIndexer {
  HistoryIndexer._();
  static final HistoryIndexer instance = HistoryIndexer._();

  final _btc = BtcHistoryIndexer();
  final _evm = EvmHistoryIndexer();
  final _tron = TronHistoryIndexer();
  final _sol = SolHistoryIndexer();
  final _xrp = XrpHistoryIndexer();
  final _dot = DotHistoryIndexer();

  Future<List<Transaction>> fetchAndCache(
    String userId, {
    String? tokenSymbol,
  }) async {
    final cached = await HistoryDb.instance.loadForUser(userId);
    final addresses = await AddressRegistry.instance.loadForWallet(userId);
    final all = <Transaction>[...cached];

    for (final entry in addresses.entries) {
      final chain = entry.key;
      final addr = entry.value;
      if (addr.isEmpty) continue;
      try {
        final txs = await _fetchChain(chain, addr);
        all.addAll(txs);
      } catch (e) {
        print('HistoryIndexer: $chain failed: $e');
      }
    }

    final deduped = <String, Transaction>{};
    for (final t in all) {
      final key = t.txHash.isNotEmpty ? t.txHash : '${t.timestamp}_${t.amount}';
      deduped[key] = t;
    }
    final list = deduped.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    await HistoryDb.instance.upsertMany(userId, list);

    if (tokenSymbol != null && tokenSymbol.isNotEmpty) {
      return list
          .where((t) => t.tokenSymbol.toUpperCase() == tokenSymbol.toUpperCase())
          .toList();
    }
    return list;
  }

  Future<List<Transaction>> _fetchChain(String blockchainName, String address) async {
    final n = blockchainName.toLowerCase();
    if (n.contains('bitcoin')) return _btc.fetch(address);
    if (n.contains('tron')) return _tron.fetch(address);
    if (n.contains('ethereum') ||
        n.contains('polygon') ||
        n.contains('bsc') ||
        n.contains('binance') ||
        n.contains('avalanche') ||
        n.contains('arbitrum')) {
      return _evm.fetch(blockchainName, address);
    }
    if (n.contains('solana') || n == 'sol') return _sol.fetch(address);
    if (n.contains('xrp') || n.contains('ripple')) return _xrp.fetch(address);
    if (n.contains('polkadot') || n == 'dot') return _dot.fetch(address);
    return [];
  }
}
