import 'package:shared_preferences/shared_preferences.dart';

/// Self-custody mode flags (non-custodial).
class WalletModePreferences {
  static const _kSelfCustody = 'wallet_self_custody_enabled';

  /// Local signing and on-chain indexers (default on).
  static Future<bool> isSelfCustodyEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSelfCustody) ?? true;
  }

  static Future<void> setSelfCustodyEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSelfCustody, value);
  }

  /// When true, balance/history should not call custodial read APIs.
  static Future<bool> usesLocalBalanceOnly() async => isSelfCustodyEnabled();

  /// Custodial balance/history APIs are disabled for this app release.
  static Future<bool> usesCustodialBalanceApis() async => false;

  // ── Migration flags (non-custodial migration) ──

  static const _kMigrationComplete = 'wallet_migration_complete';
  static const _kMigrationServerPending = 'migration_server_pending_';

  /// Returns true if a forced migration is still needed.
  static Future<bool> needsForcedMigration() async {
    final prefs = await SharedPreferences.getInstance();
    final complete = prefs.getBool(_kMigrationComplete) ?? false;
    return !complete;
  }

  static Future<void> markMigrationComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMigrationComplete, true);
  }

  static Future<void> markMigrationIncomplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMigrationComplete, false);
  }

  static Future<bool> isMigrationServerPending(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_kMigrationServerPending$userId') ?? false;
  }

  static Future<void> setMigrationServerPending(
      String userId, bool pending) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_kMigrationServerPending$userId', pending);
  }
}
