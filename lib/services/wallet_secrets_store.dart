import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../utils/secure_log.dart';
import 'wallet_secure_storage.dart';
import '../di/service_locator.dart';

/// Passcode verifier and other critical secrets — secure storage only.
class WalletSecretsStore {
  WalletSecretsStore._();

  static const _migrationDoneKey = 'wallet_secrets_migrated_v1';
  static bool _isMigrating = false;
  static bool? _migrationDoneCache;

  static const Set<String> _criticalKeys = {
    'passcode_hash',
    'passcode_salt',
    'encrypted_private_keys',
  };

  static Future<void> ensureMigratedFromLegacyPrefs() async {
    if (_migrationDoneCache == true) return;
    
    // 1. Quick check without any locking
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_migrationDoneKey) == true) {
        _migrationDoneCache = true;
        return;
      }
    } catch (e) {
      SecureLog.w('Error checking migration state', error: e);
    }

    // 2. Handle concurrent migration attempts
    if (_isMigrating) {
      int waitCount = 0;
      while (_isMigrating && waitCount < 50) { // Max 5 seconds
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }
      if (_migrationDoneCache == true) return;
      if (_isMigrating) {
        SecureLog.w('WalletSecretsStore: Migration is taking too long, proceeding anyway');
        return;
      }
    }

    _isMigrating = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_migrationDoneKey) == true) {
        _migrationDoneCache = true;
        _isMigrating = false;
        return;
      }
      
      SecureLog.d('WalletSecretsStore: Starting migration from legacy prefs...');

      for (final key in _criticalKeys) {
        try {
          final legacy = prefs.getString(key);
          if (legacy == null) continue;
          
          // Try to read existing with short timeout
          final existing = await WalletSecureStorage.instance.read(key: key)
              .timeout(const Duration(seconds: 1), onTimeout: () => null);
              
          if (existing == null) {
            await WalletSecureStorage.instance.write(key: key, value: legacy)
                .timeout(const Duration(seconds: 2), onTimeout: () {});
          }
          
          await prefs.remove(key);
        } catch (e) {
          SecureLog.e('WalletSecretsStore: Migration failed for $key', error: e);
          // If we hit a decryption error, we might want to skip this key to avoid hang
          if (e.toString().contains('AEADBadTagException') || e.toString().contains('BAD_DECRYPT')) {
             SecureLog.e('WalletSecretsStore: Fatal decryption error during migration for $key. Skipping.');
          }
        }
      }

      await prefs.setBool(_migrationDoneKey, true);
      _migrationDoneCache = true;
      SecureLog.d('WalletSecretsStore: Migration sequence finished');
    } catch (e) {
      SecureLog.e('WalletSecretsStore: Global migration error', error: e);
    } finally {
      _isMigrating = false;
    }
  }

  static Future<void> writeCritical(String key, String value) async {
    await ensureMigratedFromLegacyPrefs();
    await WalletSecureStorage.instance.write(key: key, value: value).timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        SecureLog.w('WalletSecretsStore: Write timeout for key "$key"');
        throw Exception('Secure storage write timeout');
      },
    );
  }

  static Future<String?> readCritical(String key) async {
    await ensureMigratedFromLegacyPrefs();
    try {
      return await WalletSecureStorage.instance.read(key: key).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          SecureLog.w('WalletSecretsStore: Read timeout for key "$key"');
          return null;
        },
      );
    } catch (e) {
      SecureLog.e('WalletSecretsStore: Read error for key "$key"', error: e);
      if (e.toString().contains('AEADBadTagException') || e.toString().contains('BAD_DECRYPT')) {
         // This is the fatal error the user is seeing. 
         // Since resetOnError is true, the plugin might have cleared things already.
      }
      return null;
    }
  }

  static Future<void> deleteCritical(String key) async {
    await WalletSecureStorage.instance.delete(key: key).timeout(
      const Duration(seconds: 3),
      onTimeout: () => SecureLog.w('WalletSecretsStore: Delete timeout for key "$key"'),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
