/// 📊 Chart Data Models
/// Models for chart data points and related information
library;

class ChartDataPoint {
  final DateTime timestamp;
  final double price;
  final double volume;
  final double? marketCap;
  final double? change1h;
  final double? change24h;
  final double? change7d;

  ChartDataPoint({
    required this.timestamp,
    required this.price,
    required this.volume,
    this.marketCap,
    this.change1h,
    this.change24h,
    this.change7d,
  });

  /// Create from JSON
  factory ChartDataPoint.fromJson(Map<String, dynamic> json) {
    return ChartDataPoint(
      timestamp: DateTime.parse(json['timestamp']),
      price: (json['price'] ?? 0).toDouble(),
      volume: (json['volume'] ?? 0).toDouble(),
      marketCap: json['market_cap']?.toDouble(),
      change1h: json['change_1h']?.toDouble(),
      change24h: json['change_24h']?.toDouble(),
      change7d: json['change_7d']?.toDouble(),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'price': price,
      'volume': volume,
      if (marketCap != null) 'market_cap': marketCap,
      if (change1h != null) 'change_1h': change1h,
      if (change24h != null) 'change_24h': change24h,
      if (change7d != null) 'change_7d': change7d,
    };
  }

  @override
  String toString() {
    return 'ChartDataPoint(timestamp: $timestamp, price: $price, volume: $volume)';
  }
}

/// Chart timeframe configuration
class ChartTimeframe {
  final String key;
  final String label;
  final Duration duration;
  final int maxPoints;
  final Duration pointInterval;

  const ChartTimeframe({
    required this.key,
    required this.label,
    required this.duration,
    required this.maxPoints,
    required this.pointInterval,
  });

  static const List<ChartTimeframe> predefined = [
    ChartTimeframe(
      key: '1h',
      label: '1H',
      duration: Duration(hours: 1),
      maxPoints: 60,
      pointInterval: Duration(minutes: 1),
    ),
    ChartTimeframe(
      key: '4h',
      label: '4H',
      duration: Duration(hours: 4),
      maxPoints: 48,
      pointInterval: Duration(minutes: 5),
    ),
    ChartTimeframe(
      key: '1d',
      label: '1D',
      duration: Duration(days: 1),
      maxPoints: 24,
      pointInterval: Duration(hours: 1),
    ),
    ChartTimeframe(
      key: '1w',
      label: '1W',
      duration: Duration(days: 7),
      maxPoints: 168,
      pointInterval: Duration(hours: 1),
    ),
    ChartTimeframe(
      key: '1m',
      label: '1M',
      duration: Duration(days: 30),
      maxPoints: 30,
      pointInterval: Duration(days: 1),
    ),
    ChartTimeframe(
      key: '3m',
      label: '3M',
      duration: Duration(days: 90),
      maxPoints: 90,
      pointInterval: Duration(days: 1),
    ),
  ];

  static ChartTimeframe? fromKey(String key) {
    try {
      return predefined.firstWhere((tf) => tf.key == key);
    } catch (e) {
      return null;
    }
  }
}

/// Chart statistics and analysis
class ChartAnalysis {
  final double minPrice;
  final double maxPrice;
  final double currentPrice;
  final double priceChange;
  final double priceChangePercent;
  final double averageVolume;
  final bool isUptrend;
  final double volatility;

  ChartAnalysis({
    required this.minPrice,
    required this.maxPrice,
    required this.currentPrice,
    required this.priceChange,
    required this.priceChangePercent,
    required this.averageVolume,
    required this.isUptrend,
    required this.volatility,
  });

  /// Calculate analysis from data points
  factory ChartAnalysis.fromDataPoints(List<ChartDataPoint> points) {
    if (points.isEmpty) {
      return ChartAnalysis(
        minPrice: 0,
        maxPrice: 0,
        currentPrice: 0,
        priceChange: 0,
        priceChangePercent: 0,
        averageVolume: 0,
        isUptrend: false,
        volatility: 0,
      );
    }

    final prices = points.map((p) => p.price).toList();
    final volumes = points.map((p) => p.volume).toList();
    
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final currentPrice = points.last.price;
    final firstPrice = points.first.price;
    
    final priceChange = currentPrice - firstPrice;
    final priceChangePercent = firstPrice != 0 ? (priceChange / firstPrice) * 100 : 0.0;
    
    final averageVolume = volumes.isNotEmpty 
        ? volumes.reduce((a, b) => a + b) / volumes.length.toDouble() 
        : 0.0;
    
    final isUptrend = priceChange > 0;
    
    // Calculate volatility (standard deviation of price changes)
    double volatility = 0;
    if (points.length > 1) {
      final priceChanges = <double>[];
      for (int i = 1; i < points.length; i++) {
        final change = (points[i].price - points[i-1].price) / points[i-1].price;
        priceChanges.add(change);
      }
      
      final meanChange = priceChanges.reduce((a, b) => a + b) / priceChanges.length.toDouble();
      final variance = priceChanges
          .map((change) => (change - meanChange) * (change - meanChange))
          .reduce((a, b) => a + b) / priceChanges.length.toDouble();
      volatility = variance * 100; // Convert to percentage
    }

    return ChartAnalysis(
      minPrice: minPrice,
      maxPrice: maxPrice,
      currentPrice: currentPrice,
      priceChange: priceChange,
      priceChangePercent: priceChangePercent,
      averageVolume: averageVolume,
      isUptrend: isUptrend,
      volatility: volatility,
    );
  }
}
