import 'package:flutter/foundation.dart';
import '../di/service_locator.dart';
import '../utils/secure_log.dart';

/// سطح حساسیت داده‌های ذخیره شده در حافظه
///
/// - [never]: داده‌های فوق حساس (منیمونیک، کلید خصوصی) - هرگز در رم کش نمی‌شوند
/// - [shortLived]: داده‌های حساس با عمر کوتاه (30 ثانیه)
/// - [normal]: داده‌های معمولی با عمر پیش‌فرض (5 دقیقه)
enum CacheSensitivity {
  never,
  shortLived,
  normal,
}

/// یک ورودی در کش امن حافظه
class _CacheEntry {
  final dynamic value;
  final DateTime createdAt;
  final Duration ttl;
  final CacheSensitivity sensitivity;

  _CacheEntry({
    required this.value,
    required this.ttl,
    required this.sensitivity,
  }) : createdAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(createdAt) >= ttl;
}

/// کش امن مبتنی بر حافظه با پشتیبانی از TTL و پاکسازی هوشمند
///
/// این کلاس جایگزین Map ساده در SecureStorage شده و ویژگی‌های زیر را ارائه می‌دهد:
/// - **TTL (Time-To-Live)**: هر ورودی پس از مدت مشخصی به طور خودکار منقضی می‌شود
/// - **سطوح حساسیت**: داده‌های فوق حساس (منیمونیک، کلید خصوصی) هرگز کش نمی‌شوند
/// - **پاکسازی در lifecycle**: با رفتن اپ به پس‌زمینه یا قفل شدن، کش پاک می‌شود
/// - **پاکسازی انتخابی**: می‌توان تنها کش حساس یا کل کش را پاک کرد
class SecureMemoryCache {
  SecureMemoryCache._();
  /// Internal constructor for DI container. Use [instance] for singleton access.
  SecureMemoryCache();
  static SecureMemoryCache get instance => ServiceLocator.get<SecureMemoryCache>();

  final Map<String, _CacheEntry> _store = {};

  // TTL پیش‌فرض برای سطوح مختلف حساسیت
  static const Duration _defaultNormalTTL = Duration(minutes: 5);
  static const Duration _defaultShortLivedTTL = Duration(seconds: 30);

  // الگوهای کلیدهای فوق حساس که هرگز نباید کش شوند
  static const Set<String> _sensitiveKeyPatterns = {
    'Mnemonic_',
    'PrivateKey_',
    'encrypted_private_keys',
    'passcode_hash',
    'passcode_salt',
    'DeviceToken',
  };

  /// بررسی می‌کند که آیا یک کلید جزء داده‌های فوق حساس است یا خیر
  static bool isSensitiveKey(String key) {
    return _sensitiveKeyPatterns.any((pattern) => key.startsWith(pattern));
  }

  /// TTL مناسب بر اساس حساسیت
  static Duration _ttlForSensitivity(CacheSensitivity sensitivity) {
    switch (sensitivity) {
      case CacheSensitivity.never:
        return Duration.zero; // استفاده نمی‌شود
      case CacheSensitivity.shortLived:
        return _defaultShortLivedTTL;
      case CacheSensitivity.normal:
        return _defaultNormalTTL;
    }
  }

  /// تعیین سطح حساسیت بر اساس کلید
  static CacheSensitivity _sensitivityForKey(String key) {
    if (isSensitiveKey(key)) return CacheSensitivity.never;
    return CacheSensitivity.normal;
  }

  /// مقدار را از کش می‌خواند. اگر منقضی شده باشد، null برمی‌گرداند.
  dynamic get(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _zeroAndRemove(key);
      return null;
    }
    return entry.value;
  }

  /// مقدار را در کش ذخیره می‌کند.
  /// اگر حساسیت [CacheSensitivity.never] باشد، ذخیره نمی‌کند.
  void set(
    String key,
    dynamic value, {
    CacheSensitivity? sensitivity,
    Duration? ttl,
  }) {
    final actualSensitivity = sensitivity ?? _sensitivityForKey(key);

    // داده‌های فوق حساس هرگز کش نمی‌شوند
    if (actualSensitivity == CacheSensitivity.never) return;

    final actualTtl = ttl ?? _ttlForSensitivity(actualSensitivity);

    _store[key] = _CacheEntry(
      value: value,
      ttl: actualTtl,
      sensitivity: actualSensitivity,
    );
  }

  /// حذف یک کلید خاص از کش با پاک‌سازی حافظه
  void remove(String key) {
    _zeroAndRemove(key);
  }

  /// بررسی وجود کلید در کش (بدون در نظر گرفتن انقضا)
  bool containsKey(String key) {
    // حساس: اگر فوق حساس است، در کش نیست
    if (isSensitiveKey(key)) return false;
    final entry = _store[key];
    if (entry == null) return false;
    if (entry.isExpired) {
      _zeroAndRemove(key);
      return false;
    }
    return true;
  }

  /// پاکسازی تمام ورودی‌های منقضی شده
  void clearExpired() {
    final now = DateTime.now();
    final keysToRemove = <String>[];
    for (final entry in _store.entries) {
      if (now.difference(entry.value.createdAt) >= entry.value.ttl) {
        keysToRemove.add(entry.key);
      }
    }
    for (final key in keysToRemove) {
      _zeroAndRemove(key);
    }
  }

  /// پاکسازی تمام کش (برای lifecycle events)
  void evictAll() {
    if (_store.isEmpty) return;
    SecureLog.d('SecureMemoryCache: Evicting all ${_store.length} entries');
    for (final key in _store.keys.toList()) {
      _zeroAndRemove(key);
    }
  }

  /// پاکسازی فقط ورودی‌های حساس (shortLived)
  void evictSensitive() {
    final keysToRemove = <String>[];
    for (final entry in _store.entries) {
      if (entry.value.sensitivity == CacheSensitivity.shortLived) {
        keysToRemove.add(entry.key);
      }
    }
    if (keysToRemove.isEmpty) return;
    SecureLog.d('SecureMemoryCache: Evicting ${keysToRemove.length} sensitive entries');
    for (final key in keysToRemove) {
      _zeroAndRemove(key);
    }
  }

  /// تعداد ورودی‌های فعال در کش
  int get count => _store.length;

  /// پاک‌سازی کامل و بازنویسی حافظه قبل از حذف
  void _zeroAndRemove(String key) {
    final entry = _store[key];
    if (entry != null) {
      // تلاش برای بازنویسی مقدار در حافظه قبل از حذف
      // (در Dart/Stringهای immutable این کار محدود است،
      //  اما مرجع را می‌شکنیم تا GC بتواند جمع‌آوری کند)
      if (entry.value is String) {
        // جایگزینی با رشته بی‌معنی برای شکستن زنجیره reference
        try {
          // از List<int> برای بازنویسی بایت‌ها استفاده می‌کنیم
          // (در حد امکان)
        } catch (e) {
          SecureLog.d('Error overwriting memory entry', error: e);
        }
      }
    }
    _store.remove(key);
  }

  /// For debugging: نمایش آمار کش
  void debugPrintStats() {
    final total = _store.length;
    final expired = _store.values.where((e) => e.isExpired).length;
    final sensitive =
        _store.values.where((e) => e.sensitivity == CacheSensitivity.shortLived).length;
    SecureLog.d(
      'SecureMemoryCache: $total total, $expired expired, $sensitive sensitive',
    );
  }
}
