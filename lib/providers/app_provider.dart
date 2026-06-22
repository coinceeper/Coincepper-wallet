import 'package:flutter/material.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/secure_storage.dart';
import 'token_provider.dart';
import '../utils/secure_log.dart';
import '../utils/retry_helper.dart';
import '../utils/network_error_utils.dart';
import '../services/error_service.dart';
import '../domain/services/app_settings_service.dart';
import '../domain/services/security_service.dart';
import '../domain/services/wallet_service.dart';
import '../domain/services/token_provider_coordinator.dart';
import '../di/service_locator.dart';

/// Core application coordinator.
///
/// This class acts as a thin coordinator that:
/// 1. Orchestrates initialization of domain services
/// 2. Delegates business logic to specialized services
/// 3. Provides a unified API surface for the UI layer
///
/// **Delegated responsibilities:**
/// - [WalletService]: wallet CRUD and selection
/// - [SecurityService]: lock/unlock, biometrics, passcode
/// - [AppSettingsService]: language, currency, notifications
/// - [TokenProviderCoordinator]: TokenProvider lifecycle management
class AppProvider extends ChangeNotifier {
  // ==================== COMPOSED SERVICES ====================
  final WalletService walletService = ServiceLocator.get<WalletService>();
  final SecurityService securityService = ServiceLocator.get<SecurityService>();
  final AppSettingsService appSettingsService = ServiceLocator.get<AppSettingsService>();
  final TokenProviderCoordinator tokenProviderCoordinator = ServiceLocator.get<TokenProviderCoordinator>();
  final ApiService apiService = ApiService();

  bool mounted = true;

  // ==================== STATE ====================
  bool _isInitialized = false;
  bool _isInitializing = false;

  // ==================== GETTERS ====================
  bool get isInitialized => _isInitialized;
  bool get isInitializing => _isInitializing;

  // Wallet
  String? get currentWalletName => walletService.currentWalletName;
  String? get currentUserId => walletService.currentUserId;
  List<Map<String, String>> get wallets => walletService.wallets;

  // Security
  bool get isLocked => securityService.isLocked;
  bool get isBiometricEnabled => securityService.isBiometricEnabled;
  int get autoLockTimeout => securityService.autoLockTimeout;

  // Settings
  bool get pushNotificationsEnabled => appSettingsService.pushNotificationsEnabled;
  String? get deviceToken => appSettingsService.deviceToken;
  String get currentLanguage => appSettingsService.currentLanguage;
  String get currentCurrency => appSettingsService.currentCurrency;

  // TokenProvider
  TokenProvider? get tokenProvider => tokenProviderCoordinator.currentTokenProvider;

  // ==================== INITIALIZATION ====================
  Future<void> initialize() async {
    if (_isInitialized || _isInitializing) return;

    _isInitializing = true;
    notifyListeners();

    const retryConfig = RetryConfig(
      maxRetries: 3,
      baseDelay: Duration(seconds: 2),
      maxTotalDelay: Duration(seconds: 30),
    );

    final result = await RetryHelper.retry<List>(
      _performInitialization,
      config: retryConfig,
      operationName: 'AppProvider.initialize',
      shouldRetry: _isTransientError,
      onRetry: (attempt, delay) async {
        SecureLog.w('AppProvider initialization failed on attempt $attempt, retrying in ${delay.inMilliseconds}ms');
        _isInitializing = true;
      },
      onFinalFailure: (lastError, totalAttempts) async {
        ServiceLocator.get<ErrorService>().report(
          lastError,
          message: 'Failed to initialize the app after $totalAttempts attempts. Please restart and try again.',
        );
      },
    );

    if (result.succeeded) {
      _isInitialized = true;
      SecureLog.i('AppProvider initialized (backed by domain services)');

      // Initialize TokenProvider for current user (non-blocking)
      tokenProviderCoordinator.setOnChange(_onCoordinatorChanged);
      tokenProviderCoordinator.initializeInBackground(
        currentUserId: currentUserId,
        currentWalletName: currentWalletName,
      );
    }

    _isInitializing = false;
    notifyListeners();
  }

  Future<List> _performInitialization() async {
    return Future.wait([
      securityService.initialize(),
      appSettingsService.initialize(),
      walletService.initialize(),
    ]).timeout(const Duration(seconds: 15), onTimeout: () {
      SecureLog.w('AppProvider.initialize: Slow initialization, some state might be missing');
      throw TimeoutException('Initialization timed out after 15 seconds');
    });
  }

  bool _isTransientError(Exception error) => NetworkErrorUtils.isTransientError(error);

  void _onCoordinatorChanged() {
    notifyListeners();
  }

