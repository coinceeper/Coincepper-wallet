import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'wallet_secure_storage.dart';

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
    } catch (_) {}

    // 2. Handle concurrent migration attempts
    if (_isMigrating) {
      int waitCount = 0;
      while (_isMigrating && waitCount < 50) { // Max 5 seconds
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }
      if (_migrationDoneCache == true) return;
      if (_isMigrating) {
        debugPrint('⚠️ WalletSecretsStore: Migration is taking too long, proceeding anyway');
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
      
      debugPrint('📦 WalletSecretsStore: Starting migration from legacy prefs...');

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
          debugPrint('⚠️ WalletSecretsStore: Migration failed for $key: $e');
          // If we hit a decryption error, we might want to skip this key to avoid hang
          if (e.toString().contains('AEADBadTagException') || e.toString().contains('BAD_DECRYPT')) {
             debugPrint('🚨 WalletSecretsStore: Fatal decryption error during migration for $key. Skipping.');
          }
        }
      }

      await prefs.setBool(_migrationDoneKey, true);
      _migrationDoneCache = true;
      debugPrint('✅ WalletSecretsStore: Migration sequence finished');
    } catch (e) {
      debugPrint('❌ WalletSecretsStore: Global migration error: $e');
    } finally {
      _isMigrating = false;
    }
  }

  static Future<void> writeCritical(String key, String value) async {
    await ensureMigratedFromLegacyPrefs();
    await WalletSecureStorage.instance.write(key: key, value: value).timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('⚠️ WalletSecretsStore: Write timeout for key "$key"');
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
          debugPrint('⚠️ WalletSecretsStore: Read timeout for key "$key"');
          return null;
        },
      );
    } catch (e) {
      debugPrint('⚠️ WalletSecretsStore: Read error for key "$key": $e');
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
      onTimeout: () => debugPrint('⚠️ WalletSecretsStore: Delete timeout for key "$key"'),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
