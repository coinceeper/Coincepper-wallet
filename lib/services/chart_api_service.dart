import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/secure_storage.dart';

/// سرویس API نمودار — Deprecated: از Cache Proxy V2 استفاده کنید
/// @deprecated از ChartDataManager استفاده کنید که از V2 cache proxy می‌خواند
@Deprecated('Use ChartDataManager (reads from V2 cache proxy)')
class ChartApiService {
  static const String _baseUrl = 'https://coinceeper.com/api';

  static Future<Map<String, String>> _getHeaders() async {
    final userId = await SecureStorage.getUserId();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'Flutter-App/1.0',
      if (userId != null) 'UserID': userId,
    };
  }

  /// Get chart data from the new API endpoint
  static Future<ChartApiData?> getChartData({
    required String symbol,
    String fiatCurrency = 'USD',
    required String timeframe,
    int? points,
  }) async {
    try {
      print('🔍 Fetching chart data for $symbol with timeframe $timeframe');

      // Determine points based on timeframe if not provided
      points ??= _getPointsForTimeframe(timeframe);
      
      // Map timeframe to API format
      final apiTimeframe = _mapTimeframeToApi(timeframe);

      print('🔄 API Request: Symbol=$symbol, Timeframe=$apiTimeframe, Points=$points');

      final response = await http.post(
        Uri.parse('$_baseUrl/chart-data'),
        headers: await _getHeaders(),
        body: json.encode({
          'Symbol': symbol,
          'FiatCurrency': fiatCurrency,
          'timeframe': apiTimeframe,
          'points': points,
        }),
      );

      print('🌐 Chart API Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Chart API Response Keys: ${data.keys}');

        if (data['success'] == true && data['chart_data'] != null) {
          final chartApiData = ChartApiData.fromJson(data);
          print('✅ Chart data parsed successfully: ${chartApiData.data.length} data points');
          return chartApiData;
        } else {
          final errorMessage = data['message'] ?? 'Unknown error';
          print('❌ Chart API Error: $errorMessage');
          print('📊 API Response: ${json.encode(data)}');
        }
      } else {
        print('❌ Chart API HTTP Error: ${response.statusCode}');
        print('📝 Response Body: ${response.body}');
      }
      return null;
    } catch (e) {
      print('❌ Error fetching chart data: $e');
      return null;
    }
  }

  /// Get live price updates
  static Future<Map<String, LivePriceData>?> getLivePrices({
    required List<String> symbols,
    String fiatCurrency = 'USD',
  }) async {
    try {
      print('🔍 Fetching live prices for symbols: $symbols');

      final response = await http.post(
        Uri.parse('$_baseUrl/chart-live-update'),
        headers: await _getHeaders(),
        body: json.encode({
          'Symbol': symbols,
          'FiatCurrency': fiatCurrency,
        }),
      );

      print('🌐 Live Price API Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Live Price API Response Keys: ${data.keys}');

        if (data['success'] == true && data['live_prices'] != null) {
          final livePrices = <String, LivePriceData>{};
          final pricesData = data['live_prices'] as Map<String, dynamic>;

          for (final entry in pricesData.entries) {
            try {
              livePrices[entry.key] = LivePriceData.fromJson(entry.value);
              print('✅ Live price parsed for ${entry.key}: \$${entry.value['price']}');
            } catch (parseError) {
              print('❌ Error parsing live price for ${entry.key}: $parseError');
            }
          }

          print('✅ Live prices loaded for ${livePrices.length} symbols');
          return livePrices;
        } else {
          final errorMessage = data['message'] ?? 'Unknown error';
          print('❌ Live Price API Error: $errorMessage');
          print('📊 API Response: ${json.encode(data)}');
        }
      } else {
        print('❌ Live Price API HTTP Error: ${response.statusCode}');
        print('📝 Response Body: ${response.body}');
      }
      return null;
    } catch (e) {
      print('❌ Error fetching live prices: $e');
      return null;
    }
  }

  /// Get points count for timeframe based on real API requirements
  static int _getPointsForTimeframe(String timeframe) {
    switch (timeframe) {
      case '1h':
        return 60; // 60 points for hourly data (last 60 minutes, 1-minute intervals)
      case '1d':
        return 24; // 24 points for daily data (last 24 hours, 1-hour intervals)
      case '1w':
        return 168; // 168 points for weekly data (7 days × 24 hours, 1-hour intervals)
      case '1m':
        return 30; // 30 points for monthly data (last 30 days, 1-day intervals)
      case '3m':
        return 90; // 90 points for 3-month data (last 90 days, 1-day intervals)
      case '1y':
        return 52; // 52 points for yearly data (last 52 weeks, 1-week intervals)
      default:
        return 30;
    }
  }

  /// Map Flutter timeframes to API timeframes
  static String _mapTimeframeToApi(String flutterTimeframe) {
    switch (flutterTimeframe) {
      case '1h':
        return '1h'; // Hourly data
      case '1d':
        return '1d'; // Daily data  
      case '1w':
        return '1w'; // Weekly data
      case '1m':
        return '1m'; // Monthly data
      case '3m':
        return '3m'; // 3 months data
      case '1y':
        return '1y'; // Yearly data
      default:
        return '1d'; // Default to daily
    }
  }
}

