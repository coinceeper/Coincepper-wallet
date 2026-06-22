import 'dart:io';
import '../services/platform_storage_manager.dart';

/// کلاس یکپارچه مدیریت تنظیمات توکن‌ها برای iOS و Android
class UnifiedTokenPreferences {
  final String userId;
  static const String _tokenOrderKey = 'token_order';
  static const String _tokenStatePrefix = 'token_state_';
  
  // Cache for token states - per user instance
  final Map<String, bool> _tokenStateCache = {};
  bool _cacheInitialized = false;
  
  late final PlatformStorageManager _platformStorage;

  UnifiedTokenPreferences({required this.userId}) {
    _platformStorage = PlatformStorageManager.instance;
  }
  
  /// Initialize the TokenPreferences with platform-specific optimizations
  Future<void> initialize() async {
    if (!_cacheInitialized) {
      await _initializeCache();
      _cacheInitialized = true;
    }
  }
  
  /// Initialize cache with platform-specific data recovery
  Future<void> _initializeCache() async {
    try {
      print('🔄 UnifiedTokenPreferences: Initializing cache for user $userId...');
      
      // Clear existing cache
      _tokenStateCache.clear();
      
      // Load default tokens to check their states
      final defaultTokens = ['BTC', 'ETH', 'TRX', 'BNB', 'ADA', 'DOT', 'SOL', 'DOGE'];
      final blockchains = ['Bitcoin', 'Ethereum', 'Tron', 'BinanceSmartChain', 'Cardano', 'Polkadot', 'Solana', 'Dogecoin'];
      
      int foundStates = 0;
      for (int i = 0; i < defaultTokens.length; i++) {
        final symbol = defaultTokens[i];
        final blockchain = blockchains[i % blockchains.length];
        final key = _getTokenKey(symbol, blockchain, null);
        
        // استفاده از platform storage برای دریافت داده
        final value = await _platformStorage.getData(key);
        if (value != null) {
          final boolValue = value.toLowerCase() == 'true';
          _tokenStateCache[key] = boolValue;
          foundStates++;
        }
      }
      
      print('🔄 UnifiedTokenPreferences: Loaded $foundStates token states for user $userId');
      
      // Initialize default tokens if no tokens are configured
      if (_tokenStateCache.isEmpty) {
        await _initializeDefaultTokens();
      }
      
      // Cleanup old inconsistent data
      await _cleanupInconsistentData();
      
    } catch (e) {
      print('❌ UnifiedTokenPreferences: Error initializing cache for user $userId: $e');
      await _initializeDefaultTokens();
    }
  }

  /// Save token state with platform-specific strategy
  Future<void> saveTokenState(String symbol, String blockchainName, String? smartContractAddress, bool isEnabled) async {
    try {
      final key = _getTokenKey(symbol, blockchainName, smartContractAddress);
      
      // Save with platform-specific strategy
      await _platformStorage.saveData(key, isEnabled.toString(), isCritical: false);
      
      // Update cache
      _tokenStateCache[key] = isEnabled;
      
      print('💾 Token state saved: $symbol ($blockchainName) = $isEnabled (platform: ${Platform.operatingSystem})');
    } catch (e) {
      print('❌ Error saving token state: $e');
    }
  }

  /// Get token state with platform-specific recovery
  Future<bool> getTokenState(String symbol, String blockchainName, String? smartContractAddress) async {
    final key = _getTokenKey(symbol, blockchainName, smartContractAddress);
    
    try {
      // First check cache
      if (_tokenStateCache.containsKey(key)) {
        return _tokenStateCache[key]!;
      }
      
      // Load from platform storage
      final value = await _platformStorage.getData(key);
      if (value != null) {
        final boolValue = value.toLowerCase() == 'true';
        _tokenStateCache[key] = boolValue;
        return boolValue;
      }
      
      // Default to enabled for main tokens
      final defaultEnabled = _isMainToken(symbol);
      _tokenStateCache[key] = defaultEnabled;
      
      // Save default state
      await saveTokenState(symbol, blockchainName, smartContractAddress, defaultEnabled);
      
      return defaultEnabled;
    } catch (e) {
      print('❌ Error getting token state: $e');
      return _isMainToken(symbol);
    }
  }

  /// Get token state synchronously (for UI performance)
  bool getTokenStateSync(String symbol, String blockchainName, String? smartContractAddress) {
    final key = _getTokenKey(symbol, blockchainName, smartContractAddress);
    
    if (_tokenStateCache.containsKey(key)) {
      return _tokenStateCache[key]!;
    }
    
    // Default for unknown tokens
    return _isMainToken(symbol);
  }

  /// Save token order with platform-specific strategy
  Future<void> saveTokenOrder(List<String> tokenSymbols) async {
    try {
      final key = '${_tokenOrderKey}_$userId';
      final value = tokenSymbols.join(',');
      
      await _platformStorage.saveData(key, value, isCritical: false);
      
      print('💾 Token order saved for user $userId: ${tokenSymbols.length} tokens');
    } catch (e) {
      print('❌ Error saving token order: $e');
    }
  }

