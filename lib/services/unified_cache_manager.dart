import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/crypto_token.dart';
import '../services/secure_storage.dart';

enum CacheType {
  tokens,
  balances,
  prices,
  settings,
  userPreferences,
}

/// Unified Cache Manager برای مدیریت یکپارچه تمام cache ها
/// این کلاس تمام cache invalidation و synchronization را مدیریت می‌کند
class UnifiedCacheManager extends ChangeNotifier {
  static UnifiedCacheManager? _instance;
  static UnifiedCacheManager get instance => _instance ??= UnifiedCacheManager._();
  
  UnifiedCacheManager._();
  
  // Cache metadata
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, Duration> _cacheValidityDurations = {
    'tokens': const Duration(hours: 6),
    'balances': const Duration(minutes: 5),
    'prices': const Duration(minutes: 5),
    'settings': const Duration(days: 1),
    'userPreferences': const Duration(days: 7),
  };
  
  // Cache invalidation listeners
  final Map<String, List<VoidCallback>> _invalidationListeners = {};
  
  // Locks for thread safety
  final Map<String, Completer<void>> _cacheLocks = {};
  
  /// مقداردهی اولیه
  Future<void> initialize() async {
    print('🔄 UnifiedCacheManager: Initializing...');
    await _loadCacheTimestamps();
    print('✅ UnifiedCacheManager: Initialized');
  }
  
  /// بررسی اعتبار cache
  bool isCacheValid(CacheType type, String userId) {
    final key = _getCacheKey(type, userId);
    final timestamp = _cacheTimestamps[key];
    final duration = _cacheValidityDurations[type.name];
    
    if (timestamp == null || duration == null) {
      return false;
    }
    
    final now = DateTime.now();
    final isValid = now.difference(timestamp) < duration;
    
    if (!isValid) {
      print('⚠️ UnifiedCacheManager: Cache expired for $key (age: ${now.difference(timestamp)})');
    }
    
    return isValid;
  }
  
  /// به‌روزرسانی timestamp cache
  Future<void> updateCacheTimestamp(CacheType type, String userId) async {
    final key = _getCacheKey(type, userId);
    _cacheTimestamps[key] = DateTime.now();
    await _persistCacheTimestamp(key);
    
    print('✅ UnifiedCacheManager: Updated timestamp for $key');
  }
  
  /// invalidate کردن cache خاص
  Future<void> invalidateCache(CacheType type, String userId) async {
    await _acquireLock(type, userId);
    
    try {
      final key = _getCacheKey(type, userId);
      _cacheTimestamps.remove(key);
      
      // پاک کردن cache از SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await prefs.remove('${key}_timestamp');
      
      // اطلاع به listeners
      _notifyInvalidationListeners(key);
      
      print('🧹 UnifiedCacheManager: Invalidated cache for $key');
      
    } finally {
      _releaseLock(type, userId);
    }
  }
  
  /// invalidate کردن تمام cache های کاربر
  Future<void> invalidateUserCaches(String userId) async {
    print('🧹 UnifiedCacheManager: Invalidating all caches for user: $userId');
    
    for (final type in CacheType.values) {
      await invalidateCache(type, userId);
    }
    
    notifyListeners();
    print('✅ UnifiedCacheManager: Invalidated all caches for user: $userId');
  }
  
  /// invalidate کردن تمام cache ها
  Future<void> invalidateAllCaches() async {
    print('🧹 UnifiedCacheManager: Invalidating ALL caches');
    
    _cacheTimestamps.clear();
    
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => 
      key.contains('_cache_') || key.contains('_timestamp')).toList();
    
    for (final key in keys) {
      await prefs.remove(key);
    }
    
    // اطلاع به همه listeners
    for (final listeners in _invalidationListeners.values) {
      for (final listener in listeners) {
        listener();
      }
    }
    
