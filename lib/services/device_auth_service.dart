import 'secure_storage.dart';

/// Stores device JWT for protected wallet APIs (read-only, no server refresh).
class DeviceAuthService {
  DeviceAuthService._();
  static final DeviceAuthService instance = DeviceAuthService._();

  static const _tokenKey = 'device_jwt_token';

  Future<String?> getToken() async {
    return SecureStorage.instance.getSecureData(_tokenKey);
  }
}
