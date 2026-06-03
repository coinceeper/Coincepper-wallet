import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// ⚡ ScreenCacheManager
/// 
/// مدیریت cache برای صفحات مختلف اپلیکیشن
/// اطلاعات receive addresses، token lists، و سایر داده‌ها را cache می‌کند
class ScreenCacheManager {
  static final ScreenCacheManager _instance = ScreenCacheManager._internal();
  static ScreenCacheManager get instance => _instance;
  ScreenCacheManager._internal();

  // Cache keys
  static const String _receiveAddressesKey = 'cached_receive_addresses';
  static const String _tokenListKey = 'cached_token_list';
  static const String _popularTokensKey = 'cached_popular_tokens';
  static const String _userTokensKey = 'cached_user_tokens';
  static const String _networkListKey = 'cached_network_list';
  static const String _gasFeeKey = 'cached_gas_fees';
  
  // Cache expiry times (in minutes)
  static const int _receiveAddressCacheMinutes = 60; // 1 hour
  static const int _tokenListCacheMinutes = 30; // 30 minutes
  static const int _popularTokensCacheMinutes = 15; // 15 minutes
  static const int _gasFeesCacheMinutes = 5; // 5 minutes

  // In-memory cache for faster access
  final Map<String, dynamic> _memoryCache = {};
  final Map<String, DateTime> _memoryCacheTimestamps = {};

  /// ⚡ Cache receive addresses برای wallet
  Future<void> cacheReceiveAddresses(
    String userId,
    String walletName,
    Map<String, String> addresses,
  ) async {
    try {
      final cacheData = {
        'userId': userId,
        'walletName': walletName,
        'addresses': addresses,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final prefs = await SharedPreferences.getInstance();
      final key = '${_receiveAddressesKey}_${userId}_$walletName';
      await prefs.setString(key, jsonEncode(cacheData));

      // Store in memory cache too
      _memoryCache[key] = cacheData;
      _memoryCacheTimestamps[key] = DateTime.now();

      print('✅ ScreenCache: Receive addresses cached for $walletName');
    } catch (e) {
      print('❌ ScreenCache: Error caching receive addresses: $e');
    }
  }

  /// ⚡ دریافت cached receive addresses
  Future<Map<String, String>?> getCachedReceiveAddresses(
    String userId,
    String walletName,
  ) async {
    try {
      final key = '${_receiveAddressesKey}_${userId}_$walletName';

      // Check memory cache first
      if (_memoryCache.containsKey(key)) {
        final timestamp = _memoryCacheTimestamps[key]!;
        if (DateTime.now().difference(timestamp).inMinutes < _receiveAddressCacheMinutes) {
          print('⚡ ScreenCache: Using memory cache for receive addresses');
          final data = _memoryCache[key] as Map<String, dynamic>;
          return Map<String, String>.from(data['addresses']);
        }
      }

      // Check persistent cache
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(key);
      
      if (cachedJson != null) {
        final cacheData = jsonDecode(cachedJson) as Map<String, dynamic>;
        final timestamp = cacheData['timestamp'] as int;
        final ageMinutes = (DateTime.now().millisecondsSinceEpoch - timestamp) / (1000 * 60);

        if (ageMinutes < _receiveAddressCacheMinutes) {
          print('✅ ScreenCache: Using cached receive addresses (${ageMinutes.toStringAsFixed(1)} min old)');
          
          // Update memory cache
          _memoryCache[key] = cacheData;
          _memoryCacheTimestamps[key] = DateTime.now();
          
          return Map<String, String>.from(cacheData['addresses']);
        } else {
          print('⚠️ ScreenCache: Receive addresses cache expired');
        }
      }

      return null;
    } catch (e) {
      print('❌ ScreenCache: Error getting cached receive addresses: $e');
      return null;
    }
  }

  /// ⚡ Cache token list برای add token screen
  Future<void> cacheTokenList(List<Map<String, dynamic>> tokens) async {
    try {
      final cacheData = {
        'tokens': tokens,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'count': tokens.length,
      };

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenListKey, jsonEncode(cacheData));

      // Memory cache
      _memoryCache[_tokenListKey] = cacheData;
      _memoryCacheTimestamps[_tokenListKey] = DateTime.now();

      print('✅ ScreenCache: Token list cached (${tokens.length} tokens)');
    } catch (e) {
      print('❌ ScreenCache: Error caching token list: $e');
    }
  }

