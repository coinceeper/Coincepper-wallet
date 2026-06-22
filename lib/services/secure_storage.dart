import 'dart:math';
import '../utils/secure_log.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

import '../di/service_locator.dart';
import '../domain/interfaces/wallet_data_source.dart';
import '../domain/interfaces/settings_data_source.dart';
import 'wallet_secure_storage.dart';
import 'secure_memory_cache.dart';

/// سرویس ذخیره‌سازی امن برای تمام پلتفرم‌ها
///
/// ## امنیت حافظه (Memory Security)
///
/// این کلاس از [SecureMemoryCache] برای مدیریت کش حافظه استفاده می‌کند:
///
/// - **داده‌های فوق حساس** (منیمونیک، کلید خصوصی، پسورد هش): هرگز در RAM کش نمی‌شوند
///   و همیشه مستقیماً از حافظه امن دستگاه خوانده می‌شوند.
/// - **داده‌های معمولی**: با TTL پیش‌فرض ۵ دقیقه در رم می‌مانند و پس از انقضا
///   به طور خودکار پاک می‌شوند.
/// - **پاکسازی در lifecycle**: با رفتن اپ به پس‌زمینه یا قفل شدن، کل کش پاک می‌شود.
///
/// از [clearMemoryCache] برای پاکسازی دستی در مواقع لزوم استفاده کنید.
class SecureStorage implements IWalletDataSource, ISettingsDataSource {
  static SecureStorage get instance => ServiceLocator.get<SecureStorage>();

  SecureStorage._();
  /// Internal constructor for DI container. Use [instance] for singleton access.
  SecureStorage();

  FlutterSecureStorage get _storage => WalletSecureStorage.instance;

  // ---------------------------------------------------------------
  // API عمومی کش حافظه (برای یکپارچگی با LifecycleManager)
  // ---------------------------------------------------------------

  /// پاک‌سازی کامل تمام کش حافظه (داده‌های حساس و غیرحساس)
  ///
  /// این متد را در رویدادهای lifecycle فراخوانی کنید:
  /// - وقتی اپ به پس‌زمینه می‌رود
  /// - وقتی اپ قفل می‌شود
  /// - وقتی کاربر لاگ اوت می‌کند
  Future<void> clearMemoryCache() async {
    ServiceLocator.get<SecureMemoryCache>().evictAll();
  }

  /// پاک‌سازی فقط داده‌های حساس از کش حافظه
  ///
  /// این متد ملایم‌تر از [clearMemoryCache] است و فقط ورودی‌های
  /// با TTL کوتاه را پاک می‌کند.
  void clearSensitiveMemoryCache() {
    ServiceLocator.get<SecureMemoryCache>().evictSensitive();
  }

  // ---------------------------------------------------------------
  // متدهای اصلی
  // ---------------------------------------------------------------

  Future<void> saveSecureData(String key, String value) async {
    try {
      // داده‌های فوق حساس هرگز در RAM کش نمی‌شوند
      if (!SecureMemoryCache.isSensitiveKey(key)) {
        ServiceLocator.get<SecureMemoryCache>().set(key, value);
      }
      await _storage.write(key: key, value: value);
    } catch (e) {
      SecureLog.e('Error saving secure data', error: e);
      rethrow;
    }
  }

  Future<String?> getSecureData(String key) async {
    try {
      // داده‌های فوق حساس هرگز از RAM خوانده نمی‌شوند
      if (SecureMemoryCache.isSensitiveKey(key)) {
        return await _readFromSecureStorage(key);
      }

      // برای داده‌های معمولی، اول کش را چک کن
      final cached = ServiceLocator.get<SecureMemoryCache>().get(key);
      if (cached != null) return cached as String?;

      return await _readFromSecureStorage(key);
    } catch (e) {
      SecureLog.w('SecureStorage: Read error', error: e);
      return null;
    }
  }

