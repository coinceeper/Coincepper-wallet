import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import 'platform_storage_manager.dart';
import 'wallet_crypto.dart';
import 'wallet_secrets_store.dart';

/// Manages passcode security and encryption.
class PasscodeManager {
  static const String _passcodeHashKey = 'passcode_hash';
  static const String _attemptsKey = 'failed_attempts';
  static const String _lockoutUntilKey = 'lockout_until';
  static const String _encryptedKeysKey = 'encrypted_private_keys';

  static const int _maxAttempts = 5;
  static const int _lockoutDuration = 300;
  static const int _passcodeLength = 6;

  static final PlatformStorageManager _platformStorage = PlatformStorageManager.instance;

  static Future<bool> isPasscodeSet() async {
    try {
      final results = await Future.wait([
        _platformStorage.getData(_passcodeHashKey, isCritical: true),
        _platformStorage.getData('passcode_salt', isCritical: true),
      ]).timeout(const Duration(seconds: 3), onTimeout: () => [null, null]);
      
      return results[0] != null && results[1] != null;
    } catch (e) {
      debugPrint('⚠️ PasscodeManager.isPasscodeSet error: $e');
      return false;
    }
  }

  static Future<bool> setPasscode(String passcode) async {
    if (passcode.length != _passcodeLength) {
      throw Exception('Passcode must be $_passcodeLength digits');
    }

    try {
      final salt = WalletCrypto.generateSaltBase64();
      final hash = _fastHashPasscode(passcode, salt);

      await Future.wait([
        _platformStorage.saveData(_passcodeHashKey, hash, isCritical: true),
        _platformStorage.saveData('passcode_salt', salt, isCritical: true),
        _platformStorage.deleteData(_attemptsKey),
        _platformStorage.deleteData(_lockoutUntilKey),
      ]).timeout(const Duration(seconds: 5));

      _markAppAsUsedForPasscode();
      return true;
    } catch (e) {
      debugPrint('⚠️ PasscodeManager.setPasscode error: $e');
      return false;
    }
  }

  static Future<bool> verifyPasscode(String passcode) async {
    try {
      if (await isLocked().timeout(const Duration(seconds: 2), onTimeout: () => false)) {
        throw Exception('Wallet is locked. Please try again later.');
      }

      final results = await Future.wait([
        _platformStorage.getData(_passcodeHashKey, isCritical: true),
        _platformStorage.getData('passcode_salt', isCritical: true),
      ]).timeout(const Duration(seconds: 4), onTimeout: () => [null, null]);
      
      final savedHash = results[0];
      final salt = results[1];

      if (savedHash == null || salt == null) {
        debugPrint('❌ PasscodeManager: Stored data missing or corrupted');
        return false;
      }

      final currentHash = _fastHashPasscode(passcode, salt);
      var isValid = currentHash == savedHash;
      
      if (!isValid) {
        // Fallback for legacy PBKDF2 hash
        final legacyHash = await WalletCrypto.hashPasscode(passcode, salt)
            .timeout(const Duration(seconds: 3), onTimeout: () => '');
        isValid = legacyHash == savedHash;
        if (isValid) {
          await _platformStorage.saveData(_passcodeHashKey, currentHash, isCritical: true)
              .timeout(const Duration(seconds: 2), onTimeout: () {});
        }
      }

      if (isValid) {
        unawaited(_platformStorage.deleteData(_attemptsKey));
        unawaited(_platformStorage.deleteData(_lockoutUntilKey));
      } else {
        await _recordFailedAttempt();
      }

      return isValid;
    } catch (e) {
      debugPrint('❌ PasscodeManager.verifyPasscode exception: $e');
      return false;
    }
  }

  static String _fastHashPasscode(String passcode, String salt) {
    final data = utf8.encode(passcode + salt);
    return sha256.convert(data).toString();
  }

  static Future<int> getRemainingAttempts() async {
    try {
      final attemptsStr = await _platformStorage.getData(_attemptsKey)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      final attempts = attemptsStr != null ? int.tryParse(attemptsStr) ?? 0 : 0;
      return _maxAttempts - attempts;
    } catch (e) {
      return _maxAttempts;
    }
  }

  static Future<bool> isLocked() async {
    try {
      final lockoutUntilStr = await _platformStorage.getData(_lockoutUntilKey)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      if (lockoutUntilStr != null) {
        final lockoutUntil = int.tryParse(lockoutUntilStr);
        if (lockoutUntil != null) {
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          if (now < lockoutUntil) return true;
          unawaited(_platformStorage.deleteData(_lockoutUntilKey));
          unawaited(_platformStorage.deleteData(_attemptsKey));
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> _recordFailedAttempt() async {
    try {
      final attemptsStr = await _platformStorage.getData(_attemptsKey)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      final attempts = (attemptsStr != null ? int.tryParse(attemptsStr) ?? 0 : 0) + 1;
      await _platformStorage.saveData(_attemptsKey, attempts.toString());
      if (attempts >= _maxAttempts) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await _platformStorage.saveData(_lockoutUntilKey, (now + _lockoutDuration).toString());
      }
    } catch (_) {}
  }

  static Future<int> getLockoutRemainingTime() async {
    try {
      final lockoutUntilStr = await _platformStorage.getData(_lockoutUntilKey)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      if (lockoutUntilStr != null) {
        final lockoutUntil = int.tryParse(lockoutUntilStr);
        if (lockoutUntil != null) {
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          return (lockoutUntil - now) > 0 ? (lockoutUntil - now) : 0;
        }
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  static Future<void> clearPasscode() async {
    try {
      await Future.wait([
        _platformStorage.deleteData(_passcodeHashKey),
        _platformStorage.deleteData('passcode_salt'),
        _platformStorage.deleteData(_attemptsKey),
        _platformStorage.deleteData(_lockoutUntilKey),
        WalletSecretsStore.deleteCritical(_encryptedKeysKey),
      ]).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  static Future<void> _markAppAsUsedForPasscode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_has_been_used', true);
      await prefs.setBool('passcode_set', true);
    } catch (_) {}
  }
}
