import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../utils/secure_log.dart';

/// مدیریت پاکسازی خودکار داده‌ها هنگام حذف اپلیکیشن
class UninstallDataManager {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  
  /// بررسی و پاکسازی داده‌ها در صورت fresh install
  static Future<void> checkAndCleanupOnFreshInstall() async {
    try {
      SecureLog.d('iOS: Checking for fresh install');
      
      // بررسی وجود داده‌های باقی‌مانده
      final hasRemainingData = await _hasRemainingData();
      
      // Do NOT perform cleanup automatically on app launch; only log status.
      if (!hasRemainingData) {
        SecureLog.i('iOS: No remaining data found - clean install state');
      } else {
        SecureLog.w('iOS: Remaining data detected (will not auto-clear). Use settings reset if needed.');
      }
      
      // بررسی مجدد بعد از پاکسازی
      // (Cleanup disabled by default to avoid wiping user token preferences.)
      
    } catch (e) {
      SecureLog.e('Error during fresh install cleanup', error: e);
    }
  }
  
  /// بررسی وجود داده‌های باقی‌مانده
  static Future<bool> _hasRemainingData() async {
    try {
      // بررسی SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final prefsKeys = prefs.getKeys();
      
      // بررسی SecureStorage
      final secureKeys = await _secureStorage.readAll();
      
      // بررسی فایل‌های کش
      final hasCacheFiles = await _hasCacheFiles();
      
      // بررسی داده‌های مهم
      final hasImportantData = await _hasImportantData();
      
      final hasData = prefsKeys.isNotEmpty || secureKeys.isNotEmpty || hasCacheFiles || hasImportantData;
      
      if (hasData) {
        SecureLog.d('Found remaining data - SharedPreferences: ${prefsKeys.length}, SecureStorage: ${secureKeys.length}, Cache: ${hasCacheFiles ? "Yes" : "No"}, Important: ${hasImportantData ? "Yes" : "No"}');
      }
      
      return hasData;
    } catch (e) {
      SecureLog.e('Error checking remaining data', error: e);
      return false;
    }
  }
  
  /// بررسی وجود داده‌های مهم
  static Future<bool> _hasImportantData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // بررسی داده‌های مهم در SharedPreferences
      final importantPrefsKeys = [
        'passcode_hash',
        'passcode_enabled',
        'biometric_enabled',
        'auto_lock_timeout_millis',
        'last_background_time',
        'selected_currency',
        'selected_language',
        'notification_settings',
        'fcm_token',
        'push_notifications_enabled',
        'current_language',
        'current_currency',
        'auto_lock_timeout'
      ];
      
      for (final key in importantPrefsKeys) {
        if (prefs.containsKey(key)) {
          SecureLog.d('Found important SharedPreferences key');
          return true;
        }
      }
      
      // بررسی داده‌های مهم در SecureStorage
      final secureKeys = await _secureStorage.readAll();
      final importantSecureKeys = secureKeys.keys.where((key) =>
        key.contains('UserID') ||
        key.contains('WalletID') ||
        key.contains('Mnemonic') ||
        key.contains('Passcode') ||
        key.contains('PrivateKey') ||
        key.contains('WalletSettings') ||
        key.contains('DeviceInfo')
      ).toList();
      
      if (importantSecureKeys.isNotEmpty) {
        SecureLog.d('Found important SecureStorage keys: ${importantSecureKeys.length} keys');
        return true;
      }
      
