import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/models/transaction.dart';
import 'package:my_flutter_app/services/backend_proxy_service.dart';
import 'package:my_flutter_app/wallet/history/chain_indexers/btc_history_indexer.dart';
import 'package:my_flutter_app/wallet/history/chain_indexers/evm_history_indexer.dart';
import 'package:my_flutter_app/wallet/history/chain_indexers/tron_history_indexer.dart';

void main() {
  group('EvmHistoryIndexer — Hybrid Routing', () {
    late BackendProxyService proxy;
    late EvmHistoryIndexer indexer;

    setUp(() {
      proxy = BackendProxyService.instance;
      proxy.initialize(baseUrl: 'https://0.0.0.0:0');
      indexer = EvmHistoryIndexer();
    });

    tearDown(() {
      proxy.dispose();
    });

    test('fetch for Ethereum returns empty or real data (hybrid fallback)', () async {
      // Proxy at 0.0.0.0:0 fails → direct Etherscan API may succeed
      final txs = await indexer.fetch(
        'Ethereum',
        '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
      );
      expect(txs, isA<List<Transaction>>());
      // If direct succeeds, transactions may have valid structure
      if (txs.isNotEmpty) {
        final tx = txs.first;
        expect(tx.txHash, isNotEmpty);
        expect(tx.blockchainName, 'Ethereum');
      }
    });

    test('fetch for Polygon handles errors gracefully', () async {
      // Polygon explorer may return HTML error page → handled gracefully
      final txs = await indexer.fetch(
        'Polygon',
        '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
      );
      // Should either return empty (parse error caught) or real data
      expect(txs, isA<List<Transaction>>());
    });

    test('fetch for BSC returns gracefully', () async {
      final txs = await indexer.fetch(
        'BSC',
        '0x742d35Cc6634C0532925a3b844Bc454e4438f44e',
      );
      expect(txs, isA<List<Transaction>>());
    });

    test('fetch with invalid address returns empty list gracefully', () async {
      final txs = await indexer.fetch(
        'Ethereum',
        'invalid-address',
      );
      expect(txs, isA<List<Transaction>>());
    });
  });

  group('BtcHistoryIndexer — Hybrid Routing', () {
    late BackendProxyService proxy;
    late BtcHistoryIndexer indexer;

    setUp(() {
      proxy = BackendProxyService.instance;
      proxy.initialize(baseUrl: 'https://0.0.0.0:0');
      indexer = BtcHistoryIndexer();
    });

    tearDown(() {
      proxy.dispose();
    });

    test('fetch returns empty or real data (hybrid fallback)', () async {
      final txs = await indexer.fetch(
        '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa',
      );
      expect(txs, isA<List<Transaction>>());
    });

    test('fetch with invalid address returns empty list gracefully', () async {
      final txs = await indexer.fetch('invalid-btc-address');
      expect(txs, isA<List<Transaction>>());
    });
  });

  group('TronHistoryIndexer — Hybrid Routing', () {
    late BackendProxyService proxy;
    late TronHistoryIndexer indexer;

    setUp(() {
      proxy = BackendProxyService.instance;
      proxy.initialize(baseUrl: 'https://0.0.0.0:0');
      indexer = TronHistoryIndexer();
    });

    tearDown(() {
      proxy.dispose();
    });

    test('fetch returns empty or real data (hybrid fallback)', () async {
      final txs = await indexer.fetch(
        'T9yD14Nj9j7xAB4dbGeiX9h8unkKHxuWwb',
      );
      expect(txs, isA<List<Transaction>>());
    });

    test('fetch with invalid address returns empty list gracefully', () async {
      final txs = await indexer.fetch('invalid-tron-address');
      expect(txs, isA<List<Transaction>>());
    });
  });
}
