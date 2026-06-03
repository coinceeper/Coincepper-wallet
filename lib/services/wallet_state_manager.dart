import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../navigation/route_paths.dart';
import 'secure_storage.dart';
import 'passcode_manager.dart';

/// Manages wallet state and navigation logic
class WalletStateManager {
  static WalletStateManager? _instance;
  static WalletStateManager get instance => _instance ??= WalletStateManager._();
  
  WalletStateManager._();

  Future<bool> hasWallet() async {
    try {
      final wallets = await SecureStorage.instance.getWalletsList().timeout(const Duration(seconds: 3));
      return wallets.isNotEmpty;
    } catch (e) {
      debugPrint('⚠️ Error checking wallet existence: $e');
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

  Future<bool> hasValidWallet() async {
    try {
      final wallets = await SecureStorage.instance.getWalletsList();
      if (wallets.isEmpty) {
        if (Platform.isIOS) return await _checkValidWalletFallback();
        return false;
      }
      for (final wallet in wallets) {
        final walletName = wallet['walletName'];
        final userId = wallet['userID'];
        if (walletName != null && userId != null) {
          final mnemonic = await SecureStorage.instance.getMnemonic(walletName, userId);
          if (mnemonic != null && mnemonic.isNotEmpty) return true;
        }
      }
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
      futures.add(SecureStorage.instance.saveUserId(walletName, userId));
      futures.add(SecureStorage.instance.saveSelectedWallet(walletName, userId));
      if (mnemonic != null) futures.add(SecureStorage.instance.saveMnemonic(walletName, userId, mnemonic));
      if (activeTokens != null) futures.add(SecureStorage.instance.saveActiveTokens(walletName, userId, activeTokens));
      await Future.wait(futures);
      
      final existingWallets = await SecureStorage.instance.getWalletsList();
      final walletExists = existingWallets.any((w) => w['walletName'] == walletName && w['userID'] == userId);
      if (!walletExists) {
        existingWallets.add({'walletName': walletName, 'userID': userId, 'walletId': walletId});
        await SecureStorage.instance.saveWalletsList(existingWallets);
      }
      _markAppAsUsed();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _markAppAsUsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_has_been_used', true);
      await prefs.setBool('wallet_imported', true);
    } catch (_) {}
  }

  Future<void> saveActiveTokensForWallet(String walletName, String userId, List<String> tokens) async {
    await SecureStorage.instance.saveActiveTokens(walletName, userId, tokens);
  }

  Future<void> saveActiveTokenKeysForWallet(String walletName, String userId, List<String> keys) async {
    await SecureStorage.instance.saveActiveTokenKeys(walletName, userId, keys);
  }

  Future<void> saveBalanceCacheForWallet(String walletName, String userId, Map<String, double> balances) async {
    await SecureStorage.instance.saveWalletBalanceCache(walletName, userId, balances);
  }

  Future<Map<String, dynamic>?> getCompleteWalletInfo(String walletName, String userId) async {
    try {
      final mnemonic = await SecureStorage.instance.getMnemonic(walletName, userId);
      final activeTokens = await SecureStorage.instance.getActiveTokens(walletName, userId);
      if (mnemonic != null && mnemonic.isNotEmpty) {
        return {
          'walletName': walletName,
          'userId': userId,
          'walletId': walletName,
          'mnemonic': mnemonic,
          'activeTokens': activeTokens,
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> clearWalletData() async {
    await SecureStorage.instance.clearAllSecureData();
  }

  Future<void> forceClearAllData() async {
    await SecureStorage.instance.clearAllSecureData();
  }

  Future<bool> isFreshInstall() async => await isEnhancedFreshInstall();

  Future<bool> isEnhancedFreshInstall() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
      if (prefs.getKeys().isNotEmpty) return false;
      final keys = await SecureStorage.instance.getAllKeys().timeout(const Duration(seconds: 2), onTimeout: () => []);
      return keys.isEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _checkValidWalletFallback() async {
    try {
      final allKeys = await SecureStorage.instance.getAllKeys().timeout(const Duration(seconds: 2));
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
      final name = await SecureStorage.instance.getSelectedWallet();
      final userId = await SecureStorage.instance.getSelectedUserId();
      if (name != null && userId != null) {
        return {'name': name, 'userId': userId, 'walletId': name};
      }
      final wallets = await SecureStorage.instance.getWalletsList();
      if (wallets.isNotEmpty) {
        final w = wallets.first;
        return {'name': w['walletName'] ?? '', 'userId': w['userID'] ?? '', 'walletId': w['walletId'] ?? ''};
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
