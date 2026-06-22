import 'dart:convert';
import 'dart:async';
import '../utils/secure_log.dart';
import 'package:http/http.dart' as http;

/// 📊 Advanced Chart API Service for Crypto Details
/// Handles all chart-related API calls with proper error handling and caching
class ChartApiServiceV2 {
  static const String baseUrl = 'https://api.coingecko.com/api/v3';
  static const Duration timeout = Duration(seconds: 15);

  // Cache for chart data
  static final Map<String, CachedChartData> _chartCache = {};
  static const int cacheExpiryMinutes = 5;

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

  static String? _toCoinGeckoId(String symbol) {
    return _coinIds[symbol.toUpperCase()];
  }

  // ─── Chart Data ────────────────────────────────────────────

  /// 📈 Get chart data for specific timeframe from CoinGecko
  static Future<ChartDataResponse?> getChartData({
    required String symbol,
    required String fiatCurrency,
    required String timeframe,
    int? points,
  }) async {
    try {
      final cacheKey = '${symbol}_${fiatCurrency}_${timeframe}_${points ?? 30}';
      
      // Check cache first
      if (_chartCache.containsKey(cacheKey)) {
        final cached = _chartCache[cacheKey]!;
        if (DateTime.now().difference(cached.timestamp).inMinutes < cacheExpiryMinutes) {
          SecureLog.d('ChartApiV2: Using cached data for $cacheKey');
          return cached.data;
        }
      }

      final coinId = _toCoinGeckoId(symbol);
      if (coinId == null) {
        SecureLog.w('ChartApiV2: Unknown symbol: $symbol');
        return null;
      }

      final days = _timeframeToDays(timeframe);
      SecureLog.d('ChartApiV2: Fetching chart data for $symbol ($timeframe, ${days}days)');
      
      final response = await http.get(
        Uri.parse('$baseUrl/coins/$coinId/market_chart')
            .replace(queryParameters: {
          'vs_currency': fiatCurrency.toLowerCase(),
          'days': days.toString(),
        }),
        headers: {'Accept': 'application/json'},
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final raw = jsonDecode(response.body);
        final prices = raw['prices'] as List<dynamic>?;
        
        if (prices != null && prices.isNotEmpty) {
          final dataPoints = prices.map((p) => ChartDataPoint(
            timestamp: DateTime.fromMillisecondsSinceEpoch(p[0].toInt()).toIso8601String(),
            price: (p[1] as num).toDouble(),
            volume: 0,
            marketCap: 0,
          )).toList();

          final chartResponse = ChartDataResponse(
            success: true,
            chartData: ChartData(
              symbol: symbol,
              fiat: fiatCurrency,
              timeframe: timeframe,
              data: dataPoints,
            ),
            pointsCount: dataPoints.length,
            timeframe: timeframe,
            lastUpdated: DateTime.now(),
          );

          // Cache the result
          _chartCache[cacheKey] = CachedChartData(
            data: chartResponse,
            timestamp: DateTime.now(),
          );
          
          SecureLog.d('ChartApiV2: ${dataPoints.length} data points loaded for $symbol');
          return chartResponse;
        }
      }
      
      SecureLog.w('ChartApiV2: HTTP ${response.statusCode} for $symbol');
      return null;
    } catch (e) {
      SecureLog.w('ChartApiV2: Error fetching chart data', error: e);
      return null;
    }
  }

  /// 🔴 Get live price updates from CoinGecko
  static Future<LivePriceResponse?> getLivePrices({
    required List<String> symbols,
    required String fiatCurrency,
  }) async {
    try {
      final ids = symbols
          .map((s) => _toCoinGeckoId(s) ?? s.toLowerCase())
          .join(',');
      
      SecureLog.d('ChartApiV2: Fetching live prices for ${symbols.join(", ")}');
      
      final response = await http.get(
        Uri.parse('$baseUrl/simple/price').replace(queryParameters: {
          'ids': ids,
          'vs_currencies': fiatCurrency.toLowerCase(),
          'include_24hr_change': 'true',
          'include_24hr_vol': 'true',
        }),
        headers: {'Accept': 'application/json'},
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final livePrices = <String, LivePriceData>{};
        
        for (final symbol in symbols) {
          final coinId = _toCoinGeckoId(symbol) ?? symbol.toLowerCase();
          if (data.containsKey(coinId)) {
            final coinData = data[coinId] as Map<String, dynamic>;
            livePrices[symbol] = LivePriceData(
              price: (coinData['${fiatCurrency.toLowerCase()}'] as num?)?.toDouble() ?? 0,
              change24h: (coinData['${fiatCurrency.toLowerCase()}_24h_change'] as num?)?.toDouble() ?? 0,
              volume24h: (coinData['${fiatCurrency.toLowerCase()}_24h_vol'] as num?)?.toDouble() ?? 0,
              lastUpdated: DateTime.now(),
            );
          }
        }
        
        SecureLog.d('ChartApiV2: Live prices for ${livePrices.length}/${symbols.length} symbols');
        return LivePriceResponse(
          success: livePrices.isNotEmpty,
          livePrices: livePrices,
          fiatCurrency: fiatCurrency,
          timestamp: DateTime.now(),
        );
      }
      
      SecureLog.w('ChartApiV2: Live prices HTTP ${response.statusCode}');
      return null;
    } catch (e) {
      SecureLog.w('ChartApiV2: Error fetching live prices', error: e);
      return null;
    }
  }

