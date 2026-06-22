/// In-memory cache for values already read from SecureStorage /
/// SharedPreferences during startup.
///
/// Once a value is resolved by [FastRouteResolver] or the early bootstrap,
/// downstream code (e.g. [AppProvider], [AppRouteResolver]) reads from
/// this cache instead of making redundant platform-channel round-trips.
class StartupCache {
  StartupCache._();

  static final _store = <String, Object?>{};

  // ── Key constants ──────────────────────────────────────────────

  static const String hasValidWallet = 'hasValidWallet';
  static const String hasPasscode = 'hasPasscode';
  static const String isPasscodeEnabled = 'isPasscodeEnabled';
  static const String walletsList = 'walletsList';
  static const String walletNames = 'walletNames';
  static const String currentUserId = 'currentUserId';
  static const String currentWalletName = 'currentWalletName';

  // ── Public API ─────────────────────────────────────────────────

  /// Store a value.
  static void put(String key, Object? value) {
    _store[key] = value;
  }

  /// Retrieve a value, or [defaultValue] when absent.
  static T? get<T>(String key, {T? defaultValue}) {
    final v = _store[key];
    if (v is T) return v;
    return defaultValue;
  }

  /// True when [key] has been stored (even if the stored value is null).
  static bool contains(String key) => _store.containsKey(key);

  /// Pre-populate cache with values already resolved by
  /// [FastRouteResolver] so later code reads from memory.
  static void warmFromFastResolver({
    required bool hasValidWallet,
    required bool hasPasscode,
    required bool isPasscodeEnabled,
  }) {
    put(StartupCache.hasValidWallet, hasValidWallet);
    put(StartupCache.hasPasscode, hasPasscode);
    put(StartupCache.isPasscodeEnabled, isPasscodeEnabled);
  }

  /// Clear all entries (e.g. on logout).
  static void clear() => _store.clear();
}
