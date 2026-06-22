import 'dart:convert';
import '../utils/secure_log.dart';
import 'package:http/http.dart' as http;
import '../di/service_locator.dart';

/// سرویس رسمی قیمت و داده‌های چارت از CoinGecko API
///
/// این سرویس مسئول:
/// - دریافت قیمت‌های لحظه‌ای ارزها از CoinGecko
/// - دریافت داده‌های چارت تاریخی
/// - نگاشت نماد به CoinGecko ID
///
/// معماری:
/// - Singleton ثبت شده در DI container
/// - بدون کش داخلی (کش در لایه PriceService مدیریت می‌شود)
/// - Timeout 10 ثانیه برای همه درخواست‌ها
class CoinGeckoService {
  CoinGeckoService();
  CoinGeckoService._internal();

  static CoinGeckoService get instance => ServiceLocator.get<CoinGeckoService>();

  static const String _baseUrl = 'https://api.coingecko.com/api/v3';
  static const Duration _timeout = Duration(seconds: 10);

  // ─── نگاشت نماد به CoinGecko ID ────────────────────────────

  static const Map<String, String> _symbolToId = {
    'BTC': 'bitcoin',
    'ETH': 'ethereum',
    'TRX': 'tron',
    'BNB': 'binancecoin',
    'SOL': 'solana',
    'XRP': 'ripple',
    'ADA': 'cardano',
    'DOT': 'polkadot',
    'AVAX': 'avalanche-2',
    'MATIC': 'matic-network',
    'ARB': 'arbitrum',
    'LTC': 'litecoin',
    'DOGE': 'dogecoin',
    'LINK': 'chainlink',
    'UNI': 'uniswap',
    'USDT': 'tether',
    'USDC': 'usd-coin',
    'SHIB': 'shiba-inu',
    'POL': 'matic-network',
    'ATOM': 'cosmos',
    'NEAR': 'near',
    'OP': 'optimism',
    'APT': 'aptos',
    'FIL': 'filecoin',
    'TON': 'the-open-network',
    'BCH': 'bitcoin-cash',
    'XLM': 'stellar',
    'VET': 'vechain',
    'ICP': 'internet-computer',
  };

  /// تبدیل نماد (مثل BTC) به CoinGecko ID (مثل bitcoin)
  static String? toCoinGeckoId(String symbol) {
    return _symbolToId[symbol.toUpperCase()];
  }

  /// تبدیل CoinGecko ID به نماد
  static String? fromCoinGeckoId(String id) {
    for (final entry in _symbolToId.entries) {
      if (entry.value == id) return entry.key;
    }
    return null;
  }

  // ─── دریافت قیمت‌ها ───────────────────────────────────────────

  /// دریافت قیمت‌های لحظه‌ای و داده‌های مارکت برای لیست نمادها
  ///
  /// [symbols] لیست نمادها (مثل ['BTC', 'ETH'])
  /// Returns: Map<symbol, Map<field, value>>
  ///   مثال: {'BTC': {'USD': 45000.0, 'change_24h': 2.5,
  ///                  'market_cap': 8.5e11, 'volume_24h': 2.5e10}}
  ///
  /// تمام داده‌ها در یک درخواست به CoinGecko API گرفته می‌شود.
  /// هیچ فراخوانی دومی برای market_cap یا volume لازم نیست.
  Future<Map<String, Map<String, double>>> fetchPrices(List<String> symbols) async {
    final result = <String, Map<String, double>>{};
    if (symbols.isEmpty) return result;

    try {
      final uniqueSymbols = symbols.toSet().toList();
      final ids = uniqueSymbols
          .map((s) => toCoinGeckoId(s) ?? s.toLowerCase())
          .join(',');

      final uri = Uri.parse('$_baseUrl/simple/price').replace(queryParameters: {
        'ids': ids,
        'vs_currencies': 'usd',
        'include_market_cap': 'true',
        'include_24hr_vol': 'true',
        'include_24hr_change': 'true',
      });

      SecureLog.d('CoinGecko: Fetching prices for $uniqueSymbols');
      final response = await http.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        for (final symbol in uniqueSymbols) {
          final coinId = toCoinGeckoId(symbol) ?? '';
          if (coinId.isEmpty || !data.containsKey(coinId)) continue;

          final coinData = data[coinId] as Map<String, dynamic>?;
          if (coinData == null) continue;

          final usdPrice = (coinData['usd'] as num?)?.toDouble();
          final change24h = (coinData['usd_24h_change'] as num?)?.toDouble();
          final marketCap = (coinData['usd_market_cap'] as num?)?.toDouble();
          final volume24h = (coinData['usd_24h_vol'] as num?)?.toDouble();

          if (usdPrice != null && usdPrice > 0) {
            result[symbol.toUpperCase()] = {
              'USD': usdPrice,
              'change_24h': change24h ?? 0.0,
              'market_cap': marketCap ?? 0.0,
              'volume_24h': volume24h ?? 0.0,
            };
          }
        }

        SecureLog.d('CoinGecko: Fetched ${result.length}/${uniqueSymbols.length} prices');
      } else {
        SecureLog.w('CoinGecko: HTTP ${response.statusCode}', error: 'body: [redacted]');
      }
    } catch (e) {
      SecureLog.w('CoinGecko: Error fetching prices', error: e);
    }

