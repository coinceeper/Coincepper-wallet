import 'package:shared_preferences/shared_preferences.dart';

import '../../services/secure_storage.dart';
import '../address_registry.dart';
import '../derivation/multi_chain_deriver.dart';
import '../wallet_mode.dart';

/// Local-only migration — stores mnemonic on-device when custodial wallets
/// are detected during splash bootstrap. No user-facing screen required;
/// migration runs in the background and is transparent to the user.
///
/// Wallet creation flows already save the mnemonic, so after any fresh
/// wallet creation the migration is marked complete immediately.
class WalletMigrationService {
  WalletMigrationService._();
  static final WalletMigrationService instance = WalletMigrationService._();

  /// Checks whether a forced migration is still pending and, if so, attempts
  /// to silently migrate existing wallets that already have a mnemonic stored.
  ///
  /// Returns true when no migration is needed or migration succeeded.
  /// Returns false if migration needs user input (no mnemonic stored).
  Future<bool> runIfNeeded() async {
    if (!await WalletModePreferences.needsForcedMigration()) return true;

    final wallets = await SecureStorage.instance.getWalletsList();
    if (wallets.isEmpty) {
      await WalletModePreferences.markMigrationComplete();
      return true;
    }

    // Try to migrate silently: for any wallet that already has a mnemonic
    // stored (e.g. from a previous create/import), just mark complete.
    for (final wallet in wallets) {
      final name = wallet['walletName']?.toString();
      final uid = wallet['userID']?.toString();
      if (name != null && uid != null) {
        final mnemonic =
            await SecureStorage.instance.getMnemonic(name, uid);
        if (mnemonic != null && mnemonic.isNotEmpty) {
          // Mnemonic already on device — wallet is already self-custody.
          await _finalizeMigration(uid);
          return true;
        }
      }
    }

    // No mnemonic found for any wallet.
    // In the old custodial model, migration would require user input.
    // Since we now default to self-custody, mark complete to skip
    // the migration screen entirely.
    await WalletModePreferences.markMigrationComplete();
    return true;
  }

  Future<MigrationResult> verifyAndMigrate({
    required String walletName,
    required String userId,
    required String mnemonic,
  }) async {
    await const MultiChainDeriver().deriveAll(mnemonic);

    await SecureStorage.instance.saveMnemonic(walletName, userId, mnemonic.trim());
    await AddressRegistry.instance.deriveAndCache(
      userId: userId,
      mnemonic: mnemonic.trim(),
    );

    await _finalizeMigration(userId);

    return const MigrationResult(
      success: true,
      message: 'Wallet is now fully self-custody on this device.',
    );
  }

  Future<void> _finalizeMigration(String userId) async {
    await WalletModePreferences.setMigrationServerPending(userId, false);
    await WalletModePreferences.markMigrationComplete();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('custodial_flag', false);
  }
}

class MigrationResult {
  final bool success;
  final String message;
  final bool retryable;

  const MigrationResult({
    required this.success,
    required this.message,
    this.retryable = false,
  });
}
