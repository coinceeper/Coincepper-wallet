import 'dart:async';
import '../models/crypto_token.dart';
import '../utils/secure_log.dart';

/// Manages price refresh logic and periodic update scheduling.
///
/// Uses callback-based approach instead of importing providers directly.
/// This keeps the service layer independent of the presentation layer.
class PriceRefreshService {
  Timer? _periodicTimer;
  bool _isRefreshing = false;

  /// Whether a refresh is currently in progress.
  bool get isRefreshing => _isRefreshing;

  /// Perform a full refresh of both token balances and prices.
  ///
  /// [refreshActiveTokens] — callback to refresh active token data.
  /// [getEnabledTokenSymbols] — callback returning enabled token symbols.
  /// [loadPrices] — callback to load prices for given symbols.
  Future<void> refreshPricesAndBalances({
    required Future<void> Function() refreshActiveTokens,
    required List<String> Function() getEnabledTokenSymbols,
    required Future<void> Function(List<String> symbols) loadPrices,
  }) async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      await refreshActiveTokens();
      final symbols = getEnabledTokenSymbols();
      if (symbols.isNotEmpty) {
        await loadPrices(symbols);
      }
    } catch (e) {
      SecureLog.e('PriceRefreshService: Error refreshing', error: e);
    }

    _isRefreshing = false;
  }

  /// Lightweight price-only refresh (no balance reload).
  Future<void> refreshPricesForEnabledTokens({
    required List<String> Function() getEnabledTokenSymbols,
    required Future<void> Function(List<String> symbols) loadPrices,
  }) async {
    final symbols = getEnabledTokenSymbols();
    if (symbols.isNotEmpty) {
      await loadPrices(symbols);
    }
  }

  /// Start a periodic timer that refreshes prices every [interval].
  void startPeriodicUpdates({
    required List<String> Function() getEnabledTokenSymbols,
    required Future<void> Function(List<String> symbols) loadPrices,
    Duration interval = const Duration(seconds: 30),
  }) {
    stopPeriodicUpdates();
    _periodicTimer = Timer.periodic(interval, (_) {
      refreshPricesForEnabledTokens(
        getEnabledTokenSymbols: getEnabledTokenSymbols,
        loadPrices: loadPrices,
      );
    });
  }

  /// Cancel the periodic timer if running.
  void stopPeriodicUpdates() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Release all resources.
  void dispose() {
    stopPeriodicUpdates();
  }
}
