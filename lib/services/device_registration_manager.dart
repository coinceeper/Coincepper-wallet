import '../di/service_locator.dart';
import '../utils/secure_log.dart';

/// Device registration has been removed — wallet is fully non-custodial.
/// All server-dependent registration calls are no-ops.
class DeviceRegistrationManager {
  DeviceRegistrationManager();

  DeviceRegistrationManager._();

  static DeviceRegistrationManager get instance => ServiceLocator.get<DeviceRegistrationManager>();

  /// No-op — server registration removed for non-custodial architecture.
  void registerDeviceInBackground() {
    SecureLog.d('DeviceRegistration-BG: skipped (non-custodial)');
  }

  /// No-op — server registration removed for non-custodial architecture.
  Future<bool> registerDevice() async {
    SecureLog.d('DeviceRegistration: skipped (non-custodial)');
    return true;
  }

  /// No-op — server registration removed for non-custodial architecture.
  Future<void> registerDeviceWithCallback({
    required Function(bool success) onResult,
  }) async {
    SecureLog.d('DeviceRegistration-Callback: skipped (non-custodial)');
    onResult(true);
  }

  /// No-op — server registration removed for non-custodial architecture.
  Future<bool> checkAndRegisterDevice() async {
    SecureLog.d('DeviceRegistration-Check: skipped (non-custodial)');
    return true;
  }
}
