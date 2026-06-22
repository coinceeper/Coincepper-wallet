import 'dart:async';
import '../models/crypto_token.dart';
import '../services/balance_manager.dart';
import '../services/security_settings_manager.dart';
import '../utils/secure_log.dart';
import '../di/service_locator.dart';

/// Orchestrates home screen initialization without importing from providers.
///
/// Accepts only primitive parameters and domain interfaces, not UI-layer
/// ChangeNotifiers. This keeps the service layer independent of the
/// presentation layer.
class HomeInitService {
  bool _initialized = false;
  bool _isInitializing = false;

  /// Whether the home has completed its initial initialization.
  bool get isInitialized => _initialized;

  /// Whether initialization is currently in progress.
  bool get isInitializing => _isInitializing;


  /// Run the full home initialization sequence.
  ///
  /// [securityManager] — SecuritySettingsManager or any ISecurityManager impl.
  /// [apiService] — ApiService for BalanceManager initialization.
  /// [currentUserId], [currentWalletName] — current wallet identifiers.
  /// [ensureBitcoinEthereumEnabled] — callback to ensure default tokens exist.
  /// [loadPrices] — callback to fetch prices for enabled tokens.
  /// [getEnabledTokenSymbols] — callback returning list of enabled token symbols.
  ///
  /// This is idempotent — subsequent calls are no-ops once initialized.
  Future<void> initialize({
    required SecuritySettingsManager securityManager,
    required dynamic apiService,
    String? currentUserId,
    String? currentWalletName,
    Future<void> Function()? ensureBitcoinEthereumEnabled,
    Future<void> Function(List<String> symbols)? loadPrices,
    List<String> Function()? getEnabledTokenSymbols,
  }) async {
    if (_initialized || _isInitializing) return;
    _isInitializing = true;

    try {
      await securityManager.initialize();

      await ServiceLocator.get<BalanceManager>().initialize(apiService);

      if (currentUserId != null && currentWalletName != null) {
        await Future.delayed(const Duration(milliseconds: 300));
        await ServiceLocator.get<BalanceManager>().setCurrentUserAndWallet(
          currentUserId,
          currentWalletName,
        );
      }

      if (ensureBitcoinEthereumEnabled != null) {
        await ensureBitcoinEthereumEnabled();
      }

      if (loadPrices != null && getEnabledTokenSymbols != null) {
        final symbols = getEnabledTokenSymbols();
        if (symbols.isNotEmpty) {
          await loadPrices(symbols);
        }
      }

      _initialized = true;
    } catch (e) {
      SecureLog.e('HomeInitService: Error initializing', error: e);
    } finally {
      _isInitializing = false;
    }
  }

  /// Reset initialization state (e.g. on wallet switch).
  void reset() {
    _initialized = false;
    _isInitializing = false;
  }
}
