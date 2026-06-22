/// Pure domain interface for wallet persistence operations.
///
/// Implemented by [SecureStorage] in the infrastructure layer.
/// Domain services depend on this interface instead of directly
/// depending on concrete storage implementations.
abstract class IWalletDataSource {
  Future<List<Map<String, String>>> getWalletsList();
  Future<void> saveWalletsList(List<Map<String, String>> wallets);
  Future<String?> getSelectedWallet();
  Future<void> saveSelectedWallet(String walletName, String userId);
  Future<String?> getUserIdForWallet(String walletName);
  Future<void> saveUserId(String walletName, String userId);
  Future<String?> getSelectedUserId();
  Future<String?> getUserIdForSelectedWallet();

  Future<void> saveMnemonic(String walletName, String userId, String mnemonic);
  Future<String?> getMnemonic(String walletName, String userId);

  Future<void> deleteSecureData(String key);
  Future<void> saveSecureJson(String key, Map<String, dynamic> data);
  Future<Map<String, dynamic>?> getSecureJson(String key);
  Future<bool> containsKey(String key);
  Future<void> clearAllSecureData();
  Future<String?> getSecureData(String key);
  Future<void> saveSecureData(String key, String value);
  Future<String?> getDeviceToken();
  Future<void> saveDeviceToken(String token);

  /// Balance cache persistence
  Future<Map<String, double>> getWalletBalanceCache(
      String walletName, String userId);
  Future<void> saveWalletBalanceCache(
      String walletName, String userId, Map<String, double> cache);

  Future<String?> getWalletIdForWallet(String walletName);
  Future<void> saveWalletIdForWallet(String walletName, String walletId);

  Future<void> clearMemoryCache();
}
