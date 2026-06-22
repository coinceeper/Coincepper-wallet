import 'package:shared_preferences/shared_preferences.dart';
import '../models/crypto_token.dart';
import '../utils/secure_log.dart';

/// مدیریت تنظیمات توکن‌ها (معادل TokenPreferences.kt در اندروید)
///
/// 🏦 Wallet-Scoped Architecture:
/// هر کیف پول (wallet) تنظیمات توکن مجزای خود را دارد.
/// کلیدها به صورت زیر scoped می‌شوند:
///   token_preferences_{walletName}_{userId}_{symbol}_{blockchain}_{contract}
/// این کار تضمین می‌کند که فعال/غیرفعال کردن توکن در Wallet A
/// روی Wallet B تأثیر نمی‌گذارد.
class TokenPreferences {
  final String userId;
  final String walletName;
  late SharedPreferences _prefs;
  static const String _prefsPrefix = 'token_preferences_';

  // کلید ترتیب توکن‌ها — per-wallet
  String get _tokenOrderKey => 'token_order_${walletName}_$userId';

  // Prfix مورد استفاده برای کلیدهای cache — per-wallet
  String get _walletPrefsPrefix => '$_prefsPrefix${walletName}_${userId}_';

  // کش داخلی برای کاهش فراخوانی‌های SharedPreferences
  Map<String, bool>? _enabledTokensCache;
  int _lastCacheTime = 0;
  static const int _cacheValidityPeriod = 5 * 60 * 1000; // 5 دقیقه

  TokenPreferences({required this.userId, required this.walletName});

