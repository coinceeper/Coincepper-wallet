import 'package:flutter/material.dart';
import 'dart:ui' show TextDirection;
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/app_provider.dart';
import '../providers/price_provider.dart';
import '../models/crypto_token.dart';
import '../services/service_provider.dart';
import '../layout/main_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/wallet_state_manager.dart';
import 'dart:convert';
import 'dart:async';
import '../widgets/filter_widgets.dart';
import '../services/coinmarketcap_service_main.dart';
import 'package:flutter/services.dart';

class CustomSwitch extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool> onCheckedChange;

  const CustomSwitch({
    required this.checked,
    required this.onCheckedChange,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onCheckedChange(!checked),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: checked ? const Color(0xFF27B6AC) : Colors.grey,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: checked ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(2),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NetworkOption extends StatelessWidget {
  final String name;
  final String icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _NetworkOption({
    required this.name,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF11c699).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF11c699) : Colors.grey.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Image.asset(
              icon,
              width: 24,
              height: 24,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.language, size: 24, color: Colors.grey);
              },
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? const Color(0xFF11c699) : Colors.black,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF11c699),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class AddTokenScreen extends StatefulWidget {
  const AddTokenScreen({super.key});

  @override
  State<AddTokenScreen> createState() => _AddTokenScreenState();
}

class _AddTokenScreenState extends State<AddTokenScreen> {
  static List<CryptoToken>? _cachedTokens; // کش توکن‌ها
  String searchText = '';
  String selectedNetwork = 'All Blockchains';
  bool isLoading = false;
  bool refreshing = false;
  String? errorMessage;
  List<CryptoToken> allTokens = [];
  List<CryptoToken> filteredTokens = [];
  bool _needsRefresh = false; // فلگ برای تشخیص نیاز به refresh
  bool _isCheckingCache = false; // جلوگیری از حلقه بی‌نهایت didChangeDependencies
  int _typeCastRetryCount = 0; // جلوگیری از لوپ بی‌نهایت clear cache + retry
  static const int _maxTypeCastRetries = 1; // فقط یکبار مجاز به retry

  // Advanced filter options
  String _sortOption = 'marketcap'; // default: highest market cap first
  bool _showOnlyEnabled = false;
  bool _showOnlyTokens = false; // فقط tokens (نه coins)
  bool _showOnlyCoins = false; // فقط coins (نه tokens)
  final List<String> _selectedCategories = []; // DeFi, Meme, Gaming, etc.
  String _priceRange = 'all'; // 'all', 'low', 'mid', 'high'
  // Market cap cache for sorting
  final Map<String, double> _marketCaps = {};
  bool _marketCapsLoading = false;
  
  // ⚡ LAZY LOADING: Chunked display to prevent UI freezes
  static const int _pageSize = 50; // تعداد توکن در هر صفحه
  static const double _scrollThreshold = 300.0; // پیکسل مانده به انتها برای بارگذاری صفحه بعد
  int _displayedTokenCount = _pageSize; // تعداد توکن‌هایی که در حال نمایش هستند
  bool _isLoadingMore = false; // جلوگیری از درخواست‌های تکراری بارگذاری
  late ScrollController _scrollController;
  
  /// Getter: لیست توکن‌هایی که باید نمایش داده شوند (برش خورده)
  List<CryptoToken> get _displayedTokens {
    final count = _displayedTokenCount.clamp(0, filteredTokens.length);
    return filteredTokens.sublist(0, count);
  }
  
  /// Getter: آیا توکن‌های بیشتری برای بارگذاری وجود دارد؟
  bool get _hasMoreTokens => _displayedTokenCount < filteredTokens.length;
  
  /// Safe translation helper with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      print('⚠️ Translation error for key "$key": $e');
      return fallback;
    }
  }

  /// استاندارد سازی نام توکن‌های طولانی برای جلوگیری از خطای UI
  String _standardizeTokenName(String? name) {
    if (name == null || name.isEmpty) return '';
    
    // حداکثر طول مجاز برای نام توکن
    const int maxLength = 22;
    
    if (name.length <= maxLength) return name;
    
    // لیست کلمات غیرضروری که می‌توان حذف کرد
    final unnecessaryWords = [
      'Token', 'Coin', 'Protocol', 'Network', 'Chain', 'Finance', 
      'DeFi', 'Ecosystem', 'Platform', 'Project', 'Foundation',
      'Labs', 'DAO', 'Governance', 'Utility', 'Smart', 'Digital',
      'Crypto', 'Blockchain', 'Decentralized', 'Official', 'Classic',
      'Standard', 'Exchange', 'Trading', 'Market', 'Global', 'International'
    ];
    
    String standardized = name.trim();
    
    // حذف کلمات غیرضروری از انتها و ابتدا
    for (String word in unnecessaryWords) {
      // حذف از انتها (مثل "Bitcoin Token" -> "Bitcoin")
      standardized = standardized.replaceAll(RegExp(' $word\$', caseSensitive: false), '');
      // حذف از ابتدا (مثل "Token Bitcoin" -> "Bitcoin")  
      standardized = standardized.replaceAll(RegExp('^$word ', caseSensitive: false), '');
      // حذف در وسط اگر باعث کوتاه شدن می‌شود
      if (standardized.length > maxLength) {
        standardized = standardized.replaceAll(RegExp(' $word ', caseSensitive: false), ' ');
      }
    }
    
    // حذف فاصله‌های اضافی
    standardized = standardized.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    // اگر هنوز طولانی است، کوتاه کن
    if (standardized.length > maxLength) {
      // سعی کن در محل فاصله کوتاه کنی
      if (standardized.contains(' ')) {
        List<String> words = standardized.split(' ');
        String result = '';
        for (String word in words) {
          String temp = result.isEmpty ? word : '$result $word';
          if (temp.length <= maxLength - 3) {
            result = temp;
          } else {
            break;
          }
        }
        if (result.isNotEmpty) {
          return '$result...';
        }
      }
      
      // در غیر این صورت، کوتاه کن و ... اضافه کن
      return '${standardized.substring(0, maxLength - 3)}...';
    }
    
    return standardized;
  }

  /// استاندارد سازی سمبل توکن برای جلوگیری از خطای UI
  String _standardizeTokenSymbol(String? symbol) {
    if (symbol == null || symbol.isEmpty) return '';
    
    // حداکثر طول مجاز برای سمبل
    const int maxLength = 8;
    
    if (symbol.length <= maxLength) return symbol;
    
    // کوتاه کردن سمبل طولانی
    return symbol.substring(0, maxLength);
  }
  
  final List<Map<String, dynamic>> blockchains = [
    {'name': 'All Blockchains', 'icon': 'assets/images/all.png'},
    {'name': 'Bitcoin', 'icon': 'assets/images/btc.png'},
    {'name': 'Ethereum', 'icon': 'assets/images/ethereum_logo.png'},
    {'name': 'Binance Smart Chain', 'icon': 'assets/images/binance_logo.png'},
    {'name': 'Polygon', 'icon': 'assets/images/pol.png'},
    {'name': 'Tron', 'icon': 'assets/images/tron.png'},
    {'name': 'Arbitrum', 'icon': 'assets/images/arb.png'},
    {'name': 'XRP', 'icon': 'assets/images/xrp.png'},
    {'name': 'Avalanche', 'icon': 'assets/images/avax.png'},
    {'name': 'Polkadot', 'icon': 'assets/images/dot.png'},
    {'name': 'Solana', 'icon': 'assets/images/sol.png'},
  ];
  


  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // Load tokens after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTokens();
    });
    // یکبار cache invalidation را چک کن (بدون حلقه)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkCacheInvalidation();
    });
    // Attach scroll listener AFTER the first frame so controller is ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.addListener(_onScroll);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Already handled in initState via _loadTokens
  }

  /// ⚡ LAZY LOADING: تشخیص رسیدن به انتهای لیست برای بارگذاری صفحه بعد
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoadingMore || !_hasMoreTokens) return;
    
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    
    if (maxScroll - currentScroll <= _scrollThreshold) {
      _loadNextChunk();
    }
  }
  
  /// ⚡ LAZY LOADING: بارگذاری ۵۰ توکن بعدی
  Future<void> _loadNextChunk() async {
    if (_isLoadingMore || !_hasMoreTokens) return;
    
    setState(() {
      _isLoadingMore = true;
    });
    
    // Simulate a micro-delay to let the UI breathe before building more items
    await Future.delayed(const Duration(milliseconds: 16));
    
    if (!mounted) return;
    
    setState(() {
      _displayedTokenCount = (_displayedTokenCount + _pageSize).clamp(0, filteredTokens.length);
      _isLoadingMore = false;
    });
  }

  /// ⚡ LAZY LOADING: بازنشانی صفحه‌بندی بعد از تغییر فیلتر یا جستجو
  void _resetPagination() {
    _displayedTokenCount = _pageSize;
    _isLoadingMore = false;
  }

  /// بررسی invalidation کش و refresh در صورت نیاز
  Future<void> _checkCacheInvalidation() async {
    // جلوگیری از حلقه بی‌نهایت: اگر در حال بررسی هستیم، رد شو
    if (_isCheckingCache) {
      print('ℹ️ AddTokenScreen: Cache check already in progress, skipping');
      return;
    }
    _isCheckingCache = true;
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final tokenProvider = appProvider.tokenProvider;
      
      if (tokenProvider == null) {
        print('❌ AddTokenScreen: TokenProvider is null during cache check');
        return;
      }
      
      // Check if caches are synchronized using TokenProvider method
      final synchronized = await tokenProvider.areCachesSynchronized();
      
      if (!synchronized) {
        print('🔄 AddTokenScreen: Caches not synchronized, refreshing data...');
        _needsRefresh = true;
        _cachedTokens = null; // پاک کردن cache محلی
        
        // Force synchronization
        await tokenProvider.ensureCacheSynchronization();
        
        // اگر widget ساخته شده، refresh کن
        if (mounted) {
          await _loadTokens(forceRefresh: true);
        }
      } else {
        print('✅ AddTokenScreen: Caches are synchronized');
        
        // فقط TokenPreferences را initialize کن (بدون forceUpdateTokenStates
        // که notifyListeners صدا می‌زند و باعث حلقه بی‌نهایت می‌شود)
        if (mounted) {
          await tokenProvider.tokenPreferences.initialize();
          // به‌جای forceUpdateTokenStates، مستقیماً از TokenProvider.currencies بخوان
          final freshTokens = tokenProvider.currencies;
          if (freshTokens.isNotEmpty && mounted) {
            setState(() {
              allTokens = List<CryptoToken>.from(freshTokens);
              _filterTokens();
            });
          }
        }
      }
    } catch (e) {
      print('❌ AddTokenScreen: Error checking cache invalidation: $e');
    } finally {
      _isCheckingCache = false;
    }
  }

  /// اعتبارسنجی حالت ماندگاری توکن‌ها
  Future<void> _validateTokenPersistence() async {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final tokenProvider = appProvider.tokenProvider;
      
      if (tokenProvider == null) {
        print('❌ TokenProvider is null - cannot validate persistence');
        return;
      }
      
      // اطمینان از مقداردهی اولیه TokenPreferences
      await tokenProvider.tokenPreferences.initialize();
      
      // بررسی اینکه آیا cache مقداردهی اولیه شده است
      // if (!tokenProvider.tokenPreferences.isCacheInitialized) { // Property not available in utils TokenPreferences
      //   print('⚠️ TokenPreferences cache not initialized - refreshing...');
      //   await tokenProvider.tokenPreferences.refreshCache();
      // }
      
      // بررسی اینکه آیا state توکن‌ها از SharedPreferences load شده‌اند
      final enabledTokenKeys = tokenProvider.tokenPreferences.getAllEnabledTokenKeys();
      print('✅ Persistence validation: Found ${enabledTokenKeys.length} enabled tokens in storage');
      
      // Force update token states from preferences
      await tokenProvider.forceUpdateTokenStates();
      
    } catch (e) {
      print('❌ Error validating token persistence: $e');
    }
  }

  String get _translatedSelectedNetwork {
    if (selectedNetwork == 'All Blockchains') {
      return _safeTranslate('select_network', 'Select Network');
    }
    return selectedNetwork;
  }

  /// بارگذاری توکن‌ها - مشابه Kotlin
  Future<void> _loadTokens({bool forceRefresh = false}) async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final tokenProvider = appProvider.tokenProvider;
      
      if (tokenProvider == null) {
        setState(() {
          errorMessage = _safeTranslate('token provider not available', 'Token provider not available');
          isLoading = false;
        });
        return;
      }

      print('🔄 AddTokenScreen: Loading tokens for user: ${tokenProvider.getCurrentUserId()}');

      // 1. اطمینان از مقداردهی اولیه TokenPreferences
      await tokenProvider.tokenPreferences.initialize();
      
      // 2. همگام‌سازی tokens - مشابه Kotlin
      await tokenProvider.ensureTokensSynchronized();
      
      // 3. اگر force refresh است یا cache معتبر نیست، از API بارگذاری کن
      if (forceRefresh) {
        print('🔄 AddTokenScreen: Force refresh requested, loading from API');
        await tokenProvider.smartLoadTokens(forceRefresh: true);
      }
      
      // 4. دریافت tokens از TokenProvider
      final tokens = tokenProvider.currencies;
      
      if (tokens.isNotEmpty) {
        print('✅ AddTokenScreen: Loaded ${tokens.length} tokens from TokenProvider');
        
        // به‌روزرسانی cache
        _cachedTokens = List<CryptoToken>.from(tokens);
        
        setState(() {
          allTokens = tokens;
          _filterTokens();
          _resetPagination();
          isLoading = false;
        });
        // Load market caps in background for sorting (will resort when loaded)
        _loadMarketCapsForTokens(tokens);
        
        // ذخیره cache key
        await _saveCacheKey();
        
        print('✅ AddTokenScreen: Tokens loaded and UI updated');
        return;
      }
      
      // 5. اگر هیچ token وجود نداشت، خطا نمایش بده
      print('⚠️ AddTokenScreen: No tokens found');
      setState(() {
        errorMessage = _safeTranslate('no tokens found', 'No tokens found');
        isLoading = false;
      });
      
    } catch (e) {
      print('❌ AddTokenScreen: Error loading tokens: $e');
      
      // Enhanced error handling for different error types
      if (e.toString().contains('type \'String\' is not a subtype of type \'bool') ||
          e.toString().contains('type \'int\' is not a subtype of type \'bool') ||
          e.toString().contains('type casting') ||
          e.toString().contains('subtype')) {
        _typeCastRetryCount++;
        if (_typeCastRetryCount > _maxTypeCastRetries) {
          print('🚫 AddTokenScreen: Max type cast retries ($_maxTypeCastRetries) exceeded');
          setState(() {
            errorMessage = _safeTranslate('data format error', 'Data format error. Please restart the app.');
            isLoading = false;
          });
          return;
        }
        print('🔄 AddTokenScreen: Type casting error detected (attempt $_typeCastRetryCount/$_maxTypeCastRetries), clearing cache...');
        try {
          final appProvider = Provider.of<AppProvider>(context, listen: false);
          final tokenProvider = appProvider.tokenProvider;
          
          if (tokenProvider != null) {
            // Clear cache and force reload from API
            await tokenProvider.clearCacheAndReload();
            
            // Wait a moment for the reload to complete
            await Future.delayed(const Duration(milliseconds: 500));
            
            // Try again after cache clear
            final tokens = tokenProvider.currencies;
            if (tokens.isNotEmpty) {
              setState(() {
                allTokens = tokens;
                _filterTokens();
                _resetPagination();
                isLoading = false;
                errorMessage = null;
              });
              await _saveCacheKey();
              print('✅ AddTokenScreen: Successfully loaded after cache clear');
              return;
            } else {
              print('⚠️ AddTokenScreen: No tokens available even after cache clear, forcing API reload...');
              // Force another API call
              await tokenProvider.smartLoadTokens(forceRefresh: true);
              
              final freshTokens = tokenProvider.currencies;
              if (freshTokens.isNotEmpty) {
                setState(() {
                  allTokens = freshTokens;
                  _filterTokens();
                  isLoading = false;
                  errorMessage = null;
                });
                await _saveCacheKey();
                print('✅ AddTokenScreen: Successfully loaded after forced API reload');
                return;
              }
            }
          }
        } catch (retryError) {
          print('❌ AddTokenScreen: Error even after cache clear and retry: $retryError');
        }
      }
      
      // Provide user-friendly error messages
      String userFriendlyError;
      if (e.toString().contains('SocketException') || e.toString().contains('NetworkException')) {
        userFriendlyError = _safeTranslate('network error', 'Network connection error. Please check your internet connection.');
      } else if (e.toString().contains('TimeoutException')) {
        userFriendlyError = _safeTranslate('timeout error', 'Request timeout. Please try again.');
      } else if (e.toString().contains('FormatException') || e.toString().contains('type casting')) {
        userFriendlyError = _safeTranslate('data format error', 'Data format error. Please pull down to refresh.');
      } else {
        userFriendlyError = '${_safeTranslate('error loading tokens', 'Error loading tokens')}: ${e.toString().length > 100 ? e.toString().substring(0, 100) + '...' : e.toString()}';
      }
      
      setState(() {
        errorMessage = userFriendlyError;
        isLoading = false;
      });
    }
  }

  /// ذخیره cache key برای همگام‌سازی با home screen
  Future<void> _saveCacheKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setString('add_token_cached_tokens', timestamp);
      
      // Get userId from TokenProvider
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final tokenProvider = appProvider.tokenProvider;
      if (tokenProvider != null) {
        final userId = tokenProvider.getCurrentUserId();
        // Also update the main cache timestamp to keep them in sync
        await prefs.setInt('cache_timestamp_$userId', DateTime.now().millisecondsSinceEpoch);
      }
      
      print('✅ AddTokenScreen: Cache key saved for synchronization (timestamp: $timestamp)');
    } catch (e) {
      print('❌ AddTokenScreen: Error saving cache key: $e');
    }
  }

  /// Clear cache key to trigger refresh in other screens
  Future<void> _clearCacheKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('add_token_cached_tokens');
      print('✅ AddTokenScreen: Cache key cleared');
    } catch (e) {
      print('❌ AddTokenScreen: Error clearing cache key: $e');
    }
  }

  /// تازه‌سازی توکن‌ها - مشابه Kotlin
  Future<void> _refreshTokens() async {
    setState(() => refreshing = true);
    
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final tokenProvider = appProvider.tokenProvider;
      
      if (tokenProvider == null) {
        print('❌ AddTokenScreen: TokenProvider is null during refresh');
        return;
      }
      
      print('🔄 AddTokenScreen: Refreshing tokens for user: ${tokenProvider.getCurrentUserId()}');
      
      // 1. پاک کردن cache محلی
      _cachedTokens = null;
      
      // 2. Force refresh از TokenProvider - مشابه Kotlin
      await tokenProvider.forceRefresh();
      
      // 3. بارگذاری مجدد tokens
      await _loadTokens(forceRefresh: true);
      
      // 4. ذخیره cache key
      await _saveCacheKey();
      
      print('✅ AddTokenScreen: Tokens refreshed successfully');
      
    } catch (e) {
      print('❌ AddTokenScreen: Error refreshing tokens: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در تازه‌سازی توکن‌ها: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => refreshing = false);
    }
  }

  /// Debug: بررسی وضعیت persistence توکن‌ها
  Future<void> _debugTokenPersistence() async {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final tokenProvider = appProvider.tokenProvider;
      
      if (tokenProvider == null) {
        print('❌ Debug: TokenProvider is null');
        return;
      }
      
      print('=== TOKEN PERSISTENCE DEBUG ===');
      // print('Cache initialized: ${tokenProvider.tokenPreferences.isCacheInitialized}'); // Property not available in utils TokenPreferences
      
      final enabledTokenKeys = tokenProvider.tokenPreferences.getAllEnabledTokenKeys();
      print('Enabled tokens in storage: ${enabledTokenKeys.length}');
      
      final enabledTokenNames = tokenProvider.tokenPreferences.getAllEnabledTokenNames();
      print('Enabled token names: $enabledTokenNames');
      
      final enabledTokens = tokenProvider.enabledTokens;
      print('Enabled tokens in TokenProvider: ${enabledTokens.length}');
      print('Enabled tokens list: ${enabledTokens.map((t) => '${t.symbol}(${t.isEnabled})').join(', ')}');
      
      // Test a few tokens
      if (allTokens.isNotEmpty) {
        for (int i = 0; i < allTokens.take(3).length; i++) {
          final token = allTokens[i];
          // Use services/TokenPreferences API (3-param sync method)
          final storedState = tokenProvider.tokenPreferences.getTokenStateFromParams(
            token.symbol ?? '',
            token.blockchainName ?? '',
            token.smartContractAddress,
          );
          final syncState = tokenProvider.tokenPreferences.getTokenStateFromParams(
            token.symbol ?? '',
            token.blockchainName ?? '',
            token.smartContractAddress,
          );
          print('Token ${token.symbol}: current=${token.isEnabled}, stored=$storedState, sync=$syncState');
        }
      }
      
      print('=== END DEBUG ===');
    } catch (e) {
      print('❌ Error in debug token persistence: $e');
    }
  }

  void _filterTokens() {
    var tokens = allTokens.where((token) {
      // استفاده از نام استاندارد شده برای جستجوی بهتر
      final standardizedName = _standardizeTokenName(token.name);
      final standardizedSymbol = _standardizeTokenSymbol(token.symbol);
      
      final matchesSearch = searchText.isEmpty ||
          (token.name ?? '').toLowerCase().contains(searchText.toLowerCase()) ||
          (token.symbol ?? '').toLowerCase().contains(searchText.toLowerCase()) ||
          standardizedName.toLowerCase().contains(searchText.toLowerCase()) ||
          standardizedSymbol.toLowerCase().contains(searchText.toLowerCase());
      
      final matchesNetwork = selectedNetwork == 'All Blockchains' ||
          token.blockchainName == selectedNetwork;
      
      // Advanced filters
      final matchesEnabled = !_showOnlyEnabled || token.isEnabled;
      final matchesTokenType = (!_showOnlyTokens || (token.isToken == true)) &&
                              (!_showOnlyCoins || (token.isToken == false));

      return matchesSearch && matchesNetwork && matchesEnabled && matchesTokenType;
    }).toList();
    
    // Apply sorting با استفاده از نام‌های استاندارد شده
    switch (_sortOption) {
      case 'name':
        tokens.sort((a, b) {
          final nameA = _standardizeTokenName(a.name).isNotEmpty 
              ? _standardizeTokenName(a.name) 
              : _standardizeTokenSymbol(a.symbol);
          final nameB = _standardizeTokenName(b.name).isNotEmpty 
              ? _standardizeTokenName(b.name) 
              : _standardizeTokenSymbol(b.symbol);
          return nameA.toLowerCase().compareTo(nameB.toLowerCase());
        });
        break;
      case 'marketcap':
        // Sort by market cap DESC (fallback to standardized name if unavailable)
        tokens.sort((a, b) {
          final capA = _marketCaps[(a.symbol ?? '').toUpperCase()] ?? -1;
          final capB = _marketCaps[(b.symbol ?? '').toUpperCase()] ?? -1;
          if (capA != capB) return capB.compareTo(capA);
          final nameA = _standardizeTokenName(a.name).isNotEmpty 
              ? _standardizeTokenName(a.name) 
              : _standardizeTokenSymbol(a.symbol);
          final nameB = _standardizeTokenName(b.name).isNotEmpty 
              ? _standardizeTokenName(b.name) 
              : _standardizeTokenSymbol(b.symbol);
          return nameA.toLowerCase().compareTo(nameB.toLowerCase());
        });
        break;
      case 'price':
        // Sort by price (if available, otherwise by standardized name)
        tokens.sort((a, b) {
          final nameA = _standardizeTokenName(a.name).isNotEmpty 
              ? _standardizeTokenName(a.name) 
              : _standardizeTokenSymbol(a.symbol);
          final nameB = _standardizeTokenName(b.name).isNotEmpty 
              ? _standardizeTokenName(b.name) 
              : _standardizeTokenSymbol(b.symbol);
          return nameA.toLowerCase().compareTo(nameB.toLowerCase());
        });
        break;
      case 'volume':
        // Sort by volume (if available, otherwise by standardized name)
        tokens.sort((a, b) {
          final nameA = _standardizeTokenName(a.name).isNotEmpty 
              ? _standardizeTokenName(a.name) 
              : _standardizeTokenSymbol(a.symbol);
          final nameB = _standardizeTokenName(b.name).isNotEmpty 
              ? _standardizeTokenName(b.name) 
              : _standardizeTokenSymbol(b.symbol);
          return nameA.toLowerCase().compareTo(nameB.toLowerCase());
        });
        break;
    }
    
    filteredTokens = tokens;
    _resetPagination();
  }

  /// Load market caps for a list of tokens and re-sort when complete
  /// Uses batch API to minimize network calls
  Future<void> _loadMarketCapsForTokens(List<CryptoToken> tokens) async {
    if (_marketCapsLoading) return;
    _marketCapsLoading = true;
    try {
      // Collect unique symbols that haven't been cached yet
      final symbols = tokens
          .map((t) => t.symbol ?? '')
          .where((s) => s.isNotEmpty)
          .toSet()
          .where((s) => !_marketCaps.containsKey(s.toUpperCase()))
          .toList();
      
      if (symbols.isEmpty) {
        _marketCapsLoading = false;
        return;
      }
      
      print('📊 Loading market caps for ${symbols.length} tokens (batch mode)...');
      
      // ⚡ BATCH: Use the new batch API instead of per-token calls
      final batchResults = await CoinMarketCapService.getPricesBatch(symbols);
      
      for (final entry in batchResults.entries) {
        final cap = entry.value.marketCap ?? 0.0;
        _marketCaps[entry.key.toUpperCase()] = cap;
      }
      
      print('✅ Market caps loaded for ${batchResults.length}/${symbols.length} symbols');
      
      // Re-sort by market cap once loaded
      if (mounted) {
        setState(() {
          if (_sortOption == 'marketcap') {
            _filterTokens();
          }
        });
      }
    } catch (e) {
      print('⚠️ AddTokenScreen: Error loading market caps: $e');
    } finally {
      _marketCapsLoading = false;
    }
  }

  void _showNetworkModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF11c699).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.language,
                      color: Color(0xFF11c699),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _safeTranslate('select_network', 'Select Network'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            ),
            
            // Network options
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: blockchains.map((blockchain) => _NetworkOption(
                    name: blockchain['name'] == 'All Blockchains' 
                        ? _safeTranslate('select_network', 'Select Network')
                        : blockchain['name'],
                    icon: blockchain['icon'],
                    isSelected: selectedNetwork == blockchain['name'],
                    onTap: () {
                      setState(() {
                        selectedNetwork = blockchain['name'];
                      });
                      _filterTokens();
                      Navigator.pop(context);
                    },
                  )).toList(),
                ),
              ),
            ),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
  
  /// بررسی وجود فیلترهای فعال
  bool _hasActiveFilters() {
    return _showOnlyEnabled || 
           _showOnlyTokens || 
           _showOnlyCoins || 
           _selectedCategories.isNotEmpty ||
           _priceRange != 'all';
  }
  
  /// ساخت چیپ‌های فیلتر فعال
  Widget _buildFilterChips() {
    List<Widget> chips = [];
    
    if (_showOnlyEnabled) {
      chips.add(_buildFilterChip(
        label: 'فعال شده',
        onDeleted: () {
          setState(() => _showOnlyEnabled = false);
          _filterTokens();
        },
      ));
    }
    
    if (_showOnlyTokens) {
      chips.add(_buildFilterChip(
        label: 'فقط توکن ها',
        onDeleted: () {
          setState(() => _showOnlyTokens = false);
          _filterTokens();
        },
      ));
    }
    
    if (_showOnlyCoins) {
      chips.add(_buildFilterChip(
        label: 'فقط کوین ها',
        onDeleted: () {
          setState(() => _showOnlyCoins = false);
          _filterTokens();
        },
      ));
    }
    
    for (String category in _selectedCategories) {
      chips.add(_buildFilterChip(
        label: category,
        onDeleted: () {
          setState(() => _selectedCategories.remove(category));
          _filterTokens();
        },
      ));
    }
    
    if (_priceRange != 'all') {
      String label = _priceRange == 'low' ? 'قیمت پایین' : 
                    _priceRange == 'mid' ? 'قیمت متوسط' : 'قیمت بالا';
      chips.add(_buildFilterChip(
        label: label,
        onDeleted: () {
          setState(() => _priceRange = 'all');
          _filterTokens();
        },
      ));
    }
    
    if (chips.isEmpty) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips,
      ),
    );
  }
  
  Widget _buildFilterChip({required String label, required VoidCallback onDeleted}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF11c699).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF11c699), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF11c699),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onDeleted,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Color(0xFF11c699),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// نمایش گزینه‌های مرتب سازی
  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF11c699).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.sort,
                      color: Color(0xFF11c699),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _safeTranslate('sort by', 'Sort by'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            ),
            
            // Sort options
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  _SortOption(
                    title: _safeTranslate('name', 'Name'),
                    subtitle: _safeTranslate('alphabetical az', 'A-Z alphabetical'),
                    value: 'name',
                    currentValue: _sortOption,
                    onChanged: (value) {
                      setState(() => _sortOption = value);
                      _filterTokens();
                      Navigator.pop(context);
                    },
                  ),
                  _SortOption(
                    title: _safeTranslate('market cap', 'Market Cap'),
                    subtitle: _safeTranslate('highest first', 'Highest first'),
                    value: 'marketcap',
                    currentValue: _sortOption,
                    onChanged: (value) {
                      setState(() => _sortOption = value);
                      _filterTokens();
                      Navigator.pop(context);
                    },
                  ),
                  _SortOption(
                    title: _safeTranslate('price', 'Price'),
                    subtitle: _safeTranslate('highest price', 'Highest price'),
                    value: 'price',
                    currentValue: _sortOption,
                    onChanged: (value) {
                      setState(() => _sortOption = value);
                      _filterTokens();
                      Navigator.pop(context);
                    },
                  ),
                  _SortOption(
                    title: _safeTranslate('trading volume', 'Trading Volume'),
                    subtitle: _safeTranslate('highest volume', 'Highest volume'),
                    value: 'volume',
                    currentValue: _sortOption,
                    onChanged: (value) {
                      setState(() => _sortOption = value);
                      _filterTokens();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
  
  /// Widget گزینه مرتب‌سازی شبیه home screen
  Widget _SortOption({
    required String title,
    required String subtitle,
    required String value,
    required String currentValue,
    required ValueChanged<String> onChanged,
  }) {
    final isSelected = value == currentValue;
    
    return InkWell(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF11c699).withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF11c699) : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? const Color(0xFF11c699) : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? const Color(0xFF11c699) : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF11c699),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  
  /// نمایش فیلترهای پیشرفته
  void _showAdvancedFilters() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF11c699).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.tune,
                        color: Color(0xFF11c699),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _safeTranslate('advanced filters', 'Advanced Filters'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setModalState(() {
                          _showOnlyEnabled = false;
                          _showOnlyTokens = false;
                          _showOnlyCoins = false;
                          _selectedCategories.clear();
                          _priceRange = 'all';
                        });
                        setState(() {});
                        _filterTokens();
                      },
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: Text(_safeTranslate('clear all', 'Clear All')),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF11c699),
                        textStyle: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Token Status with modern design
                      _buildAdvancedFilterSection(
                        title: _safeTranslate('token status', 'Token Status'),
                        icon: Icons.toggle_on,
                        child: Column(
                          children: [
                            _buildModernToggleOption(
                              title: _safeTranslate('show only enabled tokens', 'Show Only Enabled Tokens'),
                              subtitle: _safeTranslate('tokens you have enabled', 'Tokens you have enabled'),
                              value: _showOnlyEnabled,
                              onChanged: (value) {
                                setModalState(() => _showOnlyEnabled = value);
                                setState(() {});
                                _filterTokens();
                              },
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Token Type with visual cards
                      _buildAdvancedFilterSection(
                        title: _safeTranslate('asset type', 'Asset Type'),
                        icon: Icons.category,
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildTypeCard(
                                title: _safeTranslate('tokens', 'Tokens'),
                                subtitle: 'ERC-20, BEP-20',
                                icon: Icons.toll,
                                isSelected: _showOnlyTokens,
                                onTap: () {
                                  setModalState(() {
                                    _showOnlyTokens = !_showOnlyTokens;
                                    if (_showOnlyTokens) _showOnlyCoins = false;
                                  });
                                  setState(() {});
                                  _filterTokens();
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildTypeCard(
                                title: _safeTranslate('coins', 'Coins'),
                                subtitle: _safeTranslate('native currencies', 'Native currencies'),
                                icon: Icons.monetization_on,
                                isSelected: _showOnlyCoins,
                                onTap: () {
                                  setModalState(() {
                                    _showOnlyCoins = !_showOnlyCoins;
                                    if (_showOnlyCoins) _showOnlyTokens = false;
                                  });
                                  setState(() {});
                                  _filterTokens();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Categories with enhanced chips
                      _buildAdvancedFilterSection(
                        title: _safeTranslate('categories', 'Categories'),
                        icon: Icons.apps,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            'DeFi', 'Meme', 'Gaming', 'NFT', 'Metaverse', 'Layer 2', 'Stablecoin'
                          ].map((category) => _buildEnhancedCategoryChip(
                            label: category,
                            isSelected: _selectedCategories.contains(category),
                            onTap: () {
                              setModalState(() {
                                if (_selectedCategories.contains(category)) {
                                  _selectedCategories.remove(category);
                                } else {
                                  _selectedCategories.add(category);
                                }
                              });
                              setState(() {});
                              _filterTokens();
                            },
                          )).toList(),
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
              
              // Apply Button
              Container(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF11c699),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _safeTranslate('apply filters', 'Apply Filters'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildAdvancedFilterSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF11c699)),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
  
  Widget _buildModernToggleOption({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: value ? const Color(0xFF11c699).withOpacity(0.1) : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? const Color(0xFF11c699) : Colors.grey.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: value ? const Color(0xFF11c699) : const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF11c699),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
  
  Widget _buildTypeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF11c699).withOpacity(0.1) : Colors.grey.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF11c699) : Colors.grey.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF11c699) : Colors.grey.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 24,
                color: isSelected ? Colors.white : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? const Color(0xFF11c699) : const Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            if (isSelected)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFF11c699),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 12,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEnhancedCategoryChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected 
              ? const LinearGradient(
                  colors: [Color(0xFF11c699), Color(0xFF0F9B84)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : Colors.grey.withOpacity(0.3),
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: const Color(0xFF11c699).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              const Icon(
                Icons.check_circle,
                size: 16,
                color: Colors.white,
              ),
            if (isSelected) const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }
  


  void _onSearchChanged(String value) {
    setState(() {
      searchText = value;
      _filterTokens();
      _resetPagination();
    });
  }

  void _onNetworkSelected(String network) {
    setState(() {
      selectedNetwork = network;
      _filterTokens();
      _resetPagination();
    });
  }

  /// Toggle کردن وضعیت توکن - مشابه Kotlin
  Future<void> _toggleToken(CryptoToken token) async {
    try {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      final tokenProvider = appProvider.tokenProvider;
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      
      if (tokenProvider == null) {
        print('❌ AddTokenScreen: TokenProvider is null');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_safeTranslate('token provider not available', 'Token provider not available')),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      final newState = !token.isEnabled;
      print('🔄 AddTokenScreen: Toggle token ${token.symbol}: ${token.isEnabled} -> $newState');
      
      // ⚡ IMMEDIATE: Strong vibration feedback at the start for instant response
      try {
        HapticFeedback.heavyImpact(); // قوی‌ترین ویبره فوری
        print('✅ Immediate strong vibration feedback triggered');
      } catch (e) {
        print('⚠️ Could not trigger immediate vibration: $e');
      }

      // Show loading indicator for this specific token
      setState(() {
        // Temporarily update UI to show the toggle is in progress
        final tokenIndex = allTokens.indexWhere((t) => 
          t.symbol == token.symbol && 
          t.blockchainName == token.blockchainName &&
          t.smartContractAddress == token.smartContractAddress
        );
        
        if (tokenIndex != -1) {
          allTokens[tokenIndex] = allTokens[tokenIndex].copyWith(isEnabled: newState);
        }
        
        final filteredIndex = filteredTokens.indexWhere((t) => 
          t.symbol == token.symbol && 
          t.blockchainName == token.blockchainName &&
          t.smartContractAddress == token.smartContractAddress
        );
        
        if (filteredIndex != -1) {
          filteredTokens[filteredIndex] = filteredTokens[filteredIndex].copyWith(isEnabled: newState);
        }
      });
      
      try {
        // 1. مستقیماً از TokenProvider برای toggle استفاده کن
        await tokenProvider.toggleToken(token, newState);
        
        // 2. یک کمی صبر کن تا state ذخیره شود
        await Future.delayed(const Duration(milliseconds: 200));
        
        // 3. تأیید اینکه state درست ذخیره شده است
        final verifyState = tokenProvider.isTokenEnabled(token);
        if (verifyState != newState) {
          print('❌ AddTokenScreen: Token state verification failed for ${token.symbol}, retrying...');
          // تلاش مجدد برای ذخیره
          await tokenProvider.saveTokenStateForUser(token, newState);
          await Future.delayed(const Duration(milliseconds: 100));
          
          // بررسی مجدد
          final retryVerifyState = tokenProvider.isTokenEnabled(token);
          if (retryVerifyState != newState) {
            throw Exception('Token state could not be saved after retry');
          }
          print('🔄 AddTokenScreen: Token state saved after retry for ${token.symbol}');
        } else {
          print('✅ AddTokenScreen: Token state verified for ${token.symbol}: $newState');
        }
        
        // 4. به‌روزرسانی cache
        if (_cachedTokens != null) {
          final cacheIndex = _cachedTokens!.indexWhere((t) => 
            t.symbol == token.symbol && 
            t.blockchainName == token.blockchainName &&
            t.smartContractAddress == token.smartContractAddress
          );
          
          if (cacheIndex != -1) {
            _cachedTokens![cacheIndex] = _cachedTokens![cacheIndex].copyWith(isEnabled: newState);
          }
        }
        
        // 5. در صورت فعال بودن توکن، قیمت و موجودی fetch کن
        if (newState) {
          print('✅ AddTokenScreen: Token ${token.symbol} activated - fetching price and balance');
          
          // Fetch price in background
          final symbols = [token.symbol ?? ''];
          priceProvider.fetchPrices(symbols).catchError((e) {
            print('⚠️ AddTokenScreen: Error fetching price for ${token.symbol}: $e');
          });
                  
          // Fetch balance in background
          _fetchSingleTokenBalance(token, tokenProvider).catchError((e) {
            print('⚠️ AddTokenScreen: Error fetching balance for ${token.symbol}: $e');
          });
        }
        
        // 6. ذخیره cache key برای synchronization
        await _saveCacheKey();

        // 6.5 Persist per-wallet active tokens for fast restoration after app kill
        // FIXED: Save complete token keys instead of just symbols to handle multi-chain tokens correctly
        try {
          final walletName = appProvider.currentWalletName;
          final userId = appProvider.currentUserId;
          if (walletName != null && userId != null) {
            // Create unique keys for each token including blockchain and contract address
            final activeTokenKeys = tokenProvider.enabledTokens.map((t) {
              return tokenProvider.tokenPreferences.getTokenKeyFromParams(
                t.symbol ?? '',
                t.blockchainName ?? '',
                t.smartContractAddress,
              );
            }).toList();
            
            await WalletStateManager.instance.saveActiveTokenKeysForWallet(
              walletName,
              userId,
              activeTokenKeys,
            );
            print('💾 Persisted ${activeTokenKeys.length} active token keys for wallet $walletName');
            print('🔍 Active token keys: ${activeTokenKeys.take(3).join(', ')}...');
          }
        } catch (persistError) {
          print('⚠️ Could not persist active token keys to WalletStateManager: $persistError');
        }
        
        print('✅ AddTokenScreen: Token ${token.symbol} toggled successfully');
        
      } catch (toggleError) {
        print('❌ AddTokenScreen: Error in toggle operation for ${token.symbol}: $toggleError');
        
        // Revert UI state on error
        setState(() {
          final tokenIndex = allTokens.indexWhere((t) => 
            t.symbol == token.symbol && 
            t.blockchainName == token.blockchainName &&
            t.smartContractAddress == token.smartContractAddress
          );
          
          if (tokenIndex != -1) {
            allTokens[tokenIndex] = allTokens[tokenIndex].copyWith(isEnabled: !newState);
          }
          
          final filteredIndex = filteredTokens.indexWhere((t) => 
            t.symbol == token.symbol && 
            t.blockchainName == token.blockchainName &&
            t.smartContractAddress == token.smartContractAddress
          );
          
          if (filteredIndex != -1) {
            filteredTokens[filteredIndex] = filteredTokens[filteredIndex].copyWith(isEnabled: !newState);
          }
        });
        
        rethrow; // Re-throw to be caught by outer catch
      }
      
    } catch (e) {
      print('❌ AddTokenScreen: Error toggling token ${token.symbol}: $e');
      // نمایش خطا به کاربر
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_safeTranslate('error toggle token', 'Error changing token state: ${e.toString()}')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// دریافت موجودی فوری برای یک توکن خاص
  Future<void> _fetchSingleTokenBalance(CryptoToken token, tokenProvider) async {
    try {
      print('💰 Fetching balance for ${token.symbol}...');
      
      // فراخوانی update موجودی برای توکن خاص
      await tokenProvider.updateSingleTokenBalance(token);
      
      print('✅ Balance fetched for ${token.symbol}');
    } catch (e) {
      print('❌ Error fetching balance for ${token.symbol}: $e');
    }
  }

  /// دریافت قیمت فوری برای یک توکن خاص
  Future<void> _fetchSingleTokenPrice(CryptoToken token, PriceProvider priceProvider) async {
    try {
      print('💲 Fetching price for ${token.symbol}...');
      
      final symbol = token.symbol ?? '';
      if (symbol.isNotEmpty) {
        await priceProvider.fetchPrices([symbol]);
      }
      
      print('✅ Price fetched for ${token.symbol}');
    } catch (e) {
      print('❌ Error fetching price for ${token.symbol}: $e');
    }
  }

  /// Refresh همه توکن‌های فعال در background
  Future<void> _refreshAllEnabledTokens(tokenProvider, PriceProvider priceProvider) async {
    try {
      print('🔄 Background refresh of all enabled tokens...');
      
      final enabledTokens = tokenProvider.enabledTokens;
      if (enabledTokens.isEmpty) return;
      
      // موازی: دریافت موجودی‌ها و قیمت‌ها
      await Future.wait<void>([
        // مطابق گزارش Kotlin: موجودی‌ها فقط بعد از import wallet فراخوانی می‌شوند
        Future<void>.value(), // placeholder برای Future.wait
        // دریافت قیمت‌های همه توکن‌ها
        _fetchPricesForEnabledTokens(enabledTokens, priceProvider),
      ]);
      
      print('✅ Background refresh completed');
    } catch (e) {
      print('❌ Error in background refresh: $e');
    }
  }

  /// دریافت قیمت‌ها برای توکن‌های فعال
  Future<void> _fetchPricesForEnabledTokens(List<CryptoToken> tokens, PriceProvider priceProvider) async {
    if (tokens.isEmpty) return;
    
    final symbols = tokens.map((t) => t.symbol ?? '').where((s) => s.isNotEmpty).toList();
    
    if (symbols.isNotEmpty) {
      // دریافت قیمت برای ارزهای مختلف
      const currencies = ['USD', 'EUR', 'GBP', 'CAD', 'AUD'];
      await priceProvider.fetchPrices(symbols, currencies: currencies);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              title: Text(
                _safeTranslate('token management', 'Token Management'),
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              iconTheme: const IconThemeData(color: Colors.black),
            ),
            body: RefreshIndicator(
              onRefresh: _refreshTokens,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // ═══════════════════════════════════════
                  // HEADER SECTION — search, filters, network picker
                  // ═══════════════════════════════════════
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Search bar with filter icons
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0x25757575),
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.search, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          decoration: InputDecoration(
                                            hintText: _safeTranslate('search', 'Search'),
                                            border: InputBorder.none,
                                            isDense: true,
                                          ),
                                          onChanged: _onSearchChanged,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilterIconButton(
                                icon: Icons.sort_by_alpha,
                                tooltip: 'مرتب سازی',
                                onTap: () => _showSortOptions(),
                                isActive: _sortOption != 'name',
                              ),
                              const SizedBox(width: 8),
                              FilterIconButton(
                                icon: Icons.tune,
                                tooltip: 'فیلترهای پیشرفته',
                                onTap: () => _showAdvancedFilters(),
                                isActive: _hasActiveFilters(),
                              ),
                            ],
                          ),
                          
                          // Filter chips
                          if (_hasActiveFilters()) ...[
                            const SizedBox(height: 8),
                            _buildFilterChips(),
                          ],
                          
                          const SizedBox(height: 8),
                          // Blockchain Filter Chips
                          BlockchainFilterChips(
                            selectedBlockchain: selectedNetwork,
                            blockchains: blockchains.map((b) => b['name'] as String).toList(),
                            blockchainIcons: Map.fromEntries(
                              blockchains
                                  .where((b) => b['name'] != 'All Blockchains')
                                  .map((b) => MapEntry(b['name'] as String, b['icon'] as String)),
                            ),
                            onChanged: (chain) {
                              setState(() => selectedNetwork = chain);
                              _filterTokens();
                              _resetPagination();
                            },
                            selectedColor: const Color(0xFF11c699),
                            allLabel: _safeTranslate('select_network', 'All Blockchains'),
                          ),
                          
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _safeTranslate('cryptocurrencies', 'Cryptocurrencies'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xCB838383),
                                ),
                              ),
                              Text(
                                '${filteredTokens.length} ${_safeTranslate('cryptos', 'Cryptos')}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xCB838383),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  
                  // ═══════════════════════════════════════
                  // CONTENT SECTION — loading / error / empty / token list
                  // ═══════════════════════════════════════
                  if (isLoading)
                    // Loading state — fills remaining space
                    SliverFillRemaining(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Text(_safeTranslate('loading', 'Loading...')),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (errorMessage != null)
                    // Error state — fills remaining space
                    SliverFillRemaining(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error, color: Colors.red, size: 48),
                              const SizedBox(height: 16),
                              Text(
                                errorMessage!,
                                style: const TextStyle(color: Colors.red),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadTokens,
                                child: Text(_safeTranslate('try again', 'Try Again')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (filteredTokens.isEmpty)
                    // Empty state — fills remaining space
                    SliverFillRemaining(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _safeTranslate('no tokens found', 'No tokens found'),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    )
                  else ...[
                    // ✅ LAZY TOKEN LIST — only visible items are built
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final token = _displayedTokens[index];
                          final isEnabled = token.isEnabled;
                          
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _TokenItem(
                              token: token,
                              isEnabled: isEnabled,
                              onToggle: () async {
                                await _toggleToken(token);
                              },
                            ),
                          );
                        },
                        childCount: _displayedTokens.length,
                      ),
                    ),
                    
                    // ⚡ Loading more indicator at bottom
                    if (_isLoadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF11c699),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    
                    // ✅ Bottom padding for safe area + scroll trigger indicator
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 100),
                        child: _hasMoreTokens
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    _safeTranslate('scroll for more', '↓ Scroll for more'),
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TokenItem extends StatelessWidget {
  final CryptoToken token;
  final bool isEnabled;
  final VoidCallback onToggle;

  const _TokenItem({
    required this.token,
    required this.isEnabled,
    required this.onToggle,
  });

  /// استاندارد سازی نام توکن‌های طولانی برای جلوگیری از خطای UI
  String _standardizeTokenName(String? name) {
    if (name == null || name.isEmpty) return '';
    
    // حداکثر طول مجاز برای نام توکن
    const int maxLength = 20;
    
    if (name.length <= maxLength) return name;
    
    // لیست کلمات غیرضروری که می‌توان حذف کرد
    final unnecessaryWords = [
      'Token', 'Coin', 'Protocol', 'Network', 'Chain', 'Finance', 
      'DeFi', 'Ecosystem', 'Platform', 'Project', 'Foundation',
      'Labs', 'DAO', 'Governance', 'Utility', 'Smart', 'Digital',
      'Crypto', 'Blockchain', 'Decentralized'
    ];
    
    String standardized = name;
    
    // حذف کلمات غیرضروری
    for (String word in unnecessaryWords) {
      standardized = standardized.replaceAll(RegExp(' $word\$', caseSensitive: false), '');
      standardized = standardized.replaceAll(RegExp('^$word ', caseSensitive: false), '');
    }
    
    // اگر هنوز طولانی است، کوتاه کن
    if (standardized.length > maxLength) {
      // سعی کن در محل فاصله کوتاه کنی
      if (standardized.contains(' ')) {
        List<String> words = standardized.split(' ');
        String result = '';
        for (String word in words) {
          if (('$result $word').length <= maxLength) {
            result = result.isEmpty ? word : '$result $word';
          } else {
            break;
          }
        }
        if (result.isNotEmpty && result.length <= maxLength - 3) {
          return '$result...';
        }
      }
      
      // در غیر این صورت، کوتاه کن و ... اضافه کن
      return '${standardized.substring(0, maxLength - 3)}...';
    }
    
    return standardized;
  }

  /// استاندارد سازی سمبل توکن برای جلوگیری از خطای UI
  String _standardizeTokenSymbol(String? symbol) {
    if (symbol == null || symbol.isEmpty) return '';
    
    // حداکثر طول مجاز برای سمبل
    const int maxLength = 8;
    
    if (symbol.length <= maxLength) return symbol;
    
    // کوتاه کردن سمبل طولانی
    return symbol.substring(0, maxLength);
  }

  @override
  Widget build(BuildContext context) {
    // استاندارد سازی نام و سمبل توکن
    final standardizedName = _standardizeTokenName(token.name);
    final standardizedSymbol = _standardizeTokenSymbol(token.symbol);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Token icon
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: (token.iconUrl ?? '').startsWith('http')
                    ? Image.network(
                        token.iconUrl ?? '',
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.currency_bitcoin, size: 28, color: Colors.orange);
                        },
                      )
                    : (token.iconUrl ?? '').startsWith('assets/')
                        ? Image.asset(token.iconUrl ?? '', width: 40, height: 40, fit: BoxFit.contain)
                        : const Icon(Icons.currency_bitcoin, size: 28, color: Colors.orange),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Token info با layout بهبود یافته
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name and Symbol in same line with proper styling
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    // Token name with tooltip for full name
                    Flexible(
                      child: Tooltip(
                        message: token.name ?? '',
                        child: Text(
                          standardizedName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Color(0xFF1A1A1A),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Token symbol with grey color
                    Text(
                      standardizedSymbol,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Blockchain name with improved styling
                Text(
                  token.blockchainName ?? '',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Custom Switch
          CustomSwitch(
            checked: isEnabled,
            onCheckedChange: (_) => onToggle(),
          ),
        ],
      ),
    );
  }
}

