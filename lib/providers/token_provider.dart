import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io' show Platform;
import '../models/crypto_token.dart';
import '../models/price_data.dart';
import '../services/api_service.dart';
import '../services/api_models.dart' hide PriceData;
import '../services/token_balance_service.dart';
import '../services/token_preferences.dart';
import '../domain/services/token_service.dart';
import '../domain/services/price_service.dart';
import '../domain/services/gas_fee_service.dart';
import '../domain/services/blockchain_service.dart';
import '../domain/services/token_filter_service.dart';
import '../domain/interfaces/price_query.dart';
import '../services/error_service.dart';
import '../utils/secure_log.dart';
import '../utils/retry_helper.dart';
import '../utils/network_error_utils.dart';
import '../di/service_locator.dart';

/// Lean state manager for crypto tokens.
///
/// This class acts as a thin coordinator that:
/// 1. Maintains UI-relevant state (active tokens, loading flags, errors)
/// 2. Delegates business logic to specialized domain services
/// 3. Synchronizes state across services and notifies UI on changes
///
/// **Delegated responsibilities:**
/// - [TokenService]: token CRUD, enable/disable, preferences
/// - [PriceService]: price fetching and caching
/// - [GasFeeService]: gas fee estimation
/// - [BlockchainService]: blockchain list from API
/// - [TokenBalanceService]: on-chain balance fetching and cache
/// - [TokenFilterService]: sorting tokens (including by dollar value)
class TokenProvider extends ChangeNotifier {
  // ==================== COMPOSED SERVICES ====================
  late final TokenService tokenService;
  late final PriceService priceService;
  late final GasFeeService gasFeeService;
  late final BlockchainService blockchainService;
  late final TokenBalanceService tokenBalanceService;
  final TokenFilterService tokenFilterService;

  /// Adapter that satisfies [IPriceQuery] for use with [TokenFilterService].
  late final IPriceQuery _priceQueryAdapter;

  // ==================== STATE ====================
  List<CryptoToken> _activeTokens = [];
  bool _isLoading = false;
  String? _errorMessage;
  final String _walletName;
  String _userId;
  final ApiService apiService;

  // ==================== CONSTRUCTOR ====================
  TokenProvider({
    required String userId,
    required this.apiService,
    required String walletName,
    BuildContext? context,
    TokenBalanceService? balanceService,
    TokenFilterService? filterService,
  })  : _userId = userId,
        _walletName = walletName,
        tokenBalanceService = balanceService ?? TokenBalanceService(),
        tokenFilterService = filterService ?? const TokenFilterService() {
    _priceQueryAdapter = _TokenPriceQueryAdapter(this);
    tokenService = TokenService(userId: userId, walletName: walletName, apiService: apiService);
    priceService = PriceService();
    gasFeeService = GasFeeService();
    blockchainService = BlockchainService(apiService: apiService);

    // Sync state from services via callbacks (pure domain services)
    tokenService.addListener(_onTokenServiceChanged);
    priceService.setOnChange(_onPriceServiceChanged);
    gasFeeService.addListener(_onGasFeeServiceChanged);
    blockchainService.addListener(_onBlockchainServiceChanged);
  }

  // ==================== SERVICE LISTENERS ====================
  void _onTokenServiceChanged() {
    _syncActiveTokens();
    notifyListeners();
  }

  void _onPriceServiceChanged() {
    notifyListeners();
  }

  void _onGasFeeServiceChanged() {
    notifyListeners();
  }

  void _onBlockchainServiceChanged() {
    notifyListeners();
  }

  void _syncActiveTokens() {
    _activeTokens = tokenService.currencies
        .where((t) => tokenService.isTokenEnabled(t))
        .toList();
    // Use TokenFilterService for dollar-value sorting via adapter
    _activeTokens = tokenFilterService.sortByDollarValue(_activeTokens, _priceQueryAdapter);
  }

  // ==================== GETTERS ====================
  List<CryptoToken> get currencies => tokenService.currencies;
  bool get isLoading => _isLoading || tokenService.isLoading;
  String? get errorMessage => _errorMessage ?? tokenService.errorMessage;
  List<CryptoToken> get activeTokens => _activeTokens;
  Map<String, Map<String, PriceData>> get tokenPrices => priceService.tokenPrices;
  Map<String, String> get gasFees => gasFeeService.gasFees;
  List<ApiBlockchain> get blockchains => blockchainService.blockchains;
  String get walletName => _walletName;
  String get userId => _userId;

  List<CryptoToken> get tokens => _activeTokens;
  List<CryptoToken> get enabledTokens {
    final enabled = _activeTokens.where((t) => t.isEnabled).toList();
    return tokenFilterService.sortByDollarValue(enabled, _priceQueryAdapter);
  }

