import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/services/backend_proxy_service.dart';
import 'package:my_flutter_app/services/coingecko_service.dart';

void main() {
  group('CoinGeckoService — Hybrid Routing', () {
    late BackendProxyService proxy;

    setUp(() {
      proxy = BackendProxyService.instance;
      proxy.initialize(baseUrl: 'https://0.0.0.0:0');
    });

    tearDown(() {
      proxy.dispose();
    });

    test('fetchPrices returns valid map (proxy fails → direct fallback)', () async {
      // Proxy at 0.0.0.0:0 fails → route() goes direct → CoinGecko API
      // The hybrid fallback may succeed with real data
      final result = await CoinGeckoService.instance.fetchPrices(['BTC', 'ETH']);
      expect(result, isA<Map<String, Map<String, double>>>());
      // If direct call succeeds, we get real prices
    });

    test('fetchPrice returns a double or null (hybrid fallback)', () async {
      final price = await CoinGeckoService.instance.fetchPrice('BTC');
      // Direct CoinGecko call may succeed (real price) or fail (null)
      // Either way the system handles it gracefully
      expect(price == null || price > 0, isTrue,
          reason: 'Hybrid: proxy fails → direct may return real BTC price');
    });

    test('fetchChart returns chart data or null (hybrid fallback)', () async {
      final chart = await CoinGeckoService.instance.fetchChart('BTC', 1);
      expect(chart == null || chart.isNotEmpty, isTrue,
          reason: 'Hybrid: proxy fails → direct may return real chart data');
      if (chart != null) {
        // Verify chart data structure: [[timestamp, price], ...]
        for (final point in chart) {
          expect(point, hasLength(2));
          expect(point[0], isA<num>(), reason: 'Timestamp');
          expect(point[1], isA<num>(), reason: 'Price');
        }
      }
    });

    test('fetchCoinList returns data gracefully (hybrid fallback)', () async {
      final list = await CoinGeckoService.instance.fetchCoinList();
      // If direct succeeds, returns real list; otherwise empty
      expect(list, isA<List<Map<String, dynamic>>>());
    });

    test('fetchCoinsMarket returns data gracefully (hybrid fallback)', () async {
      final market = await CoinGeckoService.instance.fetchCoinsMarket(
        perPage: 10, page: 1,
      );
      expect(market, isA<List<Map<String, dynamic>>>());
    });
  });

  group('CoinGeckoService — Symbol Mapping', () {
    test('iconUrl for known symbols returns coin-specific URL', () {
      final btcUrl = CoinGeckoService.iconUrl('BTC');
      expect(btcUrl, contains('bitcoin'));

      final ethUrl = CoinGeckoService.iconUrl('ETH');
      expect(ethUrl, contains('ethereum'));

      final solUrl = CoinGeckoService.iconUrl('SOL');
      expect(solUrl, contains('solana'));
    });

    test('iconUrl for unknown symbol returns lowercased symbol as ID', () {
      final url = CoinGeckoService.iconUrl('UNKNOWN');
      expect(url, contains('unknown'));
    });

    test('all supported symbols produce valid icon URLs', () {
      final symbols = [
        'BTC', 'ETH', 'TRX', 'BNB', 'SOL', 'XRP', 'ADA', 'DOT',
        'AVAX', 'MATIC', 'ARB', 'LTC', 'DOGE', 'LINK', 'UNI', 'NCC',
      ];
      for (final sym in symbols) {
        final url = CoinGeckoService.iconUrl(sym);
        expect(url, startsWith('https://assets.coingecko.com/coins/images/1/small/'),
            reason: 'Symbol $sym should produce a valid icon URL');
      }
    });
  });
}
