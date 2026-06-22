import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../di/service_locator.dart';
import '../navigation/route_paths.dart';
import '../utils/secure_log.dart';
import 'secure_storage.dart';
import 'passcode_manager.dart';
import 'sensitive_data.dart';
import 'token_preferences.dart';

/// Manages wallet state and navigation logic
class WalletStateManager {
  static WalletStateManager get instance => ServiceLocator.get<WalletStateManager>();
  
  WalletStateManager._();
  /// DI constructor. Use [instance] for singleton access.
  WalletStateManager();

  Future<bool> hasWallet() async {
    try {
      final wallets = await ServiceLocator.get<SecureStorage>().getWalletsList().timeout(const Duration(seconds: 3));
      return wallets.isNotEmpty;
    } catch (e) {
      SecureLog.w('Error checking wallet existence', error: e);
      return false;
    }
  }

  Future<bool> hasPasscode() async {
    try {
      final isSet = await PasscodeManager.isPasscodeSet().timeout(const Duration(seconds: 3));
      return isSet;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isAuthenticated() async {
    return await hasWallet() && await hasPasscode();
  }

  /// بررسی وجود کیف پول معتبر (بدون بازگرداندن خود منیمونیک).
  ///
  /// امنیت: منیمونیک هرگز به عنوان String در این متد ذخیره نمی‌شود.
  /// فقط بررسی می‌کند که کلید `Mnemonic_` در SecureStorage وجود دارد.
  Future<bool> hasValidWallet() async {
    try {
      final wallets = await ServiceLocator.get<SecureStorage>().getWalletsList();
      if (wallets.isEmpty) {
        if (Platform.isIOS) return await _checkValidWalletFallback();
        return false;
      }
      for (final wallet in wallets) {
        final walletName = wallet['walletName'];
        final userId = wallet['userID'];
        if (walletName != null && userId != null) {
          final exists = await ServiceLocator.get<SecureStorage>()
              .mnemonicExists(walletName, userId);
          if (exists) return true;
        }
      }
      // On iOS, if the wallets list exists but mnemonics weren't found
      // (e.g., Keychain accessibility issue), try the fallback check.
      if (Platform.isIOS) return await _checkValidWalletFallback();
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<String> getInitialScreen() async {
    try {
      if (await isEnhancedFreshInstall()) return RoutePaths.importCreate;
      if (!await hasValidWallet()) return RoutePaths.importCreate;
      if (!await hasPasscode()) return RoutePaths.passcodeSetup;
      return RoutePaths.enterPasscode;
    } catch (e) {
      return RoutePaths.importCreate;
    }
  }

  Future<void> saveWalletInfo({
    required String walletName,
    required String userId,
    required String walletId,
    String? mnemonic,
    List<String>? activeTokens,
  }) async {
    try {
      final futures = <Future<void>>[];
      futures.add(ServiceLocator.get<SecureStorage>().saveUserId(walletName, userId));
      futures.add(ServiceLocator.get<SecureStorage>().saveSelectedWallet(walletName, userId));
      if (mnemonic != null) {
        // استفاده از scope امن برای ذخیره منیمونیک
        final sensitive = SensitiveString.fromString(mnemonic);
        try {
          await sensitive.useAsync((m) async {
            await ServiceLocator.get<SecureStorage>().saveMnemonic(walletName, userId, m);
          });
        } finally {
          sensitive.dispose();
        }
      }
      // Token enable/disable state is managed by TokenPreferences (SharedPreferences)
      // — not by SecureStorage. The initial default tokens (BTC, ETH, TRX) are set
      // by TokenPreferences.initialize() when the TokenProvider is created.
      await Future.wait(futures);
      
      final existingWallets = await ServiceLocator.get<SecureStorage>().getWalletsList();
      final walletExists = existingWallets.any((w) => w['walletName'] == walletName && w['userID'] == userId);
      if (!walletExists) {
        existingWallets.add({'walletName': walletName, 'userID': userId, 'walletId': walletId});
        await ServiceLocator.get<SecureStorage>().saveWalletsList(existingWallets);
      }
      _markAppAsUsed();
    } catch (e) {
      SecureLog.e('Error saving wallet info', error: e);
      rethrow;
    }
  }

  Future<void> _markAppAsUsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_has_been_used', true);
      await prefs.setBool('wallet_imported', true);
    } catch (e) {
      SecureLog.w('Error marking app as used', error: e);
    }
  }

  /// @Deprecated('Use TokenPreferences instead — this writes to a stale secondary store')
  Future<void> saveActiveTokensForWallet(String walletName, String userId, List<String> tokens) async {
    await ServiceLocator.get<SecureStorage>().saveActiveTokens(walletName, userId, tokens);
  }

  Future<void> saveBalanceCacheForWallet(String walletName, String userId, Map<String, double> balances) async {
    await ServiceLocator.get<SecureStorage>().saveWalletBalanceCache(walletName, userId, balances);
  }

  /// دریافت اطلاعات کامل کیف پول (بدون منیمونیک).
  ///
  /// ⚠️ امنیت: این متد منیمونیک را برنمی‌گرداند.
  /// برای دسترسی به منیمونیک از [getMnemonicSafe] استفاده کنید.
  ///
  /// **Token State Source of Truth**: [TokenPreferences] جایگزین SecureStorage
  /// برای وضعیت فعال/غیرفعال توکن‌ها شده است.
  Future<Map<String, dynamic>?> getCompleteWalletInfo(String walletName, String userId) async {
    try {
      final mnemonicExists = await ServiceLocator.get<SecureStorage>()
          .mnemonicExists(walletName, userId);
      if (!mnemonicExists) return null;

      // Read active tokens from TokenPreferences (single source of truth)
      // instead of the stale SecureStorage.getActiveTokens()
      List<String> activeTokens;
      try {
        final prefs = TokenPreferences(userId: userId, walletName: walletName);
        await prefs.initialize();
        activeTokens = prefs.getAllEnabledTokenNames();
      } catch (e) {
        SecureLog.w('Error reading TokenPreferences for wallet info', error: e);
        activeTokens = [];
      }

      return {
        'walletName': walletName,
        'userId': userId,
        'walletId': walletName,
        'activeTokens': activeTokens,
      };
    } catch (e) {
      SecureLog.w('Error getting wallet info', error: e);
      return null;
    }
  }

  /// دسترسی امن به منیمونیک از طریق callback.
  ///
  /// منیمونیک از SecureStorage خوانده می‌شود، در [SensitiveString] قرار می‌گیرد،
  /// به [callback] داده می‌شود و پس از بازگشت callback پاک می‌شود.
  Future<T> getMnemonicSafe<T>({
    required String walletName,
    required String userId,
    required Future<T> Function(String mnemonic) callback,
  }) async {
    return MnemonicScope.use(
      () => ServiceLocator.get<SecureStorage>().getMnemonic(walletName, userId),
      callback: callback,
    );
  }

  Future<void> clearWalletData() async {
    await ServiceLocator.get<SecureStorage>().clearAllSecureData();
  }

  Future<void> forceClearAllData() async {
    await ServiceLocator.get<SecureStorage>().clearAllSecureData();
  }

  Future<bool> isFreshInstall() async => await isEnhancedFreshInstall();

  Future<bool> isEnhancedFreshInstall() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
      if (prefs.getKeys().isNotEmpty) return false;
      final keys = await ServiceLocator.get<SecureStorage>().getAllKeys().timeout(const Duration(seconds: 2), onTimeout: () => []);
      return keys.isEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _checkValidWalletFallback() async {
    try {
      final allKeys = await ServiceLocator.get<SecureStorage>().getAllKeys().timeout(const Duration(seconds: 2));
      if (allKeys.any((k) => k.startsWith('Mnemonic_'))) return true;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString('selected_wallet') != null) return true;
      if (await PasscodeManager.isPasscodeSet()) return true;
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, String>?> getCurrentWallet() async {
    try {
      final name = await ServiceLocator.get<SecureStorage>().getSelectedWallet();
      final userId = await ServiceLocator.get<SecureStorage>().getSelectedUserId();
      if (name != null && userId != null) {
        return {'name': name, 'userId': userId, 'walletId': name};
      }
      final wallets = await ServiceLocator.get<SecureStorage>().getWalletsList();
      if (wallets.isNotEmpty) {
        final w = wallets.first;
        return {'name': w['walletName'] ?? '', 'userId': w['userID'] ?? '', 'walletId': w['walletId'] ?? ''};
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// @deprecated Preserved for old UI screen compatibility
  @Deprecated('Token key management is now handled by TokenProvider')
  Future<bool> saveActiveTokenKeysForWallet(String walletName, String userId, List<String> keys) async {
    SecureLog.w('saveActiveTokenKeysForWallet called but is a no-op');
    return true;
  }
}