  bool get isInitialized => tokenService.currencies.isNotEmpty;
  bool get isFullyReady =>
      !isLoading && tokenService.currencies.isNotEmpty && _activeTokens.isNotEmpty;
  bool get hasLoadedFromApi => tokenService.hasLoadedFromApi;
  TokenPreferences get tokenPreferences => tokenService.preferences;

  // ==================== PRICE MANAGEMENT ====================
  /// Returns the price for [symbol] in the given (or default USD) currency.
  double? getPrice(String symbol, {String? currency}) {
    return priceService.getTokenPrice(symbol, currency: currency ?? 'USD');
  }

  /// Fetches prices for the given symbols (backward-compatible named params).
  Future<void> fetchPrices({List<String>? activeSymbols, List<String>? fiatCurrencies}) async {
    activeSymbols ??= _activeTokens.map((t) => t.symbol).whereType<String>().toList();
    if (activeSymbols.isEmpty) return;
    await priceService.fetchPrices(activeSymbols: activeSymbols);
  }

  double getTokenPrice(String symbol, String currency) {
    return priceService.getTokenPrice(symbol, currency: currency);
  }

  String? getAverageChange24h() {
    return priceService.getAverageChange24h(
        _activeTokens.map((t) => t.symbol ?? '').toList());
  }

  // ==================== GAS FEE MANAGEMENT ====================
  Future<void> fetchGasFees() async {
    await gasFeeService.fetchGasFees();
  }

  Future<String> ensureGasFee(String blockchainName) async {
    return await gasFeeService.ensureGasFee(blockchainName);
  }

  // ==================== BLOCKCHAIN MANAGEMENT ====================
  Future<void> fetchBlockchains() async {
    await blockchainService.fetchBlockchains();
  }

  // ==================== BALANCE MANAGEMENT ====================
  Future<Map<String, String>> fetchBalancesForActiveTokens() async {
    final balances = await tokenBalanceService.fetchBalancesForActiveTokens(
      userId: _userId,
      activeTokens: _activeTokens,
    );
    if (balances.isNotEmpty) {
      _activeTokens = tokenBalanceService.applyBalances(
        balances: balances,
        tokens: _activeTokens,
      );
      _syncActiveTokens();
      notifyListeners();
    }
    return balances;
  }

  Future<bool> updateBalance() async {
    if (_userId.isEmpty) {
      _errorMessage = 'User ID is required for balance update';
      return false;
    }
    await fetchBalancesForActiveTokens();
    return true;
  }

