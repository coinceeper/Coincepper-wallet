import '../../services/build_secrets.dart';

/// Central config for on-chain indexers (API keys, base URLs).
class ChainIndexerConfig {
  ChainIndexerConfig._();

  /// Explorer API key for [blockchainName] (load-balanced from numbered keys).
  static String apiKeyForBlockchain(String blockchainName) {
    return BuildSecrets.explorerApiKeyForBlockchain(blockchainName);
  }

  static String? etherscanBaseForBlockchain(String blockchainName) {
    final key = apiKeyForBlockchain(blockchainName);
    if (key.isEmpty) return null;
    final n = blockchainName.toLowerCase();
    if (n.contains('ethereum') && !n.contains('classic')) {
      return 'https://api.etherscan.io/api';
    }
    if (n.contains('polygon')) return 'https://api.polygonscan.com/api';
    if (n.contains('bsc') || n.contains('binance')) {
      return 'https://api.bscscan.com/api';
    }
    if (n.contains('avalanche')) return 'https://api.snowtrace.io/api';
    if (n.contains('arbitrum')) return 'https://api.arbiscan.io/api';
    return null;
  }
}
