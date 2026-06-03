import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

import 'wallet_secrets_store.dart';

/// Non-critical prefs + critical secrets via [WalletSecretsStore] only.
class PlatformStorageManager {
  static PlatformStorageManager? _instance;
  static PlatformStorageManager get instance =>
      _instance ??= PlatformStorageManager._();

  PlatformStorageManager._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> saveData(String key, String value, {bool isCritical = false}) async {
    try {
      if (isCritical) {
        await WalletSecretsStore.writeCritical(key, value);
      } else {
        final prefs = await _getPrefs();
        await prefs.setString(key, value);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<String?> getData(String key, {bool isCritical = false}) async {
    try {
      if (isCritical) {
        return WalletSecretsStore.readCritical(key);
      }
      final prefs = await _getPrefs();
      return prefs.getString(key);
    } catch (e) {
      return null;
    }
  }

  Future<void> deleteData(String key) async {
    try {
      await WalletSecretsStore.deleteCritical(key);
      final prefs = await _getPrefs();
      await prefs.remove(key);
      await prefs.remove('${key}_timestamp');
    } catch (_) {}
  }

  Future<Map<String, dynamic>> checkDataIntegrity(String key) async {
    final prefs = await _getPrefs();
    final sharedPrefsValue = prefs.getString(key);
    final secureValue = await WalletSecretsStore.readCritical(key);
    return {
      'key': key,
      'platform': Platform.operatingSystem,
      'shared_prefs': sharedPrefsValue != null ? 'EXISTS' : 'NULL',
      'secure_storage': secureValue != null ? 'EXISTS' : 'NULL',
      'consistent': sharedPrefsValue == null || sharedPrefsValue == secureValue,
    };
  }

  Future<void> synchronizeStorages() async {
    await WalletSecretsStore.ensureMigratedFromLegacyPrefs();
  }

  Future<void> cleanupOldData({int maxAgeInDays = 30}) async {
    final prefs = await _getPrefs();
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    final maxAge = maxAgeInDays * 24 * 60 * 60 * 1000;
    final allKeys = prefs.getKeys();
    for (final key in allKeys) {
      if (!key.endsWith('_timestamp')) continue;
      final timestamp = prefs.getInt(key);
      if (timestamp != null && (currentTime - timestamp) > maxAge) {
        final dataKey = key.replaceAll('_timestamp', '');
        await deleteData(dataKey);
      }
    }
  }
}
