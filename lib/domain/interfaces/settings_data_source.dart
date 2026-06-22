/// Pure domain interface for app settings persistence.
///
/// Implemented by [SecureStorage] in the infrastructure layer.
/// Domain services depend on this interface instead of directly
/// importing concrete storage implementations.
abstract class ISettingsDataSource {
  Future<String?> getSecureData(String key);
  Future<void> saveSecureData(String key, String value);
  Future<String?> getDeviceToken();
  Future<void> saveDeviceToken(String token);
}
