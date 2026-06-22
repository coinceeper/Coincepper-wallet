import 'dart:async';
import '../di/service_locator.dart';
import '../services/screen_cache_manager.dart';
import '../utils/secure_log.dart';
import 'coingecko_service.dart';

/// 📈 ChartDataManager
/// 
/// مدیریت هوشمند API های مختلف برای دریافت داده‌های چارت
/// بر اساس بازه زمانی مناسب‌ترین API را انتخاب می‌کند
class ChartDataManager {
  ChartDataManager();

  ChartDataManager._internal();

  static ChartDataManager get instance => ServiceLocator.get<ChartDataManager>();
  
  // Live update timers
  final Map<String, Timer?> _liveUpdateTimers = {};
  final Map<String, Function(ChartData)?> _liveUpdateCallbacks = {};

  /// 📊 دریافت داده‌های چارت بر اساس timeframe
  Future<ChartData?> getChartData(
    String symbol, 
    String timeframe, 
    String fiatCurrency, {
    bool useCache = true,
  }) async {
    try {
      SecureLog.d('ChartDataManager: Getting chart data for $symbol, timeframe: $timeframe');

      // ⚡ Check cache first
      if (useCache) {
        final cached = await _getCachedChartData(symbol, timeframe, fiatCurrency);
        if (cached != null) {
          SecureLog.d('Using cached chart data for $symbol $timeframe');
          return cached;
        }
      }

      ChartData? chartData;

      switch (timeframe) {
        case '1h':
        case '1d':
        case '1w':
          chartData = await _getRealtimeChart(symbol, timeframe, fiatCurrency);
          break;
          
        case '1m':
        case '3m':
          chartData = await _getHistoricalChart(symbol, timeframe, fiatCurrency);
          break;
          
        case '1y':
          chartData = await _getLongTermChart(symbol, fiatCurrency);
          break;
          
        default:
          SecureLog.w('Unsupported timeframe: $timeframe');
          return null;
      }

      // Cache the result
      if (chartData != null) {
        await _cacheChartData(symbol, timeframe, fiatCurrency, chartData);
      }

      return chartData;
    } catch (e) {
      SecureLog.e('ChartDataManager: Error getting chart data', error: e);
      return null;
    }
  }

