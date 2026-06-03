import 'evm_rpc_pool.dart';

/// Public RPC endpoints for local broadcast (non-custodial).
class WalletCoreConfig {
  /// Returns the primary RPC URL via the multi-provider [EvmRpcPool].
  static String evmRpcForBlockchain(String blockchainName) =>
      EvmRpcPool.evmRpcForBlockchain(blockchainName);

  static int evmChainId(String blockchainName) {
    final n = blockchainName.toLowerCase();
    if (n.contains('bsc') || n.contains('binance')) return 56;
    if (n.contains('polygon')) return 137;
    if (n.contains('avalanche')) return 43114;
    if (n.contains('arbitrum')) return 42161;
    return 1;
  }

  static String? etherscanBaseUrl(String blockchainName) {
    final n = blockchainName.toLowerCase();
    if (n.contains('ethereum') || n == 'eth') {
      return 'https://api.etherscan.io/api';
    }
    if (n.contains('bsc') || n.contains('binance')) {
      return 'https://api.bscscan.com/api';
    }
    if (n.contains('polygon')) return 'https://api.polygonscan.com/api';
    if (n.contains('avalanche')) return 'https://api.snowtrace.io/api';
    if (n.contains('arbitrum')) return 'https://api.arbiscan.io/api';
    return null;
  }
}
