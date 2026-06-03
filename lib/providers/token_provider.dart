import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import '../models/crypto_token.dart';
import '../models/price_data.dart';
import '../services/api_service.dart';
import '../services/on_chain_balance_service.dart';
import '../services/token_preferences.dart';
import '../services/secure_storage.dart';
import '../wallet/wallet_mode.dart';

class TokenProvider extends ChangeNotifier {
  // فیلدهای وضعیت
  List<CryptoToken> _currencies = [];
  bool _isLoading = false;
  bool _backgroundRefreshInProgress = false; // جلوگیری از هم‌پوشانی background refresh
  String? _errorMessage;
  List<CryptoToken> _activeTokens = [];
  Map<String, Map<String, PriceData>> _tokenPrices = {};
  Map<String, String> _gasFees = {};
  final Map<String, List<CryptoToken>> _userTokens = {};
  final Map<String, Map<String, String>> _userBalances = {};
  final String _walletName = '';
  String _userId;
  final ApiService apiService;
  late TokenPreferences tokenPreferences;

  // کانستراکتور
  TokenProvider({
    required String userId,
    required this.apiService,
    BuildContext? context,
  }) : _userId = userId {
    tokenPreferences = TokenPreferences(userId: userId);
    // Don't call initialize here, it will be called from AppProvider
  }

  // گترها
  List<CryptoToken> get currencies => _currencies;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<CryptoToken> get activeTokens => _activeTokens;
  Map<String, Map<String, PriceData>> get tokenPrices => _tokenPrices;
  Map<String, String> get gasFees => _gasFees;
  String get walletName => _walletName;
  String get userId => _userId;

  // گترهای سازگاری با کد موجود
  List<CryptoToken> get tokens => _activeTokens;
  List<CryptoToken> get enabledTokens {
    final enabled = _activeTokens.where((t) => t.isEnabled).toList();
    return sortTokensByDollarValue(enabled);
  }
  
  // Getter to check if TokenProvider is fully initialized
  bool get isInitialized => !_isLoading && _currencies.isNotEmpty;

  /// بررسی اینکه آیا TokenProvider کاملاً آماده است
  bool get isFullyReady {
    return !_isLoading && 
           _currencies.isNotEmpty && 
           _activeTokens.isNotEmpty;
  }
  
  /// Debug method to show current state
  void debugCurrentState() {
    print('=== TokenProvider Debug State ===');
    print('User ID: $_userId');
    print('Is Loading: $_isLoading');
    print('Is Initialized: $isInitialized');
    print('Is Fully Ready: $isFullyReady');
    // print('Cache Initialized: ${tokenPreferences.isCacheInitialized}'); // Property not available in utils TokenPreferences
    print('Total Currencies: ${_currencies.length}');
    print('Active Tokens: ${_activeTokens.length}');
    print('Active Tokens List: ${_activeTokens.map((t) => '${t.symbol}(${t.isEnabled})').join(', ')}');
    print('=====================================');
  }
  
  /// نگاشت سمبل به blockchainName طبیعی
  static String? _getBlockchainNameForSymbol(String symbol) {
    const map = {
      'BTC': 'Bitcoin',
      'ETH': 'Ethereum',
      'TRX': 'Tron',
      'SOL': 'Solana',
      'XRP': 'XRP',
      'BNB': 'Binance Smart Chain',
      'ADA': 'Cardano',
      'DOT': 'Polkadot',
      'AVAX': 'Avalanche',
      'MATIC': 'Polygon',
      'LTC': 'Litecoin',
      'DOGE': 'Dogecoin',
    };
    return map[symbol.toUpperCase()];
  }
  
  /// Debug method to check token preferences
  Future<void> debugTokenPreferences() async {
    print('=== TokenPreferences Debug ===');
    print('User ID: $_userId');
    // print('Cache Initialized: ${tokenPreferences.isCacheInitialized}'); // Property not available in utils TokenPreferences
    
    // Validate userId
    if (_userId.isEmpty) {
      print('❌ ERROR: User ID is empty! This will cause token persistence to fail.');
      return;
    }
    
    // Check default tokens
    final defaultTokens = ['BTC', 'ETH', 'TRX'];
    for (final symbol in defaultTokens) {
      final state = tokenPreferences.getTokenStateFromParams(symbol, _getBlockchainNameForSymbol(symbol) ?? symbol, null);
      print('Token $symbol state: $state');
    }
    
    // Check SharedPreferences keys
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.contains(_userId)).toList();
    print('SharedPreferences keys containing userId: $keys');
    
    // Check specific keys
    for (final key in keys) {
      final value = prefs.get(key);
      print('  $key: $value');
    }
    
