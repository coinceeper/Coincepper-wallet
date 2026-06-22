import '../interfaces/i_address_book.dart';
import '../../models/address_book_entry.dart';
import '../../di/service_locator.dart';

/// سرویس اعتبارسنجی آدرس و مدیریت دفترچه آدرس
///
/// مسئول:
/// - اعتبارسنجی آدرس‌ها بر اساس بلاکچین
/// - فرمت‌سازی آدرس‌ها
/// - بارگذاری دفترچه آدرس
///
/// از [IAddressBookService] به جای [AddressBookService] مستقیم استفاده می‌کند.
class AddressValidationService {
  static AddressValidationService get instance => ServiceLocator.get<AddressValidationService>();
  AddressValidationService._();
  AddressValidationService();

  final IAddressBookService _addressBook = ServiceLocator.get<IAddressBookService>();

  // ==================== ADDRESS VALIDATION ====================

  /// Validate an address for a given blockchain.
  bool isValidAddress(String address, String? blockchainName) {
    if (address.isEmpty) return false;

    final chain = (blockchainName ?? '').toLowerCase();

    // Bitcoin (P2PKH, P2SH, Bech32)
    if (chain.contains('bitcoin')) {
      return _isBitcoinAddress(address);
    }

    // Ethereum and EVM chains (0x + 40 hex chars)
    if (chain.contains('ethereum') ||
        chain.contains('polygon') ||
        chain.contains('bsc') ||
        chain.contains('binance') ||
        chain.contains('avalanche') ||
        chain.contains('arbitrum') ||
        chain.contains('fantom') ||
        chain.contains('optimism')) {
      return _isEvmAddress(address);
    }

    // Tron (T + 33 base58 chars, starts with T)
    if (chain.contains('tron')) {
      return _isTronAddress(address);
    }

    // Solana (32-44 base58 chars)
    if (chain.contains('solana')) {
      return _isSolanaAddress(address);
    }

    // Ripple (XRP) (25-35 chars, alphanumeric)
    if (chain.contains('xrp') || chain.contains('ripple')) {
      return _isGenericAddress(address, minLen: 25, maxLen: 35);
    }

    // Polkadot / Substrate (starts with number)
    if (chain.contains('polkadot') || chain.contains('dot')) {
      return _isSubstrateAddress(address);
    }

    // Cardano (starts with addr1)
    if (chain.contains('cardano')) {
      return address.startsWith('addr1') && address.length >= 40 && address.length <= 100;
    }

    // Cosmos (starts with cosmos)
    if (chain.contains('cosmos')) {
      return address.startsWith('cosmos') && address.length >= 20 && address.length <= 50;
    }

    // Default: try EVM format (most common)
    return _isEvmAddress(address);
  }

  bool _isBitcoinAddress(String address) {
    // P2PKH (1...), P2SH (3...), Bech32 (bc1...)
    return (address.startsWith('1') || address.startsWith('3') || address.startsWith('bc1')) &&
        address.length >= 26 &&
        address.length <= 62 &&
        _isBase58(address);
  }

  bool _isEvmAddress(String address) {
    return address.startsWith('0x') && address.length == 42 && RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(address);
  }

  bool _isTronAddress(String address) {
    return address.startsWith('T') && address.length == 34 && _isBase58(address);
  }

  bool _isSolanaAddress(String address) {
    return address.length >= 32 && address.length <= 44 && _isBase58(address);
  }

  bool _isSubstrateAddress(String address) {
    if (address.isEmpty) return false;
    // Substrate addresses start with a digit or letter (not 0x)
    final firstChar = address.codeUnitAt(0);
    return (firstChar >= 48 && firstChar <= 57) && // starts with digit
        address.length >= 30 &&
        address.length <= 50 &&
        _isBase58(address);
  }

  bool _isGenericAddress(String address, {int minLen = 25, int maxLen = 40}) {
    return address.length >= minLen && address.length <= maxLen && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(address);
  }

  bool _isBase58(String value) {
    // Base58 excludes 0, O, I, l
    return RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$').hasMatch(value);
  }

  // ==================== ADDRESS FORMATTING ====================

  /// Format an address for display (shorten middle).
  String formatAddress(String address) {
    if (address.length <= 16) return address;
    final prefix = address.startsWith('0x') || address.startsWith('T') ? 6 : 8;
    const suffix = 4;
    if (prefix + suffix >= address.length) return address;
    return '${address.substring(0, prefix)}...${address.substring(address.length - suffix)}';
  }

  // ==================== ADDRESS BOOK ====================

  /// Load all address book entries from storage.
  Future<List<AddressBookEntry>> loadAddressBook() async {
    final entries = await _addressBook.loadFromKeystore();
    return entries
        .map((e) => AddressBookEntry(name: e['name'] ?? '', address: e['address'] ?? ''))
        .toList();
  }

  /// Save an address to the address book.
  Future<void> saveToAddressBook(String name, String address) async {
    await _addressBook.saveToKeystore(name, address);
  }

  /// Delete an address from the address book.
  Future<void> deleteFromAddressBook(String name) async {
    await _addressBook.deleteFromKeystore(name);
  }
}