  /// Get token order with platform-specific recovery
  Future<List<String>> getTokenOrder() async {
    try {
      final key = '${_tokenOrderKey}_$userId';
      final value = await _platformStorage.getData(key);
      
      if (value != null && value.isNotEmpty) {
        return value.split(',').where((s) => s.isNotEmpty).toList();
      }
      
      // Return default order
      return ['BTC', 'ETH', 'TRX', 'BNB', 'ADA', 'DOT', 'SOL', 'DOGE'];
    } catch (e) {
      print('❌ Error getting token order: $e');
      return ['BTC', 'ETH', 'TRX', 'BNB', 'ADA', 'DOT', 'SOL', 'DOGE'];
    }
  }

  /// Initialize default tokens with platform consistency
  Future<void> _initializeDefaultTokens() async {
    try {
      print('🔄 Initializing default tokens for user $userId...');
      
      final defaultTokens = [
        {'symbol': 'BTC', 'blockchain': 'Bitcoin', 'enabled': true},
        {'symbol': 'ETH', 'blockchain': 'Ethereum', 'enabled': true},
        {'symbol': 'TRX', 'blockchain': 'Tron', 'enabled': true},
        {'symbol': 'BNB', 'blockchain': 'BinanceSmartChain', 'enabled': true},
        {'symbol': 'ADA', 'blockchain': 'Cardano', 'enabled': false},
        {'symbol': 'DOT', 'blockchain': 'Polkadot', 'enabled': false},
        {'symbol': 'SOL', 'blockchain': 'Solana', 'enabled': false},
        {'symbol': 'DOGE', 'blockchain': 'Dogecoin', 'enabled': false},
      ];
      
      for (final token in defaultTokens) {
        await saveTokenState(
          token['symbol'] as String,
          token['blockchain'] as String,
          null,
          token['enabled'] as bool,
        );
      }
      
      print('✅ Default tokens initialized for user $userId');
    } catch (e) {
      print('❌ Error initializing default tokens: $e');
    }
  }

  /// Cleanup inconsistent data between platforms
  Future<void> _cleanupInconsistentData() async {
    try {
      if (Platform.isIOS) {
        // iOS: Check for inconsistencies and fix them
        await _platformStorage.synchronizeStorages();
        print('🧹 iOS: Synchronized storage inconsistencies');
      }
      
      // Cleanup old data
      await _platformStorage.cleanupOldData(maxAgeInDays: 30);
    } catch (e) {
      print('❌ Error during cleanup: $e');
    }
  }

  /// Check data integrity across platforms
  Future<Map<String, dynamic>> checkDataIntegrity() async {
    try {
      final mainTokens = ['BTC', 'ETH', 'TRX'];
      final results = <String, dynamic>{};
      
      for (final symbol in mainTokens) {
        final key = _getTokenKey(symbol, 'Bitcoin', null);
        final integrity = await _platformStorage.checkDataIntegrity(key);
        results[symbol] = integrity;
      }
      
      return {
        'user_id': userId,
        'platform': Platform.operatingSystem,
        'cache_size': _tokenStateCache.length,
        'integrity_checks': results,
      };
    } catch (e) {
      print('❌ Error checking data integrity: $e');
      return {'error': e.toString()};
    }
  }

  /// Clear all token data for this user
  Future<void> clearAllTokenData() async {
    try {
      // Clear from platform storage
      final defaultTokens = ['BTC', 'ETH', 'TRX', 'BNB', 'ADA', 'DOT', 'SOL', 'DOGE'];
      final blockchains = ['Bitcoin', 'Ethereum', 'Tron', 'BinanceSmartChain', 'Cardano', 'Polkadot', 'Solana', 'Dogecoin'];
      
      for (int i = 0; i < defaultTokens.length; i++) {
        final key = _getTokenKey(defaultTokens[i], blockchains[i % blockchains.length], null);
        await _platformStorage.deleteData(key);
      }
      
      // Clear token order
      await _platformStorage.deleteData('${_tokenOrderKey}_$userId');
      
      // Clear cache
      _tokenStateCache.clear();
      
      print('🗑️ All token data cleared for user $userId');
    } catch (e) {
      print('❌ Error clearing token data: $e');
    }
  }

  /// Generate token key
  String _getTokenKey(String symbol, String blockchainName, String? smartContractAddress) {
    if (smartContractAddress != null && smartContractAddress.isNotEmpty) {
      return '$_tokenStatePrefix${symbol}_${blockchainName}_${smartContractAddress}_$userId';
    }
    return '$_tokenStatePrefix${symbol}_${blockchainName}_$userId';
  }

  /// Check if a token is a main token (enabled by default)
  bool _isMainToken(String symbol) {
    final mainTokens = ['BTC', 'ETH', 'TRX', 'BNB'];
    return mainTokens.contains(symbol.toUpperCase());
  }
} 