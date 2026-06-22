import 'dart:convert';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/secure_log.dart';

import 'platform_storage_manager.dart';
import 'wallet_crypto.dart';
import 'wallet_secrets_store.dart';
import '../di/service_locator.dart';

/// Manages passcode security and encryption.
///
/// ## امنیت هش پسورد
///
/// - تمام پسوردهای جدید با PBKDF2 (120,000 iterations) هش می‌شوند
/// - هش‌های قدیمی SHA-256 در صورت تطابق به PBKDF2 ارتقا می‌یابند
/// - SHA-256 تنها برای backward compatibility پشتیبانی می‌شود
class PasscodeManager {
  static const String _passcodeHashKey = 'passcode_hash';
  static const String _attemptsKey = 'failed_attempts';
  static const String _lockoutUntilKey = 'lockout_until';
  static const String _encryptedKeysKey = 'encrypted_private_keys';

  static const int _maxAttempts = 5;
  static const int _lockoutDuration = 300;
  static const int _passcodeLength = 6;

  static final PlatformStorageManager _platformStorage = ServiceLocator.get<PlatformStorageManager>();

  static Future<bool> isPasscodeSet() async {
    try {
      final results = await Future.wait([
        _platformStorage.getData(_passcodeHashKey, isCritical: true),
        _platformStorage.getData('passcode_salt', isCritical: true),
      ]).timeout(const Duration(seconds: 3), onTimeout: () => [null, null]);
      
      return results[0] != null && results[1] != null;
    } catch (e) {
      SecureLog.w('PasscodeManager.isPasscodeSet error', error: e);
      return false;
    }
  }

  static Future<bool> setPasscode(String passcode) async {
    if (passcode.length != _passcodeLength) {
      throw Exception('Passcode must be $_passcodeLength digits');
    }

    try {
      final salt = WalletCrypto.generateSaltBase64();
      // استفاده از PBKDF2 برای تمام هش‌های جدید (120000 iterations)
      final hash = await WalletCrypto.hashPasscode(passcode, salt);

      await Future.wait([
        _platformStorage.saveData(_passcodeHashKey, hash, isCritical: true),
        _platformStorage.saveData('passcode_salt', salt, isCritical: true),
        _platformStorage.deleteData(_attemptsKey),
        _platformStorage.deleteData(_lockoutUntilKey),
      ]).timeout(const Duration(seconds: 5));

      _markAppAsUsedForPasscode();
      return true;
    } catch (e) {
      SecureLog.w('PasscodeManager.setPasscode error', error: e);
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
        SecureLog.e('PasscodeManager: Stored data missing or corrupted');
        return false;
      }

      // Priority 1: PBKDF2 hash (جدید)
      var isValid = await _verifyPbkdf2Hash(passcode, salt, savedHash);

      if (!isValid) {
        // Priority 2: Fallback به SHA-256 (قدیمی) + ارتقا
        isValid = await _verifyAndUpgradeSha256(passcode, salt, savedHash);
      }

      if (isValid) {
        unawaited(_platformStorage.deleteData(_attemptsKey));
        unawaited(_platformStorage.deleteData(_lockoutUntilKey));
      } else {
        await _recordFailedAttempt();
      }

      return isValid;
    } catch (e) {
      SecureLog.e('PasscodeManager.verifyPasscode exception', error: e);
      return false;
    }
  }

  /// بررسی هش PBKDF2
  static Future<bool> _verifyPbkdf2Hash(String passcode, String salt, String savedHash) async {
    try {
      final currentHash = await WalletCrypto.hashPasscode(passcode, salt);
      return currentHash == savedHash;
    } catch (e) {
      SecureLog.w('PasscodeManager: PBKDF2 verify error', error: e);
      return false;
    }
  }

  /// بررسی هش SHA-256 قدیمی و ارتقا به PBKDF2 در صورت تطابق
  static Future<bool> _verifyAndUpgradeSha256(String passcode, String salt, String savedHash) async {
    try {
      final legacyHash = _legacySha256Hash(passcode, salt);
      if (legacyHash == savedHash) {
        // ارتقا به PBKDF2
        final newHash = await WalletCrypto.hashPasscode(passcode, salt);
        await _platformStorage.saveData(_passcodeHashKey, newHash, isCritical: true)
            .timeout(const Duration(seconds: 2), onTimeout: () {});
        SecureLog.i('Passcode hash upgraded from SHA-256 to PBKDF2');
        return true;
      }
      return false;
    } catch (e) {
      SecureLog.w('PasscodeManager: legacy hash verify error', error: e);
      return false;
    }
  }

  /// SHA-256 هش قدیمی (برای backward compatibility)
  static String _legacySha256Hash(String passcode, String salt) {
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
    } catch (e) {
      SecureLog.w('Error recording failed passcode attempt', error: e);
    }
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
    } catch (e) {
      SecureLog.w('Error clearing passcode data', error: e);
    }
  }

  static Future<void> _markAppAsUsedForPasscode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_has_been_used', true);
      await prefs.setBool('passcode_set', true);
    } catch (e) {
      SecureLog.w('Error marking app as used for passcode', error: e);
    }
  }
}
