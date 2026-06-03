import '../../core/evm_rpc_pool.dart';

/// Fetches EVM gas price (wei) from the multi-provider RPC pool.
class EvmFeeEstimator {
  const EvmFeeEstimator();

  Future<int> gasPriceWei(String blockchainName) async {
    final fees = await eip1559MaxFeesWei(blockchainName);
    return fees.maxFeePerGas;
  }

  /// EIP-1559 fee hints; falls back to legacy gas price.
  Future<({int maxFeePerGas, int maxPriorityFeePerGas})> eip1559MaxFeesWei(
    String blockchainName,
  ) async {
    try {
      final priority = await _rpcHexInt(blockchainName, 'eth_maxPriorityFeePerGas', const []);
      final base = await _rpcHexInt(blockchainName, 'eth_gasPrice', const []);
      if (priority != null && base != null) {
        return (maxFeePerGas: base + priority, maxPriorityFeePerGas: priority);
      }
      if (base != null) return (maxFeePerGas: base, maxPriorityFeePerGas: 0);
    } catch (_) {
      // fall through to ultimate fallback
    }
    return (maxFeePerGas: 20000000000, maxPriorityFeePerGas: 1000000000);
  }

  Future<int?> _rpcHexInt(
    String blockchainName,
    String method,
    List<dynamic> params,
  ) async {
    try {
      final result = await EvmRpcPool.tryPost(blockchainName, {
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
        'id': 1,
      }, timeout: const Duration(seconds: 10));
      final hex = result['result']?.toString();
      if (hex != null && hex.startsWith('0x')) {
        return int.parse(hex.substring(2), radix: 16);
      }
    } catch (_) {}
    return null;
  }
}