  /// ⚡ دریافت cached token list
  Future<List<Map<String, dynamic>>?> getCachedTokenList() async {
    try {
      // Check memory cache first
      if (_memoryCache.containsKey(_tokenListKey)) {
        final timestamp = _memoryCacheTimestamps[_tokenListKey]!;
        if (DateTime.now().difference(timestamp).inMinutes < _tokenListCacheMinutes) {
          print('⚡ ScreenCache: Using memory cache for token list');
          final data = _memoryCache[_tokenListKey] as Map<String, dynamic>;
          return List<Map<String, dynamic>>.from(data['tokens']);
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_tokenListKey);
      
      if (cachedJson != null) {
        final cacheData = jsonDecode(cachedJson) as Map<String, dynamic>;
        final timestamp = cacheData['timestamp'] as int;
        final ageMinutes = (DateTime.now().millisecondsSinceEpoch - timestamp) / (1000 * 60);

        if (ageMinutes < _tokenListCacheMinutes) {
          print('✅ ScreenCache: Using cached token list (${ageMinutes.toStringAsFixed(1)} min old)');
          
          // Update memory cache
          _memoryCache[_tokenListKey] = cacheData;
          _memoryCacheTimestamps[_tokenListKey] = DateTime.now();
          
          return List<Map<String, dynamic>>.from(cacheData['tokens']);
        }
      }

      return null;
    } catch (e) {
      print('❌ ScreenCache: Error getting cached token list: $e');
      return null;
    }
  }

  /// ⚡ Cache popular tokens
  Future<void> cachePopularTokens(List<Map<String, dynamic>> popularTokens) async {
    try {
      final cacheData = {
        'tokens': popularTokens,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_popularTokensKey, jsonEncode(cacheData));

      // Memory cache
      _memoryCache[_popularTokensKey] = cacheData;
      _memoryCacheTimestamps[_popularTokensKey] = DateTime.now();

      print('✅ ScreenCache: Popular tokens cached (${popularTokens.length} tokens)');
    } catch (e) {
      print('❌ ScreenCache: Error caching popular tokens: $e');
    }
  }

  /// ⚡ دریافت cached popular tokens
  Future<List<Map<String, dynamic>>?> getCachedPopularTokens() async {
    try {
      // Check memory cache first
      if (_memoryCache.containsKey(_popularTokensKey)) {
        final timestamp = _memoryCacheTimestamps[_popularTokensKey]!;
        if (DateTime.now().difference(timestamp).inMinutes < _popularTokensCacheMinutes) {
          print('⚡ ScreenCache: Using memory cache for popular tokens');
          final data = _memoryCache[_popularTokensKey] as Map<String, dynamic>;
          return List<Map<String, dynamic>>.from(data['tokens']);
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_popularTokensKey);
      
      if (cachedJson != null) {
        final cacheData = jsonDecode(cachedJson) as Map<String, dynamic>;
        final timestamp = cacheData['timestamp'] as int;
        final ageMinutes = (DateTime.now().millisecondsSinceEpoch - timestamp) / (1000 * 60);

        if (ageMinutes < _popularTokensCacheMinutes) {
          print('✅ ScreenCache: Using cached popular tokens');
          
          // Update memory cache
          _memoryCache[_popularTokensKey] = cacheData;
          _memoryCacheTimestamps[_popularTokensKey] = DateTime.now();
          
          return List<Map<String, dynamic>>.from(cacheData['tokens']);
        }
      }

      return null;
    } catch (e) {
      print('❌ ScreenCache: Error getting cached popular tokens: $e');
      return null;
    }
  }

  /// ⚡ Cache user's custom tokens
  Future<void> cacheUserTokens(
    String userId,
    List<Map<String, dynamic>> userTokens,
  ) async {
    try {
      final cacheData = {
        'userId': userId,
        'tokens': userTokens,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final prefs = await SharedPreferences.getInstance();
      final key = '${_userTokensKey}_$userId';
      await prefs.setString(key, jsonEncode(cacheData));

      // Memory cache
      _memoryCache[key] = cacheData;
      _memoryCacheTimestamps[key] = DateTime.now();

      print('✅ ScreenCache: User tokens cached for $userId');
    } catch (e) {
      print('❌ ScreenCache: Error caching user tokens: $e');
    }
  }

  /// ⚡ دریافت cached user tokens
  Future<List<Map<String, dynamic>>?> getCachedUserTokens(String userId) async {
    try {
      final key = '${_userTokensKey}_$userId';

      // Check memory cache first
      if (_memoryCache.containsKey(key)) {
        final timestamp = _memoryCacheTimestamps[key]!;
        if (DateTime.now().difference(timestamp).inMinutes < _tokenListCacheMinutes) {
          print('⚡ ScreenCache: Using memory cache for user tokens');
          final data = _memoryCache[key] as Map<String, dynamic>;
          return List<Map<String, dynamic>>.from(data['tokens']);
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(key);
      
      if (cachedJson != null) {
        final cacheData = jsonDecode(cachedJson) as Map<String, dynamic>;
        final timestamp = cacheData['timestamp'] as int;
        final ageMinutes = (DateTime.now().millisecondsSinceEpoch - timestamp) / (1000 * 60);

        if (ageMinutes < _tokenListCacheMinutes) {
          print('✅ ScreenCache: Using cached user tokens');
          
          // Update memory cache
          _memoryCache[key] = cacheData;
          _memoryCacheTimestamps[key] = DateTime.now();
          
          return List<Map<String, dynamic>>.from(cacheData['tokens']);
        }
      }

      return null;
    } catch (e) {
      print('❌ ScreenCache: Error getting cached user tokens: $e');
      return null;
    }
  }

  /// ⚡ Cache network list
  Future<void> cacheNetworkList(List<Map<String, dynamic>> networks) async {
    try {
      final cacheData = {
        'networks': networks,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_networkListKey, jsonEncode(cacheData));

      // Memory cache
      _memoryCache[_networkListKey] = cacheData;
      _memoryCacheTimestamps[_networkListKey] = DateTime.now();

      print('✅ ScreenCache: Network list cached (${networks.length} networks)');
    } catch (e) {
      print('❌ ScreenCache: Error caching network list: $e');
    }
  }

  /// ⚡ دریافت cached network list
  Future<List<Map<String, dynamic>>?> getCachedNetworkList() async {
    try {
      // Check memory cache first
      if (_memoryCache.containsKey(_networkListKey)) {
        final timestamp = _memoryCacheTimestamps[_networkListKey]!;
        if (DateTime.now().difference(timestamp).inMinutes < _tokenListCacheMinutes) {
          print('⚡ ScreenCache: Using memory cache for network list');
          final data = _memoryCache[_networkListKey] as Map<String, dynamic>;
          return List<Map<String, dynamic>>.from(data['networks']);
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_networkListKey);
      
      if (cachedJson != null) {
        final cacheData = jsonDecode(cachedJson) as Map<String, dynamic>;
        final timestamp = cacheData['timestamp'] as int;
        final ageMinutes = (DateTime.now().millisecondsSinceEpoch - timestamp) / (1000 * 60);

        if (ageMinutes < _tokenListCacheMinutes) {
          print('✅ ScreenCache: Using cached network list');
          
          // Update memory cache
          _memoryCache[_networkListKey] = cacheData;
          _memoryCacheTimestamps[_networkListKey] = DateTime.now();
          
          return List<Map<String, dynamic>>.from(cacheData['networks']);
        }
      }

      return null;
    } catch (e) {
      print('❌ ScreenCache: Error getting cached network list: $e');
      return null;
    }
  }

  /// ⚡ Cache gas fees
  Future<void> cacheGasFees(Map<String, dynamic> gasFees) async {
    try {
      final cacheData = {
        'gasFees': gasFees,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_gasFeeKey, jsonEncode(cacheData));

      // Memory cache
      _memoryCache[_gasFeeKey] = cacheData;
      _memoryCacheTimestamps[_gasFeeKey] = DateTime.now();

      print('✅ ScreenCache: Gas fees cached');
    } catch (e) {
      print('❌ ScreenCache: Error caching gas fees: $e');
    }
  }

  /// ⚡ دریافت cached gas fees
  Future<Map<String, dynamic>?> getCachedGasFees() async {
    try {
      // Check memory cache first
      if (_memoryCache.containsKey(_gasFeeKey)) {
        final timestamp = _memoryCacheTimestamps[_gasFeeKey]!;
        if (DateTime.now().difference(timestamp).inMinutes < _gasFeesCacheMinutes) {
          print('⚡ ScreenCache: Using memory cache for gas fees');
          final data = _memoryCache[_gasFeeKey] as Map<String, dynamic>;
          return Map<String, dynamic>.from(data['gasFees']);
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_gasFeeKey);
      
      if (cachedJson != null) {
        final cacheData = jsonDecode(cachedJson) as Map<String, dynamic>;
        final timestamp = cacheData['timestamp'] as int;
        final ageMinutes = (DateTime.now().millisecondsSinceEpoch - timestamp) / (1000 * 60);

        if (ageMinutes < _gasFeesCacheMinutes) {
          print('✅ ScreenCache: Using cached gas fees');
          
          // Update memory cache
          _memoryCache[_gasFeeKey] = cacheData;
          _memoryCacheTimestamps[_gasFeeKey] = DateTime.now();
          
          return Map<String, dynamic>.from(cacheData['gasFees']);
        }
      }

      return null;
    } catch (e) {
      print('❌ ScreenCache: Error getting cached gas fees: $e');
      return null;
    }
  }

  /// ⚡ Cache با expiry time سفارشی
  Future<void> cacheWithCustomExpiry(
    String key,
    dynamic data,
    int expiryMinutes,
  ) async {
    try {
      final cacheData = {
        'data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'expiryMinutes': expiryMinutes,
      };

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_$key', jsonEncode(cacheData));

      // Memory cache
      _memoryCache['custom_$key'] = cacheData;
      _memoryCacheTimestamps['custom_$key'] = DateTime.now();

      print('✅ ScreenCache: Custom data cached with key: $key');
    } catch (e) {
      print('❌ ScreenCache: Error caching custom data: $e');
    }
  }

  /// ⚡ دریافت cache با expiry سفارشی
  Future<T?> getCachedWithCustomExpiry<T>(String key) async {
    try {
      final fullKey = 'custom_$key';

      // Check memory cache first
      if (_memoryCache.containsKey(fullKey)) {
        final cacheData = _memoryCache[fullKey] as Map<String, dynamic>;
        final timestamp = _memoryCacheTimestamps[fullKey]!;
        final expiryMinutes = cacheData['expiryMinutes'] as int;
        
        if (DateTime.now().difference(timestamp).inMinutes < expiryMinutes) {
          print('⚡ ScreenCache: Using memory cache for custom key: $key');
          return cacheData['data'] as T;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(fullKey);
      
      if (cachedJson != null) {
        final cacheData = jsonDecode(cachedJson) as Map<String, dynamic>;
        final timestamp = cacheData['timestamp'] as int;
        final expiryMinutes = cacheData['expiryMinutes'] as int;
        final ageMinutes = (DateTime.now().millisecondsSinceEpoch - timestamp) / (1000 * 60);

        if (ageMinutes < expiryMinutes) {
          print('✅ ScreenCache: Using cached custom data: $key');
          
          // Update memory cache
          _memoryCache[fullKey] = cacheData;
          _memoryCacheTimestamps[fullKey] = DateTime.now();
          
          return cacheData['data'] as T;
        }
      }

      return null;
    } catch (e) {
      print('❌ ScreenCache: Error getting cached custom data: $e');
      return null;
    }
  }

  /// ⚡ Preload critical data برای سرعت بیشتر
  Future<void> preloadCriticalData(String userId, String walletName) async {
    print('🚀 ScreenCache: Preloading critical data...');
    
    try {
      // Preload در background
      Future.microtask(() async {
        // Preload receive addresses
        await getCachedReceiveAddresses(userId, walletName);
        
        // Preload token list
        await getCachedTokenList();
        
        // Preload popular tokens
        await getCachedPopularTokens();
        
        // Preload gas fees
        await getCachedGasFees();
        
        print('✅ ScreenCache: Critical data preloaded');
      });
    } catch (e) {
      print('❌ ScreenCache: Error preloading data: $e');
    }
  }

  /// ⚡ بهینه‌سازی cache برای memory
  void optimizeMemoryCache() {
    try {
      final now = DateTime.now();
      final keysToRemove = <String>[];

      // حذف cache های منقضی شده از memory
      _memoryCacheTimestamps.forEach((key, timestamp) {
        if (now.difference(timestamp).inMinutes > 60) { // 1 hour max in memory
          keysToRemove.add(key);
        }
      });

      for (final key in keysToRemove) {
        _memoryCache.remove(key);
        _memoryCacheTimestamps.remove(key);
      }

      if (keysToRemove.isNotEmpty) {
        print('🧹 ScreenCache: Cleaned ${keysToRemove.length} expired memory cache entries');
      }
    } catch (e) {
      print('❌ ScreenCache: Error optimizing memory cache: $e');
    }
  }

  /// ⚡ پاک کردن تمام cache
  Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      final cacheKeys = keys.where((key) => 
        key.startsWith('cached_') || key.startsWith('custom_')
      ).toList();
      
      for (final key in cacheKeys) {
        await prefs.remove(key);
      }

      // Clear memory cache
      _memoryCache.clear();
      _memoryCacheTimestamps.clear();

      print('✅ ScreenCache: All cache cleared');
    } catch (e) {
      print('❌ ScreenCache: Error clearing cache: $e');
    }
  }

  /// ⚡ پاک کردن cache منقضی شده
  Future<void> clearExpiredCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final now = DateTime.now().millisecondsSinceEpoch;
      
      final cacheKeys = keys.where((key) => 
        key.startsWith('cached_') || key.startsWith('custom_')
      ).toList();
      
      int removedCount = 0;
      
      for (final key in cacheKeys) {
        final cachedJson = prefs.getString(key);
        if (cachedJson != null) {
          try {
            final cacheData = jsonDecode(cachedJson) as Map<String, dynamic>;
            final timestamp = cacheData['timestamp'] as int;
            final ageMinutes = (now - timestamp) / (1000 * 60);
            
            // Default expiry 2 hours
            final maxAge = cacheData['expiryMinutes'] as int? ?? 120;
            
            if (ageMinutes > maxAge) {
              await prefs.remove(key);
              removedCount++;
            }
          } catch (e) {
            // Invalid cache data, remove it
            await prefs.remove(key);
            removedCount++;
          }
        }
      }

      if (removedCount > 0) {
        print('🧹 ScreenCache: Removed $removedCount expired cache entries');
      }
    } catch (e) {
      print('❌ ScreenCache: Error clearing expired cache: $e');
    }
  }

  /// 📊 دریافت آمار cache
  Map<String, dynamic> getCacheStats() {
    return {
      'memory_cache_size': _memoryCache.length,
      'memory_cache_keys': _memoryCache.keys.toList(),
      'oldest_entry': _memoryCacheTimestamps.values.isNotEmpty 
        ? _memoryCacheTimestamps.values.reduce((a, b) => a.isBefore(b) ? a : b).toIso8601String()
        : null,
      'newest_entry': _memoryCacheTimestamps.values.isNotEmpty
        ? _memoryCacheTimestamps.values.reduce((a, b) => a.isAfter(b) ? a : b).toIso8601String()
        : null,
    };
  }

  /// 🧹 Dispose resources
  void dispose() {
    _memoryCache.clear();
    _memoryCacheTimestamps.clear();
  }
}
