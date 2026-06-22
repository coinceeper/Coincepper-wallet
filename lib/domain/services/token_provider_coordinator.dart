import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../di/service_locator.dart';
import '../../providers/token_provider.dart';
import '../../services/api_service.dart';
import '../../services/balance_manager.dart';
import '../../services/error_service.dart';
import '../../services/secure_storage.dart';
import '../../services/wallet_state_manager.dart';
import '../../utils/secure_log.dart';

/// Coordinator for TokenProvider lifecycle management.
///
/// This service is responsible for:
/// 1. Creating, caching, and disposing TokenProvider instances
/// 2. Wallet-switching (saving/restoring balance cache between wallets)
/// 3. Emergency fallback initialization
/// 4. Deduplicating concurrent creation requests
///
/// It is a pure domain service (no ChangeNotifier) and communicates
/// state changes through callbacks.
class TokenProviderCoordinator {
  // ==================== CALLBACK ====================
  VoidCallback? _onChange;

  /// Set callback to notify upstream (AppProvider) of state changes.
  void setOnChange(VoidCallback? callback) {
    _onChange = callback;
  }

  // ==================== DEPENDENCIES ====================
  final ApiService _apiService = ApiService();

  // ==================== STATE ====================
  final Map<String, TokenProvider> _tokenProviders = {};
  TokenProvider? _currentTokenProvider;

  /// Guard preventing concurrent/redundant token provider initialization.
  bool _isInitializing = false;

  /// Per-key pending TokenProvider creation trackers.
  ///
  /// Key format matches [_tokenProviderKey]: "walletName_userId".
  /// When multiple callers concurrently request a TokenProvider for the same
  /// wallet-user pair that does not exist yet, only one actually creates it;
  /// the rest await the shared [Completer.future].
  final Map<String, Completer<TokenProvider>> _pendingCreations = {};

  /// Guard set preventing concurrent emergency initialization for the same key.
  final Set<String> _emergencyInProgress = {};

  // ==================== GETTERS ====================
  TokenProvider? get currentTokenProvider => _currentTokenProvider;
  bool get isInitializing => _isInitializing;

  // ==================== KEY UTILITY ====================
  String _key(String userId, {String? walletName}) {
    return '${walletName ?? 'default'}_$userId';
  }

  // ==================== PUBLIC API ====================

