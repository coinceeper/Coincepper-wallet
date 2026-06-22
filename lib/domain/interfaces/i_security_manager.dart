/// Pure domain interface for security settings management.
///
/// Implemented by [SecuritySettingsManager] in the infrastructure layer.
/// Domain services depend on this interface instead of directly
/// depending on concrete implementations.
///
/// Uses primitive types only to avoid coupling to infrastructure enums.
abstract class ISecurityManager {
  Future<void> initialize();
  Future<bool> isPasscodeEnabled();
  Future<bool> setPasscodeEnabled(bool enabled);
  Future<void> setAutoLockTimeout(int minutes);
  Future<bool> isBiometricAvailable();
  Future<bool> isPasscodeSet();
  Future<bool> isFaceIdSupported();
  Future<bool> authenticateWithBiometric({String? reason});
  Future<Map<String, dynamic>> getSecuritySettingsSummary();
  Future<void> saveLastBackgroundTime();
  Future<bool> shouldShowPasscodeAfterBackground();
  Future<void> clearLastBackgroundTime();
  Future<void> clearSecuritySettings();
}

/// Lock method options for the security screen.
enum LockMethod {
  passcodeAndBiometric,
  passcodeOnly,
  biometricOnly,
}

/// Auto-lock duration options for the security screen.
enum AutoLockDuration {
  immediate,
  oneMinute,
  fiveMinutes,
  tenMinutes,
  fifteenMinutes,
}
