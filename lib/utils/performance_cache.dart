/// ⚡ Performance Cache for ultra-fast app operations
class PerformanceCache {
  static final PerformanceCache _instance = PerformanceCache._internal();
  factory PerformanceCache() => _instance;
  PerformanceCache._internal();
  
  static PerformanceCache get instance => _instance;
  
  // ⚡ Memory cache for frequent operations
  final Map<String, dynamic> _memoryCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Duration _cacheExpiry = const Duration(minutes: 5);
  
  /// ⚡ Cache frequently used data
  void cache(String key, dynamic value) {
    _memoryCache[key] = value;
    _cacheTimestamps[key] = DateTime.now();
    
    // Clean old entries periodically
    if (_memoryCache.length > 100) {
      _cleanExpiredCache();
    }
  }
  
  /// ⚡ Get cached data
  T? get<T>(String key) {
    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return null;
    
    // Check if expired
    if (DateTime.now().difference(timestamp) > _cacheExpiry) {
      _memoryCache.remove(key);
      _cacheTimestamps.remove(key);
      return null;
    }
    
    return _memoryCache[key] as T?;
  }
  
  /// ⚡ Clear expired cache entries
  void _cleanExpiredCache() {
    final now = DateTime.now();
    final expiredKeys = <String>[];
    
    _cacheTimestamps.forEach((key, timestamp) {
      if (now.difference(timestamp) > _cacheExpiry) {
        expiredKeys.add(key);
      }
    });
    
    for (final key in expiredKeys) {
      _memoryCache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }
  
  /// ⚡ Clear all cache
  void clearAll() {
    _memoryCache.clear();
    _cacheTimestamps.clear();
  }
  
  /// ⚡ Pre-warm cache with common data
  void preWarmCache() {
    // Pre-calculate common values
    cache('app_start_time', DateTime.now().millisecondsSinceEpoch);
    cache('default_tokens', ['BTC', 'ETH', 'TRX']);
    cache('supported_currencies', ['USD', 'EUR', 'GBP', 'JPY']);
  }
} 