  /// 📊 Get historical prices for longer periods
  static Future<HistoricalPriceResponse?> getHistoricalPrices({
    required List<String> symbols,
    required List<String> fiatCurrencies,
    required DateTime timeStart,
    required DateTime timeEnd,
    String interval = 'daily',
  }) async {
    try {
      final result = <String, Map<String, HistoricalCurrencyData>>{};
      
      for (final symbol in symbols) {
        final coinId = _toCoinGeckoId(symbol);
        if (coinId == null) continue;
        
        final fromSec = timeStart.millisecondsSinceEpoch ~/ 1000;
        final toSec = timeEnd.millisecondsSinceEpoch ~/ 1000;
        
        final response = await http.get(
          Uri.parse('$baseUrl/coins/$coinId/market_chart/range').replace(queryParameters: {
            'vs_currency': fiatCurrencies.first.toLowerCase(),
            'from': fromSec.toString(),
            'to': toSec.toString(),
          }),
          headers: {'Accept': 'application/json'},
        ).timeout(timeout);
        
        if (response.statusCode == 200) {
          final raw = jsonDecode(response.body);
          final prices = raw['prices'] as List<dynamic>?;
          final volumes = raw['total_volumes'] as List<dynamic>?;
          final marketCaps = raw['market_caps'] as List<dynamic>?;
          
          if (prices != null && prices.isNotEmpty) {
            final timestamps = prices.map((p) => 
              DateTime.fromMillisecondsSinceEpoch(p[0].toInt()).toIso8601String()
            ).toList();
            final priceValues = prices.map((p) => (p[1] as num).toDouble()).toList();
            final volumeValues = volumes?.map((v) => (v[1] as num).toDouble()).toList() ?? [];
            final marketCapValues = marketCaps?.map((m) => (m[1] as num).toDouble()).toList() ?? [];
            
            result[symbol] = {
              fiatCurrencies.first: HistoricalCurrencyData(
                prices: priceValues,
                timestamps: timestamps,
                marketCaps: marketCapValues,
                volumes: volumeValues,
              ),
            };
          }
        }
      }
      
      if (result.isEmpty) return null;
      
      return HistoricalPriceResponse(
        success: true,
        historicalData: result,
        interval: interval,
        timeStart: timeStart,
        timeEnd: timeEnd,
      );
    } catch (e) {
      SecureLog.w('ChartApiV2: Error fetching historical prices', error: e);
      return null;
    }
  }