    return result;
  }

  // ─── دریافت داده‌های چارت ─────────────────────────────────────

  /// دریافت داده‌های چارت تاریخی از CoinGecko
  ///
  /// [symbol] نماد ارز (مثل BTC)
  /// [days] تعداد روزهای گذشته (1, 7, 30, 90, 365, max)
  /// Returns: List<[timestamp_ms, price]> یا null در صورت خطا
  Future<List<List<num>>?> fetchChart(String symbol, int days) async {
    try {
      final coinId = toCoinGeckoId(symbol);
      if (coinId == null) {
        SecureLog.w('CoinGecko: Unknown symbol for chart: $symbol');
        return null;
      }

      final uri = Uri.parse('$_baseUrl/coins/$coinId/market_chart').replace(
        queryParameters: {
          'vs_currency': 'usd',
          'days': days.toString(),
        },
      );

      SecureLog.d('CoinGecko: Fetching chart for $symbol ($days days)');
      final response = await http.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final prices = data['prices'] as List<dynamic>?;

        if (prices != null && prices.isNotEmpty) {
          final result = prices
              .map((p) => [p[0] as num, p[1] as num])
              .toList();
          SecureLog.d('CoinGecko: Chart data for $symbol: ${result.length} points');
          return result;
        }
      } else {
        SecureLog.w('CoinGecko: Chart HTTP ${response.statusCode}');
      }
    } catch (e) {
      SecureLog.w('CoinGecko: Error fetching chart', error: e);
    }

    return null;
  }

  // ─── دریافت داده‌های مارکت ────────────────────────────────────

  /// دریافت داده‌های کامل مارکت برای یک ارز
  Future<Map<String, dynamic>?> fetchMarketData(String symbol) async {
    try {
      final coinId = toCoinGeckoId(symbol);
      if (coinId == null) return null;

      final uri = Uri.parse('$_baseUrl/coins/$coinId').replace(
        queryParameters: {
          'localization': 'false',
          'tickers': 'false',
          'community_data': 'false',
          'developer_data': 'false',
          'sparkline': 'false',
        },
      );

      SecureLog.d('CoinGecko: Fetching market data for $symbol');
      final response = await http.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final marketData = data['market_data'] as Map<String, dynamic>?;

        if (marketData != null) {
          final usdQuote = marketData['current_price']?['usd']?.toDouble() ?? 0.0;
          final marketCap = marketData['market_cap']?['usd']?.toDouble();
          final volume24h = marketData['total_volume']?['usd']?.toDouble();
          final priceChange24h = marketData['price_change_percentage_24h']?.toDouble();
          final priceChange7d = marketData['price_change_percentage_7d']?.toDouble();

          return {
            'price': usdQuote,
            'market_cap_usd': marketCap,
            'volume_24h_usd': volume24h,
            'price_change_24h': priceChange24h,
            'price_change_7d': priceChange7d,
          };
        }
      }
    } catch (e) {
      SecureLog.w('CoinGecko: Error fetching market data', error: e);
    }

    return null;
  }

  /// دریافت داده‌های مارکت برای چند ارز (batch)
  Future<Map<String, Map<String, double>>> fetchBatchMarketData(List<String> symbols) async {
    final result = <String, Map<String, double>>{};
    if (symbols.isEmpty) return result;

    try {
      final ids = symbols
          .map((s) => toCoinGeckoId(s) ?? s.toLowerCase())
          .join(',');

      final uri = Uri.parse('$_baseUrl/simple/price').replace(queryParameters: {
        'ids': ids,
        'vs_currencies': 'usd',
        'include_market_cap': 'true',
        'include_24hr_vol': 'true',
        'include_24hr_change': 'true',
      });

      final response = await http.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        for (final symbol in symbols) {
          final coinId = toCoinGeckoId(symbol) ?? '';
          if (coinId.isEmpty || !data.containsKey(coinId)) continue;

          final coinData = data[coinId] as Map<String, dynamic>?;
          if (coinData == null) continue;

          result[symbol.toUpperCase()] = {
            'usd': (coinData['usd'] as num?)?.toDouble() ?? 0,
            'usd_market_cap': (coinData['usd_market_cap'] as num?)?.toDouble() ?? 0,
            'usd_24h_vol': (coinData['usd_24h_vol'] as num?)?.toDouble() ?? 0,
            'usd_24h_change': (coinData['usd_24h_change'] as num?)?.toDouble() ?? 0,
          };
        }
      }
    } catch (e) {
      SecureLog.w('CoinGecko: Error fetching batch market data', error: e);
    }

    return result;
  }

  // ─── Convenience helpers ──────────────────────────────────────

  /// Convenience: fetch a single coin price.
  /// Returns the USD price or null on failure.
  Future<double?> fetchPrice(String symbol) async {
    final prices = await fetchPrices([symbol]);
    return prices[symbol.toUpperCase()]?['USD'];
  }

  /// Fetch the full coin list from CoinGecko.
  Future<List<Map<String, dynamic>>> fetchCoinList() async {
    try {
      final uri = Uri.parse('$_baseUrl/coins/list');
      final response = await http.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      SecureLog.w('CoinGecko: Error fetching coin list', error: e);
    }
    return [];
  }

  /// Fetch market data for multiple coins (paginated).
  Future<List<Map<String, dynamic>>> fetchCoinsMarket({
    int perPage = 50,
    int page = 1,
    String vsCurrency = 'usd',
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/coins/markets').replace(queryParameters: {
        'vs_currency': vsCurrency,
        'order': 'market_cap_desc',
        'per_page': perPage.toString(),
        'page': page.toString(),
        'sparkline': 'false',
      });

      final response = await http.get(uri, headers: {
        'Accept': 'application/json',
      }).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>;
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      SecureLog.w('CoinGecko: Error fetching coins market', error: e);
    }
    return [];
  }

  /// CoinGecko icon URL for a given symbol.
  static String iconUrl(String symbol) {
    final coinId = toCoinGeckoId(symbol) ?? symbol.toLowerCase();
    return 'https://assets.coingecko.com/coins/images/1/small/$coinId.png';
  }
}