class ChartApiData {
  final String symbol;
  final String fiat;
  final String timeframe;
  final List<ChartDataPoint> data;
  final int pointsCount;
  final DateTime lastUpdated;

  ChartApiData({
    required this.symbol,
    required this.fiat,
    required this.timeframe,
    required this.data,
    required this.pointsCount,
    required this.lastUpdated,
  });

  factory ChartApiData.fromJson(Map<String, dynamic> json) {
    final chartData = json['chart_data'];
    final dataList = chartData['data'] as List;

    return ChartApiData(
      symbol: chartData['symbol'] ?? '',
      fiat: chartData['fiat'] ?? 'USD',
      timeframe: chartData['timeframe'] ?? '1d',
      data: dataList.map((item) => ChartDataPoint.fromJson(item)).toList(),
      pointsCount: json['points_count'] ?? dataList.length,
      lastUpdated: DateTime.tryParse(json['last_updated'] ?? '') ?? DateTime.now(),
    );
  }

  // Convert to the format expected by existing chart widget
  ChartData toChartData() {
    if (data.isEmpty) {
      return ChartData(
        points: [],
        currentPrice: 0.0,
        priceChange: 0.0,
        priceChangePercent: 0.0,
        minPrice: 0.0,
        maxPrice: 0.0,
        timeFrame: timeframe,
      );
    }

    final points = data.map((point) => ChartPoint(
      timestamp: point.timestamp,
      price: point.price,
    )).toList();

    final prices = data.map((point) => point.price).toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);

    final currentPrice = data.last.price;
    final previousPrice = data.first.price;
    final priceChange = currentPrice - previousPrice;
    final priceChangePercent = (priceChange / previousPrice) * 100;

    return ChartData(
      points: points,
      currentPrice: currentPrice,
      priceChange: priceChange,
      priceChangePercent: priceChangePercent,
      minPrice: minPrice,
      maxPrice: maxPrice,
      timeFrame: timeframe,
    );
  }
}

class ChartDataPoint {
  final DateTime timestamp;
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
      timestamp: DateTime.parse(json['timestamp']),
      price: (json['price'] as num).toDouble(),
      volume: (json['volume'] as num?)?.toDouble() ?? 0.0,
      marketCap: (json['market_cap'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

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
      price: (json['price'] as num).toDouble(),
      change24h: (json['change_24h'] as num).toDouble(),
      volume24h: (json['volume_24h'] as num?)?.toDouble() ?? 0.0,
      lastUpdated: DateTime.tryParse(json['last_updated'] ?? '') ?? DateTime.now(),
    );
  }
}

// Import existing classes to maintain compatibility
class ChartData {
  final List<ChartPoint> points;
  final double currentPrice;
  final double priceChange;
  final double priceChangePercent;
  final double minPrice;
  final double maxPrice;
  final String timeFrame;

  ChartData({
    required this.points,
    required this.currentPrice,
    required this.priceChange,
    required this.priceChangePercent,
    required this.minPrice,
    required this.maxPrice,
    required this.timeFrame,
  });
}

class ChartPoint {
  final DateTime timestamp;
  final double price;

  ChartPoint({required this.timestamp, required this.price});
}
