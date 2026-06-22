import 'dart:convert';
import 'package:http/http.dart' as http;
import '../di/service_locator.dart';
import '../models/chart_models.dart';
import '../utils/secure_log.dart';

/// 📊 Advanced Chart Data Service
/// Provides chart data from CoinGecko API.
/// No fake/mock data is generated — null is returned on failure.
class ChartDataService {
  ChartDataService();

  ChartDataService._internal();

  static ChartDataService get instance => ServiceLocator.get<ChartDataService>();

  final Map<String, List<ChartDataPoint>> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheTimeout = Duration(minutes: 5);

  // ─── CoinGecko ID mapping ──────────────────────────────────

  static const Map<String, String> _coinIds = {
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
  };

  static String? _getCoinGeckoId(String symbol) {
    return _coinIds[symbol.toUpperCase()];
  }

  /// 📈 Get chart data from CoinGecko API
  /// Returns empty list if data is unavailable (no mock/fake data).
  Future<List<ChartDataPoint>> getChartData({
    required String symbol,
    required String timeframe,
    String currency = 'USD',
  }) async {
    final cacheKey = '${symbol}_${timeframe}_$currency';
    
    // Check cache first
    if (_isDataCached(cacheKey)) {
      SecureLog.d('ChartDataService: Using cached chart data for $cacheKey');
      return _cache[cacheKey]!;
    }

    try {
      List<ChartDataPoint>? data;

      // 1. Try CoinGecko
      data = await _getCoinGeckoData(symbol, timeframe, currency);

      // Cache the data if available
      if (data != null && data.isNotEmpty) {
        _cache[cacheKey] = data;
        _cacheTimestamps[cacheKey] = DateTime.now();
        SecureLog.d('ChartDataService: Chart data loaded for $symbol ($timeframe): ${data.length} points');
        return data;
      }

      SecureLog.w('ChartDataService: No chart data available for $symbol ($timeframe)');
      return []; // Empty list = no data, no fallback
      
    } catch (e) {
      SecureLog.w('ChartDataService: Error getting chart data', error: e);
      return []; // Empty list = no data, no fallback
    }
  }

  /// 📊 CoinGecko API
  Future<List<ChartDataPoint>?> _getCoinGeckoData(String symbol, String timeframe, String currency) async {
    try {
      final coinId = _getCoinGeckoId(symbol);
      if (coinId == null) return null;

      final days = _getTimeframeDays(timeframe);
      
      final url = 'https://api.coingecko.com/api/v3/coins/$coinId/market_chart'
          '?vs_currency=${currency.toLowerCase()}'
          '&days=$days';

      SecureLog.d('ChartDataService: Fetching from CoinGecko');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final raw = jsonDecode(response.body);
        if (raw['prices'] != null) {
          final prices = raw['prices'] as List;
          return prices.map((price) => ChartDataPoint(
            timestamp: DateTime.fromMillisecondsSinceEpoch(price[0]),
            price: price[1].toDouble(),
            volume: 0,
          )).toList();
        }
      } else {
        SecureLog.w('ChartDataService: CoinGecko API HTTP ${response.statusCode}');
      }
    } catch (e) {
      SecureLog.w('ChartDataService: CoinGecko API error', error: e);
    }
    return null;
  }

  /// 📅 Get days for timeframe
  int _getTimeframeDays(String timeframe) {
    switch (timeframe) {
      case '1h': return 1;
      case '4h': return 1;
      case '1d': return 1;
      case '1w': return 7;
      case '1m': return 30;
      case '3m': return 90;
      default: return 7;
    }
  }

  /// 💾 Check if data is cached and valid
  bool _isDataCached(String cacheKey) {
    if (!_cache.containsKey(cacheKey) || !_cacheTimestamps.containsKey(cacheKey)) {
      return false;
    }
    
    final cacheTime = _cacheTimestamps[cacheKey]!;
    return DateTime.now().difference(cacheTime) < _cacheTimeout;
  }

  /// 🗑️ Clear cache
  void clearCache() {
    _cache.clear();
    _cacheTimestamps.clear();
    SecureLog.d('ChartDataService: Chart data cache cleared');
  }
}
