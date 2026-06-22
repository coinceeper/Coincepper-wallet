import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../di/service_locator.dart';
import '../models/crypto_token.dart';
import '../services/secure_storage.dart';
import '../utils/secure_log.dart';

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
  UnifiedCacheManager();

  UnifiedCacheManager._();

  static UnifiedCacheManager get instance => ServiceLocator.get<UnifiedCacheManager>();
  
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
    SecureLog.i('UnifiedCacheManager: Initializing...');
    await _loadCacheTimestamps();
    SecureLog.i('UnifiedCacheManager: Initialized');
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
      SecureLog.w('UnifiedCacheManager: Cache expired for ${type.name} (age: ${now.difference(timestamp)})');
    }
    
    return isValid;
  }
  
  /// به‌روزرسانی timestamp cache
  Future<void> updateCacheTimestamp(CacheType type, String userId) async {
    final key = _getCacheKey(type, userId);
    _cacheTimestamps[key] = DateTime.now();
    await _persistCacheTimestamp(key);
    
    SecureLog.i('UnifiedCacheManager: Updated timestamp for ${type.name}');
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
      
      SecureLog.i('UnifiedCacheManager: Invalidated cache for ${type.name}');
      
    } finally {
      _releaseLock(type, userId);
    }
  }
  
  /// invalidate کردن تمام cache های کاربر
  Future<void> invalidateUserCaches(String userId) async {
    SecureLog.i('UnifiedCacheManager: Invalidating all caches');
    
    for (final type in CacheType.values) {
      await invalidateCache(type, userId);
    }
    
    notifyListeners();
    SecureLog.i('UnifiedCacheManager: Invalidated all caches');
  }
  
  /// invalidate کردن تمام cache ها
  Future<void> invalidateAllCaches() async {
    SecureLog.i('UnifiedCacheManager: Invalidating ALL caches');
    
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
    SecureLog.i('UnifiedCacheManager: Invalidated ALL caches');
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
      
      SecureLog.i('UnifiedCacheManager: Cached data for ${type.name}');
      
    } finally {
      _releaseLock(type, userId);
    }
  }
  
  /// دریافت داده از cache
  Future<T?> getCache<T>(CacheType type, String userId) async {
    final key = _getCacheKey(type, userId);
    
    if (!isCacheValid(type, userId)) {
      SecureLog.w('UnifiedCacheManager: Cache invalid for ${type.name}');
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
      SecureLog.e('UnifiedCacheManager: Error reading cache for ${type.name}', error: e);
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
    SecureLog.i('UnifiedCacheManager: Synchronizing caches');
    
    try {
      // بررسی consistency بین cache های مختلف
      final tokensCacheValid = isCacheValid(CacheType.tokens, userId);
      final balancesCacheValid = isCacheValid(CacheType.balances, userId);
      
      // اگر token cache معتبر نیست اما balance cache معتبر است، balance را invalidate کن
      if (!tokensCacheValid && balancesCacheValid) {
        await invalidateCache(CacheType.balances, userId);
        SecureLog.i('UnifiedCacheManager: Invalidated balances due to token cache expiry');
      }
      
      // SecureStorage consistency check removed — SecureStorage is no longer
      // authoritative for token state (TokenPreferences is the single source of truth).
      // Previously _synchronizeWithSecureStorage compared against stale SecureStorage
      // data, causing false cache invalidations.
      
      SecureLog.i('UnifiedCacheManager: Cache synchronization completed');
      
    } catch (e) {
      SecureLog.e('UnifiedCacheManager: Error during cache synchronization', error: e);
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
          SecureLog.e('UnifiedCacheManager: Error in invalidation listener', error: e);
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
      
      SecureLog.i('UnifiedCacheManager: Loaded ${_cacheTimestamps.length} cache timestamps');
      
    } catch (e) {
      SecureLog.e('UnifiedCacheManager: Error loading cache timestamps', error: e);
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
      SecureLog.e('UnifiedCacheManager: Error persisting timestamp', error: e);
    }
  }
  
  bool _setsEqual<T>(Set<T> set1, Set<T> set2) {
    if (set1.length != set2.length) return false;
    return set1.every(set2.contains);
  }
  
  /// Debug method
  void debugCacheState() {
    SecureLog.i('=== UnifiedCacheManager Debug ===');
    SecureLog.i('Cache timestamps: ${_cacheTimestamps.length}');
    SecureLog.i('Invalidation listeners: ${_invalidationListeners.length}');
    SecureLog.i('Active locks: ${_cacheLocks.length}');
    
    for (final entry in _cacheTimestamps.entries) {
      final age = DateTime.now().difference(entry.value);
      SecureLog.i('  ${entry.key}: ${entry.value} (age: $age)');
    }
    SecureLog.i('===============================');
  }
}
