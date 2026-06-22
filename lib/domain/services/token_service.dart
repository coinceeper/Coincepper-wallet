import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../../models/crypto_token.dart';
import '../../services/api_service.dart';
import '../../services/api_models.dart';
import '../../services/token_preferences.dart';
import '../../services/token_balance_service.dart';
import '../../utils/secure_log.dart';

/// Domain service for token CRUD, enabling/disabling, and preferences.
///
/// Delegates persistence to [TokenPreferences] and network fetching
/// to [ApiService]. This is a pure Dart class — no ChangeNotifier.
class TokenService {
  final String _userId;
  final String _walletName;
  final ApiService _apiService;
  late final TokenPreferences _preferences;

  List<CryptoToken> _currencies = [];
  bool _isLoading = false;
  bool _hasLoadedFromApi = false;
  String? _errorMessage;
  VoidCallback? _onChange;

  TokenService({
    required String userId,
    required String walletName,
    required ApiService apiService,
  })  : _userId = userId,
        _walletName = walletName,
        _apiService = apiService {
    _preferences = TokenPreferences(userId: userId, walletName: walletName);
  }

  // ==================== GETTERS ====================

  List<CryptoToken> get currencies => _currencies;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  TokenPreferences get preferences => _preferences;
  bool get hasLoadedFromApi => _hasLoadedFromApi;

  // ==================== LISTENER ====================

  void addListener(VoidCallback callback) {
    _onChange = callback;
  }

  void removeListener(VoidCallback callback) {
    _onChange = null;
  }

  // ==================== PUBLIC API ====================

  /// Initialize with default tokens (BTC, ETH, TRX).
  Future<void> initializeDefaultTokensOnly() async {
    await _preferences.initialize();
    _currencies = _getDefaultTokens();
    _hasLoadedFromApi = false;
    _notifyChange();
  }

  /// Initialize service, loading default token preferences.
  Future<void> initialize() async {
    await _preferences.initialize();
    _currencies = _getDefaultTokens();
    _notifyChange();
  }

  /// Smart load: try cache first, then API.
  Future<void> smartLoadTokens({bool forceRefresh = false}) async {
    if (_isLoading) return;
    _isLoading = true;

    try {
      if (!forceRefresh) {
        final cached = await _loadFromCache();
        if (cached != null) {
          _currencies = cached;
          _hasLoadedFromApi = false;
          _isLoading = false;
          _notifyChange();
          return;
        }
      }

      await _fetchFromApi();
    } catch (e) {
      SecureLog.e('TokenService: smartLoadTokens error', error: e);
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      _notifyChange();
    }
  }

  /// Load tokens directly from the API.
  Future<void> loadFromApi() async {
    if (_isLoading) return;
    _isLoading = true;
    try {
      await _fetchFromApi();
    } catch (e) {
      SecureLog.e('TokenService: loadFromApi error', error: e);
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      _notifyChange();
    }
  }

  /// Update current tokens based on stored preferences.
  void updateCurrenciesFromPreferences() {
    _currencies = _currencies.map((t) {
      final enabled = _preferences.isTokenEnabled(t);
      return t.copyWith(isEnabled: enabled);
    }).toList();
    _notifyChange();
  }

  bool isTokenEnabled(CryptoToken token) {
    return _preferences.isTokenEnabled(token);
  }

  Future<void> toggleToken(CryptoToken token, bool newState,
      {bool isManualToggle = false}) async {
    await _preferences.saveTokenStateFromToken(token, newState);
    updateCurrenciesFromPreferences();
  }

  /// Clear cached data and reload from API.
  Future<void> clearCacheAndReload() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_tokens_${_walletName}_$_userId');
    await smartLoadTokens(forceRefresh: true);
  }

  // ==================== INTERNAL ====================

  List<CryptoToken> _getDefaultTokens() {
    return [
      CryptoToken(
        name: 'Bitcoin',
        symbol: 'BTC',
        blockchainName: 'Bitcoin',
        iconUrl: 'https://assets.coingecko.com/coins/images/1/small/bitcoin.png',
        isEnabled: true,
        amount: 0.0,
        isToken: false,
      ),
      CryptoToken(
        name: 'Ethereum',
        symbol: 'ETH',
        blockchainName: 'Ethereum',
        iconUrl: 'https://assets.coingecko.com/coins/images/279/small/ethereum.png',
        isEnabled: true,
        amount: 0.0,
        isToken: false,
      ),
      CryptoToken(
        name: 'Tron',
        symbol: 'TRX',
        blockchainName: 'Tron',
        iconUrl: 'https://assets.coingecko.com/coins/images/1094/small/tron-logo.png',
        isEnabled: true,
        amount: 0.0,
        isToken: false,
      ),
    ];
  }

  Future<void> _fetchFromApi() async {
    final response = await _apiService.getAllCurrencies();
    if (response.success && response.currencies.isNotEmpty) {
      _currencies = response.currencies.map((apiCurrency) {
        final enabled = _preferences.getTokenStateFromParams(
          apiCurrency.symbol ?? '',
          apiCurrency.blockchainName ?? '',
          apiCurrency.smartContractAddress,
        );
        return CryptoToken(
          name: apiCurrency.currencyName ?? '',
          symbol: apiCurrency.symbol ?? '',
          blockchainName: apiCurrency.blockchainName ?? '',
          iconUrl: apiCurrency.icon ??
              'https://assets.coingecko.com/coins/images/1/small/bitcoin.png',
          isEnabled: enabled,
          amount: 0.0,
          isToken: apiCurrency.isToken ?? true,
          smartContractAddress: apiCurrency.smartContractAddress,
        );
      }).toList();
      _hasLoadedFromApi = true;
      _errorMessage = null;
      await _saveToCache(_currencies);
    }
  }

  Future<List<CryptoToken>?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('cached_tokens_${_walletName}_$_userId');
      if (jsonStr == null) return null;
      final list = json.decode(jsonStr) as List<dynamic>;
      return list.map((e) => CryptoToken.fromJson(e)).toList();
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveToCache(List<CryptoToken> tokens) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = json.encode(tokens.map((t) => t.toJson()).toList());
      await prefs.setString('cached_tokens_${_walletName}_$_userId', jsonStr);
    } catch (e) {
      SecureLog.d('TokenService: cache save failed', error: e);
    }
  }

  void _notifyChange() {
    _onChange?.call();
  }
}