  /// 📈 Smart chart data fetcher
  static Future<ChartDataPoints?> getSmartChartData({
    required String symbol,
    required String fiatCurrency,
    required String timeframe,
  }) async {
    try {
      SecureLog.d('ChartApiV2: Smart fetching for $symbol ($timeframe)');
      
      // For short timeframes, use market_chart API
      final chartResponse = await getChartData(
        symbol: symbol,
        fiatCurrency: fiatCurrency,
        timeframe: timeframe,
      );
      
      if (chartResponse != null && chartResponse.chartData.data.isNotEmpty) {
        return ChartDataPoints(
          symbol: symbol,
          fiatCurrency: fiatCurrency,
          timeframe: timeframe,
          points: chartResponse.chartData.data.map((point) => ChartPoint(
            timestamp: DateTime.parse(point.timestamp),
            price: point.price,
            volume: point.volume,
            marketCap: point.marketCap,
          )).toList(),
        );
      }
      
      // For longer timeframes, use market_chart/range API
      if (['1m', '3m', '6m', '1y'].contains(timeframe)) {
        final now = DateTime.now();
        DateTime startTime;
        
        switch (timeframe) {
          case '1m':
            startTime = now.subtract(const Duration(days: 30));
            break;
          case '3m':
            startTime = now.subtract(const Duration(days: 90));
            break;
          case '6m':
            startTime = now.subtract(const Duration(days: 180));
            break;
          case '1y':
            startTime = now.subtract(const Duration(days: 365));
            break;
          default:
            startTime = now.subtract(const Duration(days: 30));
        }
        
        final historicalResponse = await getHistoricalPrices(
          symbols: [symbol],
          fiatCurrencies: [fiatCurrency],
          timeStart: startTime,
          timeEnd: now,
        );
        
        if (historicalResponse != null) {
          final symbolData = historicalResponse.historicalData[symbol];
          final currencyData = symbolData?[fiatCurrency];
          
          if (currencyData != null) {
            final points = <ChartPoint>[];
            for (int i = 0; i < currencyData.prices.length; i++) {
              if (i < currencyData.timestamps.length) {
                points.add(ChartPoint(
                  timestamp: DateTime.parse(currencyData.timestamps[i]),
                  price: currencyData.prices[i],
                  volume: i < currencyData.volumes.length ? currencyData.volumes[i] : 0,
                  marketCap: i < currencyData.marketCaps.length ? currencyData.marketCaps[i] : 0,
                ));
              }
            }
            
            return ChartDataPoints(
              symbol: symbol,
              fiatCurrency: fiatCurrency,
              timeframe: timeframe,
              points: points,
            );
          }
        }
      }
      
      SecureLog.w('ChartApiV2: No data available for $symbol ($timeframe)');
      return null;
    } catch (e) {
      SecureLog.w('ChartApiV2: Error in smart chart data', error: e);
      return null;
    }
  }

  /// Convert timeframe to days for CoinGecko API
  static int _timeframeToDays(String timeframe) {
    switch (timeframe) {
      case '1h': return 1;
      case '4h': return 1;
      case '1d': return 1;
      case '1w': return 7;
      case '1m': return 30;
      case '3m': return 90;
      case '6m': return 180;
      case '1y': return 365;
      default: return 1;
    }
  }

  /// Clear cache
  static void clearCache() {
    _chartCache.clear();
    SecureLog.d('ChartApiV2: Cache cleared');
  }
}

/// Cached chart data
class CachedChartData {
  final ChartDataResponse data;
  final DateTime timestamp;

  CachedChartData({required this.data, required this.timestamp});
}

/// Chart data response model
class ChartDataResponse {
  final bool success;
  final ChartData chartData;
  final int pointsCount;
  final String timeframe;
  final DateTime lastUpdated;

  ChartDataResponse({
    required this.success,
    required this.chartData,
    required this.pointsCount,
    required this.timeframe,
    required this.lastUpdated,
  });

