import 'package:flutter/foundation.dart';

/// Device registration has been removed — wallet is fully non-custodial.
/// All server-dependent registration calls are no-ops.
class DeviceRegistrationManager {
  static DeviceRegistrationManager? _instance;
  static DeviceRegistrationManager get instance => _instance ??= DeviceRegistrationManager._();
  
  DeviceRegistrationManager._();

  /// No-op — server registration removed for non-custodial architecture.
  void registerDeviceInBackground({
    required String userId,
    required String walletId,
  }) {
    debugPrint('📱 DeviceRegistration-BG: skipped (non-custodial)');
  }

  /// No-op — server registration removed for non-custodial architecture.
  Future<bool> registerDevice({
    required String userId,
    required String walletId,
  }) async {
    debugPrint('📱 DeviceRegistration: skipped (non-custodial)');
    return true;
  }

  /// No-op — server registration removed for non-custodial architecture.
  Future<void> registerDeviceWithCallback({
    required String userId,
    required String walletId,
    required Function(bool success) onResult,
  }) async {
    debugPrint('📱 DeviceRegistration-Callback: skipped (non-custodial)');
    onResult(true);
  }

  /// No-op — server registration removed for non-custodial architecture.
  Future<bool> checkAndRegisterDevice({
    required String userId,
    required String walletId,
  }) async {
    debugPrint('📱 DeviceRegistration-Check: skipped (non-custodial)');
    return true;
  }
}