      return false;
    } catch (e) {
      SecureLog.e('Error checking important data', error: e);
      return false;
    }
  }
  
  /// بررسی وجود فایل‌های کش
  static Future<bool> _hasCacheFiles() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      if (await cacheDir.exists()) {
        final files = cacheDir.listSync();
        return files.isNotEmpty;
      }
      return false;
    } catch (e) {
      SecureLog.e('Error checking cache files', error: e);
      return false;
    }
  }
  
  /// پاکسازی کامل تمام داده‌ها
  static Future<void> _performCompleteCleanup() async {
    try {
      SecureLog.i('Starting complete data cleanup');
      
      // Step 1: Clear SecureStorage
      await _clearSecureStorage();
      
      // Step 2: Clear SharedPreferences
      await _clearSharedPreferences();
      
      // Step 3: Clear Cache
      await _clearCache();
      
      // Step 4: Clear App Documents
      await _clearAppDocuments();
      
      // Step 5: Clear External Storage (Android)
      await _clearExternalStorage();
      
      SecureLog.i('Complete data cleanup finished');
      
    } catch (e) {
      SecureLog.e('Error during complete cleanup', error: e);
    }
  }
  
  /// پاکسازی SecureStorage
  static Future<void> _clearSecureStorage() async {
    try {
      await _secureStorage.deleteAll();
      SecureLog.i('SecureStorage cleared');
    } catch (e) {
      SecureLog.e('Error clearing SecureStorage', error: e);
    }
  }
  
  /// پاکسازی SharedPreferences
  static Future<void> _clearSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      SecureLog.i('SharedPreferences cleared');
    } catch (e) {
      SecureLog.e('Error clearing SharedPreferences', error: e);
    }
  }
  
  /// پاکسازی کش
  static Future<void> _clearCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        SecureLog.i('Cache cleared');
      }
    } catch (e) {
      SecureLog.e('Error clearing cache', error: e);
    }
  }
  
  /// پاکسازی فایل‌های Documents اپلیکیشن
  static Future<void> _clearAppDocuments() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      if (await appDir.exists()) {
        final files = appDir.listSync();
        for (final file in files) {
          if (file is File) {
            await file.delete();
          } else if (file is Directory) {
            await file.delete(recursive: true);
          }
        }
        SecureLog.i('App documents cleared');
      }
    } catch (e) {
      SecureLog.e('Error clearing app documents', error: e);
    }
  }
  
  /// پاکسازی External Storage (Android)
  static Future<void> _clearExternalStorage() async {
    try {
      if (Platform.isAndroid) {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null && await externalDir.exists()) {
          final files = externalDir.listSync();
          for (final file in files) {
            if (file is File) {
              await file.delete();
            } else if (file is Directory) {
              await file.delete(recursive: true);
            }
          }
          SecureLog.i('External storage cleared');
        }
      }
    } catch (e) {
      SecureLog.e('Error clearing external storage', error: e);
    }
  }
  
  /// پاکسازی داده‌های کیف پول
  static Future<void> clearWalletData() async {
    try {
      // حذف تمام کلیدهای مربوط به کیف پول از SecureStorage
      final allKeys = await _secureStorage.readAll();
      final walletKeys = allKeys.keys.where((key) => 
        key.contains('UserID') || 
        key.contains('WalletID') || 
        key.contains('Mnemonic') || 
        key.contains('PrivateKey') || 
        key.contains('WalletSettings') ||
        key.contains('DeviceInfo')
      ).toList();
      
      for (final key in walletKeys) {
        await _secureStorage.delete(key: key);
      }
      
      // حذف داده‌های کیف پول از SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final prefsKeys = prefs.getKeys();
      final walletPrefsKeys = prefsKeys.where((key) =>
        key.contains('wallet') ||
        key.contains('user_wallets') ||
        key.contains('selected_wallet')
      ).toList();
      
      for (final key in walletPrefsKeys) {
        await prefs.remove(key);
      }
      
      SecureLog.i('Wallet data cleared');
    } catch (e) {
      SecureLog.e('Error clearing wallet data', error: e);
    }
  }
  
  /// پاکسازی داده‌های پسکد
  static Future<void> clearPasscodeData() async {
    try {
      // حذف پسکد از SecureStorage
      await _secureStorage.delete(key: 'Passcode');
      
      // حذف پسکد از SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('passcode_hash');
      await prefs.remove('passcode_enabled');
      await prefs.remove('biometric_enabled');
      
      // حذف تمام کلیدهای مربوط به passcode از SecureStorage
      final allKeys = await _secureStorage.readAll();
      final passcodeKeys = allKeys.keys.where((key) => 
        key.toLowerCase().contains('passcode') ||
        key.toLowerCase().contains('biometric') ||
        key.toLowerCase().contains('security')
      ).toList();
      
      for (final key in passcodeKeys) {
        await _secureStorage.delete(key: key);
      }
      
      // حذف تمام کلیدهای مربوط به passcode از SharedPreferences
      final prefsKeys = prefs.getKeys();
      final passcodePrefsKeys = prefsKeys.where((key) =>
        key.toLowerCase().contains('passcode') ||
        key.toLowerCase().contains('biometric') ||
        key.toLowerCase().contains('security') ||
        key.toLowerCase().contains('lock')
      ).toList();
      
      for (final key in passcodePrefsKeys) {
        await prefs.remove(key);
      }
      
      SecureLog.i('Passcode data cleared');
    } catch (e) {
      SecureLog.e('Error clearing passcode data', error: e);
    }
  }
  
  /// پاکسازی داده‌های تنظیمات
  static Future<void> clearSettingsData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // حذف تنظیمات اپلیکیشن
      final settingsKeys = [
        'selected_currency',
        'selected_language',
        'auto_lock_timeout_millis',
        'last_background_time',
        'notification_settings',
        'fcm_token',
        'push_notifications_enabled',
        'current_language',
        'current_currency',
        'auto_lock_timeout'
      ];
      
      for (final key in settingsKeys) {
        await prefs.remove(key);
      }
      
      SecureLog.i('Settings data cleared');
    } catch (e) {
      SecureLog.e('Error clearing settings data', error: e);
    }
  }
  
  /// پاکسازی داده‌های کش قیمت‌ها
  static Future<void> clearPriceCacheData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      // حذف کش قیمت‌ها
      final priceKeys = keys.where((key) =>
        key.startsWith('price_') ||
        key.startsWith('cached_prices') ||
        key.contains('prices_cache')
      ).toList();
      
      for (final key in priceKeys) {
        await prefs.remove(key);
      }
      
      SecureLog.i('Price cache data cleared');
    } catch (e) {
      SecureLog.e('Error clearing price cache data', error: e);
    }
  }
  
  /// پاکسازی داده‌های توکن‌ها
  static Future<void> clearTokenData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      // حذف تنظیمات توکن‌ها
      final tokenKeys = keys.where((key) =>
        key.startsWith('token_') ||
        key.contains('token_state') ||
        key.contains('token_order')
      ).toList();
      
      for (final key in tokenKeys) {
        await prefs.remove(key);
      }
      
      SecureLog.i('Token data cleared');
    } catch (e) {
      SecureLog.e('Error clearing token data', error: e);
    }
  }
  
  /// پاکسازی داده‌های تراکنش‌ها
  static Future<void> clearTransactionData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      // حذف داده‌های تراکنش‌ها
      final transactionKeys = keys.where((key) =>
        key.contains('transaction') ||
        key.contains('tx_') ||
        key.contains('pending_')
      ).toList();
      
      for (final key in transactionKeys) {
        await prefs.remove(key);
      }
      
      SecureLog.i('Transaction data cleared');
    } catch (e) {
      SecureLog.e('Error clearing transaction data', error: e);
    }
  }
  
  /// پاکسازی داده‌های آدرس‌ها
  static Future<void> clearAddressBookData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      // حذف داده‌های دفترچه آدرس
      final addressKeys = keys.where((key) =>
        key.startsWith('wallet_name_') ||
        key.startsWith('wallet_address_') ||
        key.contains('address_book')
      ).toList();
      
      for (final key in addressKeys) {
        await prefs.remove(key);
      }
      
      SecureLog.i('Address book data cleared');
    } catch (e) {
      SecureLog.e('Error clearing address book data', error: e);
    }
  }
  
  /// پاکسازی کامل تمام داده‌ها (برای استفاده در تنظیمات)
  static Future<void> performCompleteDataCleanup(BuildContext context) async {
    try {
      SecureLog.i('Starting complete data cleanup from settings...');
      
      // پاکسازی تمام انواع داده‌ها
      await Future.wait([
        clearWalletData(),
        clearPasscodeData(),
        clearSettingsData(),
        clearPriceCacheData(),
        clearTokenData(),
        clearTransactionData(),
        clearAddressBookData(),
        _clearSecureStorage(),
        _clearSharedPreferences(),
        _clearCache(),
        _clearAppDocuments(),
        _clearExternalStorage(),
      ]);
      
      SecureLog.i('Complete data cleanup finished');
      
      // نمایش پیام موفقیت
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمام داده‌ها با موفقیت پاک شدند'),
            backgroundColor: Color(0xFF16B369),
            duration: Duration(seconds: 3),
          ),
        );
      }
      
    } catch (e) {
      SecureLog.e('Error during complete data cleanup', error: e);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در پاکسازی داده‌ها: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  /// بررسی وضعیت داده‌های باقی‌مانده
  static Future<Map<String, dynamic>> getDataStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final secureKeys = await _secureStorage.readAll();
      final hasCacheFiles = await _hasCacheFiles();
      
      return {
        'sharedPreferencesKeys': prefs.getKeys().length,
        'secureStorageKeys': secureKeys.length,
        'hasCacheFiles': hasCacheFiles,
        'totalDataItems': prefs.getKeys().length + secureKeys.length + (hasCacheFiles ? 1 : 0),
      };
    } catch (e) {
      SecureLog.e('Error getting data status', error: e);
      return {};
    }
  }
} 