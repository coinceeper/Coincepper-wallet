import 'dart:convert';
import 'package:dio/dio.dart';

/// CoinMarketCap API service for fetching crypto prices and historical data.
/// **Deprecated** — the project primarily uses V2 cache proxy on coinceeper.com.
/// The API key must be provided via `--dart-define=COINMARKETCAP_API_KEY=...`.
class CoinMarketCapService {
  static const String _baseUrl = 'https://pro-api.coinmarketcap.com/v1/';
  static const String _apiKey = String.fromEnvironment(
    'COINMARKETCAP_API_KEY',
    defaultValue: '',
  );

  late final Dio _dio;

  CoinMarketCapService() {
    _initializeDio();
  }

  void _initializeDio() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-CMC_PRO_API_KEY': _apiKey,
      },
    ));

    _dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
      logPrint: (obj) => print('🪙 CoinMarketCap API: $obj'),
    ));
  }

  /// Get current price data for a cryptocurrency
  Future<CryptoPriceData?> getCryptoPriceData(String symbol) async {
    try {
      // For demo purposes, return mock data since API might have restrictions
      print('🪙 Generating mock price data for $symbol');
      return _generateMockPriceData(symbol);
    } catch (e) {
      print('❌ Error fetching crypto price data: $e');
      return _generateMockPriceData(symbol);
    }
  }

  /// Generate mock price data for demonstration
  CryptoPriceData _generateMockPriceData(String symbol) {
    final random = DateTime.now().millisecondsSinceEpoch % 1000;
    const basePrice = 851.03;
    final actualPrice = basePrice + (random - 500) / 100;

    return CryptoPriceData(
      symbol: symbol,
      name: symbol == 'BNB' ? 'BNB' : symbol,
      price: actualPrice,
      percentChange1h: -0.11,
      percentChange24h: -0.11,
      percentChange7d: 2.45,
      marketCap: 125000000000,
      volume24h: 1500000000,
      lastUpdated: DateTime.now(),
    );
  }

  /// Get historical price data for a cryptocurrency
  Future<List<ChartDataPoint>?> getHistoricalData(String symbol, String timeRange) async {
    try {
      // For demo purposes, generate mock data since CoinMarketCap historical API requires paid plan
      print('🪙 Generating mock chart data for $symbol - $timeRange');
      return _generateMockChartData(timeRange);
    } catch (e) {
      print('❌ Error fetching historical data: $e');
      return _generateMockChartData(timeRange);
    }
  }

  /// Generate mock chart data for demonstration
  List<ChartDataPoint> _generateMockChartData(String timeRange) {
    final now = DateTime.now();
    final random = DateTime.now().millisecondsSinceEpoch % 1000;
    final basePrice = 850.0 + (random / 10); // Base price around $850

    int dataPoints;
    Duration interval;

    switch (timeRange) {
      case '1H':
        dataPoints = 12; // 5-minute intervals
        interval = const Duration(minutes: 5);
        break;
      case '1D':
        dataPoints = 24; // Hourly intervals
        interval = const Duration(hours: 1);
        break;
      case '1W':
        dataPoints = 7; // Daily intervals
        interval = const Duration(days: 1);
        break;
      case '1M':
        dataPoints = 30; // Daily intervals
        interval = const Duration(days: 1);
        break;
      case '1Y':
        dataPoints = 12; // Monthly intervals
        interval = const Duration(days: 30);
        break;
      case 'All':
        dataPoints = 24; // Monthly intervals for 2 years
        interval = const Duration(days: 30);
        break;
      default:
        dataPoints = 24;
        interval = const Duration(hours: 1);
    }

    final data = <ChartDataPoint>[];
    double currentPrice = basePrice;

    for (int i = 0; i < dataPoints; i++) {
      final timestamp = now.subtract(interval * (dataPoints - i - 1));

      // Add some realistic price variation
      final change = (DateTime.now().millisecondsSinceEpoch + i) % 200 - 100;
      currentPrice += change / 100.0;

      // Keep price in reasonable range
      currentPrice = currentPrice.clamp(basePrice * 0.8, basePrice * 1.2);

      data.add(ChartDataPoint(
        timestamp: timestamp,
        price: currentPrice,
        volume: 1000000.0 + (change.abs() * 10000),
      ));
    }

    return data;
  }

  /// Get cryptocurrency metadata (logo, description, etc.)
  Future<CryptoMetadata?> getCryptoMetadata(String symbol) async {
    try {
      final response = await _dio.get(
        'cryptocurrency/info',
        queryParameters: {
          'symbol': symbol.toUpperCase(),
        },
      );

      if (response.statusCode == 200) {
        final data = response.data['data'][symbol.toUpperCase()];
        if (data != null) {
          return CryptoMetadata.fromJson(data);
        }
      }
      return null;
    } catch (e) {
      print('❌ Error fetching crypto metadata: $e');
      return null;
    }
  }
}

/// Model for cryptocurrency price data
class CryptoPriceData {
  final String symbol;
  final String name;
  final double price;
  final double percentChange1h;
  final double percentChange24h;
  final double percentChange7d;
  final double marketCap;
  final double volume24h;
  final DateTime lastUpdated;

  CryptoPriceData({
    required this.symbol,
    required this.name,
    required this.price,
    required this.percentChange1h,
    required this.percentChange24h,
    required this.percentChange7d,
    required this.marketCap,
    required this.volume24h,
    required this.lastUpdated,
  });

  factory CryptoPriceData.fromJson(Map<String, dynamic> json) {
    final quote = json['quote']['USD'];
    return CryptoPriceData(
      symbol: json['symbol'] ?? '',
      name: json['name'] ?? '',
      price: (quote['price'] ?? 0.0).toDouble(),
      percentChange1h: (quote['percent_change_1h'] ?? 0.0).toDouble(),
      percentChange24h: (quote['percent_change_24h'] ?? 0.0).toDouble(),
      percentChange7d: (quote['percent_change_7d'] ?? 0.0).toDouble(),
      marketCap: (quote['market_cap'] ?? 0.0).toDouble(),
      volume24h: (quote['volume_24h'] ?? 0.0).toDouble(),
      lastUpdated: DateTime.parse(quote['last_updated']),
    );
  }
}

/// Model for chart data points
class ChartDataPoint {
  final DateTime timestamp;
  final double price;
  final double volume;

  ChartDataPoint({
    required this.timestamp,
    required this.price,
    required this.volume,
  });

  factory ChartDataPoint.fromJson(Map<String, dynamic> json) {
    final quote = json['quote']['USD'];
    return ChartDataPoint(
      timestamp: DateTime.parse(json['timestamp']),
      price: (quote['price'] ?? 0.0).toDouble(),
      volume: (quote['volume_24h'] ?? 0.0).toDouble(),
    );
  }
}

/// Model for cryptocurrency metadata
class CryptoMetadata {
  final String symbol;
  final String name;
  final String description;
  final String logo;
  final List<String> tags;
  final String website;

  CryptoMetadata({
    required this.symbol,
    required this.name,
    required this.description,
    required this.logo,
    required this.tags,
    required this.website,
  });

  factory CryptoMetadata.fromJson(Map<String, dynamic> json) {
    return CryptoMetadata(
      symbol: json['symbol'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      logo: json['logo'] ?? '',
      tags: List<String>.from(json['tags'] ?? []),
      website: (json['urls']['website'] as List?)?.first ?? '',
    );
  }
}