  /// مقداردهی اولیه
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _initializeDefaultTokens();
    _loadEnabledTokensCache();
  }

  /// مقداردهی توکن‌های پیش‌فرض (فقط اولین بار برای این Wallet)
  void _initializeDefaultTokens() {
    final defaults = [
      getTokenKeyFromParams('BTC', 'Bitcoin', null),
      getTokenKeyFromParams('ETH', 'Ethereum', null),
      getTokenKeyFromParams('TRX', 'Tron', null),
    ];
    bool anyNew = false;
    for (final key in defaults) {
      if (!_prefs.containsKey(key)) {
        _prefs.setBool(key, true);
        _enabledTokensCache ??= <String, bool>{};
        _enabledTokensCache![key] = true;
        anyNew = true;
      }
    }
    if (anyNew) {
      SecureLog.i('TokenPreferences: Default tokens initialized');
    }
  }

  /// بارگذاری کش داخلی — فقط کلیدهای مربوط به این Wallet
  void _loadEnabledTokensCache() {
    final allKeys = _prefs.getKeys();
    _enabledTokensCache = <String, bool>{};
    
    final walletPrefix = _walletPrefsPrefix;
    for (final key in allKeys) {
      if (key.startsWith(walletPrefix)) {
        _enabledTokensCache![key] = _prefs.getBool(key) ?? false;
      }
    }
    
    _lastCacheTime = DateTime.now().millisecondsSinceEpoch;
  }

  /// بررسی اعتبار کش داخلی
  bool _isCacheValid() {
    return _enabledTokensCache != null && 
           (DateTime.now().millisecondsSinceEpoch - _lastCacheTime) < _cacheValidityPeriod;
  }

  /// تولید کلید منحصر به فرد برای هر توکن (شامل SmartContractAddress)
  String getTokenKey(CryptoToken token) {
    return _scopedKey(token.symbol ?? '', token.blockchainName ?? 'Unknown', token.smartContractAddress);
  }

  /// تولید کلید منحصر به فرد با پارامترهای جداگانه
  String getTokenKeyFromParams(String symbol, String blockchainName, String? contract) {
    return _scopedKey(symbol, blockchainName, contract);
  }

  /// کلید نهایی: token_preferences_{walletName}_{userId}_{symbol}_{blockchain}_{contract}
  /// این فرمت تضمین می‌کند که هر Wallet فضای نام جداگانه‌ای دارد.
  String _scopedKey(String symbol, String blockchainName, String? contract) {
    final bc = (blockchainName.isEmpty || blockchainName == 'null') ? 'Unknown' : blockchainName;
    final normalized = "${symbol}_${bc}_${contract ?? ""}";
    return "$_walletPrefsPrefix$normalized";
  }

  /// ذخیره ترتیب توکن‌ها — per-wallet
  Future<void> saveTokenOrder(List<String> tokenOrder) async {
    final orderString = tokenOrder.join(",");
    await _prefs.setString(_tokenOrderKey, orderString);
  }

  /// دریافت ترتیب توکن‌ها — per-wallet
  List<String> getTokenOrder() {
    final orderString = _prefs.getString(_tokenOrderKey) ?? "";
    if (orderString.isEmpty) {
      return [];
    }
    return orderString.split(",");
  }

  /// ذخیره وضعیت توکن با کلید کامل
  Future<void> saveTokenState(String tokenKey, bool isEnabled) async {
    await _prefs.setBool(tokenKey, isEnabled);
    _enabledTokensCache?[tokenKey] = isEnabled;
  }

  /// ذخیره وضعیت توکن با پارامترهای جداگانه
  Future<void> saveTokenStateFromParams(String symbol, String blockchainName, String? contract, bool isEnabled, {bool isManualToggle = false}) async {
    final key = getTokenKeyFromParams(symbol, blockchainName, contract);
    await _prefs.setBool(key, isEnabled);
    _enabledTokensCache?[key] = isEnabled;
    
    // Track manual disable state if needed
    if (isManualToggle && !isEnabled) {
      await _saveManuallyDisabledState(symbol, blockchainName, contract, true);
    } else if (isManualToggle && isEnabled) {
      await _saveManuallyDisabledState(symbol, blockchainName, contract, false);
    }
  }

  /// ذخیره وضعیت توکن با استفاده از CryptoToken
  Future<void> saveTokenStateFromToken(CryptoToken token, bool isEnabled) async {
    final key = getTokenKey(token);
    await _prefs.setBool(key, isEnabled);
    _enabledTokensCache?[key] = isEnabled;
  }

  /// دریافت وضعیت توکن با کلید کامل
  bool getTokenState(String tokenKey) {
    // استفاده از کش داخلی اگر معتبر است
    if (_isCacheValid() && _enabledTokensCache?.containsKey(tokenKey) == true) {
      return _enabledTokensCache![tokenKey] ?? false;
    }
    // Try scoped key first
    bool? isEnabled = _prefs.getBool(tokenKey);
    // Fallback: اگر کلید wallet-scoped پیدا نشد، کلید قدیمی userId-only را چک کن
    if (isEnabled == null) {
      final legacyKey = tokenKey.replaceFirst(_walletPrefsPrefix, "");
      isEnabled = _prefs.getBool(legacyKey);
    }
    final result = isEnabled ?? false;
    _enabledTokensCache ??= <String, bool>{};
    _enabledTokensCache![tokenKey] = result;
    return result;
  }

  /// نگاشت سمبل به blockchainName طبیعی — برای fallback در کش‌های قدیمی
  static const Map<String, String> _knownBlockchains = {
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

  /// دریافت وضعیت توکن با پارامترهای جداگانه
  bool getTokenStateFromParams(String symbol, String blockchainName, String? contract) {
    // تلاش اول با blockchainName داده شده
    final key = getTokenKeyFromParams(symbol, blockchainName, contract);
    final result = getTokenState(key);
    if (result) return true;
    
    // Fallback: اگر blockchainName خالی/Unknown/Other است (از CoinGecko API)، با نگاشت طبیعی امتحان کن
    final isGenericBlockchain = blockchainName.isEmpty ||
        blockchainName == 'Unknown' ||
        blockchainName == 'Other';
    if (isGenericBlockchain) {
      final mappedBc = _knownBlockchains[symbol.toUpperCase()];
      if (mappedBc != null) {
        final fallbackKey = getTokenKeyFromParams(symbol, mappedBc, contract);
        final fallbackResult = getTokenState(fallbackKey);
        if (fallbackResult) return true;
      }
    }
    
    // Fallback: اگر blockchainName پر است، با Unknown امتحان کن
    if (blockchainName.isNotEmpty && !isGenericBlockchain) {
      final fallbackKey = getTokenKeyFromParams(symbol, 'Unknown', contract);
      final fallbackResult = getTokenState(fallbackKey);
      if (fallbackResult) return true;
    }
    
    return result;
  }

  /// دریافت وضعیت توکن - در صورت عدم وجود کلید، null برمی‌گرداند
  bool? getTokenStateOrNull(String symbol, String blockchainName, String? contract) {
    final key = getTokenKeyFromParams(symbol, blockchainName, contract);
    
    // استفاده از کش داخلی اگر معتبر است
    if (_isCacheValid() && _enabledTokensCache?.containsKey(key) == true) {
      return _enabledTokensCache![key];
    }
    
    // Try scoped key first
    if (_prefs.containsKey(key)) return _prefs.getBool(key);
    
    // Fallback: اگر کلید wallet-scoped پیدا نشد، کلید قدیمی userId-only را چک کن
    final legacyKey = key.replaceFirst(_walletPrefsPrefix, "");
    if (_prefs.containsKey(legacyKey)) return _prefs.getBool(legacyKey);
    
    return null; // never saved — caller decides fallback
  }

  /// دریافت وضعیت توکن با استفاده از CryptoToken
  bool getTokenStateFromToken(CryptoToken token) {
    final key = getTokenKey(token);
    return getTokenState(key);
  }

  /// دریافت تمام کلیدهای توکن‌های فعال — فقط برای این Wallet
  List<String> getAllEnabledTokenKeys() {
    if (!_isCacheValid()) {
      _loadEnabledTokensCache();
    }
    
    final walletPrefix = _walletPrefsPrefix;
    return _enabledTokensCache?.entries
        .where((entry) => entry.value && entry.key.startsWith(walletPrefix))
        .map((entry) => entry.key)
        .toList() ?? [];
  }

  /// دریافت تمام نام‌های توکن‌های فعال
  List<String> getAllEnabledTokenNames() {
    return getAllEnabledTokenKeys();
  }

  /// دریافت تمام توکن‌های فعال از لیست کامل
  List<CryptoToken> getAllEnabledTokens(List<CryptoToken> allTokens) {
    final enabledKeys = getAllEnabledTokenKeys();
    return allTokens.map((token) {
      final key = getTokenKey(token);
      return token.copyWith(isEnabled: enabledKeys.contains(key));
    }).where((token) => token.isEnabled).toList();
  }

  /// فعال کردن توکن
  Future<void> enableToken(CryptoToken token) async {
    await saveTokenStateFromToken(token, true);
  }

  /// غیرفعال کردن توکن
  Future<void> disableToken(CryptoToken token) async {
    await saveTokenStateFromToken(token, false);
  }

  /// تغییر وضعیت توکن (toggle)
  Future<void> toggleTokenState(CryptoToken token) async {
    final currentState = getTokenStateFromToken(token);
    await saveTokenStateFromToken(token, !currentState);
  }

  /// بررسی اینکه آیا توکن فعال است یا نه
  bool isTokenEnabled(CryptoToken token) {
    return getTokenStateFromToken(token);
  }

  /// دریافت تعداد توکن‌های فعال
  int getEnabledTokenCount() {
    return getAllEnabledTokenKeys().length;
  }

  /// Save manually disabled state
  Future<void> _saveManuallyDisabledState(String symbol, String blockchainName, String? contract, bool isManuallyDisabled) async {
    try {
      final key = '${getTokenKeyFromParams(symbol, blockchainName, contract)}_manual_disabled';
      await _prefs.setBool(key, isManuallyDisabled);
      SecureLog.i('Manual disable state saved: $symbol = $isManuallyDisabled');
    } catch (e) {
      SecureLog.e('Error saving manual disable state', error: e);
    }
  }

  /// Check if token was manually disabled by user
  Future<bool> isTokenManuallyDisabled(String symbol, String blockchainName, String? contract) async {
    try {
      final key = '${getTokenKeyFromParams(symbol, blockchainName, contract)}_manual_disabled';
      return _prefs.getBool(key) ?? false;
    } catch (e) {
      SecureLog.e('Error checking manual disable state', error: e);
      return false;
    }
  }

  /// پاک کردن تمام تنظیمات توکن‌ها — فقط برای این Wallet
  Future<void> clearAllTokenPreferences() async {
    final walletPrefix = _walletPrefsPrefix;
    final allKeys = _prefs.getKeys();
    for (final key in allKeys) {
      if (key.startsWith(walletPrefix) || key == _tokenOrderKey) {
        await _prefs.remove(key);
      }
    }
    _enabledTokensCache?.clear();
  }

  /// دریافت توکن‌های فعال بر اساس بلاکچین
  List<CryptoToken> getEnabledTokensByBlockchain(List<CryptoToken> allTokens, String blockchainName) {
    final enabledTokens = getAllEnabledTokens(allTokens);
    return enabledTokens.where((token) => (token.blockchainName ?? 'Unknown') == blockchainName).toList();
  }

  /// ذخیره ترتیب توکن‌ها بر اساس لیست CryptoToken
  Future<void> saveTokenOrderFromTokens(List<CryptoToken> tokens) async {
    final tokenKeys = tokens.map((token) => getTokenKey(token)).toList();
    await saveTokenOrder(tokenKeys);
  }

  /// دریافت ترتیب توکن‌ها به صورت CryptoToken
  List<CryptoToken> getTokenOrderAsTokens(List<CryptoToken> allTokens) {
    final orderKeys = getTokenOrder();
    final orderedTokens = <CryptoToken>[];
    
    for (final key in orderKeys) {
      final token = allTokens.firstWhere(
        (token) => getTokenKey(token) == key,
        orElse: () => allTokens.first,
      );
      orderedTokens.add(token);
    }
    
    return orderedTokens;
  }

  /// به‌روزرسانی وضعیت چندین توکن همزمان
  Future<void> updateMultipleTokenStates(Map<CryptoToken, bool> tokenStates) async {
    for (final entry in tokenStates.entries) {
      await saveTokenStateFromToken(entry.key, entry.value);
    }
  }

  /// دریافت آمار توکن‌ها
  Map<String, dynamic> getTokenStatistics(List<CryptoToken> allTokens) {
    final enabledTokens = getAllEnabledTokens(allTokens);
    final totalTokens = allTokens.length;
    final enabledCount = enabledTokens.length;
    
    final blockchainGroups = <String, int>{};
    for (final token in enabledTokens) {
      final blockchainName = token.blockchainName ?? 'Unknown';
      blockchainGroups[blockchainName] = (blockchainGroups[blockchainName] ?? 0) + 1;
    }
    
    return {
      'totalTokens': totalTokens,
      'enabledTokens': enabledCount,
      'disabledTokens': totalTokens - enabledCount,
      'blockchainDistribution': blockchainGroups,
      'enabledPercentage': totalTokens > 0 ? (enabledCount / totalTokens * 100).roundToDouble() : 0.0,
    };
  }

  /// بررسی تغییرات در تنظیمات توکن‌ها
  Future<bool> hasTokenPreferencesChanged() async {
    final lastUpdate = _prefs.getInt('last_token_preferences_update_${walletName}_$userId') ?? 0;
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    return (currentTime - lastUpdate) > 300000; // 5 دقیقه
  }

  /// ذخیره زمان آخرین به‌روزرسانی
  Future<void> updateLastPreferencesTime() async {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setInt('last_token_preferences_update_${walletName}_$userId', currentTime);
  }

  /// تبدیل ApiCurrency به CryptoToken (مشابه Helper.kt)
  CryptoToken toCryptoToken(Map<String, dynamic> apiCurrency) {
    final symbol = apiCurrency['Symbol'] ?? '';
    final blockchainName = apiCurrency['BlockchainName'] ?? '';
    final smartContractAddress = apiCurrency['SmartContractAddress'];
    final isEnabled = getTokenStateFromParams(symbol, blockchainName, smartContractAddress);
    
    return CryptoToken(
      name: apiCurrency['CurrencyName'] ?? '',
      symbol: symbol,
      blockchainName: blockchainName,
      iconUrl: apiCurrency['Icon'] ?? 'https://assets.coingecko.com/coins/images/1/small/bitcoin.png',
      isEnabled: isEnabled,
      amount: 0.0,
      isToken: apiCurrency['IsToken'] ?? true,
      smartContractAddress: smartContractAddress,
    );
  }
}

/// Extension function برای تبدیل ApiCurrency به CryptoToken (مشابه Helper.kt)
extension ApiCurrencyExtension on Map<String, dynamic> {
  CryptoToken toCryptoToken() {
    return CryptoToken(
      name: this['CurrencyName'] ?? '',
      symbol: this['Symbol'] ?? '',
      blockchainName: this['BlockchainName'] ?? '',
      iconUrl: this['Icon'] ?? 'https://assets.coingecko.com/coins/images/1/small/bitcoin.png',
      isEnabled: false,
      amount: 0.0,
      isToken: this['IsToken'] ?? true,
      smartContractAddress: this['SmartContractAddress'],
    );
  }
}
