import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../services/secure_storage.dart';
import '../services/platform_storage_manager.dart';

/// کلاس مدیریت تنظیمات توکن‌ها
class TokenPreferences {
  final String userId;
  static const String _tokenOrderKey = 'token_order';
  static const String _tokenStatePrefix = 'token_state_';
  
  // Cache for token states to support sync operations - per user instance
  final Map<String, bool> _tokenStateCache = {};
  bool _cacheInitialized = false;

  TokenPreferences({required this.userId});
  
  /// Initialize the TokenPreferences
  Future<void> initialize() async {
    if (!_cacheInitialized) {
      await _initializeCache();
      _cacheInitialized = true;
    }
  }
  
  /// Initialize cache from SharedPreferences
  Future<void> _initializeCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      // Clear existing cache
      _tokenStateCache.clear();
      
      // Only load keys for this user
      for (final key in keys) {
        if (key.startsWith(_tokenStatePrefix) && key.contains(userId)) {
          final value = prefs.getBool(key);
          if (value != null) {
            _tokenStateCache[key] = value;
          }
        }
      }
      
      print('🔄 TokenPreferences: Initialized cache for user $userId with ${_tokenStateCache.length} token states from SharedPreferences');
      
      // iOS: Also try to load from SecureStorage and merge
      if (Platform.isIOS) {
        await _loadFromSecureStorageOnIOS(prefs);
      }
      