  /// ⏰ دریافت چارت Real-time (1h, 1d, 1w) — از CoinGecko
  Future<ChartData?> _getRealtimeChart(String symbol, String timeframe, String fiatCurrency) async {
    try {
      final daysMap = {'1h': 1, '1d': 1, '1w': 7};
      final days = daysMap[timeframe] ?? 1;
      final raw = await ServiceLocator.get<CoinGeckoService>().fetchChart(symbol, days);
      if (raw == null || raw.isEmpty) return null;

      final points = raw.map((arr) => ChartPoint(
        timestamp: DateTime.fromMillisecondsSinceEpoch(arr[0].toInt()),
        price: (arr[1]).toDouble(),
      )).toList();

      return ChartData(
        symbol: symbol.toUpperCase(),
        timeframe: timeframe,
        points: points,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  /// 📅 دریافت چارت Historical (1m, 3m) — از CoinGecko
  Future<ChartData?> _getHistoricalChart(String symbol, String timeframe, String fiatCurrency) async {
    try {
      final monthsMap = {'1m': 30, '3m': 90};
      final days = monthsMap[timeframe] ?? 30;
      final raw = await ServiceLocator.get<CoinGeckoService>().fetchChart(symbol, days);
      if (raw == null || raw.isEmpty) return null;

      final points = raw.map((arr) => ChartPoint(
        timestamp: DateTime.fromMillisecondsSinceEpoch(arr[0].toInt()),
        price: (arr[1]).toDouble(),
      )).toList();

      return ChartData(
        symbol: symbol.toUpperCase(),
        timeframe: timeframe,
        points: points,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  /// 📊 دریافت چارت Long-term (1y) — از CoinGecko
  Future<ChartData?> _getLongTermChart(String symbol, String fiatCurrency) async {
    try {
      final raw = await ServiceLocator.get<CoinGeckoService>().fetchChart(symbol, 365);
      if (raw == null || raw.isEmpty) return null;

      final points = raw.map((arr) => ChartPoint(
        timestamp: DateTime.fromMillisecondsSinceEpoch(arr[0].toInt()),
        price: (arr[1]).toDouble(),
      )).toList();

      return ChartData(
        symbol: symbol.toUpperCase(),
        timeframe: '1y',
        points: points,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  /// 🔄 شروع آپدیت زنده
  void startLiveUpdates(
    String symbol, 
    String timeframe, 
    String fiatCurrency,
    Function(ChartData) onUpdate,
  ) {
    final key = '${symbol}_${timeframe}_$fiatCurrency';
    
    // متوقف کردن timer قبلی در صورت وجود
    stopLiveUpdates(symbol, timeframe, fiatCurrency);

    // تنها برای timeframe های کوتاه مدت
    if (!['1h', '1d', '1w'].contains(timeframe)) {
      SecureLog.w('Live updates not supported for timeframe: $timeframe');
      return;
    }

    final updateIntervals = {
      '1h': const Duration(seconds: 30),
      '1d': const Duration(minutes: 1),
      '1w': const Duration(minutes: 5),
    };

    final interval = updateIntervals[timeframe] ?? const Duration(minutes: 1);
    
    SecureLog.d('Starting live updates for $symbol $timeframe (every ${interval.inSeconds}s)');
    
    _liveUpdateCallbacks[key] = onUpdate;
    
    _liveUpdateTimers[key] = Timer.periodic(interval, (timer) async {
      try {
        final liveData = await _getLiveUpdate(symbol, fiatCurrency);
        if (liveData != null) {
          final callback = _liveUpdateCallbacks[key];
          if (callback != null) {
            // Create updated chart data with live price
            final currentData = await getChartData(symbol, timeframe, fiatCurrency, useCache: true);
            if (currentData != null) {
              final updatedData = currentData.copyWithLiveUpdate(liveData);
              callback(updatedData);
            }
          }
        }
      } catch (e) {
        SecureLog.e('Error in live update', error: e);
      }
    });
  }

  /// ⏹️ متوقف کردن آپدیت زنده
  void stopLiveUpdates(String symbol, String timeframe, String fiatCurrency) {
    final key = '${symbol}_${timeframe}_$fiatCurrency';
    
    _liveUpdateTimers[key]?.cancel();
    _liveUpdateTimers.remove(key);
    _liveUpdateCallbacks.remove(key);
    
    SecureLog.d('Stopped live updates for $symbol $timeframe');
  }

  /// 📡 دریافت آپدیت زنده — از CoinGecko
  Future<LiveUpdateData?> _getLiveUpdate(String symbol, String fiatCurrency) async {
    try {
      final prices = await ServiceLocator.get<CoinGeckoService>().fetchPrices([symbol]);
      final coin = prices[symbol.toUpperCase()];
      if (coin != null) {
        return LiveUpdateData.simple(
          price: coin['USD'] ?? 0,
          change24h: coin['change_24h'] ?? 0,
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 💾 Cache chart data
  Future<void> _cacheChartData(String symbol, String timeframe, String fiatCurrency, ChartData data) async {
    try {
      final key = 'chart_${symbol}_${timeframe}_$fiatCurrency';
      final expiryMinutes = _getCacheExpiryMinutes(timeframe);
      
      await ServiceLocator.get<ScreenCacheManager>().cacheWithCustomExpiry(
        key,
        data.toJson(),
        expiryMinutes,
      );
      
      SecureLog.i('Chart data cached for $symbol $timeframe (expires in ${expiryMinutes}m)');
    } catch (e) {
      SecureLog.e('Error caching chart data', error: e);
    }
  }

  /// 📖 دریافت chart data از cache
  Future<ChartData?> _getCachedChartData(String symbol, String timeframe, String fiatCurrency) async {
    try {
      final key = 'chart_${symbol}_${timeframe}_$fiatCurrency';
      final cachedData = await ServiceLocator.get<ScreenCacheManager>().getCachedWithCustomExpiry<Map<String, dynamic>>(key);
      
      if (cachedData != null) {
        return ChartData.fromJson(cachedData);
      }
      
      return null;
    } catch (e) {
      SecureLog.e('Error getting cached chart data', error: e);
      return null;
    }
  }

  /// ⏰ تعیین مدت زمان cache بر اساس timeframe
  int _getCacheExpiryMinutes(String timeframe) {
    switch (timeframe) {
      case '1h': return 5;   // 5 دقیقه
      case '1d': return 15;  // 15 دقیقه
      case '1w': return 60;  // 1 ساعت
      case '1m': return 240; // 4 ساعت
      case '3m': return 480; // 8 ساعت
      case '1y': return 1440; // 24 ساعت
      default: return 60;
    }
  }

  /// 🧹 پاک کردن تمام live updates
  void dispose() {
    for (final timer in _liveUpdateTimers.values) {
      timer?.cancel();
    }
    _liveUpdateTimers.clear();
    _liveUpdateCallbacks.clear();
    SecureLog.d('ChartDataManager disposed');
  }
}

/// 📊 مدل داده چارت
class ChartData {
  final String symbol;
  final String timeframe;
  final List<ChartPoint> points;
  final List<VolumePoint>? volumeData;
  final TechnicalIndicators? indicators;
  final DateTime lastUpdated;

  ChartData({
    required this.symbol,
    required this.timeframe,
    required this.points,
    this.volumeData,
    this.indicators,
    required this.lastUpdated,
  });

  factory ChartData.fromRealtimeApi(Map<String, dynamic> data, String symbol, String timeframe) {
    final priceData = data['price_data'] as List<dynamic>? ?? [];
    final volumeData = data['volume_data'] as List<dynamic>? ?? [];
    final indicatorData = data['technical_indicators'] as Map<String, dynamic>?;

    final points = priceData.map((point) => ChartPoint(
      timestamp: DateTime.parse(point['timestamp']),
      price: (point['price'] as num).toDouble(),
      high: (point['high'] as num?)?.toDouble(),
      low: (point['low'] as num?)?.toDouble(),
      open: (point['open'] as num?)?.toDouble(),
      close: (point['close'] as num?)?.toDouble(),
    )).toList();

    final volume = volumeData.map((vol) => VolumePoint(
      timestamp: DateTime.parse(vol['timestamp']),
      volume: (vol['volume'] as num).toDouble(),
    )).toList();

    return ChartData(
      symbol: symbol,
      timeframe: timeframe,
      points: points,
      volumeData: volume.isNotEmpty ? volume : null,
      indicators: indicatorData != null ? TechnicalIndicators.fromJson(indicatorData) : null,
      lastUpdated: DateTime.now(),
    );
  }

  factory ChartData.fromHistoricalApi(Map<String, dynamic> data, String symbol, String timeframe) {
    final prices = data['prices'] as Map<String, dynamic>? ?? {};
    final symbolData = prices[symbol] as List<dynamic>? ?? [];

    final points = symbolData.map((point) => ChartPoint(
      timestamp: DateTime.parse(point['date']),
      price: (point['price'] as num).toDouble(),
    )).toList();

    return ChartData(
      symbol: symbol,
      timeframe: timeframe,
      points: points,
      lastUpdated: DateTime.now(),
    );
  }

  factory ChartData.fromJson(Map<String, dynamic> json) {
    return ChartData(
      symbol: json['symbol'],
      timeframe: json['timeframe'],
      points: (json['points'] as List).map((p) => ChartPoint.fromJson(p)).toList(),
      volumeData: json['volumeData'] != null 
        ? (json['volumeData'] as List).map((v) => VolumePoint.fromJson(v)).toList()
        : null,
      indicators: json['indicators'] != null 
        ? TechnicalIndicators.fromJson(json['indicators'])
        : null,
      lastUpdated: DateTime.parse(json['lastUpdated']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'symbol': symbol,
      'timeframe': timeframe,
      'points': points.map((p) => p.toJson()).toList(),
      'volumeData': volumeData?.map((v) => v.toJson()).toList(),
      'indicators': indicators?.toJson(),
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }

  /// Create copy with live update
  ChartData copyWithLiveUpdate(LiveUpdateData liveData) {
    final updatedPoints = List<ChartPoint>.from(points);
    
    // Add or update the latest point
    final latestPoint = ChartPoint(
      timestamp: liveData.timestamp,
      price: liveData.price,
    );
    
    if (updatedPoints.isNotEmpty && 
        updatedPoints.last.timestamp.isAtSameMomentAs(liveData.timestamp)) {
      updatedPoints[updatedPoints.length - 1] = latestPoint;
    } else {
      updatedPoints.add(latestPoint);
    }

    return ChartData(
      symbol: symbol,
      timeframe: timeframe,
      points: updatedPoints,
      volumeData: volumeData,
      indicators: indicators,
      lastUpdated: DateTime.now(),
    );
  }
}

/// 📍 نقطه چارت
class ChartPoint {
  final DateTime timestamp;
  final double price;
  final double? high;
  final double? low;
  final double? open;
  final double? close;

  ChartPoint({
    required this.timestamp,
    required this.price,
    this.high,
    this.low,
    this.open,
    this.close,
  });

  factory ChartPoint.fromJson(Map<String, dynamic> json) {
    return ChartPoint(
      timestamp: DateTime.parse(json['timestamp']),
      price: json['price'].toDouble(),
      high: json['high']?.toDouble(),
      low: json['low']?.toDouble(),
      open: json['open']?.toDouble(),
      close: json['close']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'price': price,
      'high': high,
      'low': low,
      'open': open,
      'close': close,
    };
  }
}

/// 📊 نقطه حجم معاملات
class VolumePoint {
  final DateTime timestamp;
  final double volume;

  VolumePoint({
    required this.timestamp,
    required this.volume,
  });

  factory VolumePoint.fromJson(Map<String, dynamic> json) {
    return VolumePoint(
      timestamp: DateTime.parse(json['timestamp']),
      volume: json['volume'].toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'volume': volume,
    };
  }
}

/// 📈 اندیکاتورهای تکنیکال
class TechnicalIndicators {
  final List<double>? sma; // Simple Moving Average
  final List<double>? ema; // Exponential Moving Average
  final RSIData? rsi;      // Relative Strength Index
  final MACDData? macd;    // Moving Average Convergence Divergence

  TechnicalIndicators({
    this.sma,
    this.ema,
    this.rsi,
    this.macd,
  });

  factory TechnicalIndicators.fromJson(Map<String, dynamic> json) {
    return TechnicalIndicators(
      sma: json['sma'] != null ? List<double>.from(json['sma']) : null,
      ema: json['ema'] != null ? List<double>.from(json['ema']) : null,
      rsi: json['rsi'] != null ? RSIData.fromJson(json['rsi']) : null,
      macd: json['macd'] != null ? MACDData.fromJson(json['macd']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sma': sma,
      'ema': ema,
      'rsi': rsi?.toJson(),
      'macd': macd?.toJson(),
    };
  }
}

/// 📊 داده RSI
class RSIData {
  final List<double> values;
  final double current;

  RSIData({required this.values, required this.current});

  factory RSIData.fromJson(Map<String, dynamic> json) {
    return RSIData(
      values: List<double>.from(json['values']),
      current: json['current'].toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'values': values,
      'current': current,
    };
  }
}

/// 📈 داده MACD
class MACDData {
  final List<double> macdLine;
  final List<double> signalLine;
  final List<double> histogram;

  MACDData({
    required this.macdLine,
    required this.signalLine,
    required this.histogram,
  });

  factory MACDData.fromJson(Map<String, dynamic> json) {
    return MACDData(
      macdLine: List<double>.from(json['macdLine']),
      signalLine: List<double>.from(json['signalLine']),
      histogram: List<double>.from(json['histogram']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'macdLine': macdLine,
      'signalLine': signalLine,
      'histogram': histogram,
    };
  }
}

/// 🔄 داده آپدیت زنده
class LiveUpdateData {
  final DateTime timestamp;
  final double price;
  final double? volume;
  final double? change24h;

  LiveUpdateData({
    required this.timestamp,
    required this.price,
    this.volume,
    this.change24h,
  });

  /// سازنده ساده برای V2 — بدون timestamp
  LiveUpdateData.simple({
    required this.price,
    this.change24h,
  }) : timestamp = DateTime.now(), volume = null;

  factory LiveUpdateData.fromJson(Map<String, dynamic> json) {
    return LiveUpdateData(
      timestamp: DateTime.parse(json['timestamp']),
      price: json['price'].toDouble(),
      volume: json['volume']?.toDouble(),
      change24h: json['change_24h']?.toDouble(),
    );
  }
}
