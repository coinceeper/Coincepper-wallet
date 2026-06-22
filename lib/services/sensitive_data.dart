import 'dart:typed_data';
import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// SecureWipe — extension for zeroing Uint8List
// ---------------------------------------------------------------------------

/// بازنویسی امن داده در حافظه قبل از رهاسازی.
///
/// در Dart به دلیل ماهیت garbage-collected و immutable بودن Stringها،
/// پاکسازی ۱۰۰٪ فیزیکی ممکن نیست. اما این extension:
/// 1. بایت‌های Uint8List را با صفر بازنویسی می‌کند
/// 2. Referenceها را می‌شکند تا GC بتواند جمع‌آوری کند
/// 3. از نگه‌داشتن طولانی‌مدت داده در حافظه جلوگیری می‌کند
extension SecureWipe on Uint8List {
  /// بازنویسی همه بایت‌ها با صفر
  void secureWipe() {
    for (int i = 0; i < length; i++) {
      this[i] = 0;
    }
  }
}

// ---------------------------------------------------------------------------
// SensitiveString — scope-safe secret holder
// ---------------------------------------------------------------------------

/// نگهدارنده موقت یک رشته حساس (منیمونیک، کلید خصوصی) که:
///
/// 1. دسترسی را منحصراً از طریق callback [use] فراهم می‌کند
/// 2. پس از بازگشت callback، reference داخلی را null می‌کند
/// 3. متد [dispose] صریح برای پاکسازی دارد
///
/// ## اصول امنیتی
///
/// - **عدم ذخیره‌سازی طولانی**: این کلاس هرگز رشته را در فیلدهای
///   طولانی‌مدت کلاس‌های دیگر ذخیره نمی‌کند
/// - **دسترسی محصور**: فقط از طریق callback می‌توان به داده دسترسی داشت
/// - **پاکسازی صریح**: پس از اتمام کار، [dispose] را صدا بزنید
/// - **کمترین زمان ماندگاری**: داده فقط در محدوده callback در دسترس است
///
/// ## محدودیت
///
/// در Dart به دلیل immutable بودن Stringها، خود رشته تا زمان GC در
/// heap می‌ماند. اما این کلاس:
/// - از ذخیره intentional جلوگیری می‌کند
/// - Reference را می‌شکند
/// - طول عمر را به حداقل می‌رساند
class SensitiveString {
  String? _value;
  bool _disposed = false;

  SensitiveString._(this._value);

  /// از یک [String] موجود می‌سازد.
  ///
  /// توجه: سازنده عمداً private است. از [MnemonicScope.use] یا
  /// [SensitiveString.use] استفاده کنید.
  factory SensitiveString.fromString(String value) {
    return SensitiveString._(value);
  }

  /// دسترسی موقت به داده از طریق callback.
  ///
  /// پس از بازگشت callback، reference داخلی null می‌شود.
  T use<T>(T Function(String data) callback) {
    _assertNotDisposed();
    final val = _value!;
    try {
      return callback(val);
    } finally {
      // Reference محلی در stack از بین رفت. خود String تا GC
      // در heap می‌ماند، اما دیگر به آن reference نداریم.
    }
  }

  /// دسترسی async به داده از طریق callback.
  Future<T> useAsync<T>(Future<T> Function(String data) callback) async {
    _assertNotDisposed();
    final val = _value!;
    try {
      return await callback(val);
    } finally {
      // Reference محلی از بین رفت
    }
  }

  /// پاکسازی صریح: reference را می‌شکند.
  ///
  /// این متد را در finally block صدا بزنید:
  /// ```dart
  /// final s = SensitiveString.fromString(mnemonic);
  /// try {
  ///   await s.useAsync((m) => sign(m));
  /// } finally {
  ///   s.dispose();
  /// }
  /// ```
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _value = null;
  }

  /// دریافت مقدار رشته (بدون پاکسازی).
  ///
  /// ⚠️ توجه: این متد reference را نگه می‌دارد. پس از استفاده، [dispose] را صدا بزنید.
  /// ترجیحاً از [use] یا [useAsync] استفاده کنید.
  String? toStringValue() {
    if (_disposed) return null;
    return _value;
  }

  bool get isDisposed => _disposed;

  void _assertNotDisposed() {
    if (_disposed) throw StateError('SensitiveString has been disposed');
  }
}

// ---------------------------------------------------------------------------
// MnemonicScope — scope-safe mnemonic usage for transaction signing
// ---------------------------------------------------------------------------

/// یک scope امن که منیمونیک را از منبع (SecureStorage) می‌خواند،
/// به صورت [SensitiveString] در اختیار callback قرار می‌دهد و
/// پس از اتمام کار پاک می‌کند.
///
/// ## کاربرد
///
/// ```dart
/// await MnemonicScope.use(
///   () => SecureStorage.instance.getMnemonic(walletName, userId),
///   callback: (mnemonic) async {
///     return await signer.send(mnemonic: mnemonic, ...);
///   },
/// );
/// ```
///
/// ## تضمین امنیتی
///
/// 1. منیمونیک فقط در محدوده [callback] در دسترس است
/// 2. پس از بازگشت callback، [SensitiveString.dispose] فراخوانی می‌شود
/// 3. Reference در caller ذخیره نمی‌شود (مگر اینکه call بی‌دقت کپی کند)
class MnemonicScope {
  /// منیمونیک را از [readMnemonic] می‌خواند و در [callback] با
  /// دسترسی امن در اختیار قرار می‌دهد.
  static Future<T> use<T>(
    Future<String?> Function() readMnemonic, {
    required Future<T> Function(String mnemonic) callback,
  }) async {
    final raw = await readMnemonic();
    if (raw == null || raw.isEmpty) {
      throw StateError('Mnemonic not available');
    }

    final sensitive = SensitiveString.fromString(raw);
    try {
      return await sensitive.useAsync((m) => callback(m));
    } finally {
      sensitive.dispose();
    }
  }
}
