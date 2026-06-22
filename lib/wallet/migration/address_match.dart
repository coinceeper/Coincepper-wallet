/// Normalizes addresses for migration comparison.
class AddressMatch {
  static String normalize(String blockchainName, String address) {
    final a = address.trim();
    final n = blockchainName.toLowerCase();
    if (n.contains('ethereum') ||
        n.contains('polygon') ||
        n.contains('bsc') ||
        n.contains('binance') ||
        n.contains('avalanche') ||
        n.contains('arbitrum')) {
      var h = a.toLowerCase();
      if (!h.startsWith('0x')) h = '0x$h';
      return h;
    }
    return a.toLowerCase();
  }

  static bool equals(String blockchainName, String a, String b) {
    return normalize(blockchainName, a) == normalize(blockchainName, b);
  }
}
