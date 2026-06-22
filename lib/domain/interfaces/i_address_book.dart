/// Pure domain interface for address book operations.
///
/// Implemented by [AddressBookService] in the infrastructure layer.
/// Domain services depend on this interface instead of directly
/// depending on concrete implementations.
abstract class IAddressBookService {
  Future<void> saveToKeystore(String walletName, String walletAddress);
  Future<List<Map<String, String>>> loadFromKeystore();
  Future<void> deleteFromKeystore(String walletName);
}
