import 'package:local_auth/local_auth.dart';

import '../../services/secure_storage.dart';
import '../../services/sensitive_data.dart';
import '../../di/service_locator.dart';
import '../../utils/secure_log.dart';

/// Reads secrets from secure storage with optional biometric gate before signing.
///
/// ## امنیت حافظه
///
/// از [MnemonicScope] و [SensitiveString] برای محدود کردن طول عمر
/// منیمونیک در حافظه استفاده کنید:
///
/// ```dart
/// await SecureKeyVault.instance.withMnemonic(
///   walletName: name,
///   userId: uid,
///   callback: (mnemonic) async {
///     // منیمونیک فقط در این scope در دسترس است
///     return await signer.send(mnemonic: mnemonic, ...);
///   },
/// );
/// // پس از بازگشت، reference منیمونیک پاک شده است
/// ```
class SecureKeyVault {
  SecureKeyVault._();
  SecureKeyVault();
  static SecureKeyVault get instance => ServiceLocator.get<SecureKeyVault>();

  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<bool> authenticateForSigning(
      {String reason = 'Confirm transaction'}) async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      if (!canCheck && !supported) return true;
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      SecureLog.w('SecureKeyVault: biometric authentication failed', error: e);
      return false;
    }
  }

  /// دریافت منیمونیک به صورت String ساده.
  ///
  /// ⚠️ توجه امنیتی: این متد منیمونیک را به صورت String برمی‌گرداند که
  /// تا زمان GC در حافظه می‌ماند. ترجیحاً از [withMnemonic] استفاده کنید.
  @Deprecated('Use withMnemonic() callback-based API for better memory safety')
  Future<String?> mnemonic({
    required String walletName,
    required String userId,
    bool requireBiometric = true,
  }) async {
    if (requireBiometric) {
      final ok = await authenticateForSigning();
      if (!ok) return null;
    }
    return ServiceLocator.get<SecureStorage>().getMnemonic(walletName, userId);
  }

  /// دسترسی امن به منیمونیک از طریق callback.
  ///
  /// منیمونیک از SecureStorage خوانده می‌شود، به [callback] داده می‌شود،
  /// و پس از بازگشت callback، reference آن پاک می‌شود.
  ///
  /// [biometricReason] متن نمایشی برای احراز هویت بیومتریک.
  Future<T> withMnemonic<T>({
    required String walletName,
    required String userId,
    required Future<T> Function(String mnemonic) callback,
    String biometricReason = 'Confirm transaction',
  }) async {
    final ok = await authenticateForSigning(reason: biometricReason);
    if (!ok) {
      throw StateError('Biometric authentication failed or was cancelled');
    }

    return MnemonicScope.use(
      () => ServiceLocator.get<SecureStorage>().getMnemonic(walletName, userId),
      callback: callback,
    );
  }
}