  factory ChartDataResponse.fromJson(Map<String, dynamic> json) {
    return ChartDataResponse(
      success: json['success'] ?? false,
      chartData: ChartData.fromJson(json['chart_data'] ?? {}),
      pointsCount: json['points_count'] ?? 0,
      timeframe: json['timeframe'] ?? '',
      lastUpdated: DateTime.parse(json['last_updated'] ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Chart data model
class ChartData {
  final String symbol;
  final String fiat;
  final String timeframe;
  final List<ChartDataPoint> data;

  ChartData({
    required this.symbol,
    required this.fiat,
    required this.timeframe,
    required this.data,
  });

  factory ChartData.fromJson(Map<String, dynamic> json) {
    final dataList = json['data'] as List<dynamic>? ?? [];
    return ChartData(
      symbol: json['symbol'] ?? '',
      fiat: json['fiat'] ?? '',
      timeframe: json['timeframe'] ?? '',
      data: dataList.map((item) => ChartDataPoint.fromJson(item)).toList(),
    );
  }
}

/// Individual chart data point
class ChartDataPoint {
  final String timestamp;
  final double price;
  final double volume;
  final double marketCap;

  ChartDataPoint({
    required this.timestamp,
    required this.price,
    required this.volume,
    required this.marketCap,
  });

  factory ChartDataPoint.fromJson(Map<String, dynamic> json) {
    return ChartDataPoint(
      timestamp: json['timestamp'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      volume: (json['volume'] ?? 0).toDouble(),
      marketCap: (json['market_cap'] ?? 0).toDouble(),
    );
  }
}

/// Live price response model
class LivePriceResponse {
  final bool success;
  final Map<String, LivePriceData> livePrices;
  final String fiatCurrency;
  final DateTime timestamp;

  LivePriceResponse({
    required this.success,
    required this.livePrices,
    required this.fiatCurrency,
    required this.timestamp,
  });

  factory LivePriceResponse.fromJson(Map<String, dynamic> json) {
    final livePricesMap = <String, LivePriceData>{};
    final livePricesJson = json['live_prices'] as Map<String, dynamic>? ?? {};
    
    livePricesJson.forEach((key, value) {
      livePricesMap[key] = LivePriceData.fromJson(value);
    });

    return LivePriceResponse(
      success: json['success'] ?? false,
      livePrices: livePricesMap,
      fiatCurrency: json['fiat_currency'] ?? '',
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Live price data model
class LivePriceData {
  final double price;
  final double change24h;
  final double volume24h;
  final DateTime lastUpdated;

  LivePriceData({
    required this.price,
    required this.change24h,
    required this.volume24h,
    required this.lastUpdated,
  });

  factory LivePriceData.fromJson(Map<String, dynamic> json) {
    return LivePriceData(
      price: (json['price'] ?? 0).toDouble(),
      change24h: (json['change_24h'] ?? 0).toDouble(),
      volume24h: (json['volume_24h'] ?? 0).toDouble(),
      lastUpdated: DateTime.parse(json['last_updated'] ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Historical price response model
class HistoricalPriceResponse {
  final bool success;
  final Map<String, Map<String, HistoricalCurrencyData>> historicalData;
  final String interval;
  final DateTime timeStart;
  final DateTime timeEnd;

  HistoricalPriceResponse({
    required this.success,
    required this.historicalData,
    required this.interval,
    required this.timeStart,
    required this.timeEnd,
  });

  factory HistoricalPriceResponse.fromJson(Map<String, dynamic> json) {
    final historicalDataMap = <String, Map<String, HistoricalCurrencyData>>{};
    final historicalDataJson = json['historical_data'] as Map<String, dynamic>? ?? {};
    
    historicalDataJson.forEach((symbol, symbolData) {
      final symbolMap = <String, HistoricalCurrencyData>{};
      final symbolDataMap = symbolData as Map<String, dynamic>;
      
      symbolDataMap.forEach((currency, currencyData) {
        symbolMap[currency] = HistoricalCurrencyData.fromJson(currencyData);
      });
      
      historicalDataMap[symbol] = symbolMap;
    });

    return HistoricalPriceResponse(
      success: json['success'] ?? false,
      historicalData: historicalDataMap,
      interval: json['interval'] ?? '',
      timeStart: DateTime.parse(json['time_start'] ?? DateTime.now().toIso8601String()),
      timeEnd: DateTime.parse(json['time_end'] ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Historical currency data model
class HistoricalCurrencyData {
  final List<double> prices;
  final List<String> timestamps;
  final List<double> marketCaps;
  final List<double> volumes;

  HistoricalCurrencyData({
    required this.prices,
    required this.timestamps,
    required this.marketCaps,
    required this.volumes,
  });

  factory HistoricalCurrencyData.fromJson(Map<String, dynamic> json) {
    return HistoricalCurrencyData(
      prices: (json['prices'] as List<dynamic>? ?? [])
          .map<double>((e) => (e ?? 0).toDouble())
          .toList(),
      timestamps: (json['timestamps'] as List<dynamic>? ?? [])
          .map<String>((e) => e.toString())
          .toList(),
      marketCaps: (json['market_caps'] as List<dynamic>? ?? [])
          .map<double>((e) => (e ?? 0).toDouble())
          .toList(),
      volumes: (json['volumes'] as List<dynamic>? ?? [])
          .map<double>((e) => (e ?? 0).toDouble())
          .toList(),
    );
  }
}

/// Unified chart data points model
class ChartDataPoints {
  final String symbol;
  final String fiatCurrency;
  final String timeframe;
  final List<ChartPoint> points;

  ChartDataPoints({
    required this.symbol,
    required this.fiatCurrency,
    required this.timeframe,
    required this.points,
  });
}

/// Individual chart point
class ChartPoint {
  final DateTime timestamp;
  final double price;
  final double volume;
  final double marketCap;

  ChartPoint({
    required this.timestamp,
    required this.price,
    required this.volume,
    required this.marketCap,
  });
}
