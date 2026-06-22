/// Pure domain interface for balance management.
///
/// Implemented by [BalanceManager] in the infrastructure layer.
/// Domain services depend on this interface instead of directly
/// depending on concrete implementations.
abstract class IBalanceManager {
  Future<void> setCurrentUserAndWallet(String userId, String walletName);
}