  Future<bool> updateSingleTokenBalance(CryptoToken token) async {
    if (_userId.isEmpty) return false;
    final updated =
        await tokenBalanceService.updateSingleTokenBalance(userId: _userId, token: token);
    if (updated != null) {
      final idx = _activeTokens.indexWhere(
          (t) => t.symbol == token.symbol && t.blockchainName == token.blockchainName);
      if (idx != -1) {
        _activeTokens[idx] = updated;
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  // ==================== TOKEN MANAGEMENT ====================
  Future<void> smartLoadTokens({bool forceRefresh = false}) async {
    await tokenService.smartLoadTokens(forceRefresh: forceRefresh);
    _syncActiveTokens();
  }

  Future<void> toggleToken(CryptoToken token, bool newState,
      {bool isManualToggle = false}) async {
    await tokenService.toggleToken(token, newState, isManualToggle: isManualToggle);
    _syncActiveTokens();

    if (newState) {
      final symbol = token.symbol;
      if (symbol != null && symbol.isNotEmpty) {
        try {
          await apiService.getPrices([symbol], ['USD']);
        } catch (e) {
          SecureLog.d('Price fetch after toggle failed for $symbol: $e');
        }
      }
    }

    notifyListeners();
  }

  bool isTokenEnabled(CryptoToken token) => tokenService.isTokenEnabled(token);

  Future<void> saveTokenStateForUser(CryptoToken token, bool isEnabled,
      {bool isManualToggle = false}) async {
    await tokenService.toggleToken(token, isEnabled, isManualToggle: isManualToggle);
  }

  bool getTokenStateForUser(CryptoToken token) => tokenService.isTokenEnabled(token);

  // ==================== USER MANAGEMENT ====================
  Future<void> updateUserId(String newUserId) async {
    if (_userId == newUserId) return;
    _userId = newUserId;
    tokenService = TokenService(
        userId: newUserId, walletName: _walletName, apiService: apiService);
    tokenService.addListener(_onTokenServiceChanged);
    await tokenService.smartLoadTokens(forceRefresh: true);
    _syncActiveTokens();
    notifyListeners();
  }

  String getCurrentUserId() => _userId;

  // ==================== INITIALIZATION ====================
  Future<void> initializeInBackground() async {
    _isLoading = true;
    notifyListeners();

    const retryConfig = RetryConfig(
      maxRetries: 3,
      baseDelay: Duration(seconds: 2),
      maxTotalDelay: Duration(seconds: 30),
    );

    final result = await RetryHelper.retry<void>(
      _performBackgroundInitialization,
      config: retryConfig,
      operationName: 'TokenProvider.initializeInBackground',
      shouldRetry: NetworkErrorUtils.isTransientError,
      onRetry: (attempt, delay) async {
        SecureLog.w(
            'TokenProvider init failed on attempt $attempt, retrying in ${delay.inMilliseconds}ms');
        _isLoading = true;
      },
      onFinalFailure: (lastError, totalAttempts) async {
        _errorMessage =
            'Background initialization failed after $totalAttempts attempts: ${lastError.toString()}';
        ServiceLocator.get<ErrorService>().report(
          lastError,
          message: 'Some token data could not be loaded. Basic functionality is available.',
        );
        SecureLog.w('TokenProvider: Falling back to default tokens after all retries exhausted');
        await tokenService.initializeDefaultTokensOnly();
      },
    );

    if (result.succeeded) {
      _runBackgroundTasks();
    }

    _isLoading = false;
    _syncActiveTokens();
    notifyListeners();
  }

  Future<void> _performBackgroundInitialization() async {
    await tokenService.initialize();

    // Load balance cache via dedicated service
    final cachedTokens = await tokenBalanceService.loadBalanceCache(
      userId: _userId,
      walletName: _walletName,
      currencies: tokenService.currencies,
    );
    _activeTokens = cachedTokens.where((t) => t.isEnabled).toList();

    if (tokenService.currencies.isNotEmpty) {
      _isLoading = false;
      _syncActiveTokens();
      notifyListeners();
    }

    await tokenService
        .smartLoadTokens(forceRefresh: false)
        .timeout(const Duration(seconds: 5))
        .catchError((e) {
      SecureLog.w('TokenService smartLoadTokens timed out', error: e);
    });
    await ensureTokensSynchronized()
        .timeout(const Duration(seconds: 5))
        .catchError((e) {
      SecureLog.w('TokenProvider ensureTokensSynchronized timed out', error: e);
    });
  }

  Future<void> initializeDefaultTokensOnly() async {
    await tokenService.initializeDefaultTokensOnly();
    _syncActiveTokens();
    notifyListeners();
  }

  Future<void> initialize() async {
    await initializeInBackground();
  }

  void _runBackgroundTasks() {
    Future.delayed(const Duration(seconds: 1), () => fetchGasFees());
    Future.delayed(const Duration(seconds: 2), () {
      tokenService.smartLoadTokens(forceRefresh: false).catchError((e) {
        SecureLog.d('Background token load failed', error: e);
      });
    });
  }

  // ==================== SYNCHRONIZATION ====================
  Future<void> ensureTokensSynchronized() async {
    if (tokenService.currencies.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('cachedUserTokens_$_userId');
      if (jsonStr != null) {
        await tokenService.smartLoadTokens(forceRefresh: false);
      } else {
        await tokenService.loadFromApi();
      }
    }
    tokenService.updateCurrenciesFromPreferences();
    _syncActiveTokens();
    if (_activeTokens.isNotEmpty) {
      await priceService.fetchPrices(
          activeSymbols: _activeTokens.map((t) => t.symbol ?? '').toList());
    }
    notifyListeners();
  }

  Future<void> ensureTokensLoaded() async {
    if (!hasLoadedFromApi) {
      await tokenService.smartLoadTokens(forceRefresh: true);
    } else {
      await tokenService.smartLoadTokens(forceRefresh: false);
    }
  }

  // ==================== FORCE REFRESH ====================
  Future<void> forceRefresh() async {
    _isLoading = true;
    notifyListeners();
    try {
      await gasFeeService.fetchGasFees();
      await tokenService.smartLoadTokens(forceRefresh: true);
      await priceService.fetchPrices(
          activeSymbols: _activeTokens.map((t) => t.symbol ?? '').toList());
      _syncActiveTokens();
    } catch (e) {
      _errorMessage = 'Failed to refresh data: ${e.toString()}';
      ServiceLocator.get<ErrorService>().report(e, message: 'Failed to refresh token data.');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ==================== STATE MANIPULATION ====================
  Future<void> setActiveTokens(List<CryptoToken> newTokens) async {
    _activeTokens = newTokens;
    notifyListeners();
  }

  void setAllTokens(List<CryptoToken> allTokens) {
    _activeTokens = allTokens.where((t) => t.isEnabled).toList();
    notifyListeners();
  }

  Future<void> clearCacheAndReload() async {
    await tokenService.clearCacheAndReload();
    _syncActiveTokens();
  }

  Future<void> invalidateAllCaches() async {
    await tokenService.clearCacheAndReload();
  }

  Future<bool> areCachesSynchronized() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('cachedUserTokens_$_userId');
  }

  Future<void> ensureCacheSynchronization() async {
    final synchronized = await areCachesSynchronized();
    if (!synchronized) {
      await tokenService.smartLoadTokens(forceRefresh: true);
    }
  }

  Future<void> setActiveTokensForUser(List<CryptoToken> tokens) async {
    _activeTokens = tokens;
    notifyListeners();
  }

  void setActiveTokensForUserDeprecated(List<CryptoToken> tokens) {
    _activeTokens = tokens;
    notifyListeners();
  }

  Future<void> updateActiveTokensFromPreferences() async {
    tokenService.updateCurrenciesFromPreferences();
    _syncActiveTokens();
  }

  Future<void> resetAllTokenStates() async {
    await tokenService.preferences.clearAllTokenPreferences();
    _syncActiveTokens();
  }

  Future<void> updateTokenOrder(List<CryptoToken> newOrder) async {
    _activeTokens = tokenFilterService.sortByDollarValue(newOrder, _priceQueryAdapter);
    notifyListeners();
  }

  Future<void> refreshActiveTokens() async {
    _syncActiveTokens();
    notifyListeners();
  }

  Future<void> forceUpdateTokenStates() async {
    tokenService.updateCurrenciesFromPreferences();
    _syncActiveTokens();
    if (_activeTokens.isNotEmpty) {
      await priceService.fetchPrices(
          activeSymbols: _activeTokens.map((t) => t.symbol ?? '').toList());
    }
    notifyListeners();
  }

  Future<void> loadTokensWithBalance({bool forceRefresh = false}) async {
    await tokenService.smartLoadTokens(forceRefresh: forceRefresh);
    _syncActiveTokens();
  }

  Future<void> loadTokens() async {
    await tokenService.smartLoadTokens(forceRefresh: false);
    _syncActiveTokens();
  }

  Future<void> autoEnableTokensWithBalance() async {
    final cachedTokens = await tokenBalanceService.loadBalanceCache(
      userId: _userId,
      walletName: _walletName,
      currencies: tokenService.currencies,
    );
    final enabled = cachedTokens.where((t) => t.isEnabled).toList();
    if (enabled.isNotEmpty) {
      _activeTokens = enabled;
      notifyListeners();
    }
  }

  void debugCurrentState() {
    SecureLog.d('=== TokenProvider Debug State ===');
    SecureLog.d('Active Tokens: ${_activeTokens.length}');
  }

  /// Ensured via [TokenService.initialize]; kept for backward compatibility.
  Future<void> ensureBitcoinEthereumEnabled() async {
    // Delegated to TokenService.initialize
  }

  Future<void> handleiOSAppResume() async {
    if (!Platform.isIOS) return;
    await ensureTokensSynchronized();
  }

  @override
  void dispose() {
    tokenService.removeListener(_onTokenServiceChanged);
    priceService.setOnChange(null);
    gasFeeService.removeListener(_onGasFeeServiceChanged);
    blockchainService.removeListener(_onBlockchainServiceChanged);
    super.dispose();
  }

  /// @deprecated Debug-only method preserved for old UI compatibility.
  @Deprecated('No longer supported in new architecture')
  void debugTokenPreferences() {
    SecureLog.w('debugTokenPreferences called but is a no-op in new architecture');
  }
}

/// Adapter that exposes [TokenProvider]'s price data via the [IPriceQuery]
/// interface, enabling clean use with [TokenFilterService].
///
/// This avoids making [TokenProvider] implement [IPriceQuery] directly,
/// which would conflict with its existing `fetchPrices()` signature.
class _TokenPriceQueryAdapter implements IPriceQuery {
  final TokenProvider _provider;

  _TokenPriceQueryAdapter(this._provider);

  @override
  double? getPrice(String symbol, {String? currency}) {
    return _provider.priceService.getTokenPrice(symbol, currency: currency ?? 'USD');
  }

  @override
  Future<void> fetchPrices(List<String> symbols, {List<String>? currencies}) async {
    // TokenProvider manages its own price fetching; this adapter exists
    // solely to satisfy IPriceQuery for TokenFilterService sorting.
  }
}