  /// Get or create a TokenProvider for the given userId and walletName.
  /// This is the main entry point for all TokenProvider access.
  Future<TokenProvider> getOrCreate(
    String userId, {
    String? walletName,
  }) async {
    final wallet = walletName ?? 'default';
    final key = _key(userId, walletName: wallet);

    // Fast path: already exists.
    if (_tokenProviders.containsKey(key)) {
      _currentTokenProvider = _tokenProviders[key]!;
      return _currentTokenProvider!;
    }

    // Dedup path: another call is already creating this one — await it.
    if (_pendingCreations.containsKey(key)) {
      SecureLog.d('TokenProviderCoordinator: Awaiting in-progress creation for $key');
      return _pendingCreations[key]!.future;
    }

    // === Slow path: create and initialise ===
    final completer = Completer<TokenProvider>();
    _pendingCreations[key] = completer;

    try {
      final tokenProvider = TokenProvider(
        userId: userId,
        walletName: wallet,
        apiService: _apiService,
        context: null,
      );

      tokenProvider.addListener(_onTokenProviderChanged);
      _tokenProviders[key] = tokenProvider;
      _currentTokenProvider = tokenProvider;

      await tokenProvider.initializeInBackground();
      await tokenProvider.ensureTokensSynchronized();

      // Restore per-wallet state
      await _restoreBalanceCache(tokenProvider, wallet, userId);

      // Fetch prices
      final enabledSymbols = tokenProvider.enabledTokens
          .map((t) => t.symbol ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      if (enabledSymbols.isNotEmpty) {
        await tokenProvider.fetchPrices(activeSymbols: enabledSymbols);
      }

      _notifyChange();
      completer.complete(tokenProvider);
      return tokenProvider;
    } catch (e) {
      // Clean up partially-initialised provider so future calls retry.
      _cleanupFailedProvider(key);
      completer.completeError(e);
      rethrow;
    } finally {
      _pendingCreations.remove(key);
    }
  }

  /// Initialize TokenProvider for the current wallet.
  /// Shared between background init and HomeScreen timeout protection.
  /// Uses the same guard so both paths cannot run concurrently.
  Future<void> initializeForCurrentWallet({
    required String? currentUserId,
    required String? currentWalletName,
  }) async {
    final userId = currentUserId;
    if (userId == null) return;
    if (_isInitializing) {
      SecureLog.d('TokenProviderCoordinator: initializeForCurrentWallet skipped — already initializing');
      return;
    }

    _isInitializing = true;
    SecureLog.d('TokenProviderCoordinator: initializeForCurrentWallet starting');
    try {
      await _initializeAsync(userId, walletName: currentWalletName);
    } finally {
      _isInitializing = false;
    }
  }

  /// Background initialization of TokenProvider with normal/emergency fallback.
  Future<void> initializeInBackground({
    required String? currentUserId,
    required String? currentWalletName,
  }) async {
    final userId = currentUserId;
    if (userId == null || _isInitializing) return;
    _isInitializing = true;

    SecureLog.d('TokenProviderCoordinator: Starting background initialization');

    _initializeAsync(userId, walletName: currentWalletName).whenComplete(() {
      _isInitializing = false;
    });
  }

  /// Switch wallet — saves balance cache for old wallet, loads for new one.
  Future<TokenProvider?> switchWallet({
    required String? oldWalletName,
    required String? oldUserId,
    required String newWalletName,
    required String newUserId,
    TokenProvider? currentProvider,
  }) async {
    // Save current token state before switching
    if (currentProvider != null && oldWalletName != null && oldUserId != null) {
      await _saveBalanceCache(currentProvider, oldWalletName, oldUserId);
    }

    // Get or create TokenProvider for new wallet
    final tokenProvider = await getOrCreate(newUserId, walletName: newWalletName);

    // Restore balance cache from SecureStorage
    await _restoreBalanceCache(tokenProvider, newWalletName, newUserId);

    await tokenProvider.ensureTokensSynchronized();

    // Update BalanceManager
    try {
      await ServiceLocator.get<BalanceManager>()
          .setCurrentUserAndWallet(newUserId, newWalletName);
    } catch (e, st) {
      SecureLog.e('Error updating BalanceManager', error: e, stackTrace: st);
      ServiceLocator.get<ErrorService>().report(e, message: 'Failed to update balance.', stackTrace: st);
    }

    _notifyChange();
    return tokenProvider;
  }

  /// Remove a wallet's TokenProvider.
  void removeWallet(String walletName, String userId) {
    final key = _key(userId, walletName: walletName);
    final tokenProvider = _tokenProviders[key];
    if (tokenProvider != null) {
      tokenProvider.removeListener(_onTokenProviderChanged);
      tokenProvider.dispose();
    }
    _tokenProviders.remove(key);
  }

  /// Add a wallet and create its TokenProvider.
  Future<TokenProvider?> addWallet(
    String walletName,
    String userId,
  ) async {
    final provider = await getOrCreate(userId, walletName: walletName);
    _notifyChange();
    return provider;
  }

  /// Reset current provider reference when the currently displayed wallet is removed.
  void clearCurrentProvider() {
    _currentTokenProvider = null;
  }

  /// Abort all in-flight TokenProvider operations.
  void abortPending() {
    _isInitializing = false;
    _emergencyInProgress.clear();

    for (final entry in _pendingCreations.entries) {
      if (!entry.value.isCompleted) {
        entry.value.completeError(
          StateError('TokenProviderCoordinator: creation aborted during clear/reset'),
        );
      }
    }
    _pendingCreations.clear();
  }

  /// Clear all TokenProviders and reset state.
  void clearAll() {
    abortPending();
    for (final provider in _tokenProviders.values) {
      provider.removeListener(_onTokenProviderChanged);
      provider.dispose();
    }
    _tokenProviders.clear();
    _currentTokenProvider = null;
  }

  // ==================== INTERNAL METHODS ====================

  Future<void> _initializeAsync(String userId, {String? walletName}) async {
    try {
      // Phase 1: Create (or get existing) TokenProvider with a 5-second budget.
      final tokenProvider = await getOrCreate(userId, walletName: walletName)
          .timeout(const Duration(seconds: 5));

      // Phase 2: Sync tokens with another 3-second budget.
      await tokenProvider.ensureTokensSynchronized()
          .timeout(const Duration(seconds: 3))
          .catchError((_) {
        SecureLog.w('Token sync timed out, continuing with current state');
      });

      SecureLog.d('TokenProviderCoordinator: Initialized successfully via normal path');
    } on TimeoutException {
      SecureLog.w('TokenProviderCoordinator: Normal path timed out, using emergency');
      await _emergencyInit(userId, walletName: walletName ?? 'default');
    } catch (error) {
      SecureLog.e('TokenProviderCoordinator: Normal path failed', error: error);
      await _emergencyInit(userId, walletName: walletName ?? 'default');
    }
  }

  Future<void> _emergencyInit(String userId, {required String walletName}) async {
    final key = _key(userId, walletName: walletName);
    if (_emergencyInProgress.contains(key)) {
      SecureLog.d('TokenProviderCoordinator: Emergency init already in progress for $key, skipping');
      return;
    }

    _emergencyInProgress.add(key);
    try {
      final provider = await _createEmergencyProvider(userId, walletName: walletName);
      _tokenProviders[key] = provider;
      _currentTokenProvider = provider;
      _notifyChange();
    } finally {
      _emergencyInProgress.remove(key);
    }
  }

  Future<TokenProvider> _createEmergencyProvider(String userId, {required String walletName}) async {
    final tokenProvider = TokenProvider(
      userId: userId,
      walletName: walletName,
      apiService: _apiService,
      context: null,
    );
    tokenProvider.addListener(_onTokenProviderChanged);
    await tokenProvider.initializeDefaultTokensOnly();
    return tokenProvider;
  }

  Future<void> _saveBalanceCache(TokenProvider provider, String walletName, String userId) async {
    final balanceCache = <String, double>{};
    for (final token in provider.enabledTokens) {
      if (token.amount > 0) balanceCache[token.symbol ?? ''] = token.amount;
    }
    if (balanceCache.isNotEmpty) {
      await ServiceLocator.get<WalletStateManager>()
          .saveBalanceCacheForWallet(walletName, userId, balanceCache);
    }
  }

  Future<void> _restoreBalanceCache(TokenProvider provider, String walletName, String userId) async {
    try {
      final balanceCache = await ServiceLocator.get<SecureStorage>()
          .getWalletBalanceCache(walletName, userId);

      if (balanceCache.isNotEmpty) {
        final updatedTokens = provider.enabledTokens.map((token) {
          final symbol = token.symbol ?? '';
          final chain = token.blockchainName ?? '';
          final qualifiedKey = chain.isNotEmpty ? '${symbol}_$chain' : symbol;
          final cachedBalance = balanceCache[qualifiedKey] ?? balanceCache[symbol] ?? 0.0;
          if (cachedBalance > 0.0) return token.copyWith(amount: cachedBalance);
          return token;
        }).toList();

        await provider.setActiveTokens(updatedTokens);
      }
    } catch (e, st) {
      SecureLog.e('Error restoring balance cache', error: e, stackTrace: st);
      _reportError(e, 'Failed to restore balance cache', st);
    }
  }

  void _onTokenProviderChanged() {
    _notifyChange();
  }

  void _cleanupFailedProvider(String key) {
    final failedProvider = _tokenProviders[key];
    if (failedProvider != null) {
      failedProvider.removeListener(_onTokenProviderChanged);
      failedProvider.dispose();
    }
    _tokenProviders.remove(key);
    if (_currentTokenProvider?.hashCode == failedProvider?.hashCode) {
      _currentTokenProvider = null;
    }
  }

  void _notifyChange() {
    _onChange?.call();
  }

  void _reportError(Object error, String message, [StackTrace? stackTrace]) {
    try {
      ServiceLocator.get<ErrorService>().report(
        error,
        message: message,
        stackTrace: stackTrace,
      );
    } catch (e) {
      SecureLog.e('TokenProviderCoordinator: ErrorService unavailable', error: e);
    }
  }
}