  // ==================== TOKEN PROVIDER MANAGEMENT ====================
  Future<void> initializeForCurrentWallet() async {
    await tokenProviderCoordinator.initializeForCurrentWallet(
      currentUserId: currentUserId,
      currentWalletName: currentWalletName,
    );
  }

  // ==================== WALLET MANAGEMENT ====================
  Future<void> selectWallet(String walletName) async {
    final oldUserId = currentUserId;
    final oldWalletName = currentWalletName;

    // Delegate to coordinator: saves old wallet state, loads new one
    if (currentUserId != null) {
      await tokenProviderCoordinator.switchWallet(
        oldWalletName: oldWalletName,
        oldUserId: oldUserId,
        newWalletName: walletName,
        newUserId: currentUserId!,
        currentProvider: tokenProviderCoordinator.currentTokenProvider,
      );
    }

    await walletService.selectWallet(walletName);
    notifyListeners();
  }

  Future<void> setCurrentWallet(String walletName) async {
    await selectWallet(walletName);
  }

  Future<void> addWallet(String walletName, String userId) async {
    await walletService.addWallet(walletName, userId);
    await tokenProviderCoordinator.addWallet(walletName, userId);
    notifyListeners();
  }

  Future<void> removeWallet(String walletName) async {
    final userId = await ServiceLocator.get<SecureStorage>().getUserIdForWallet(walletName);

    await walletService.removeWallet(walletName);

    if (userId != null) {
      tokenProviderCoordinator.removeWallet(walletName, userId);
      if (currentWalletName == walletName) {
        tokenProviderCoordinator.clearCurrentProvider();
      }
    }

    // Initialize TokenProvider for new current wallet
    if (currentUserId != null && currentWalletName != null) {
      await tokenProviderCoordinator.getOrCreate(currentUserId!);
    }

    notifyListeners();
  }

  Future<void> refreshWallets() async {
    await walletService.reload();
  }

  Future<void> saveMnemonic(String walletName, String userId, String mnemonic) async {
    await walletService.saveMnemonic(walletName, userId, mnemonic);
  }

  Future<String?> getMnemonic(String walletName, String userId) async {
    return await walletService.getMnemonic(walletName, userId);
  }

  // ==================== SECURITY ====================
  Future<void> setAutoLockTimeout(int minutes) async {
    await securityService.setAutoLockTimeout(minutes);
    notifyListeners();
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await securityService.setBiometricEnabled(enabled);
    notifyListeners();
  }

  void lockApp() => securityService.lockApp();
  void unlockApp() => securityService.unlockApp();

  Future<Map<String, dynamic>> getDeviceInfo() async {
    return await securityService.getDeviceInfo();
  }

  Future<bool> isBiometricSupported() async {
    return await securityService.isBiometricSupported();
  }

  Future<bool> isFaceIdSupported() async {
    return await securityService.isFaceIdSupported();
  }

  // ==================== SETTINGS ====================
  Future<void> setPushNotificationsEnabled(bool enabled) async {
    await appSettingsService.setPushNotificationsEnabled(enabled);
    notifyListeners();
  }

  Future<void> setDeviceToken(String token) async {
    await appSettingsService.setDeviceToken(token);
    notifyListeners();
  }

  Future<void> setLanguage(String language) async {
    await appSettingsService.setLanguage(language);
    notifyListeners();
  }

  Future<void> setCurrency(String currency) async {
    await appSettingsService.setCurrency(currency);
    notifyListeners();
  }

  // ==================== DATA MANAGEMENT ====================
  Future<void> clearAllData() async {
    tokenProviderCoordinator.clearAll();
    try {
      await ServiceLocator.get<SecureStorage>().clearAllSecureData();
      await walletService.clearAllData();
      await securityService.clearData();
      notifyListeners();
    } catch (e, st) {
      SecureLog.e('Error clearing data', error: e, stackTrace: st);
      _reportError(e, 'Failed to clear data.', st);
    }
  }

  Future<void> resetToFreshInstall() async {
    tokenProviderCoordinator.clearAll();
    try {
      await ServiceLocator.get<SecureStorage>().clearAllSecureData();
      await walletService.clearAllData();
      await securityService.clearData();
      notifyListeners();
    } catch (e, st) {
      SecureLog.e('Error resetting app', error: e, stackTrace: st);
      _reportError(e, 'Failed to reset app.', st);
    }
  }

  void _reportError(Object error, String message, [StackTrace? stackTrace]) {
    try {
      ServiceLocator.get<ErrorService>().report(
        error,
        message: message,
        stackTrace: stackTrace,
      );
    } catch (e) {
      SecureLog.e('AppProvider: ErrorService unavailable', error: e);
    }
  }

  @override
  void dispose() {
    mounted = false;
    super.dispose();
  }
}
