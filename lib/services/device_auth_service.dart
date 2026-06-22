import 'secure_storage.dart';
import '../di/service_locator.dart';

/// Stores device JWT for protected wallet APIs (read-only, no server refresh).
class DeviceAuthService {
  DeviceAuthService._();
  DeviceAuthService();
  static DeviceAuthService get instance => ServiceLocator.get<DeviceAuthService>();

  static const _tokenKey = 'device_jwt_token';

  Future<String?> getToken() async {
    return ServiceLocator.get<SecureStorage>().getSecureData(_tokenKey);
  }
}