  /// خواندن مستقیم از حافظه امن بدون کش کردن
  Future<String?> _readFromSecureStorage(String key) async {
    try {
      final value = await _storage.read(key: key).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          SecureLog.w('SecureStorage: Read timeout');
          return null;
        },
      );
      // اگر داده فوق حساس نبود، در کش ذخیره کن
      if (value != null && !SecureMemoryCache.isSensitiveKey(key)) {
        ServiceLocator.get<SecureMemoryCache>().set(key, value);
      }
      return value;
    } catch (e) {
      SecureLog.w('SecureStorage: Read error', error: e);
      return null;
    }
  }

  Future<void> saveSecureJson(String key, Map<String, dynamic> data) async {
    try {
      // داده‌های فوق حساس هرگز در RAM کش نمی‌شوند
      if (!SecureMemoryCache.isSensitiveKey(key)) {
        ServiceLocator.get<SecureMemoryCache>().set(key, data);
      }
      final jsonString = jsonEncode(data);
      await _storage.write(key: key, value: jsonString);
    } catch (e) {
      SecureLog.e('Error saving secure JSON', error: e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getSecureJson(String key) async {
    try {
      // داده‌های فوق حساس هرگز از RAM خوانده نمی‌شوند
      if (!SecureMemoryCache.isSensitiveKey(key)) {
        final cached = ServiceLocator.get<SecureMemoryCache>().get(key);
        if (cached is Map<String, dynamic>) return cached;
      }

      final jsonString = await _storage.read(key: key).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          SecureLog.w('SecureStorage: Read JSON timeout');
          return null;
        },
      );
      if (jsonString != null) {
        try {
          final data = jsonDecode(jsonString) as Map<String, dynamic>;
          // داده‌های فوق حساس هرگز در RAM کش نمی‌شوند
          if (!SecureMemoryCache.isSensitiveKey(key)) {
            ServiceLocator.get<SecureMemoryCache>().set(key, data);
          }
          return data;
        } catch (e) {
          SecureLog.w('SecureStorage: JSON parse error', error: e);
          return null;
        }
      }
      return null;
    } catch (e) {
      SecureLog.w('SecureStorage: read error', error: e);
      return null;
    }
  }

  Future<void> deleteSecureData(String key) async {
    try {
      ServiceLocator.get<SecureMemoryCache>().remove(key);
      await _storage.delete(key: key);
    } catch (e) {
      SecureLog.e('Error deleting secure data', error: e);
      rethrow;
    }
  }

  Future<void> clearAllSecureData() async {
    try {
      ServiceLocator.get<SecureMemoryCache>().evictAll();
      await _storage.deleteAll();
      SecureLog.d('All secure data cleared');
    } catch (e) {
      SecureLog.e('Error clearing secure data', error: e);
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
      SecureLog.e('Error checking key existence', error: e);
      return false;
    }
  }

  Future<List<String>> getAllKeys() async {
    try {
      final keys = await _storage.readAll();
      return keys.keys.toList();
    } catch (e) {
      SecureLog.e('Error getting all keys', error: e);
      return [];
    }
  }

  // ---------------------------------------------------------------
  // Wallet Methods
  // ---------------------------------------------------------------

  Future<void> saveUserId(String walletName, String userId) async {
    await saveSecureData('UserID_$walletName', userId);
  }

  Future<String?> getUserIdForWallet(String walletName) async {
    return await getSecureData('UserID_$walletName');
  }

  Future<void> saveMnemonic(
      String walletName, String userId, String mnemonic) async {
    // منیمونیک از نوع داده‌های فوق حساس است و در RAM کش نمی‌شود
    final key = 'Mnemonic_${userId}_$walletName';
    await _storage.write(key: key, value: mnemonic);
  }

  Future<String?> getMnemonic(String walletName, String userId) async {
    // منیمونیک هرگز از RAM خوانده نمی‌شود - همیشه از حافظه امن
    final key = 'Mnemonic_${userId}_$walletName';
    try {
      return await _storage.read(key: key).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          SecureLog.w('SecureStorage: Read Mnemonic timeout');
          return null;
        },
      );
    } catch (e) {
      SecureLog.w('SecureStorage: Read Mnemonic error', error: e);
      return null;
    }
  }

  /// بررسی وجود منیمونیک در حافظه امن (بدون بازگرداندن مقدار).
  ///
  /// امنیت: منیمونیک هرگز به عنوان String بازگردانده نمی‌شود.
  Future<bool> mnemonicExists(String walletName, String userId) async {
    final key = 'Mnemonic_${userId}_$walletName';
    try {
      return await containsKey(key);
    } catch (e) {
      SecureLog.w('SecureStorage: mnemonicExists error', error: e);
      return false;
    }
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
        (data['wallets'] as List)
            .map((item) => Map<String, String>.from(item as Map)),
      );
    }
    return [];
  }

  Future<void> saveWalletIdForWallet(
      String walletName, String walletId) async {
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

  // ---------------------------------------------------------------
  // Anonymous Device ID (برای Notification API — بدون UserID)
  // ---------------------------------------------------------------

  static const String _anonDeviceIdKey = 'anonymous_device_id';

  /// Returns a persistent anonymous device identifier.
  ///
  /// This ID is generated once on first call and stored securely.
  /// It is used INSTEAD of [userId] for notification API calls so
  /// that the proxy server never learns the actual user identity.
  ///
  /// The ID is a UUID v4 — completely random, no PII, no link to
  /// the wallet or blockchain addresses.
  Future<String> getAnonymousDeviceId() async {
    final existing = await getSecureData(_anonDeviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    // Generate UUID v4: 8-4-4-4-12 hex chars
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    // Set version 4 (0100 in high nibble of byte 6)
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Set variant 2 (10 in high 2 bits of byte 8)
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final uuid = [
      _toHex(bytes, 0, 4),
      _toHex(bytes, 4, 2),
      _toHex(bytes, 6, 2),
      _toHex(bytes, 8, 2),
      _toHex(bytes, 10, 6),
    ].join('-');
    await saveSecureData(_anonDeviceIdKey, uuid);
    SecureLog.d('Anonymous device ID generated');
    return uuid;
  }

  /// Convert a range of [bytes] starting at [offset] for [length] bytes to hex.
  static String _toHex(List<int> bytes, int offset, int length) {
    return bytes
        .sublist(offset, offset + length)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<void> saveSecuritySettings(Map<String, dynamic> settings) async {
    await saveSecureJson('SecuritySettings', settings);
  }

  Future<Map<String, dynamic>?> getSecuritySettings() async {
    return await getSecureJson('SecuritySettings');
  }

  // ---------------------------------------------------------------
  // Debug Methods
  // ---------------------------------------------------------------

  Future<void> debugPrintAllKeychainKeys() async {
    try {
      final allData = await _storage.readAll();
      SecureLog.d('Keychain keys: ${allData.keys.join(", ")}');
    } catch (e) {
      SecureLog.e('Error debugging keychain', error: e);
    }
  }

  Future<void> checkAndClearOrphanedData() async {
    SecureLog.d('Checking for orphaned data...');
  }

  Future<void> debugForceClearAllData() async {
    await clearAllSecureData();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // ---------------------------------------------------------------
  // Compatibility static methods
  // ---------------------------------------------------------------

  static Future<String?> getUserId() async {
    return await instance.getSelectedUserId();
  }

  static Future<String?> getWalletId() async {
    return await instance.getSelectedWallet();
  }

  Future<String?> getUserIdForSelectedWallet() async => getSelectedUserId();

  Future<void> saveActiveTokens(
      String walletName, String userId, List<String> tokens) async {
    await saveSecureJson('ActiveTokens_${userId}_$walletName', {'tokens': tokens});
  }

  Future<List<String>> getActiveTokens(
      String walletName, String userId) async {
    final data =
        await getSecureJson('ActiveTokens_${userId}_$walletName');
    if (data != null && data['tokens'] != null) {
      return List<String>.from(data['tokens'] as List);
    }
    return [];
  }

  Future<void> saveWalletBalanceCache(
      String walletName, String userId, Map<String, double> balances) async {
    await saveSecureJson('BalanceCache_${userId}_$walletName', balances);
  }

  Future<Map<String, double>> getWalletBalanceCache(
      String walletName, String userId) async {
    final data =
        await getSecureJson('BalanceCache_${userId}_$walletName');
    if (data != null) {
      return Map<String, double>.from(
          data.map((k, v) => MapEntry(k, (v as num).toDouble())));
    }
    return {};
  }
}
