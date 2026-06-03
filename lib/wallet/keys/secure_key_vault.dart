import 'package:local_auth/local_auth.dart';

import '../../services/secure_storage.dart';

/// Reads secrets from secure storage with optional biometric gate before signing.
class SecureKeyVault {
  SecureKeyVault._();
  static final SecureKeyVault instance = SecureKeyVault._();

  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<bool> authenticateForSigning({String reason = 'Confirm transaction'}) async {
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
    } catch (_) {
      return false;
    }
  }

  Future<String?> mnemonic({
    required String walletName,
    required String userId,
    bool requireBiometric = true,
  }) async {
    if (requireBiometric) {
      final ok = await authenticateForSigning();
      if (!ok) return null;
    }
    return SecureStorage.instance.getMnemonic(walletName, userId);
  }
}