      // Initialize default tokens if no tokens are configured for this user
      if (_tokenStateCache.isEmpty) {
        await _initializeDefaultTokens();
      }
    } catch (e) {
      print('❌ TokenPreferences: Error initializing cache for user $userId: $e');
      // If initialization fails, use default tokens
      await _initializeDefaultTokens();
    }
  }

  /// iOS-specific: Load ALL token states from SecureStorage and merge with SharedPreferences
  Future<void> _loadFromSecureStorageOnIOS(SharedPreferences prefs) async {
    try {
      print('🍎 TokenPreferences: Starting comprehensive iOS SecureStorage recovery for user $userId...');
      
      // استراتژی جامع: بازیابی همه توکن‌های ممکن از SecureStorage
      // لیست کامل توکن‌هایی که ممکنه کاربر فعال کرده باشه
      final allPossibleTokens = {
        'BTC': {'blockchain': 'Bitcoin', 'contract': null},
        'ETH': {'blockchain': 'Ethereum', 'contract': null},
        'TRX': {'blockchain': 'Tron', 'contract': null},
        'BNB': {'blockchain': 'Binance', 'contract': null},
        'USDT': {'blockchain': 'Ethereum', 'contract': '0xdAC17F958D2ee523a2206206994597C13D831ec7'},
        'USDT': {'blockchain': 'Tron', 'contract': 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t'},
        'USDT': {'blockchain': 'Binance', 'contract': '0x55d398326f99059fF775485246999027B3197955'},
        'USDC': {'blockchain': 'Ethereum', 'contract': '0xA0b86a33E6441b15bCC36C0d8a5c7B5e8b1b0e1f'},
        'USDC': {'blockchain': 'Binance', 'contract': '0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d'},
        'SHIB': {'blockchain': 'Ethereum', 'contract': '0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE'},
        'ADA': {'blockchain': 'Cardano', 'contract': null},
        'DOT': {'blockchain': 'Polkadot', 'contract': null},
        'SOL': {'blockchain': 'Solana', 'contract': null},
        'AVAX': {'blockchain': 'Avalanche', 'contract': null},
        'MATIC': {'blockchain': 'Polygon', 'contract': null},
        'XRP': {'blockchain': 'XRP', 'contract': null},
        'LINK': {'blockchain': 'Ethereum', 'contract': '0x514910771AF9Ca656af840dff83E8264EcF986CA'},
        'UNI': {'blockchain': 'Ethereum', 'contract': '0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984'},
        'LTC': {'blockchain': 'Litecoin', 'contract': null},
        'DOGE': {'blockchain': 'Dogecoin', 'contract': null},
        'NCC': {'blockchain': 'Netcoincapital', 'contract': null},
      };
      
      int recoveredCount = 0;
      
      // بازیابی همه توکن‌های ممکن از SecureStorage
      for (final entry in allPossibleTokens.entries) {
        final symbol = entry.key;
        final tokenInfo = entry.value;
        final blockchain = tokenInfo['blockchain'] as String;
        final contract = tokenInfo['contract'];
        
        final key = _getTokenKey(symbol, blockchain, contract);
        
        // فقط اگر در SharedPreferences نداریم، از SecureStorage بگیر
        if (!_tokenStateCache.containsKey(key)) {
          try {
            final secureValue = await SecureStorage.instance.getSecureData(key);
            if (secureValue != null) {
              final boolValue = secureValue.toLowerCase() == 'true';
              
              // فقط اگر true باشه، اضافه کن (توکن‌های غیرفعال رو نادیده بگیر)
              if (boolValue) {
                _tokenStateCache[key] = boolValue;
                
                // همگام‌سازی با SharedPreferences برای دفعات بعد
                await prefs.setBool(key, boolValue);
                
                recoveredCount++;
                print('🍎 TokenPreferences: Recovered enabled token from SecureStorage: $symbol ($blockchain) = $boolValue');
              }
            }
          } catch (e) {
            // اگر خطا داشت، ادامه بده (ممکنه توکن موجود نباشه)
            print('🔍 TokenPreferences: Token $symbol ($blockchain) not found in SecureStorage (normal)');
          }
        }
      }
      
      // همچنین بررسی کن که آیا کلیدهای user-specific دیگری هم هست
      await _recoverCustomUserTokens(prefs);
      
      print('🍎 TokenPreferences: iOS SecureStorage recovery completed!');
      print('🍎 TokenPreferences: Recovered $recoveredCount enabled tokens from SecureStorage');
      print('🍎 TokenPreferences: Total cache size: ${_tokenStateCache.length}');
      
    } catch (e) {
      print('❌ TokenPreferences: Error in comprehensive iOS SecureStorage recovery: $e');
    }
  }
  
  /// بازیابی توکن‌های سفارشی کاربر از SecureStorage  
  Future<void> _recoverCustomUserTokens(SharedPreferences prefs) async {
    try {
      // استفاده از pattern matching برای یافتن کلیدهای مربوط به این کاربر
      final userKeyPatterns = [
        '$_tokenStatePrefix${userId}_',
        '_${userId}_',
        '${userId}_'
      ];
      
      // بررسی key های احتمالی با userId
      for (int i = 0; i < 1000; i++) { // محدودیت برای جلوگیری از loop بی‌نهایت
        final testKey = '$_tokenStatePrefix${userId}_token_$i';
        try {
          final secureValue = await SecureStorage.instance.getSecureData(testKey);
          if (secureValue != null) {
            final boolValue = secureValue.toLowerCase() == 'true';
            if (boolValue && !_tokenStateCache.containsKey(testKey)) {
              _tokenStateCache[testKey] = boolValue;
              await prefs.setBool(testKey, boolValue);
              print('🍎 TokenPreferences: Recovered custom user token: $testKey = $boolValue');
            }
          }
        } catch (e) {
          // اگر کلید وجود نداشت، break کن (طبیعیه)
          break;
        }
      }
    } catch (e) {
      print('❌ TokenPreferences: Error recovering custom user tokens: $e');
    }
  }
  
  /// Initialize default tokens for this user
  Future<void> _initializeDefaultTokens() async {
    try {
      final defaultTokens = {
        'BTC': {'name': 'Bitcoin', 'blockchain': 'Bitcoin'},
        'ETH': {'name': 'Ethereum', 'blockchain': 'Ethereum'},
        'TRX': {'name': 'Tron', 'blockchain': 'Tron'},
      };
      
      for (final entry in defaultTokens.entries) {
        final symbol = entry.key;
        final tokenInfo = entry.value;
        
        await saveTokenState(
          symbol, 
          tokenInfo['blockchain']!, 
          null, 
          true
        );
        
        print('✅ TokenPreferences: Initialized default token for user $userId: $symbol');
      }
      
      print('✅ TokenPreferences: All default tokens initialized for user $userId');
    } catch (e) {
      print('❌ TokenPreferences: Error initializing default tokens for user $userId: $e');
    }
  }

  /// Save token state with enhanced iOS persistence strategy
  Future<void> saveTokenState(String symbol, String blockchainName, String? smartContractAddress, bool isEnabled) async {
    try {
      final key = _getTokenKey(symbol, blockchainName, smartContractAddress);
      
      print('💾 TokenPreferences: Saving token state for $symbol ($blockchainName): $isEnabled');
      
      // Always save to SharedPreferences first
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, isEnabled);
      
      // iOS: Enhanced persistence with double confirmation
      if (Platform.isIOS) {
        // اول ذخیره کن
        await SecureStorage.instance.saveSecureData(key, isEnabled.toString());
        
        // سپس تأیید کن که درست ذخیره شده
        final verification = await SecureStorage.instance.getSecureData(key);
        final isVerified = verification?.toLowerCase() == isEnabled.toString().toLowerCase();
        
        if (isVerified) {
          print('🍎✅ TokenPreferences: iOS SecureStorage save verified: $key = $isEnabled');
        } else {
          print('🍎⚠️ TokenPreferences: iOS SecureStorage save verification failed, retrying...');
          
          // تلاش مجدد با PlatformStorageManager
          try {
            await _saveWithPlatformManager(key, isEnabled);
            print('🍎🔄 TokenPreferences: Retry with PlatformStorageManager succeeded');
          } catch (retryError) {
            print('🍎❌ TokenPreferences: Retry failed: $retryError');
          }
        }
        
        // اضافه کردن backup key برای اطمینان بیشتر
        final backupKey = '${key}_backup_${DateTime.now().millisecondsSinceEpoch}';
        await SecureStorage.instance.saveSecureData(backupKey, isEnabled.toString());
        
      } else {
        // Android: فقط SharedPreferences کافیه
        print('🤖 TokenPreferences: Android save completed');
      }
      
      // Update cache
      _tokenStateCache[key] = isEnabled;
      
      print('✅ TokenPreferences: Token state saved successfully: ${symbol}_$blockchainName = $isEnabled');
    } catch (e) {
      print('❌ TokenPreferences: Error saving token state for user $userId: $e');
      
      // Fallback: حداقل در cache ذخیره کن
      final key = _getTokenKey(symbol, blockchainName, smartContractAddress);
      _tokenStateCache[key] = isEnabled;
      
      rethrow;
    }
  }
  
  /// Fallback save method using PlatformStorageManager
  Future<void> _saveWithPlatformManager(String key, bool isEnabled) async {
    // استفاده از PlatformStorageManager به عنوان backup
    final platformManager = PlatformStorageManager.instance;
    await platformManager.saveData(key, isEnabled.toString(), isCritical: true);
  }

  /// Get token state with iOS dual storage support
  Future<bool> getTokenState(String symbol, String blockchainName, String? smartContractAddress) async {
    try {
      final key = _getTokenKey(symbol, blockchainName, smartContractAddress);
      
      // First try SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      bool? sharedPrefsValue = prefs.getBool(key);
      
      // iOS: If SharedPreferences fails, try SecureStorage
      if (Platform.isIOS && sharedPrefsValue == null) {
        final secureValue = await SecureStorage.instance.getSecureData(key);
        if (secureValue != null) {
          final boolValue = secureValue.toLowerCase() == 'true';
          print('🍎 TokenPreferences: Retrieved from SecureStorage (iOS): $key = $boolValue');
          
          // Sync back to SharedPreferences
          await prefs.setBool(key, boolValue);
          sharedPrefsValue = boolValue;
        }
      }
      
      // Update cache
      if (sharedPrefsValue != null) {
        _tokenStateCache[key] = sharedPrefsValue;
      }
      
      return sharedPrefsValue ?? false;
    } catch (e) {
      print('❌ TokenPreferences: Error getting token state for user $userId: $e');
      return false;
    }
  }

  /// دریافت وضعیت توکن (sync) - بهبود یافته
  bool? getTokenStateSync(String symbol, String blockchainName, String? smartContractAddress) {
    final key = _getTokenKey(symbol, blockchainName, smartContractAddress);
    
    // Check cache first
    if (_tokenStateCache.containsKey(key)) {
      return _tokenStateCache[key];
    }
    
    // If not in cache and cache is initialized, check default tokens
    if (_cacheInitialized) {
      final defaultTokens = ['BTC', 'ETH', 'TRX'];
      if (defaultTokens.contains(symbol.toUpperCase())) {
        _tokenStateCache[key] = true;
        // Also save to SharedPreferences for persistence
        _saveTokenStateInBackground(symbol, blockchainName, smartContractAddress, true);
        return true;
      }
      
      // Default to disabled for non-default tokens
      _tokenStateCache[key] = false;
      return false;
    }
    
    // If cache not initialized, return null to indicate uncertainty
    return null;
  }

  /// ذخیره وضعیت توکن در background (برای sync methods)
  void _saveTokenStateInBackground(String symbol, String blockchainName, String? smartContractAddress, bool isEnabled) {
    Future.microtask(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = _getTokenKey(symbol, blockchainName, smartContractAddress);
        await prefs.setBool(key, isEnabled);
      } catch (e) {
        print('❌ TokenPreferences: Error saving token state in background for $symbol: $e');
      }
    });
  }

  /// ذخیره ترتیب توکن‌ها
  Future<void> saveTokenOrder(List<String> tokenSymbols) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('${_tokenOrderKey}_$userId', tokenSymbols);
      print('✅ TokenPreferences: Saved token order with ${tokenSymbols.length} tokens');
    } catch (e) {
      print('❌ TokenPreferences: Error saving token order: $e');
    }
  }

  /// دریافت ترتیب توکن‌ها
  Future<List<String>> getTokenOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList('${_tokenOrderKey}_$userId') ?? [];
    } catch (e) {
      print('❌ TokenPreferences: Error getting token order: $e');
      return [];
    }
  }

  /// دریافت ترتیب توکن‌ها (sync) - بهبود یافته
  List<String>? getTokenOrderSync() {
    // We can't do sync SharedPreferences operations, so return null
    // This indicates that async method should be used
    return null;
  }

  /// دریافت تمام نام‌های توکن‌های فعال
  Future<List<String>> getAllEnabledTokenNames() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final enabledTokens = <String>[];
      
      for (final key in keys) {
        if (key.startsWith(_tokenStatePrefix) && prefs.getBool(key) == true) {
          final tokenName = key.replaceFirst(_tokenStatePrefix, '');
          enabledTokens.add(tokenName);
        }
      }
      
      return enabledTokens;
    } catch (e) {
      print('❌ TokenPreferences: Error getting enabled token names: $e');
      return [];
    }
  }

  /// دریافت تمام کلیدهای توکن‌های فعال
  Future<List<String>> getAllEnabledTokenKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final enabledKeys = <String>[];
      
      for (final key in keys) {
        if (key.startsWith(_tokenStatePrefix) && prefs.getBool(key) == true) {
          enabledKeys.add(key);
        }
      }
      
      return enabledKeys;
    } catch (e) {
      print('❌ TokenPreferences: Error getting enabled token keys: $e');
      return [];
    }
  }

  /// دریافت تمام نام‌های توکن‌های فعال (sync) - بهبود یافته
  List<String>? getAllEnabledTokenNamesSync() {
    if (!_cacheInitialized) return null;
    
    final enabledTokens = <String>[];
    
    for (final entry in _tokenStateCache.entries) {
      if (entry.value == true) {
        // Extract token name from key
        final tokenName = entry.key.replaceFirst(_tokenStatePrefix, '');
        enabledTokens.add(tokenName);
      }
    }
    
    return enabledTokens;
  }

  /// دریافت تمام کلیدهای توکن‌های فعال (sync) - بهبود یافته
  List<String>? getAllEnabledTokenKeysSync() {
    if (!_cacheInitialized) return null;
    
    final enabledKeys = <String>[];
    
    for (final entry in _tokenStateCache.entries) {
      if (entry.value == true) {
        enabledKeys.add(entry.key);
      }
    }
    
    return enabledKeys;
  }

  /// پاک کردن تمام تنظیمات توکن‌ها
  Future<void> clearAllTokenStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      for (final key in keys) {
        if (key.startsWith(_tokenStatePrefix)) {
          await prefs.remove(key);
        }
      }
      
      // Clear cache
      _tokenStateCache.clear();
      
      print('✅ TokenPreferences: Cleared all token states');
    } catch (e) {
      print('❌ TokenPreferences: Error clearing token states: $e');
    }
  }

  /// بازنشانی cache (برای debug یا refresh)
  Future<void> refreshCache() async {
    _cacheInitialized = false;
    await _initializeCache();
    _cacheInitialized = true;
  }

  /// تولید کلید منحصر به فرد برای توکن
  String _getTokenKey(String symbol, String blockchainName, String? smartContractAddress) {
    return '$_tokenStatePrefix${userId}_${symbol}_${blockchainName}_${smartContractAddress ?? ''}';
  }
  
  /// بررسی اینکه آیا cache مقداردهی اولیه شده است
  bool get isCacheInitialized => _cacheInitialized;
  
  /// Debug method برای نمایش وضعیت فعلی tokens در iOS
  Future<void> debugTokenRecoveryStatus() async {
    if (!Platform.isIOS) {
      print('🤖 Debug: Not iOS, skipping recovery status check');
      return;
    }
    
    print('🍎 === iOS TOKEN RECOVERY DEBUG STATUS ===');
    print('🍎 User ID: $userId');
    print('🍎 Cache Initialized: $_cacheInitialized');
    print('🍎 Cache Size: ${_tokenStateCache.length}');
    
    if (_tokenStateCache.isNotEmpty) {
      print('🍎 Cached Tokens:');
      _tokenStateCache.forEach((key, value) {
        if (value) { // فقط توکن‌های فعال نمایش بده
          print('🍎   ✅ $key = $value');
        }
      });
    } else {
      print('🍎 ⚠️ No tokens in cache!');
    }
    
    // تست direct access به SecureStorage
    print('🍎 === TESTING DIRECT SECURESTORAGE ACCESS ===');
    final testTokens = ['BTC_Bitcoin_', 'ETH_Ethereum_', 'TRX_Tron_'];
    
    for (final tokenKey in testTokens) {
      final key = '$_tokenStatePrefix${userId}_$tokenKey';
      try {
        final secureValue = await SecureStorage.instance.getSecureData(key);
        print('🍎 SecureStorage test - $key: ${secureValue ?? 'NOT_FOUND'}');
      } catch (e) {
        print('🍎 SecureStorage test error - $key: $e');
      }
    }
    
    // تست SharedPreferences
    print('🍎 === TESTING SHAREDPREFERENCES ACCESS ===');
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      final relevantKeys = allKeys.where((k) => k.contains(userId)).toList();
      
      print('🍎 SharedPreferences - Total keys: ${allKeys.length}');
      print('🍎 SharedPreferences - User-related keys: ${relevantKeys.length}');
      
      for (final key in relevantKeys) {
        final value = prefs.getBool(key);
        if (value == true) {
          print('🍎   ✅ SharedPrefs: $key = $value');
        }
      }
    } catch (e) {
      print('🍎 SharedPreferences test error: $e');
    }
    
    print('🍎 === END OF DEBUG STATUS ===');
  }
  
  /// Force recovery از SecureStorage برای troubleshooting
  Future<void> forceRecoveryFromSecureStorage() async {
    if (!Platform.isIOS) {
      print('🤖 Force recovery: Not iOS, skipping');
      return;
    }
    
    print('🍎 === FORCING RECOVERY FROM SECURESTORAGE ===');
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Clear existing cache and SharedPreferences for this user
      final keysToRemove = prefs.getKeys().where((k) => k.contains(userId)).toList();
      for (final key in keysToRemove) {
        await prefs.remove(key);
        print('🍎 Removed from SharedPreferences: $key');
      }
      
      _tokenStateCache.clear();
      print('🍎 Cache cleared');
      
      // Force reload from SecureStorage
      await _loadFromSecureStorageOnIOS(prefs);
      
      print('🍎 === FORCE RECOVERY COMPLETED ===');
      
      // Show results
      await debugTokenRecoveryStatus();
      
    } catch (e) {
      print('🍎 ❌ Force recovery failed: $e');
    }
  }
} 