    print('===============================');
  }

  /// مقداردهی اولیه در background - مشابه Kotlin
  Future<void> initializeInBackground() async {
    print('🔄 TokenProvider: Initializing in background for user: $_userId');
    
    _isLoading = true;
    notifyListeners();
    
    try {
      // 0. Ensure we have a valid userId
      await _ensureValidUserId();
      
      // Recreate TokenPreferences with correct userId
      tokenPreferences = TokenPreferences(userId: _userId);
      
      // 🚀 Optimize: Parallelize initial token loading and balance cache loading
      await Future.wait([
        Future(() async {
          await tokenPreferences.initialize();
          await _initializeDefaultTokensQuickly();
          await _loadCachedTokensQuickly();
        }),
        _loadBalanceCacheFromSecureStorage(),
      ]).timeout(const Duration(seconds: 10), onTimeout: () {
        print('⚠️ TokenProvider: Background initialization timeout - continuing with partial data');
        return [];
      });
      
      // Non-blocking smart load and synchronization
      // We don't necessarily need to await these before finishing background init
      // but we do it to ensure consistency.
      await smartLoadTokens(forceRefresh: false).timeout(const Duration(seconds: 5)).catchError((_) => null);
      await ensureTokensSynchronized().timeout(const Duration(seconds: 5)).catchError((_) => null);
      
      // 7. Background tasks - fetch fresh data
      _runBackgroundTasks();
      
      print('✅ TokenProvider: Background initialization completed for user: $_userId');
      
    } catch (e) {
      print('❌ TokenProvider: Error in background initialization: $e');
      _errorMessage = 'Error initializing: ${e.toString()}';
      await _initializeDefaultTokens();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // متد اولیه‌سازی (legacy - برای compatibility)
  Future<void> initialize() async {
    print('🔄 TokenProvider: Initializing for user: $_userId');
    
    // Initialize TokenPreferences first
    await tokenPreferences.initialize();
    
    // Initialize default tokens
    await _initializeDefaultTokens();
    
    // Fetch gas fees in background
    _fetchGasFees();
    
    // Load tokens with smart caching
    await smartLoadTokens(forceRefresh: false);
    
    // مطابق گزارش Kotlin: موجودی‌ها فقط بعد از import wallet فراخوانی می‌شوند
    print('ℹ️ TokenProvider: Skipping balance fetch in initialization - balances only fetched after wallet import');
    
    print('✅ TokenProvider: Initialized successfully for user: $_userId');
  }

  // مقداردهی اولیه سریع توکن‌های پیش‌فرض
  Future<void> _initializeDefaultTokensQuickly() async {
    final defaultTokens = [
      const CryptoToken(
        name: 'Bitcoin',
        symbol: 'BTC',
        blockchainName: 'Bitcoin',
        iconUrl: 'https://coinceeper.com/defaultIcons/bitcoin.png',
        isEnabled: true,
        isToken: false,
        smartContractAddress: null,
      ),
      const CryptoToken(
        name: 'Ethereum',
        symbol: 'ETH',
        blockchainName: 'Ethereum',
        iconUrl: 'https://coinceeper.com/defaultIcons/ethereum.png',
        isEnabled: true,
        isToken: false,
        smartContractAddress: null,
      ),
      const CryptoToken(
        name: 'Tron',
        symbol: 'TRX',
        blockchainName: 'Tron',
        iconUrl: 'https://coinceeper.com/defaultIcons/tron.png',
        isEnabled: true,
        isToken: false,
        smartContractAddress: null,
      ),
    ];
    
    // Set default tokens immediately
    _currencies = defaultTokens;
    _activeTokens = defaultTokens;
    notifyListeners();
    
    print('✅ TokenProvider: Default tokens set immediately');
  }
  
  /// بارگذاری سریع توکن‌های cached
  Future<void> _loadCachedTokensQuickly() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('cachedUserTokens_$_userId');
      
      if (jsonStr != null) {
        final List<dynamic> list = json.decode(jsonStr);
        
        // Enhanced parsing with better error handling
        List<CryptoToken> cachedTokens = [];
        int successfulQuickParsedCount = 0;
        
        for (int i = 0; i < list.length; i++) {
          try {
            final item = list[i] as Map<String, dynamic>;
            
            // Pre-process boolean fields for quick cache loading
            if (item.containsKey('isEnabled')) {
              final isEnabledValue = item['isEnabled'];
              if (isEnabledValue is String) {
                item['isEnabled'] = isEnabledValue.toLowerCase() == 'true' || isEnabledValue == '1';
              } else if (isEnabledValue is int) {
                item['isEnabled'] = isEnabledValue != 0;
              }
            }
            
            if (item.containsKey('isToken')) {
              final isTokenValue = item['isToken'];
              if (isTokenValue is String) {
                item['isToken'] = isTokenValue.toLowerCase() == 'true' || isTokenValue == '1';
              } else if (isTokenValue is int) {
                item['isToken'] = isTokenValue != 0;
              }
            }
            
            final token = CryptoToken.fromJson(item);
            cachedTokens.add(token);
            successfulQuickParsedCount++;
          } catch (e) {
            print('❌ Error parsing quick cache item $i: $e');
            
            // Try fallback parsing for quick cache
            try {
              final item = list[i] as Map<String, dynamic>;
              final fallbackToken = CryptoToken(
                name: item['name']?.toString() ?? 'Unknown',
                symbol: item['symbol']?.toString() ?? 'UNK',
                blockchainName: item['blockchainName']?.toString() ?? item['BlockchainName']?.toString() ?? 'Unknown',
                iconUrl: item['iconUrl']?.toString() ?? 'https://coinceeper.com/defaultIcons/coin.png',
                isEnabled: false, // Safe default for quick load
                isToken: true, // Safe default
                smartContractAddress: item['smartContractAddress']?.toString() ?? item['SmartContractAddress']?.toString(),
                amount: 0.0, // Safe default
              );
              cachedTokens.add(fallbackToken);
              print('⚠️ Created fallback token in quick cache for item $i: ${fallbackToken.symbol}');
            } catch (fallbackError) {
              print('❌ Could not create fallback token in quick cache for item $i: $fallbackError');
              // Skip this item and continue
            }
          }
        }
        
        if (cachedTokens.isEmpty) {
          print('⚠️ TokenProvider: No valid tokens in quick cache, clearing');
          await _clearAllCache(prefs);
          return;
        }
        
        print('✅ TokenProvider: Quick parsed $successfulQuickParsedCount/${list.length} tokens from cache');
        
        print('🔄 TokenProvider: Found ${cachedTokens.length} cached tokens');
        
        // به‌روزرسانی state توکن‌ها از TokenPreferences
        final updatedTokens = cachedTokens.map((token) {
          final isEnabled = tokenPreferences.getTokenStateFromParams(
            token.symbol ?? '', 
            token.blockchainName ?? '', 
            token.smartContractAddress
          );
          
          // اگر state موجود نیست، برای توکن‌های پیش‌فرض true استفاده کن
          final finalState = isEnabled ?? ['BTC', 'ETH', 'TRX'].contains(token.symbol?.toUpperCase());
          
          print('🔍 TokenProvider: Token ${token.symbol} - cached: ${token.isEnabled}, preferences: $isEnabled, final: $finalState');
          
          return token.copyWith(isEnabled: finalState);
        }).toList();
        
        // به‌روزرسانی currencies با state درست
        _currencies = updatedTokens;
        
        // فوری به‌روزرسانی active tokens
        _activeTokens = updatedTokens.where((t) => t.isEnabled).toList();
        
        // ذخیره user tokens
        _userTokens[_userId] = updatedTokens;
        
        print('✅ TokenProvider: Cached tokens loaded quickly (${_activeTokens.length} active)');
        print('✅ TokenProvider: Active tokens: ${_activeTokens.map((t) => '${t.symbol}(${t.isEnabled})').join(', ')}');
        
        notifyListeners();
      } else {
        print('⚠️ TokenProvider: No cached tokens found for user: $_userId');
      }
    } catch (e) {
      print('❌ TokenProvider: Could not load cached tokens: $e');
    }
  }

  /// بارگذاری کش موجودی از SecureStorage
  Future<void> _loadBalanceCacheFromSecureStorage() async {
    try {
      print('🔄 TokenProvider: Loading balance cache from SecureStorage...');
      
      // دریافت نام کیف پول فعلی
      final currentWallet = await SecureStorage.instance.getSelectedWallet();
      if (currentWallet == null) {
        print('⚠️ TokenProvider: No selected wallet found');
        return;
      }
      
      // بارگذاری کش موجودی برای کیف پول فعلی
      final balanceCache = await SecureStorage.instance.getWalletBalanceCache(currentWallet, _userId);
      
      if (balanceCache.isNotEmpty) {
        print('💾 TokenProvider: Found cached balances: $balanceCache');
        
        // اعمال موجودی‌های cached به توکن‌های موجود
        _currencies = _currencies.map((token) {
          final symbol = token.symbol ?? '';
          final cachedBalance = balanceCache[symbol] ?? 0.0;
          if (cachedBalance > 0.0) {
            print('   💰 Applied cached balance to ${token.symbol}: $cachedBalance');
            return token.copyWith(amount: cachedBalance);
          }
          return token;
        }).toList();
        
        // به‌روزرسانی active tokens با موجودی‌های cached
        _activeTokens = _activeTokens.map((token) {
          final symbol = token.symbol ?? '';
          final cachedBalance = balanceCache[symbol] ?? 0.0;
          if (cachedBalance > 0.0) {
            return token.copyWith(amount: cachedBalance);
          }
          return token;
        }).toList();
        
        // اضافه کردن توکن‌هایی که موجودی دارند اما در لیست نیستند
        for (final symbol in balanceCache.keys) {
          final balance = balanceCache[symbol] ?? 0.0;
          if (balance > 0.0) {
            final existsInActive = _activeTokens.any((t) => t.symbol == symbol);
            if (!existsInActive) {
              // بررسی وضعیت enabled بودن از preferences
              final isEnabled = tokenPreferences.getTokenStateFromParams(symbol, 'Tron', null) ?? true;
              
              if (isEnabled) {
                final newToken = CryptoToken(
                  name: symbol,
                  symbol: symbol,
                  blockchainName: 'Tron',
                  iconUrl: 'https://coinceeper.com/defaultIcons/coin.png',
                  isEnabled: true,
                  amount: balance,
                  isToken: true,
                );
                
                _activeTokens.add(newToken);
                _currencies.add(newToken);
                print('   ✅ Added cached token to active list: $symbol = $balance');
              }
            }
          }
        }
        
        notifyListeners();
        print('✅ TokenProvider: Balance cache applied successfully');
      } else {
        print('⚠️ TokenProvider: No cached balances found');
      }
    } catch (e) {
      print('❌ TokenProvider: Error loading balance cache: $e');
    }
  }
  
  // اجرای tasks در background
  void _runBackgroundTasks() {
    print('🔄 TokenProvider: Starting background tasks...');
    
    // Fetch gas fees (non-critical) a bit later
    Future.delayed(const Duration(seconds: 1), () {
      _fetchGasFees();
    });
    
    // Load fresh tokens from API with small delay
    Future.delayed(const Duration(seconds: 2), () {
      smartLoadTokens(forceRefresh: false).then((_) {
        print('✅ TokenProvider: Fresh tokens loaded from API');
      }).catchError((e) {
        print('❌ TokenProvider: Error loading fresh tokens: $e');
      });
    });
    
    // مطابق گزارش Kotlin: موجودی‌ها فقط بعد از import wallet فراخوانی می‌شوند
    print('ℹ️ TokenProvider: Skipping background balance fetch - balances only fetched after wallet import');
  }
  
  /// مقداردهی اولیه توکن‌های پیش‌فرض - مشابه Kotlin
  Future<void> _initializeDefaultTokens() async {
    try {
      final defaultTokens = [
        const CryptoToken(
          name: 'Bitcoin',
          symbol: 'BTC',
          blockchainName: 'Bitcoin',
          iconUrl: 'https://coinceeper.com/defaultIcons/bitcoin.png',
          isEnabled: true,
          isToken: false,
          smartContractAddress: null,
        ),
        const CryptoToken(
          name: 'Ethereum',
          symbol: 'ETH',
          blockchainName: 'Ethereum',
          iconUrl: 'https://coinceeper.com/defaultIcons/ethereum.png',
          isEnabled: true,
          isToken: false,
          smartContractAddress: null,
        ),
        const CryptoToken(
          name: 'Tron',
          symbol: 'TRX',
          blockchainName: 'Tron',
          iconUrl: 'https://coinceeper.com/defaultIcons/tron.png',
          isEnabled: true,
          isToken: false,
          smartContractAddress: null,
        ),
      ];
      
      final prefs = await SharedPreferences.getInstance();
      final isFirstRun = prefs.getBool('is_first_run_$_userId') ?? true;
      
      print('🔄 TokenProvider - Initialize default tokens for user: $_userId (first run: $isFirstRun)');
      
      if (isFirstRun) {
        // اولین اجرا - ذخیره tokens پیش‌فرض
        for (final token in defaultTokens) {
          await tokenPreferences.saveTokenStateFromParams(
            token.symbol ?? '',
            token.blockchainName ?? '',
            token.smartContractAddress,
            true,
          );
          print('✅ TokenProvider - Saved default token: ${token.symbol}');
        }
        
        await prefs.setBool('is_first_run_$_userId', false);
        _currencies = defaultTokens;
        _activeTokens = defaultTokens;
        _userTokens[_userId] = defaultTokens;
        
        print('✅ TokenProvider - Default tokens set for first run');
      } else {
        // نه اولین اجرا - بررسی وضعیت موجود
        final existingTokens = <CryptoToken>[];
        
        for (final token in defaultTokens) {
          final enabled = tokenPreferences.getTokenStateFromParams(
            token.symbol ?? '',
            token.blockchainName ?? '',
            token.smartContractAddress,
          ) ?? true; // پیش‌فرض true برای tokens اصلی
          
          if (enabled) {
            existingTokens.add(token);
            print('✅ TokenProvider - Default token ${token.symbol} is enabled');
          } else {
            print('⚪ TokenProvider - Default token ${token.symbol} is disabled');
          }
        }
        
        // اطمینان از حداقل یک token فعال
        if (existingTokens.isEmpty) {
          print('⚠️ TokenProvider - No enabled default tokens, re-enabling Bitcoin');
          await tokenPreferences.saveTokenStateFromParams('BTC', 'Bitcoin', null, true);
          existingTokens.add(defaultTokens[0]); // Bitcoin
        }
        
        // به‌روزرسانی لیست‌ها
        _activeTokens.addAll(existingTokens.where((token) => 
          !_activeTokens.any((existing) => existing.symbol == token.symbol)
        ));
        
        print('✅ TokenProvider - Default tokens ensured: ${existingTokens.length} enabled');
      }
      
      // اطمینان از notify
      notifyListeners();
      
    } catch (e) {
      print('❌ TokenProvider - Error initializing default tokens: $e');
      _errorMessage = 'Error initializing default tokens: ${e.toString()}';
      notifyListeners();
    }
  }

  // متد نمونه برای دریافت گس‌فی — با debounce جلوگیری از درخواست‌های تکراری
  DateTime? _lastGasFeeFetch;
  static const Duration _gasFeeDebounce = Duration(seconds: 10);
  
  Future<void> _fetchGasFees() async {
    // Debounce: اگر کمتر از ۱۰ ثانیه از آخرین درخواست گذشته، رد شو
    final now = DateTime.now();
    if (_lastGasFeeFetch != null && now.difference(_lastGasFeeFetch!) < _gasFeeDebounce) {
      print('ℹ️ TokenProvider: Skipping duplicate gas fee fetch (debounce)');
      return;
    }
    _lastGasFeeFetch = now;
    
    try {
      // اولویت با V2 API (non-custodial, cache proxy)
      final v2Gas = await apiService.getGasV2();
      if (v2Gas != null && v2Gas.isNotEmpty) {
        _gasFees = {
          'Bitcoin': (v2Gas['Bitcoin']?.toString() ?? v2Gas['bitcoin']?.toString()) ?? '0.0',
          'Ethereum': (v2Gas['Ethereum']?.toString() ?? v2Gas['ethereum']?.toString()) ?? '0.0',
          'Tron': (v2Gas['Tron']?.toString() ?? v2Gas['tron']?.toString()) ?? '0.0',
          'Binance Smart Chain': (v2Gas['Binance Smart Chain']?.toString() ?? v2Gas['binance']?.toString()) ?? '0.0',
        };
        notifyListeners();
        return;
      }
      
      // Fallback به V1 API
      final gasFeeResponse = await apiService.getGasFee();
      _gasFees = {
        'Bitcoin': gasFeeResponse.bitcoin?.gasFee ?? '0.0',
        'Ethereum': gasFeeResponse.ethereum?.gasFee ?? '0.0',
        'Tron': gasFeeResponse.tron?.gasFee ?? '0.0',
        'Binance Smart Chain': gasFeeResponse.binance?.gasFee ?? '0.0',
      };
      notifyListeners();
    } catch (_) {
      _gasFees = {'Bitcoin': '0.0', 'Ethereum': '0.0'};
      notifyListeners();
    }
  }

  // متد هوشمند بارگذاری توکن‌ها
  Future<void> smartLoadTokens({bool forceRefresh = false}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheValid = _isCacheValid(prefs);
      
      // Always try cache first (non-custodial: cache-first strategy)
      final loadedFromCache = await _loadFromCache(prefs);
      
      if (forceRefresh || !cacheValid) {
        // Background refresh from API — فقط یکبار و بدون هم‌پوشانی
        if (!_backgroundRefreshInProgress) {
          _backgroundRefreshInProgress = true;
          _loadFromApi(prefs).then((_) {
            print('✅ TokenProvider: Background API refresh completed');
            _backgroundRefreshInProgress = false;
          }).catchError((e) {
            print('⚠️ TokenProvider: Background API refresh failed: $e');
            _backgroundRefreshInProgress = false;
            // Cache is still valid, no error to user
          });
        } else {
          print('ℹ️ TokenProvider: Background API refresh already in progress, skipping');
        }
      }
      
      if (!loadedFromCache && _currencies.isEmpty) {
        // No cache at all — this is first run, use default tokens
        await _initializeDefaultTokensQuickly();
      }
      // ذخیره توکن‌های کاربر
      _userTokens[_userId] = _currencies;
    } catch (e) {
      _errorMessage = 'Error: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // بررسی اعتبار کش
  bool _isCacheValid(SharedPreferences prefs) {
    final lastCache = prefs.getInt('cache_timestamp_$_userId') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    // اعتبار 24 ساعت
    return (now - lastCache) < (24 * 60 * 60 * 1000);
  }

  // بارگذاری از کش
  Future<bool> _loadFromCache(SharedPreferences prefs) async {
    final jsonStr = prefs.getString('cachedUserTokens_$_userId');
    if (jsonStr == null) return false;
    try {
      print('🔄 TokenProvider: Attempting to load cache for user: $_userId');
      final List<dynamic> list = json.decode(jsonStr);
      print('📁 TokenProvider: Cache contains ${list.length} items');
      
      // Try to parse with enhanced error handling
      List<CryptoToken> tokens = [];
      int successfulParsedCount = 0;
      
      for (int i = 0; i < list.length; i++) {
        try {
          final item = list[i] as Map<String, dynamic>;
          print('🔄 Parsing cache item $i: ${item.keys.toList()}');
          
          // Pre-process boolean fields to ensure compatibility
          if (item.containsKey('isEnabled')) {
            final isEnabledValue = item['isEnabled'];
            print('   isEnabled: $isEnabledValue (${isEnabledValue.runtimeType})');
            
            // Convert to proper boolean if needed
            if (isEnabledValue is String) {
              item['isEnabled'] = isEnabledValue.toLowerCase() == 'true' || isEnabledValue == '1';
            } else if (isEnabledValue is int) {
              item['isEnabled'] = isEnabledValue != 0;
            }
          }
          
          if (item.containsKey('isToken')) {
            final isTokenValue = item['isToken'];
            print('   isToken: $isTokenValue (${isTokenValue.runtimeType})');
            
            // Convert to proper boolean if needed
            if (isTokenValue is String) {
              item['isToken'] = isTokenValue.toLowerCase() == 'true' || isTokenValue == '1';
            } else if (isTokenValue is int) {
              item['isToken'] = isTokenValue != 0;
            }
          }
          
          final token = CryptoToken.fromJson(item);
          tokens.add(token);
          successfulParsedCount++;
          print('✅ Successfully parsed cache item $i: ${token.symbol}');
        } catch (e) {
          print('❌ Error parsing cache item $i: $e');
          print('   Item data: ${list[i]}');
          
          // Try to create a fallback token from raw data
          try {
            final item = list[i] as Map<String, dynamic>;
            final fallbackToken = CryptoToken(
              name: item['name']?.toString() ?? 'Unknown',
              symbol: item['symbol']?.toString() ?? 'UNK',
              blockchainName: item['blockchainName']?.toString() ?? item['BlockchainName']?.toString() ?? 'Unknown',
              iconUrl: item['iconUrl']?.toString() ?? 'https://coinceeper.com/defaultIcons/coin.png',
              isEnabled: false, // Safe default
              isToken: true, // Safe default
              smartContractAddress: item['smartContractAddress']?.toString() ?? item['SmartContractAddress']?.toString(),
              amount: 0.0, // Safe default
            );
            tokens.add(fallbackToken);
            print('⚠️ Created fallback token for item $i: ${fallbackToken.symbol}');
          } catch (fallbackError) {
            print('❌ Could not create fallback token for item $i: $fallbackError');
            // Skip this item completely
          }
        }
      }
      
      if (tokens.isEmpty) {
        print('⚠️ TokenProvider: No valid tokens found in cache, clearing');
        await _clearAllCache(prefs);
        return false;
      }
      
      print('✅ TokenProvider: Successfully parsed $successfulParsedCount/${list.length} tokens from cache');
      
      // به‌روزرسانی state توکن‌ها از preferences
      final updatedTokens = tokens.map((token) {
        final isEnabled = tokenPreferences.getTokenStateFromParams(
          token.symbol ?? '', 
          token.blockchainName ?? '', 
          token.smartContractAddress
        );
        // اگر state موجود نیست، برای توکن‌های پیش‌فرض true استفاده کن
        final finalState = isEnabled ?? ['BTC', 'ETH', 'TRX'].contains(token.symbol?.toUpperCase());
        return token.copyWith(isEnabled: finalState);
      }).toList();
      
      _currencies = updatedTokens;
      _activeTokens = updatedTokens.where((t) => t.isEnabled).toList();
      notifyListeners();
      return true;
    } catch (e) {
      print('❌ TokenProvider: Unexpected error in _loadFromCache: $e');
      await _clearAllCache(prefs);
      return false;
    }
  }

  /// پاک کردن کامل cache
  Future<void> _clearAllCache(SharedPreferences prefs) async {
    try {
      print('🗑️ TokenProvider: Clearing all cache for user: $_userId');
      await prefs.remove('cachedUserTokens_$_userId');
      await prefs.remove('cache_timestamp_$_userId');
      await prefs.remove('add_token_cached_tokens');
      
      // Clear any other related cache keys
      final keys = prefs.getKeys().where((key) => key.contains(_userId)).toList();
      for (final key in keys) {
        if (key.contains('cached') || key.contains('timestamp')) {
          await prefs.remove(key);
          print('🗑️ Removed cache key: $key');
        }
      }
      
      print('✅ TokenProvider: All cache cleared for user: $_userId');
    } catch (e) {
      print('❌ Error clearing cache: $e');
    }
  }

  // بارگذاری از API — non-custodial, graceful failure
  Future<void> _loadFromApi(SharedPreferences prefs) async {
    try {
      print('🔄 TokenProvider: Loading from API (V2 cache proxy)...');
      final response = await apiService.getAllCurrencies();
      print('📥 TokenProvider: getAllCurrencies response success: ${response.success}');
      
      if (!response.success || response.currencies.isEmpty) {
        print('⚠️ TokenProvider: API returned empty/failed response, keeping cached tokens');
        _errorMessage = null; // Don't show error for optional catalog fetch
        return;
      }
      
      print('📥 TokenProvider: currencies count: ${response.currencies.length}');
      final tokens = response.currencies.map<CryptoToken>((token) {
        print('🔄 Processing token: ${token.symbol} (IsToken: ${token.isToken}, type: ${token.isToken.runtimeType})');
        
        const defaultTokens = ['BTC', 'ETH', 'TRX'];
        final isEnabled = tokenPreferences.getTokenStateFromParams(
          token.symbol ?? '',
          token.blockchainName ?? '',
          token.smartContractAddress,
        ) || defaultTokens.contains(token.symbol?.toUpperCase());
        
        try {
          final isTokenBool = token.isToken ?? true;
          
          final cryptoToken = CryptoToken(
            name: token.currencyName,
            symbol: token.symbol,
            blockchainName: token.blockchainName,
            iconUrl: token.icon ?? 'https://coinceeper.com/defaultIcons/coin.png',
            isEnabled: isEnabled,
            isToken: isTokenBool,
            smartContractAddress: token.smartContractAddress,
          );
          print('✅ Successfully created CryptoToken for ${token.symbol} (isToken: $isTokenBool)');
          return cryptoToken;
        } catch (e) {
          print('❌ Error creating CryptoToken for ${token.symbol}: $e');
          print('   token.isToken value: ${token.isToken}');
          print('   token.isToken type: ${token.isToken.runtimeType}');
          
          bool safeIsToken = true;
          
          if (token.isToken != null) {
            try {
              if (token.isToken is bool) {
                safeIsToken = token.isToken!;
              } else if (token.isToken is int) {
                safeIsToken = token.isToken != 0;
              } else if (token.isToken is String) {
                final stringValue = token.isToken.toString().toLowerCase();
                safeIsToken = stringValue == 'true' || stringValue == '1';
              } else {
                print('⚠️ Unexpected isToken type: ${token.isToken.runtimeType}, using default');
              }
            } catch (conversionError) {
              print('❌ Manual conversion also failed: $conversionError');
            }
          }
          
          final fallbackToken = CryptoToken(
            name: token.currencyName ?? 'Unknown',
            symbol: token.symbol ?? 'UNK',
            blockchainName: token.blockchainName ?? 'Unknown',
            iconUrl: token.icon ?? 'https://coinceeper.com/defaultIcons/coin.png',
            isEnabled: isEnabled,
            isToken: safeIsToken,
            smartContractAddress: token.smartContractAddress,
          );
          print('⚠️ Created fallback CryptoToken for ${token.symbol} with isToken: $safeIsToken');
          return fallbackToken;
        }
      }).toList();
      // ⚡ CRITICAL FIX: Ensure BTC/ETH/TRX always survive in the list
      // V2 /api/v2/coins may only return partial data (e.g. 50 obscure coins)
      final tokensWithDefaults = _ensureDefaultTokensPresent(tokens);
      final ordered = _maintainTokenOrder(tokensWithDefaults);
      await _saveToCache(prefs, ordered);
      _currencies = ordered;
      _activeTokens = ordered.where((t) => t.isEnabled).toList();
      
      // ⚡ If no tokens are enabled after API load, force-enable defaults
      if (_activeTokens.isEmpty) {
        print('⚠️ TokenProvider: No enabled tokens after API load, force-enabling defaults');
        await _initializeDefaultTokens();
        // The defaults are already in _currencies, just update states
        _currencies = _currencies.map((token) {
          final isEnabled = tokenPreferences.getTokenStateFromParams(
            token.symbol ?? '',
            token.blockchainName ?? '',
            token.smartContractAddress,
          );
          // For BTC/ETH/TRX, always enabled
          const defaults = ['BTC', 'ETH', 'TRX'];
          final finalState = isEnabled ?? defaults.contains(token.symbol?.toUpperCase()) || false;
          return token.copyWith(isEnabled: finalState);
        }).toList();
        _activeTokens = _currencies.where((t) => t.isEnabled).toList();
        print('✅ TokenProvider: After force-enable, ${_activeTokens.length} active tokens');
      }
      
      notifyListeners();
    } catch (e) {
      print('❌ TokenProvider: API error in _loadFromApi: $e');
      _backgroundRefreshInProgress = false;
      // Don't set error message — optional catalog fetch should never block the user
    }
  }

  // ذخیره توکن‌ها در کش
  Future<void> _saveToCache(SharedPreferences prefs, List<CryptoToken> tokens) async {
    final jsonStr = json.encode(tokens.map((e) => e.toJson()).toList());
    await prefs.setString('cachedUserTokens_$_userId', jsonStr);
    await prefs.setInt('cache_timestamp_$_userId', DateTime.now().millisecondsSinceEpoch);
  }

  /// ⚡ CRITICAL FIX: اطمینان از حضور همیشگی BTC/ETH/TRX در لیست
  /// V2 /api/v2/coins ممکن است فقط subset ای از ارزها را برگرداند
  List<CryptoToken> _ensureDefaultTokensPresent(List<CryptoToken> tokens) {
    const defaultSymbols = ['BTC', 'ETH', 'TRX'];
    const defaultNames = ['Bitcoin', 'Ethereum', 'Tron'];
    const defaultBlockchains = ['Bitcoin', 'Ethereum', 'Tron'];
    
    for (int i = 0; i < defaultSymbols.length; i++) {
      final sym = defaultSymbols[i];
      final exists = tokens.any((t) =>
        t.symbol?.toUpperCase() == sym &&
        t.blockchainName == defaultBlockchains[i]
      );
      if (!exists) {
        print('🔧 TokenProvider: Injecting missing default token: $sym');
        tokens.add(CryptoToken(
          name: defaultNames[i],
          symbol: sym,
          blockchainName: defaultBlockchains[i],
          iconUrl: 'https://coinceeper.com/defaultIcons/${sym.toLowerCase()}.png',
          isEnabled: true,
          isToken: false,
        ));
      }
    }
    return tokens;
  }

  // حفظ ترتیب توکن‌ها بر اساس ذخیره قبلی
  List<CryptoToken> _maintainTokenOrder(List<CryptoToken> tokens) {
    final List<String> savedOrder = tokenPreferences.getTokenOrder();
    if (savedOrder.isEmpty) return tokens;
    final tokenMap = {for (var t in tokens) '${t.symbol ?? ''}_${t.name ?? ''}': t};
    final orderedTokens = <CryptoToken>[];
    for (final symbol in savedOrder) {
      if (tokenMap.containsKey(symbol)) {
        orderedTokens.add(tokenMap[symbol]!);
      }
    }
    for (final token in tokens) {
      if (!orderedTokens.contains(token)) {
        orderedTokens.add(token);
      }
    }
    return orderedTokens;
  }

  // --- قیمت توکن‌ها ---
  static const int PRICE_CACHE_EXPIRY_TIME = 5 * 60 * 1000; // 5 دقیقه

  Future<void> fetchPrices({List<String>? activeSymbols, List<String>? fiatCurrencies}) async {
    activeSymbols ??= _activeTokens.map((t) => t.symbol).whereType<String>().toList();
    fiatCurrencies ??= ['USD', 'EUR', 'IRR'];
    if (activeSymbols.isEmpty) {
      print('⚠️ TokenProvider.fetchPrices: No active symbols to fetch prices for');
      return;
    }
    
    print('🔄 TokenProvider.fetchPrices: Starting for symbols: $activeSymbols');
    
    final prefs = await SharedPreferences.getInstance();
    bool cacheLoaded = false;
    
    // بارگذاری از کش اگر معتبر باشد
    if (_isPriceCacheValid(prefs)) {
      print('💾 TokenProvider.fetchPrices: Loading from cache...');
      await loadPricesFromCache(prefs);
      cacheLoaded = true;
      print('✅ TokenProvider.fetchPrices: Cache loaded successfully');
    } else {
      print('⚠️ TokenProvider.fetchPrices: Cache invalid or expired');
    }
    
    try {
      print('🌐 TokenProvider.fetchPrices: Fetching from V2 cache proxy...');
      final v2Prices = await apiService.getPricesV2();

      if (v2Prices.isNotEmpty) {
        print('✅ TokenProvider.fetchPrices: V2 response successful (${v2Prices.length} coins)');

        // تبدیل {COINID: {USD: value}} به {SYMBOL: {USD: PriceData}}
        final convertedPrices = <String, Map<String, PriceData>>{};
        v2Prices.forEach((coinId, currencyMap) {
          final usdPrice = currencyMap['USD'];
          final change24h = currencyMap['change_24h'] ?? 0;
          if (usdPrice != null) {
            convertedPrices[coinId] = {
              'USD': PriceData(change24h: change24h.toStringAsFixed(2), price: usdPrice.toStringAsFixed(6)),
            };
          }
        });

        _tokenPrices = convertedPrices;
        await savePricesToCache(prefs, _tokenPrices);
        notifyListeners();

        print('💾 TokenProvider.fetchPrices: V2 prices saved to cache and UI notified');
        return;
      }

      // Fallback: امتحان V1 (ممکن است سرور قدیمی هنوز V1 داشته باشد)
      print('⚠️ TokenProvider.fetchPrices: V2 empty, falling back to V1...');
      final pricesResponse = await apiService.getPrices(activeSymbols, fiatCurrencies);
      
      if (pricesResponse.success && pricesResponse.prices != null) {
        print('✅ TokenProvider.fetchPrices: API response successful');
        
        // تبدیل PriceData از api_models به models
        final convertedPrices = <String, Map<String, PriceData>>{};
        pricesResponse.prices!.forEach((symbol, currencyMap) {
          convertedPrices[symbol] = currencyMap.map((currency, priceData) => 
            MapEntry(currency, PriceData(
              change24h: priceData.change24h,
              price: priceData.price,
            ))
          );
        });
        
        _tokenPrices = convertedPrices;
        await savePricesToCache(prefs, _tokenPrices);
        notifyListeners();
        
        print('💾 TokenProvider.fetchPrices: Prices saved to cache and UI notified');
        print('🔍 TokenProvider.fetchPrices: Final prices: ${_tokenPrices.keys.toList()}');
      } else {
        print('❌ TokenProvider.fetchPrices: API failed or returned no prices');
        if (!cacheLoaded) {
          // اگر کش هم نبود، حداقل مقادیر پیش‌فرض تنظیم کن
          notifyListeners();
        }
      }
    } catch (e) {
      print('❌ TokenProvider.fetchPrices: Exception occurred: $e');
      if (!cacheLoaded) {
        // اگر کش هم نبود، حداقل UI را notify کن
        notifyListeners();
      }
    }
  }

  bool _isPriceCacheValid(SharedPreferences prefs) {
    final lastCache = prefs.getInt('price_cache_timestamp') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - lastCache) < PRICE_CACHE_EXPIRY_TIME;
  }

  Future<void> loadPricesFromCache(SharedPreferences prefs) async {
    final jsonStr = prefs.getString('cached_prices');
    if (jsonStr == null) return;
    try {
      final Map<String, dynamic> map = json.decode(jsonStr);
      _tokenPrices = map.map((k, v) => MapEntry(k, (v as Map<String, dynamic>).map((kk, vv) => MapEntry(kk, PriceData.fromJson(vv)))));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> savePricesToCache(SharedPreferences prefs, Map<String, Map<String, PriceData>> prices) async {
    final map = prices.map((k, v) => MapEntry(k, v.map((kk, vv) => MapEntry(kk, vv.toJson()))));
    final jsonStr = json.encode(map);
    await prefs.setString('cached_prices', jsonStr);
    await prefs.setInt('price_cache_timestamp', DateTime.now().millisecondsSinceEpoch);
  }

  // --- فعال/غیرفعال کردن توکن ---
  /// Toggle کردن وضعیت توکن - مشابه Kotlin
  Future<void> toggleToken(CryptoToken token, bool newState, {bool isManualToggle = false}) async {
    try {
      print('🔄 TokenProvider - Toggling token ${token.name} (${token.symbol}) to $newState for user: $_userId (manual: $isManualToggle)');
      
      // 1. ذخیره state در preferences با کلید user-specific (scoped) و فلگ manual toggle
      await tokenPreferences.saveTokenStateFromParams(
        token.symbol ?? '', 
        token.blockchainName ?? '', 
        token.smartContractAddress, 
        newState,
        isManualToggle: isManualToggle
      );
      
      // 2. به‌روزرسانی currencies list
      _currencies = _currencies.map((currentToken) {
        if (currentToken.symbol == token.symbol && 
            currentToken.blockchainName == token.blockchainName &&
            currentToken.smartContractAddress == token.smartContractAddress) {
          return currentToken.copyWith(isEnabled: newState);
        }
        return currentToken;
      }).toList();
      
      // 3. به‌روزرسانی active tokens list
      if (newState) {
        // اگر توکن فعال شده، آن را به لیست فعال اضافه کن
        final existingToken = _activeTokens.firstWhere(
          (t) => t.symbol == token.symbol && 
                 t.blockchainName == token.blockchainName &&
                 t.smartContractAddress == token.smartContractAddress,
          orElse: () => const CryptoToken(name: '', symbol: '', blockchainName: '', isEnabled: false, isToken: true),
        );
        
        if (existingToken.symbol?.isEmpty ?? true) {
          // توکن در لیست فعال نیست، اضافه کن
          _activeTokens.add(token.copyWith(isEnabled: true));
        } else {
          // توکن در لیست فعال است، به‌روزرسانی کن
          final index = _activeTokens.indexWhere(
            (t) => t.symbol == token.symbol && 
                   t.blockchainName == token.blockchainName &&
                   t.smartContractAddress == token.smartContractAddress
          );
          if (index != -1) {
            _activeTokens[index] = _activeTokens[index].copyWith(isEnabled: true);
          }
        }
      } else {
        // اگر توکن غیرفعال شده، آن را از لیست فعال حذف کن
        _activeTokens.removeWhere(
          (t) => t.symbol == token.symbol && 
                 t.blockchainName == token.blockchainName &&
                 t.smartContractAddress == token.smartContractAddress
        );
      }
      
      // 4. ذخیره state به‌روزرسانی شده در cache
      await _saveToCache(await SharedPreferences.getInstance(), _currencies);
      
      // 5. ذخیره توکن‌های user-specific
      _userTokens[_userId] = _currencies;

      // ⚡ FIXED: Persist complete active token keys per-wallet for restoration after app kill
      try {
        final currentWallet = await SecureStorage.instance.getSelectedWallet();
        final currentUser = await SecureStorage.instance.getSelectedUserId();
        if (currentWallet != null && currentUser != null) {
          // Create unique keys for each enabled token including blockchain and contract address
          final enabledTokens = _currencies.where((t) => t.isEnabled).toList();
          final activeTokenKeys = enabledTokens.map((t) {
            return tokenPreferences.getTokenKeyFromParams(
              t.symbol ?? '',
              t.blockchainName ?? '',
              t.smartContractAddress,
            );
          }).toList();
          
          // Save both formats for compatibility
          await SecureStorage.instance.saveActiveTokenKeys(currentWallet, currentUser, activeTokenKeys);
          
          // Legacy format for backward compatibility
          final activeSymbols = enabledTokens.map((t) => t.symbol ?? '').toList();
          await SecureStorage.instance.saveActiveTokens(currentWallet, currentUser, activeSymbols);
          
          print('💾 TokenProvider: Persisted ${activeTokenKeys.length} active token keys after toggle');
          print('🔍 Active token keys: ${activeTokenKeys.take(3).join(', ')}...');
        }
      } catch (e) {
        print('⚠️ TokenProvider: Error persisting active tokens after toggle: $e');
      }
      
      print('🔄 TokenProvider - Active tokens after toggle: ${_activeTokens.map((t) => '${t.symbol}(${t.isEnabled})').join(', ')}');
      
      // 6. مرتب‌سازی مجدد بعد از toggle
      _activeTokens = sortTokensByDollarValue(_activeTokens);
      print('🔄 TokenProvider - Tokens sorted after toggle');
      
      // 7. فوراً notify کن
      notifyListeners();
      
      // 8. اگر توکن فعال شده، قیمت و موجودی fetch کن (فوری و سبک)
      if (newState) {
        // فقط قیمت‌های این توکن را لود کن
        final symbol = token.symbol;
        if (symbol != null && symbol.isNotEmpty) {
          try {
            await apiService.getPrices([symbol], ['USD']);
          } catch (_) {}
        }
        // مطابق گزارش Kotlin: موجودی‌ها فقط بعد از import wallet فراخوانی می‌شوند
        print('ℹ️ TokenProvider: Skipping background balance fetch in toggle - balances only fetched after wallet import');
      }
      
      print('✅ TokenProvider - Token ${token.symbol} successfully toggled to $newState');
      
    } catch (e) {
      print('❌ TokenProvider - Error toggling token ${token.symbol}: $e');
      _errorMessage = 'Failed to update token state: ${e.toString()}';
      notifyListeners();
    }
  }
  
  /// بررسی فعال بودن توکن برای کاربر خاص - مشابه Kotlin
  bool isTokenEnabled(CryptoToken token) {
    final state = tokenPreferences.getTokenStateFromParams(
      token.symbol ?? '', 
      token.blockchainName ?? '', 
      token.smartContractAddress
    );
    
    return state;
  }
  
  /// ذخیره state توکن برای کاربر خاص - مشابه Kotlin
  Future<void> saveTokenStateForUser(CryptoToken token, bool isEnabled, {bool isManualToggle = false}) async {
    await tokenPreferences.saveTokenStateFromParams(
      token.symbol ?? '', 
      token.blockchainName ?? '', 
      token.smartContractAddress, 
      isEnabled,
      isManualToggle: isManualToggle
    );
  }
  
  /// دریافت state توکن برای کاربر خاص - مشابه Kotlin
  bool getTokenStateForUser(CryptoToken token) {
    return tokenPreferences.getTokenStateFromParams(
      token.symbol ?? '', 
      token.blockchainName ?? '', 
      token.smartContractAddress
    ) ?? false;
  }
  
  /// تنظیم tokens فعال برای کاربر خاص - مشابه Kotlin
  void setActiveTokensForUser(List<CryptoToken> tokens) {
    _activeTokens = tokens;
    _userTokens[_userId] = tokens;
    notifyListeners();
  }
  
  /// ذخیره tokens کاربر - مشابه Kotlin
  void saveUserTokens(String userId, List<CryptoToken> tokens) {
    _userTokens[userId] = tokens;
  }
  
  /// ذخیره balances کاربر - مشابه Kotlin
  void saveUserBalances(String userId, Map<String, String> balances) {
    _userBalances[userId] = balances;
  }
  
  /// دریافت userId فعلی - مشابه Kotlin
  String getCurrentUserId() => _userId;

  Future<void> updateActiveTokensFromPreferences() async {
    _currencies = _currencies.map((token) {
      final isEnabled = tokenPreferences.getTokenStateFromParams(token.symbol ?? '', token.blockchainName ?? '', token.smartContractAddress) ?? false;
      return token.copyWith(isEnabled: isEnabled);
    }).toList();
    _activeTokens = _currencies.where((t) => t.isEnabled).toList();
    notifyListeners();
  }

  // --- متد کمکی برای قیمت توکن ---
  double getTokenPrice(String symbol, String currency) {
    final priceStr = _tokenPrices[symbol]?[currency]?.price;
    if (priceStr != null) {
      return double.tryParse(priceStr.replaceAll(',', '')) ?? 0.0;
    }
    return 0.0;
  }

  // --- مدیریت موجودی ---
  Future<Map<String, String>> fetchBalancesForActiveTokens() async {
    if (_userId.isEmpty || _activeTokens.isEmpty) return {};
    try {
      if (await WalletModePreferences.usesLocalBalanceOnly()) {
        final balancesMap =
            await OnChainBalanceService.instance.balancesForActiveTokens(
          _userId,
          _activeTokens,
        );
        if (balancesMap.isNotEmpty) {
          _userBalances[_userId] = balancesMap;
          await _updateTokensWithBalances(balancesMap);
          notifyListeners();
          return balancesMap;
        }
        print(
          '⚠️ TokenProvider - On-chain balances empty; not using custodial getBalance',
        );
        return _userBalances[_userId] ?? {};
      }
    } catch (e) {
      _errorMessage = 'Error fetching balances: ${e.toString()}';
      print('❌ TokenProvider - Error fetching balances: $e');
    }
    return {};
  }

  /// به‌روزرسانی موجودی کاربر با استفاده از API update-balance
  Future<bool> updateBalance() async {
    if (_userId.isEmpty) {
      _errorMessage = 'User ID is required for balance update';
      return false;
    }

    await fetchBalancesForActiveTokens();
    return true;
  }

  /// به‌روزرسانی موجودی فوری برای یک توکن خاص
  Future<bool> updateSingleTokenBalance(CryptoToken token) async {
    if (_userId.isEmpty) {
      _errorMessage = 'User ID is required for balance update';
      return false;
    }
    
    try {
      print('💰 TokenProvider - Updating balance for single token: ${token.symbol}');

      if (await WalletModePreferences.usesLocalBalanceOnly()) {
        final map = await OnChainBalanceService.instance.balancesForActiveTokens(
          _userId,
          [token],
        );
        final sym = token.symbol ?? '';
        final chain = token.blockchainName ?? '';
        final key = chain.isNotEmpty ? '${sym}_$chain' : sym;
        final raw = map[key] ?? map[sym];
        if (raw != null) {
          final balanceValue = double.tryParse(raw) ?? 0.0;
          final tokenIndex = _activeTokens.indexWhere(
            (t) =>
                t.symbol == token.symbol &&
                t.blockchainName == token.blockchainName &&
                t.smartContractAddress == token.smartContractAddress,
          );
          if (tokenIndex != -1) {
            _activeTokens[tokenIndex] =
                _activeTokens[tokenIndex].copyWith(amount: balanceValue);
          }
          notifyListeners();
          return true;
        }
        return false;
      }

      return false;
    } catch (e) {
      _errorMessage = 'Error fetching single token balance: ${e.toString()}';
      print('❌ TokenProvider - Error fetching single token balance: $e');
      return false;
    }
  }

  Future<void> _updateTokensWithBalances(Map<String, String> balances) async {
    print('🔍 TokenProvider - _updateTokensWithBalances called with ${balances.length} balances');
    // اگر هیچ بالانسی وجود ندارد، وضعیت فعلی را حفظ کن
    if (balances.isEmpty) {
      print('⚠️ TokenProvider - Empty balances map; skipping updates to preserve existing amounts');
      return;
    }
    print('🔍 TokenProvider - Available balances: $balances');
    print('🔍 TokenProvider - Current active tokens count: ${_activeTokens.length}');
    print('🔍 TokenProvider - Active tokens symbols: ${_activeTokens.map((t) => t.symbol).toList()}');
    print('🔍 TokenProvider - Current currencies count: ${_currencies.length}');
    print('🔍 TokenProvider - Currencies symbols: ${_currencies.map((t) => t.symbol).toList()}');
    
    // Update currencies: فقط نمادهای موجود در پاسخ را به‌روزرسانی کن
    _currencies = _currencies.map((token) {
      final tokenSymbol = token.symbol ?? '';
      if (!balances.containsKey(tokenSymbol)) {
        return token; // عدم تغییر اگر در پاسخ نیست
      }
      final balance = balances[tokenSymbol] ?? '0.0';
      final balanceDouble = double.tryParse(balance) ?? 0.0;
      print('   Currency: $tokenSymbol -> Balance: $balance (parsed: $balanceDouble)');
      return token.copyWith(amount: balanceDouble);
    }).toList();
    
    // Check for tokens with balance that are not in active tokens yet
    for (final balanceSymbol in balances.keys) {
      final balanceValue = balances[balanceSymbol] ?? '0.0';
      final balanceDouble = double.tryParse(balanceValue) ?? 0.0;
      
      if (balanceDouble > 0.0) {
        // Check if this token exists in active tokens
        final existsInActive = _activeTokens.any((token) => token.symbol == balanceSymbol);
        if (!existsInActive) {
          // Find token in currencies and add to active if enabled
          final currencyToken = _currencies.firstWhere(
            (token) => token.symbol == balanceSymbol,
            orElse: () => CryptoToken(
              name: balanceSymbol,
              symbol: balanceSymbol,
              blockchainName: 'Tron', // Default to Tron for NCC
              iconUrl: 'https://coinceeper.com/defaultIcons/coin.png',
              isEnabled: true,
              amount: 0.0,
              isToken: true,
            ),
          );
          
          print('   🔍 Found token in currencies: ${currencyToken.name} (${currencyToken.symbol})');
          
          // Check if token was manually disabled by user
          final isManuallyDisabled = await tokenPreferences.isTokenManuallyDisabled(
            currencyToken.symbol ?? '',
            currencyToken.blockchainName ?? '',
            currencyToken.smartContractAddress,
          );
          
          // Only auto-enable tokens with balance if they were not manually disabled
          final shouldAutoEnable = !isManuallyDisabled;
          final isEnabled = shouldAutoEnable;
          
          print('   🔄 Adding token with balance to active tokens: $balanceSymbol = $balanceDouble (enabled: $isEnabled, manually disabled: $isManuallyDisabled)');
          final newToken = currencyToken.copyWith(amount: balanceDouble, isEnabled: isEnabled);
          
          if (isEnabled) {
            _activeTokens.add(newToken);
          }
          
          // Also add to currencies if not exists
          final existsInCurrencies = _currencies.any((token) => token.symbol == balanceSymbol);
          if (!existsInCurrencies) {
            _currencies.add(newToken);
            print('   ✅ Added token to currencies list: $balanceSymbol');
          }
          
          // Save to preferences with current state (respecting manual disable)
          await tokenPreferences.saveTokenStateFromParams(
            currencyToken.symbol ?? '',
            currencyToken.blockchainName ?? '',
            currencyToken.smartContractAddress,
            isEnabled,
          );
        }
      }
    }
    
    // Update active tokens - ⚡ FIXED: Handle multi-chain tokens properly
    int updatedCount = 0;
    _activeTokens = _activeTokens.map((token) {
      final tokenSymbol = token.symbol ?? '';
      final tokenBlockchain = token.blockchainName ?? '';
      
      String? balance;
      
      // Try blockchain-specific key first (for multi-chain tokens like USDT)
      if (tokenBlockchain.isNotEmpty) {
        final blockchainKey = '${tokenSymbol}_$tokenBlockchain';
        if (balances.containsKey(blockchainKey)) {
          balance = balances[blockchainKey];
          print('   🔗 Found blockchain-specific balance for $tokenSymbol on $tokenBlockchain: $balance');
        }
      }
      
      // ⚡ SMART FALLBACK: Use legacy key intelligently
      if (balance == null) {
        // Use legacy key for backward compatibility
        if (balances.containsKey(tokenSymbol)) {
          balance = balances[tokenSymbol];
          
          // Check if this is a multi-chain token conflict
          final hasMultipleBlockchains = balances.keys.any((key) => 
            key.startsWith('${tokenSymbol}_') && key != '${tokenSymbol}_$tokenBlockchain'
          );
          
          if (hasMultipleBlockchains && tokenBlockchain.isNotEmpty) {
            // This is a multi-chain token without specific blockchain balance
            print('   ⚠️ Multi-chain token $tokenSymbol ($tokenBlockchain) has no specific balance, setting to 0');
            balance = '0.0';
          } else {
            // Safe to use legacy balance
            print('   📄 Found legacy balance for $tokenSymbol: $balance');
          }
        } else {
          print('   ⚠️ No balance found for $tokenSymbol ($tokenBlockchain), setting to 0');
          balance = '0.0';
        }
      }
      
      final balanceDouble = double.tryParse(balance ?? '0.0') ?? 0.0;
      if (balanceDouble > 0.0) {
        updatedCount++;
        print('   ✅ Active Token Updated: $tokenSymbol ($tokenBlockchain) -> Balance: $balance (parsed: $balanceDouble)');
      } else {
        print('   ⚪ Active Token Zero Balance: $tokenSymbol ($tokenBlockchain) -> Balance: $balance (parsed: $balanceDouble)');
      }
      return token.copyWith(amount: balanceDouble);
    }).toList();
    
    print('🔍 TokenProvider - Updated $updatedCount active tokens with positive balance');
    print('🔍 TokenProvider - Final active tokens: ${_activeTokens.map((t) => '${t.symbol}(${t.amount})').toList()}');
    
    // مرتب‌سازی مجدد بعد از به‌روزرسانی موجودی‌ها
    _activeTokens = sortTokensByDollarValue(_activeTokens);
    print('🔄 TokenProvider - Tokens sorted by balance and value');
  }

  // --- مرتب‌سازی توکن‌ها بر اساس موجودی و ارزش دلاری ---
  List<CryptoToken> sortTokensByDollarValue(List<CryptoToken> tokens) {
    return tokens.toList()..sort((a, b) {
      final aAmount = a.amount ?? 0.0;
      final bAmount = b.amount ?? 0.0;
      
      // اول: توکن‌های با موجودی > 0 در اول
      if (aAmount > 0 && bAmount == 0) return -1;
      if (aAmount == 0 && bAmount > 0) return 1;
      
      // دوم: اگر هر دو موجودی دارند، بر اساس ارزش دلاری sort کن
      if (aAmount > 0 && bAmount > 0) {
        final aPrice = getTokenPrice(a.symbol ?? '', 'USD');
        final bPrice = getTokenPrice(b.symbol ?? '', 'USD');
        final aValue = aAmount * aPrice;
        final bValue = bAmount * bPrice;
        final valueComparison = bValue.compareTo(aValue); // نزولی
        if (valueComparison != 0) return valueComparison;
      }
      
      // سوم: اگر هر دو موجودی ندارند، بر اساس نام sort کن
      return (a.symbol ?? '').compareTo(b.symbol ?? '');
    });
  }

  // --- مدیریت کاربر ---
  Future<void> updateUserId(String newUserId) async {
    if (_userId == newUserId) return;
    _userId = newUserId;
    tokenPreferences = TokenPreferences(userId: newUserId);
    final userTokens = _userTokens[newUserId];
    if (userTokens != null) {
      _currencies = userTokens;
      _activeTokens = userTokens.where((t) => t.isEnabled).toList();
    } else {
      await smartLoadTokens(forceRefresh: true);
    }
    final userBalances = _userBalances[newUserId];
    if (userBalances != null) {
      await _updateTokensWithBalances(userBalances);
    } else {
      // مطابق گزارش Kotlin: موجودی‌ها فقط بعد از import wallet فراخوانی می‌شوند
      print('ℹ️ TokenProvider: Skipping balance fetch in updateUserId - balances only fetched after wallet import');
    }
    notifyListeners();
  }

  // --- همگام‌سازی و force refresh ---
  Future<void> forceRefresh() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _fetchGasFees();
      await smartLoadTokens(forceRefresh: true);
      // مطابق گزارش Kotlin: موجودی‌ها فقط بعد از import wallet فراخوانی می‌شوند
      print('ℹ️ TokenProvider: Skipping balance fetch in forceRefresh - balances only fetched after wallet import');
      await fetchPrices();
      final sortedTokens = sortTokensByDollarValue(_activeTokens);
      _activeTokens = sortedTokens;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to refresh data: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// فعال کردن توکن‌های پیش‌فرض (BTC, ETH, TRX) بدون هیچ API call
  /// این متد برای جلوگیری از حلقه بی‌نهایت در زمان timeout API استفاده می‌شود
  Future<void> ensureDefaultTokensEnabled() async {
    if (_currencies.isEmpty) {
      print('⚠️ TokenProvider: No tokens loaded, cannot enable defaults');
      _isLoading = false;
      notifyListeners();
      return;
    }
    
    print('🔧 TokenProvider: Ensuring default tokens are enabled...');
    
    // نگاشت سمبل به blockchainName ترجیحی — فقط یک بار در هر سمبل فعال کن
    const defaultSymbols = ['BTC', 'ETH', 'TRX'];
    final Map<String, String> nativeBlockchains = {
      'BTC': 'Bitcoin',
      'ETH': 'Ethereum',
      'TRX': 'Tron',
    };
    
    // فعال‌شده‌ها را track کن — فقط اولین توکن واقعی هر سمبل فعال شود
    final enabledDefaults = <String>{};
    
    final updatedTokens = _currencies.map((token) {
      if (token.isEnabled) return token;
      
      final symbol = token.symbol?.toUpperCase() ?? '';
      if (!defaultSymbols.contains(symbol)) return token;
      
      // اگر قبلاً یکی با این سمبل فعال شده، رد شو
      if (enabledDefaults.contains(symbol)) return token;
      
      // فقط توکنی فعال شود که blockchainName طبیعی دارد
      final isNative = (token.blockchainName ?? '') == nativeBlockchains[symbol];
      if (!isNative) return token;
      
      print('🔧 TokenProvider: Enabling default token: $symbol (${token.blockchainName})');
      tokenPreferences.saveTokenStateFromParams(
        token.symbol ?? '',
        token.blockchainName ?? '',
        token.smartContractAddress,
        true,
      );
      enabledDefaults.add(symbol);
      return token.copyWith(isEnabled: true);
    }).toList();
    
    _currencies = updatedTokens;
    _activeTokens = updatedTokens.where((t) => t.isEnabled).toList();
    _userTokens[_userId] = updatedTokens;
    
    print('✅ TokenProvider: Default tokens enabled, ${_activeTokens.length} active tokens');
    
    _isLoading = false;
    notifyListeners();
  }

  /// اطمینان از همگام‌سازی کامل tokens - مشابه Kotlin
  Future<void> ensureTokensSynchronized() async {
    try {
      print('🔄 TokenProvider - Ensuring tokens are fully synchronized for user: $_userId');
      
      // 🍎 iOS Debug: بررسی وضعیت recovery قبل از شروع
      if (Platform.isIOS) {
        print('🍎 TokenProvider - iOS detected, checking recovery status...');
        // Debug functionality removed - method not available
      }
      
      // 1. اگر currencies خالی است، ابتدا از cache یا API بارگذاری کن
      if (_currencies.isEmpty) {
        print('📁 TokenProvider - Currencies is empty, loading from cache or API');
        final loaded = await _loadFromCache(await SharedPreferences.getInstance());
        if (!loaded) {
          print('📁 TokenProvider - No cache available, loading from API');
          await _loadFromApi(await SharedPreferences.getInstance());
        }
      }
      
      // ⚡ CRITICAL FIX: Ensure BTC/ETH/TRX are always in currencies list
      _currencies = _ensureDefaultTokensPresent(_currencies);
      
      // 2. همگام‌سازی کامل وضعیت tokens با preferences
      final updatedCurrencies = _currencies.map((token) {
        final isEnabled = tokenPreferences.getTokenStateFromParams(
          token.symbol ?? '', 
          token.blockchainName ?? '', 
          token.smartContractAddress
        ) ?? false;
        return token.copyWith(isEnabled: isEnabled);
      }).toList();
      
      _currencies = updatedCurrencies;
      
      // 3. به‌روزرسانی active tokens بر اساس preferences
      final enabledTokens = updatedCurrencies.where((t) => t.isEnabled).toList();
      
      // 4. اطمینان از وجود tokens پیش‌فرض اگر هیچ token فعال نیست
      if (enabledTokens.isEmpty) {
        print('⚠️ TokenProvider - No enabled tokens found, initializing defaults...');
        await _initializeDefaultTokens();
        
        // بررسی مجدد پس از اولیه‌سازی
        final reloadedCurrencies = _currencies.map((token) {
          final isEnabled = tokenPreferences.getTokenStateFromParams(
            token.symbol ?? '', 
            token.blockchainName ?? '', 
            token.smartContractAddress
          ) ?? (token.name == 'Bitcoin' || token.name == 'Ethereum' || token.name == 'Tron');
          return token.copyWith(isEnabled: isEnabled);
        }).toList();
        
        _currencies = reloadedCurrencies;
        final finalEnabledTokens = reloadedCurrencies.where((t) => t.isEnabled).toList();
        _activeTokens = finalEnabledTokens;
        
        print('✅ TokenProvider - Default tokens reinitialized: ${finalEnabledTokens.length} enabled');
      } else {
        _activeTokens = enabledTokens;
      }
      
      // 5. ذخیره user tokens
      _userTokens[_userId] = _currencies;
      
      print('✅ TokenProvider - Synchronization completed');
      print('✅ TokenProvider - Total currencies: ${_currencies.length}');
      print('✅ TokenProvider - Active tokens: ${_activeTokens.length}');
      print('✅ TokenProvider - Active list: ${_activeTokens.map((t) => '${t.name}(${t.symbol})').join(', ')}');
      
      // 6. بارگذاری قیمت‌ها برای tokens فعال
      if (_activeTokens.isNotEmpty) {
        await fetchPrices();
      }
      
      // 7. Notify listeners
      notifyListeners();
      
    } catch (e) {
      print('❌ TokenProvider - Error in synchronization: $e');
      _errorMessage = 'Error synchronizing tokens: ${e.toString()}';
      notifyListeners();
    }
  }

  /// اطمینان از وجود userId معتبر
  Future<void> _ensureValidUserId() async {
    if (_userId.isEmpty) {
      print('⚠️ TokenProvider: User ID is empty, trying to load from storage...');
      
      try {
        // Try to get from SharedPreferences (used by ApiService)
        final prefs = await SharedPreferences.getInstance();
        final sharedPrefsUserId = prefs.getString('UserID');
        
        if (sharedPrefsUserId != null && sharedPrefsUserId.isNotEmpty) {
          _userId = sharedPrefsUserId;
          print('✅ TokenProvider: Loaded user ID from SharedPreferences: $_userId');
          return;
        }
        
        // Try to get from SecureStorage
        final selectedUserId = await SecureStorage.instance.getSelectedUserId();
        if (selectedUserId != null && selectedUserId.isNotEmpty) {
          _userId = selectedUserId;
          print('✅ TokenProvider: Loaded user ID from SecureStorage: $_userId');
          return;
        }
        
        // Try to get from wallet list
        final wallets = await SecureStorage.instance.getWalletsList();
        if (wallets.isNotEmpty) {
          final firstWallet = wallets.first;
          final walletUserId = firstWallet['userID'];
          if (walletUserId != null && walletUserId.isNotEmpty) {
            _userId = walletUserId;
            print('✅ TokenProvider: Loaded user ID from wallet list: $_userId');
            return;
          }
        }
        
        print('❌ TokenProvider: Could not find valid user ID anywhere!');
        _userId = 'default_user'; // Fallback
        print('⚠️ TokenProvider: Using fallback user ID: $_userId');
        
      } catch (e) {
        print('❌ TokenProvider: Error loading user ID: $e');
        _userId = 'default_user'; // Fallback
        print('⚠️ TokenProvider: Using fallback user ID: $_userId');
      }
    }
  }

  // --- متدهای کمکی ---
  String? getAverageChange24h() {
    if (_activeTokens.isEmpty) return null;
    double totalChange = 0.0;
    int validCount = 0;
    for (final token in _activeTokens) {
      final priceData = _tokenPrices[token.symbol]?['USD'];
      if (priceData?.change24h != null) {
        final change = double.tryParse((priceData!.change24h ?? '').replaceAll('%', '')) ?? 0.0;
        totalChange += change;
        validCount++;
      }
    }
    if (validCount > 0) {
      final avg = totalChange / validCount;
      return '${avg >= 0 ? '+' : ''}${avg.toStringAsFixed(2)}%';
    }
    return null;
  }

  Future<String> ensureGasFee(String blockchainName) async {
    final currentFee = _gasFees[blockchainName];
    if (currentFee == null || currentFee == '0.0') {
      await _fetchGasFees();
      final updatedFee = _gasFees[blockchainName];
      if (updatedFee == null || updatedFee == '0.0') {
        return _getFallbackGasFee(blockchainName);
      }
      return updatedFee;
    }
    return currentFee;
  }

  String _getFallbackGasFee(String blockchainName) {
    switch (blockchainName) {
      case 'Ethereum': return '0.0012';
      case 'Bitcoin': return '0.0001';
      case 'Tron': return '0.00001';
      case 'Binance': return '0.0005';
      default: return '0.001';
    }
  }

  // --- متدهای باقیمانده ---
  Future<void> resetAllTokenStates() async {
    await tokenPreferences.clearAllTokenPreferences();
    final defaultTokens = ['Bitcoin', 'Ethereum'];
    for (final tokenName in defaultTokens) {
      await tokenPreferences.saveTokenStateFromParams(tokenName, tokenName, null, true);
    }
    _currencies = _currencies.map((token) {
      final isDefault = defaultTokens.contains(token.name);
      return token.copyWith(isEnabled: isDefault);
    }).toList();
    _activeTokens = _currencies.where((t) => t.isEnabled).toList();
    await fetchPrices();
    notifyListeners();
  }

  Future<void> updateTokenOrder(List<CryptoToken> newOrder) async {
    final sortedByValue = sortTokensByDollarValue(newOrder);
    _activeTokens = sortedByValue;
    await tokenPreferences.saveTokenOrder(sortedByValue.map((t) => t.symbol ?? '').toList());
    notifyListeners();
  }

  Future<void> refreshActiveTokens() async {
    final enabledTokens = _currencies.where((t) => t.isEnabled).toList();
    _activeTokens = enabledTokens;
    notifyListeners();
  }

  /// پاک کردن کامل cache و بارگذاری مجدد از API
  Future<void> clearCacheAndReload() async {
    try {
      print('🗑️ TokenProvider: Manual cache clear requested');
      final prefs = await SharedPreferences.getInstance();
      await _clearAllCache(prefs);
      
      // Force reload from API
      await smartLoadTokens(forceRefresh: true);
      
      // Notify all listeners of the change
      notifyListeners();
      
      print('✅ TokenProvider: Cache cleared and reloaded from API');
    } catch (e) {
      print('❌ Error in clearCacheAndReload: $e');
      _errorMessage = 'Error clearing cache: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Synchronized cache invalidation across all screens
  Future<void> invalidateAllCaches() async {
    try {
      print('🗑️ TokenProvider: Invalidating all caches globally');
      final prefs = await SharedPreferences.getInstance();
      
      // Remove all cache-related keys
      await _clearAllCache(prefs);
      
      // Clear add_token_screen cache key to trigger reload there
      await prefs.remove('add_token_cached_tokens');
      
      // Clear any other screen-specific cache keys
      final keys = prefs.getKeys().toList();
      for (final key in keys) {
        if (key.contains('cached') || key.contains('timestamp')) {
          await prefs.remove(key);
          print('🗑️ Removed global cache key: $key');
        }
      }
      
      // Reset internal state
      _currencies.clear();
      _activeTokens.clear();
      
      // Force fresh initialization
      await initializeInBackground();
      
      print('✅ TokenProvider: All caches invalidated and reinitialized');
    } catch (e) {
      print('❌ Error in invalidateAllCaches: $e');
      _errorMessage = 'Error invalidating caches: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Check if caches are synchronized between screens
  Future<bool> areCachesSynchronized() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check main cache
      final mainCacheExists = prefs.containsKey('cachedUserTokens_$_userId');
      final mainTimestamp = prefs.getInt('cache_timestamp_$_userId') ?? 0;
      
      // Check add_token cache key
      final addTokenCacheExists = prefs.containsKey('add_token_cached_tokens');
      
      print('🔍 Cache sync check: main=$mainCacheExists (ts: $mainTimestamp), addToken=$addTokenCacheExists');
      
      // If both exist or both don't exist, they're synchronized
      return mainCacheExists == addTokenCacheExists;
    } catch (e) {
      print('❌ Error checking cache synchronization: $e');
      return false;
    }
  }

  /// Ensure all caches are properly synchronized
  Future<void> ensureCacheSynchronization() async {
    try {
      final synchronized = await areCachesSynchronized();
      if (!synchronized) {
        print('⚠️ TokenProvider: Caches out of sync, synchronizing...');
        await invalidateAllCaches();
      } else {
        print('✅ TokenProvider: Caches are synchronized');
      }
    } catch (e) {
      print('❌ Error ensuring cache synchronization: $e');
    }
  }



  // --- متدهای debug ---
  void debugBalanceState() {
    print('=== DEBUG BALANCE STATE ===');
    print('User ID: $_userId');
    print('Active tokens count: ${_activeTokens.length}');
    print('Active tokens: ${_activeTokens.map((t) => '${t.symbol}(${t.amount})').join(', ')}');
    debugTokenAmounts();
  }

  void debugTokenAmounts() {
    print('=== CURRENT TOKEN AMOUNTS DEBUG ===');
    print('Active Tokens (${_activeTokens.length}):');
    for (int i = 0; i < _activeTokens.length; i++) {
      final token = _activeTokens[i];
      print('  [$i] ${token.symbol} (${token.name}): amount=${token.amount}');
    }
    print('Currencies List (${_currencies.length}):');
    for (int i = 0; i < _currencies.take(10).length; i++) {
      final token = _currencies[i];
      print('  [$i] ${token.symbol} (${token.name}): amount=${token.amount}, enabled=${token.isEnabled}');
    }
  }

  // --- متدهای utility ---
  List<String> getEnabledTokenNames() {
    return tokenPreferences.getAllEnabledTokenNames();
  }

  List<String> getEnabledTokenKeys() {
    return tokenPreferences.getAllEnabledTokenKeys();
  }

  Future<void> loadTokensWithBalance({bool forceRefresh = false}) async {
    _isLoading = true;
    notifyListeners();
    try {
      await smartLoadTokens(forceRefresh: forceRefresh);
      // مطابق گزارش Kotlin: موجودی‌ها فقط بعد از import wallet فراخوانی می‌شوند
      print('ℹ️ TokenProvider: Skipping balance fetch in loadTokensWithBalance - balances only fetched after wallet import');
      final tokensWithBalance = _activeTokens.where((t) => (t.amount ?? 0.0) > 0).toList();
      final sortedTokens = sortTokensByDollarValue(tokensWithBalance);
      _activeTokens = sortedTokens;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error loading tokens with balance: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateActiveTokens(List<CryptoToken> tokens) async {
    _activeTokens = tokens;
    _currencies = _currencies.map((currentToken) {
      final updatedToken = tokens.firstWhere((t) => t.name == currentToken.name, orElse: () => currentToken);
      return currentToken.copyWith(isEnabled: updatedToken.isEnabled);
    }).toList();
    await fetchPrices();
    notifyListeners();
  }

  Future<void> setActiveTokens(List<CryptoToken> newTokens) async {
    _activeTokens = newTokens;
    notifyListeners();
  }

  // --- متدهای کمکی برای مدیریت ترتیب ---
  List<CryptoToken> loadSavedTokenOrder(List<CryptoToken> tokens) {
    final List<String> savedOrder = tokenPreferences.getTokenOrder();
    if (savedOrder.isEmpty) return tokens;
    final tokenMap = {for (var t in tokens) '${t.symbol ?? ''}_${t.name ?? ''}': t};
    final orderedTokens = <CryptoToken>[];
    for (final symbol in savedOrder) {
      if (tokenMap.containsKey(symbol)) {
        orderedTokens.add(tokenMap[symbol]!);
      }
    }
    for (final token in tokens) {
      if (!orderedTokens.contains(token)) {
        orderedTokens.add(token);
      }
    }
    return orderedTokens;
  }

  Future<void> loadTokens() async {
    try {
      final tokens = await _getTokens();
      final orderedTokens = loadSavedTokenOrder(tokens);
      _activeTokens = orderedTokens;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Error loading tokens: ${e.toString()}';
    }
  }

  Future<List<CryptoToken>> _getTokens() async {
    try {
      final response = await apiService.getAllCurrencies();
      if (response.success) {
        return response.currencies.map<CryptoToken>((token) {
          final isEnabled = tokenPreferences.getTokenStateFromParams(token.symbol ?? '', token.blockchainName ?? '', token.smartContractAddress) ?? false;
          return CryptoToken(
            name: token.currencyName,
            symbol: token.symbol,
            blockchainName: token.blockchainName,
            iconUrl: token.icon ?? 'https://coinceeper.com/defaultIcons/coin.png',
            isEnabled: isEnabled,
            isToken: token.isToken ?? true,
            smartContractAddress: token.smartContractAddress,
          );
        }).toList();
      }
    } catch (e) {
      _errorMessage = 'Error getting tokens: ${e.toString()}';
    }
    return [];
  }



  // --- متدهای سازگاری با کد موجود ---
  void setAllTokens(List<CryptoToken> allTokens) {
    _currencies = allTokens;
    _activeTokens = allTokens.where((t) => t.isEnabled).toList();
    notifyListeners();
  }
  
  // متد جدید برای اطمینان از به‌روزرسانی فوری
  Future<void> forceUpdateTokenStates() async {
    print('🔄 Force updating token states...');
    
    // به‌روزرسانی وضعیت توکن‌ها از preferences
    _currencies = _currencies.map((token) {
      final isEnabled = tokenPreferences.getTokenStateFromParams(
        token.symbol ?? '', 
        token.blockchainName ?? '', 
        token.smartContractAddress
      ) ?? false;
      return token.copyWith(isEnabled: isEnabled);
    }).toList();
    
    // به‌روزرسانی توکن‌های فعال
    _activeTokens = _currencies.where((t) => t.isEnabled).toList();
    
    print('🔄 Force update - Active tokens: ${_activeTokens.map((t) => '${t.symbol}(${t.isEnabled})').join(', ')}');
    
    // ذخیره state به‌روزرسانی شده در cache
    await _saveToCache(await SharedPreferences.getInstance(), _currencies);

    // Persist active token keys per-wallet for restoration after app kill (FIXED for multi-chain)
    try {
      final currentWallet = await SecureStorage.instance.getSelectedWallet();
      final currentUser = await SecureStorage.instance.getSelectedUserId();
      if (currentWallet != null && currentUser != null) {
        // Create unique keys for each token including blockchain and contract address
        final activeTokenKeys = _activeTokens.map((t) {
          return tokenPreferences.getTokenKeyFromParams(
            t.symbol ?? '',
            t.blockchainName ?? '',
            t.smartContractAddress,
          );
        }).toList();
        
        await SecureStorage.instance.saveActiveTokenKeys(currentWallet, currentUser, activeTokenKeys);
        print('💾 TokenProvider: Persisted active token keys in SecureStorage (${activeTokenKeys.length})');
        
        // Also save legacy format for backward compatibility
        final activeSymbols = _activeTokens.map((t) => t.symbol ?? '').toList();
        await SecureStorage.instance.saveActiveTokens(currentWallet, currentUser, activeSymbols);
      }
    } catch (e) {
      print('⚠️ TokenProvider: Error persisting active token keys: $e');
    }
    
    // اگر توکن‌های فعال وجود دارند، قیمت‌ها را دریافت کن
    if (_activeTokens.isNotEmpty) {
      await fetchPrices();
    }
    
    notifyListeners();
  }

  /// iOS-specific: Recover token states from SecureStorage
  Future<void> _recoverTokenStatesFromSecureStorageIOS() async {
    if (!Platform.isIOS) return;
    
    try {
      print('🍎 TokenProvider: Attempting to recover token states from SecureStorage (iOS)...');
      
      // Force re-initialize TokenPreferences cache
      await tokenPreferences.initialize();
      
      // Get current currencies and update their states
      final updatedCurrencies = _currencies.map((token) {
        final isEnabled = tokenPreferences.getTokenStateFromParams(
          token.symbol ?? '', 
          token.blockchainName ?? '', 
          token.smartContractAddress
        );
        
        // If state found, update the token
        print('🍎 TokenProvider: Recovered iOS token state: ${token.symbol} = $isEnabled');
        return token.copyWith(isEnabled: isEnabled);
              
        return token;
      }).toList();
      
      _currencies = updatedCurrencies;
      _activeTokens = updatedCurrencies.where((t) => t.isEnabled).toList();
      
      print('🍎 TokenProvider: iOS recovery completed. Active tokens: ${_activeTokens.length}');
      
      notifyListeners();
    } catch (e) {
      print('❌ TokenProvider: Error recovering token states from SecureStorage (iOS): $e');
    }
  }

  /// iOS-specific: Handle app returning from background
  Future<void> handleiOSAppResume() async {
    if (!Platform.isIOS) return;
    
    try {
      print('🍎 TokenProvider: Handling iOS app resume...');
      
      // Re-synchronize token states in case they were lost
      await _recoverTokenStatesFromSecureStorageIOS();
      
      // Ensure synchronization
      await ensureTokensSynchronized();
      
      print('🍎 TokenProvider: iOS app resume handling completed');
    } catch (e) {
      print('❌ TokenProvider: Error handling iOS app resume: $e');
    }
  }
  
  /// ⚡ ANDROID FIX: Emergency initialization with only default tokens (no API calls)
  Future<void> initializeDefaultTokensOnly() async {
    try {
      print('🚨 ANDROID FIX: Emergency initialization with default tokens only');
      
      _isLoading = true;
      notifyListeners();
      
      // Ensure we have a valid userId
      await _ensureValidUserId();
      
      // Recreate TokenPreferences with correct userId
      tokenPreferences = TokenPreferences(userId: _userId);
      await tokenPreferences.initialize();
      
      // Initialize only default tokens (no API calls)
      await _initializeDefaultTokensQuickly();
      
      print('✅ ANDROID FIX: Emergency default tokens initialized');
      
    } catch (e) {
      print('❌ ANDROID FIX: Emergency initialization failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// ⚡ PRICE FIX: Ensure Bitcoin and Ethereum are enabled
  Future<void> ensureBitcoinEthereumEnabled() async {
    try {
      print('💰 TokenProvider: Ensuring Bitcoin and Ethereum are enabled...');
      
      bool needsUpdate = false;
      
      // Check for Bitcoin
      CryptoToken? btcToken = _activeTokens.where((t) => t.symbol?.toUpperCase() == 'BTC').firstOrNull;
      if (btcToken == null) {
        // Add Bitcoin token
        btcToken = const CryptoToken(
          symbol: 'BTC',
          name: 'Bitcoin',
          blockchainName: 'Bitcoin',
          isEnabled: true,
          amount: 0.0,
          isToken: false, // Bitcoin is a coin, not a token
        );
        _activeTokens.add(btcToken);
        needsUpdate = true;
        print('💰 TokenProvider: Added Bitcoin token');
      } else if (!btcToken.isEnabled) {
        // Create a new token with enabled=true since isEnabled is final
        final newBtcToken = btcToken.copyWith(isEnabled: true);
        final index = _activeTokens.indexOf(btcToken);
        _activeTokens[index] = newBtcToken;
        needsUpdate = true;
        print('💰 TokenProvider: Enabled Bitcoin token');
      }
      
      // Check for Ethereum
      CryptoToken? ethToken = _activeTokens.where((t) => t.symbol?.toUpperCase() == 'ETH').firstOrNull;
      if (ethToken == null) {
        // Add Ethereum token
        ethToken = const CryptoToken(
          symbol: 'ETH',
          name: 'Ethereum',
          blockchainName: 'Ethereum',
          isEnabled: true,
          amount: 0.0,
          isToken: false, // Ethereum is a coin, not a token
        );
        _activeTokens.add(ethToken);
        needsUpdate = true;
        print('💰 TokenProvider: Added Ethereum token');
      } else if (!ethToken.isEnabled) {
        // Create a new token with enabled=true since isEnabled is final
        final newEthToken = ethToken.copyWith(isEnabled: true);
        final index = _activeTokens.indexOf(ethToken);
        _activeTokens[index] = newEthToken;
        needsUpdate = true;
        print('💰 TokenProvider: Enabled Ethereum token');
      }
      
      if (needsUpdate) {
        notifyListeners();
        
        // Save the updated state using tokenPreferences
        try {
          for (final token in _activeTokens) {
            if (token.symbol != null) {
              await tokenPreferences.saveTokenStateFromParams(
                token.symbol!,
                token.blockchainName ?? '',
                token.smartContractAddress,
                token.isEnabled,
              );
            }
          }
          print('💰 TokenProvider: Saved updated token states');
        } catch (e) {
          print('❌ TokenProvider: Error saving token states: $e');
        }
      }
      
      print('✅ TokenProvider: Bitcoin and Ethereum are now enabled');
      
    } catch (e) {
      print('❌ TokenProvider: Error ensuring Bitcoin/Ethereum enabled: $e');
    }
  }
} 