    notifyListeners();
    print('✅ UnifiedCacheManager: Invalidated ALL caches');
  }
  
  /// ذخیره داده در cache
  Future<void> setCache<T>(CacheType type, String userId, T data) async {
    await _acquireLock(type, userId);
    
    try {
      final key = _getCacheKey(type, userId);
      final prefs = await SharedPreferences.getInstance();
      
      String jsonData;
      if (data is List<CryptoToken>) {
        jsonData = json.encode(data.map((token) => token.toJson()).toList());
      } else if (data is Map) {
        jsonData = json.encode(data);
      } else {
        jsonData = json.encode(data);
      }
      
      await prefs.setString(key, jsonData);
      await updateCacheTimestamp(type, userId);
      
      print('💾 UnifiedCacheManager: Cached data for $key');
      
    } finally {
      _releaseLock(type, userId);
    }
  }
  
  /// دریافت داده از cache
  Future<T?> getCache<T>(CacheType type, String userId) async {
    final key = _getCacheKey(type, userId);
    
    if (!isCacheValid(type, userId)) {
      print('⚠️ UnifiedCacheManager: Cache invalid for $key');
      return null;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonData = prefs.getString(key);
      
      if (jsonData == null) {
        return null;
      }
      
      final decodedData = json.decode(jsonData);
      
      // Type-specific deserialization
      if (T == List<CryptoToken>) {
        final list = decodedData as List;
        final tokens = list.map((item) => CryptoToken.fromJson(item)).toList();
        return tokens as T;
      } else if (decodedData is Map) {
        // Generic type comparisons like T == Map<String, String> are not valid in Dart.
        return Map<String, dynamic>.from(decodedData) as T;
      } else {
        return decodedData as T;
      }
      
    } catch (e) {
      print('❌ UnifiedCacheManager: Error reading cache for $key: $e');
      return null;
    }
  }
  
  /// اضافه کردن listener برای invalidation
  void addInvalidationListener(CacheType type, String userId, VoidCallback listener) {
    final key = _getCacheKey(type, userId);
    _invalidationListeners[key] ??= [];
    _invalidationListeners[key]!.add(listener);
  }
  
  /// حذف listener
  void removeInvalidationListener(CacheType type, String userId, VoidCallback listener) {
    final key = _getCacheKey(type, userId);
    _invalidationListeners[key]?.remove(listener);
  }
  
  /// synchronize کردن cache بین منابع مختلف
  Future<void> synchronizeCaches(String userId) async {
    print('🔄 UnifiedCacheManager: Synchronizing caches for user: $userId');
    
    try {
      // بررسی consistency بین cache های مختلف
      final tokensCacheValid = isCacheValid(CacheType.tokens, userId);
      final balancesCacheValid = isCacheValid(CacheType.balances, userId);
      
      // اگر token cache معتبر نیست اما balance cache معتبر است، balance را invalidate کن
      if (!tokensCacheValid && balancesCacheValid) {
        await invalidateCache(CacheType.balances, userId);
        print('🔄 UnifiedCacheManager: Invalidated balances due to token cache expiry');
      }
      
      // بررسی SecureStorage consistency
      await _synchronizeWithSecureStorage(userId);
      
      print('✅ UnifiedCacheManager: Cache synchronization completed');
      
    } catch (e) {
      print('❌ UnifiedCacheManager: Error during cache synchronization: $e');
    }
  }
  
  /// دریافت اطلاعات cache برای debug
  Map<String, dynamic> getCacheInfo(String userId) {
    final info = <String, dynamic>{};
    
    for (final type in CacheType.values) {
      final key = _getCacheKey(type, userId);
      final timestamp = _cacheTimestamps[key];
      final duration = _cacheValidityDurations[type.name];
      
      info[type.name] = {
        'timestamp': timestamp?.toIso8601String(),
        'age': timestamp != null ? DateTime.now().difference(timestamp).toString() : null,
        'validity': duration?.toString(),
        'isValid': isCacheValid(type, userId),
      };
    }
    
    return info;
  }
  
  // Private helper methods
  
  String _getCacheKey(CacheType type, String userId) {
    return '${type.name}_cache_$userId';
  }
  
  Future<void> _acquireLock(CacheType type, String userId) async {
    final lockKey = '${type.name}_$userId';
    
    while (_cacheLocks.containsKey(lockKey)) {
      await _cacheLocks[lockKey]!.future;
    }
    
    _cacheLocks[lockKey] = Completer<void>();
  }
  
  void _releaseLock(CacheType type, String userId) {
    final lockKey = '${type.name}_$userId';
    final completer = _cacheLocks.remove(lockKey);
    completer?.complete();
  }
  
  void _notifyInvalidationListeners(String key) {
    final listeners = _invalidationListeners[key];
    if (listeners != null) {
      for (final listener in listeners) {
        try {
          listener();
        } catch (e) {
          print('❌ UnifiedCacheManager: Error in invalidation listener: $e');
        }
      }
    }
  }
  
  Future<void> _loadCacheTimestamps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.endsWith('_timestamp')).toList();
      
      for (final key in keys) {
        final timestamp = prefs.getInt(key);
        if (timestamp != null) {
          final cacheKey = key.replaceAll('_timestamp', '');
          _cacheTimestamps[cacheKey] = DateTime.fromMillisecondsSinceEpoch(timestamp);
        }
      }
      
      print('✅ UnifiedCacheManager: Loaded ${_cacheTimestamps.length} cache timestamps');
      
    } catch (e) {
      print('❌ UnifiedCacheManager: Error loading cache timestamps: $e');
    }
  }
  
  Future<void> _persistCacheTimestamp(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = _cacheTimestamps[key];
      
      if (timestamp != null) {
        await prefs.setInt('${key}_timestamp', timestamp.millisecondsSinceEpoch);
      }
      
    } catch (e) {
      print('❌ UnifiedCacheManager: Error persisting timestamp for $key: $e');
    }
  }
  
  Future<void> _synchronizeWithSecureStorage(String userId) async {
    try {
      // بررسی consistency با SecureStorage
      final currentWallet = await SecureStorage.instance.getSelectedWallet();
      if (currentWallet != null) {
        final secureActiveTokens = await SecureStorage.instance.getActiveTokens(currentWallet, userId);
        final cachedTokens = await getCache<List<CryptoToken>>(CacheType.tokens, userId);
        
        if (cachedTokens != null && secureActiveTokens.isNotEmpty) {
          final cachedActiveSymbols = cachedTokens
              .where((t) => t.isEnabled)
              .map((t) => t.symbol ?? '')
              .toSet();
          final secureActiveSymbols = secureActiveTokens.toSet();
          
          // اگر تفاوت وجود دارد، cache را invalidate کن
          if (!_setsEqual(cachedActiveSymbols, secureActiveSymbols)) {
            await invalidateCache(CacheType.tokens, userId);
            print('🔄 UnifiedCacheManager: Invalidated token cache due to SecureStorage mismatch');
          }
        }
      }
      
    } catch (e) {
      print('❌ UnifiedCacheManager: Error synchronizing with SecureStorage: $e');
    }
  }
  
  bool _setsEqual<T>(Set<T> set1, Set<T> set2) {
    if (set1.length != set2.length) return false;
    return set1.every(set2.contains);
  }
  
  /// Debug method
  void debugCacheState() {
    print('=== UnifiedCacheManager Debug ===');
    print('Cache timestamps: ${_cacheTimestamps.length}');
    print('Invalidation listeners: ${_invalidationListeners.length}');
    print('Active locks: ${_cacheLocks.length}');
    
    for (final entry in _cacheTimestamps.entries) {
      final age = DateTime.now().difference(entry.value);
      print('  ${entry.key}: ${entry.value} (age: $age)');
    }
    print('===============================');
  }
}
