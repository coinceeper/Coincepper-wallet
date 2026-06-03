import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

import 'wallet_secure_storage.dart';

/// سرویس ذخیره‌سازی امن برای تمام پلتفرم‌ها
class SecureStorage {
  static SecureStorage? _instance;
  static SecureStorage get instance => _instance ??= SecureStorage._();
  
  SecureStorage._();
  
  FlutterSecureStorage get _storage => WalletSecureStorage.instance;

  final Map<String, dynamic> _memoryCache = {};

  Future<void> saveSecureData(String key, String value) async {
    try {
      _memoryCache[key] = value;
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('Error saving secure data: $e');
      rethrow;
    }
  }

  Future<String?> getSecureData(String key) async {
    try {
      if (_memoryCache.containsKey(key)) {
        return _memoryCache[key] as String?;
      }
      
      final value = await _storage.read(key: key).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('⚠️ SecureStorage: Read timeout for key "$key"');
          return null;
        },
      );
      _memoryCache[key] = value;
      return value;
    } catch (e) {
      debugPrint('⚠️ SecureStorage: Read error for key "$key": $e');
      return null;
    }
  }

  Future<void> saveSecureJson(String key, Map<String, dynamic> data) async {
    try {
      _memoryCache[key] = data;
      final jsonString = jsonEncode(data);
      await _storage.write(key: key, value: jsonString);
    } catch (e) {
      debugPrint('Error saving secure JSON: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getSecureJson(String key) async {
    try {
      if (_memoryCache.containsKey(key)) {
        final cached = _memoryCache[key];
        if (cached is Map<String, dynamic>) return cached;
      }

      final jsonString = await _storage.read(key: key).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('⚠️ SecureStorage: Read JSON timeout for key "$key"');
          return null;
        },
      );
      if (jsonString != null) {
        try {
          final data = jsonDecode(jsonString) as Map<String, dynamic>;
          _memoryCache[key] = data;
          return data;
        } catch (e) {
          debugPrint('⚠️ SecureStorage: JSON parse error for key "$key": $e');
          return null;
        }
      }
      _memoryCache[key] = null;
      return null;
    } catch (e) {
      debugPrint('⚠️ SecureStorage: read error for key "$key": $e');
      return null;
    }
  }

  Future<void> deleteSecureData(String key) async {
    try {
      _memoryCache.remove(key);
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('Error deleting secure data: $e');
      rethrow;
    }
  }

  Future<void> clearAllSecureData() async {
    try {
      _memoryCache.clear();
      await _storage.deleteAll();
      debugPrint('✅ All secure data cleared');
    } catch (e) {
      debugPrint('Error clearing secure data: $e');
      rethrow;
    }
  }

  Future<void> deleteAll() async {
    await clearAllSecureData();
  }

  Future<bool> containsKey(String key) async {
    try {
      return await _storage.containsKey(key: key);
    } catch (e) {
      debugPrint('Error checking key existence: $e');
      return false;
    }
  }

  Future<List<String>> getAllKeys() async {
    try {
      final keys = await _storage.readAll();
      return keys.keys.toList();
    } catch (e) {
      debugPrint('Error getting all keys: $e');
      return [];
    }
  }

  // Wallet Methods
  Future<void> saveUserId(String walletName, String userId) async {
    await saveSecureData('UserID_$walletName', userId);
  }

  Future<String?> getUserIdForWallet(String walletName) async {
    return await getSecureData('UserID_$walletName');
  }

  Future<void> saveMnemonic(String walletName, String userId, String mnemonic) async {
    await saveSecureData('Mnemonic_${userId}_$walletName', mnemonic);
  }

  Future<String?> getMnemonic(String walletName, String userId) async {
    return await getSecureData('Mnemonic_${userId}_$walletName');
  }

  Future<void> saveSelectedWallet(String walletName, String userId) async {
    await saveSecureData('selected_wallet', walletName);
    await saveSecureData('selected_user_id', userId);
  }

  Future<String?> getSelectedWallet() async {
    return await getSecureData('selected_wallet');
  }

  Future<String?> getSelectedUserId() async {
    return await getSecureData('selected_user_id');
  }

  Future<void> saveWalletsList(List<Map<String, String>> wallets) async {
    await saveSecureJson('user_wallets', {'wallets': wallets});
  }

  Future<List<Map<String, String>>> getWalletsList() async {
    final data = await getSecureJson('user_wallets');
    if (data != null && data['wallets'] != null) {
      return List<Map<String, String>>.from(
        (data['wallets'] as List).map((item) => Map<String, String>.from(item as Map)),
      );
    }
    return [];
  }

  Future<void> saveWalletIdForWallet(String walletName, String walletId) async {
    await saveSecureData('WalletID_$walletName', walletId);
  }

  Future<String?> getWalletIdForWallet(String walletName) async {
    return await getSecureData('WalletID_$walletName');
  }

  Future<String?> getWalletIdForSelectedWallet() async {
    final selectedWallet = await getSelectedWallet();
    if (selectedWallet != null) {
      return await getWalletIdForWallet(selectedWallet);
    }
    return null;
  }

  Future<void> saveDeviceToken(String deviceToken) async {
    await saveSecureData('DeviceToken', deviceToken);
  }

  Future<String?> getDeviceToken() async {
    return await getSecureData('DeviceToken');
  }

  Future<void> saveSecuritySettings(Map<String, dynamic> settings) async {
    await saveSecureJson('SecuritySettings', settings);
  }

  Future<Map<String, dynamic>?> getSecuritySettings() async {
    return await getSecureJson('SecuritySettings');
  }

  // Debug Methods
  Future<void> debugPrintAllKeychainKeys() async {
    try {
      final allData = await _storage.readAll();
      print('📱 Keychain keys: ${allData.keys.join(", ")}');
    } catch (e) {
      print('❌ Error debugging keychain: $e');
    }
  }

  Future<void> checkAndClearOrphanedData() async {
    print('🔍 Checking for orphaned data...');
  }

  Future<void> debugForceClearAllData() async {
    await clearAllSecureData();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // Compatibility static methods
  static Future<String?> getUserId() async {
    return await instance.getSelectedUserId();
  }

  static Future<String?> getWalletId() async {
    return await instance.getSelectedWallet();
  }

  Future<String?> getUserIdForSelectedWallet() async => getSelectedUserId();
  
  Future<void> saveActiveTokens(String walletName, String userId, List<String> tokens) async {
     await saveSecureJson('ActiveTokens_${userId}_$walletName', {'tokens': tokens});
  }
  
  Future<List<String>> getActiveTokens(String walletName, String userId) async {
    final data = await getSecureJson('ActiveTokens_${userId}_$walletName');
    if (data != null && data['tokens'] != null) return List<String>.from(data['tokens'] as List);
    return [];
  }
  
  Future<void> saveActiveTokenKeys(String walletName, String userId, List<String> keys) async {
     await saveSecureJson('ActiveTokenKeys_${userId}_$walletName', {'tokenKeys': keys});
  }
  
  Future<List<String>> getActiveTokenKeys(String walletName, String userId) async {
    final data = await getSecureJson('ActiveTokenKeys_${userId}_$walletName');
    if (data != null && data['tokenKeys'] != null) return List<String>.from(data['tokenKeys'] as List);
    return [];
  }
  
  Future<void> saveWalletBalanceCache(String walletName, String userId, Map<String, double> balances) async {
     await saveSecureJson('BalanceCache_${userId}_$walletName', balances);
  }

  Future<Map<String, double>> getWalletBalanceCache(String walletName, String userId) async {
    final data = await getSecureJson('BalanceCache_${userId}_$walletName');
    if (data != null) return Map<String, double>.from(data.map((k, v) => MapEntry(k, (v as num).toDouble())));
    return {};
  }
}
