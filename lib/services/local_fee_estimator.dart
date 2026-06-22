import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';
import 'api_models.dart';
import 'backend_proxy_service.dart';
import '../domain/interfaces/i_fee_estimator.dart';
import '../wallet/core/wallet_core_config.dart';
import '../di/service_locator.dart';
import '../utils/secure_log.dart';

/// Estimates transaction fees directly from public RPCs (non-custodial).
///
/// No server call — each chain is queried from its public RPC / indexer.
class LocalFeeEstimator implements IFeeEstimator {
  LocalFeeEstimator._();
  LocalFeeEstimator();
  static LocalFeeEstimator get instance => ServiceLocator.get<LocalFeeEstimator>();

  /// Estimate fee for a given blockchain transaction.
  ///
  /// ## استراتژی Hybrid:
  /// 1. **Proxy (Primary)**: GET /api/v2/gas — cache دار
  /// 2. **Direct (Fallback)**: از RPC عمومی (همین الان)
  ///
  /// Returns an [EstimateFeeResponse] matching the legacy API shape so the
  /// send screen needs zero UI changes.
  Future<EstimateFeeResponse> estimateFee({
    required String blockchain,
    required String fromAddress,
    required String toAddress,
    required double amount,
    String tokenContract = '',
  }) async {
    final chain = blockchain.toLowerCase();

    if (chain.contains('ethereum') ||
        chain.contains('polygon') ||
        chain.contains('bsc') ||
        chain.contains('binance') ||
        chain.contains('avalanche') ||
        chain.contains('arbitrum')) {
      return ServiceLocator.get<BackendProxyService>().route(
        endpoint: 'gas/$chain',
        proxyCall: () => _estimateEvmFeeFromProxy(
          blockchain: blockchain,
          fromAddress: fromAddress,
          toAddress: toAddress,
          tokenContract: tokenContract,
        ),
        directCall: () => _estimateEvmFee(
          blockchain: blockchain,
          fromAddress: fromAddress,
          toAddress: toAddress,
          tokenContract: tokenContract,
        ),
      );
    }

    if (chain.contains('bitcoin')) return _estimateBtcFee();
    if (chain.contains('tron')) return _estimateTronFee();

    // Fallback: generic defaults
    return _fallbackFeeResponse();
  }

  @override
  Future<Map<String, dynamic>> estimateRaw({
    required String blockchain,
    required String fromAddress,
    required String toAddress,
    required double amount,
    required String tokenContract,
  }) async {
    final response = await estimateFee(
      blockchain: blockchain,
      fromAddress: fromAddress,
      toAddress: toAddress,
      amount: amount,
      tokenContract: tokenContract,
    );
    return {
      'fee': response.fee,
      'fee_currency': response.feeCurrency,
      'gas_price': response.gasPrice,
      'gas_used': response.gasUsed,
      'priority_options': response.priorityOptions?.toJson(),
      'timestamp': response.timestamp,
      'unit': response.unit,
      'usd_price': response.usdPrice,
    };
  }

  /// Get gas fee estimate from backend proxy.
  Future<EstimateFeeResponse> _estimateEvmFeeFromProxy({
    required String blockchain,
    required String fromAddress,
    required String toAddress,
    String tokenContract = '',
  }) async {
    final response = await ServiceLocator.get<BackendProxyService>()
        .proxyGet('gas', queryParams: {
      'chain': blockchain.toLowerCase(),
    });

    final json = BackendProxyService.parseJson(response);
    if (json == null || json['status'] != 'ok') {
      throw Exception('Proxy gas fee failed');
    }

    final gasData = json['data'] as Map<String, dynamic>? ?? {};
    final gasPriceGwei = (gasData['gas_price'] as num?)?.toInt() ?? 20;
    final gasLimit = (gasData['gas_limit'] as num?)?.toInt() ?? 21000;
    final feeCurrency = gasData['currency'] as String? ?? _evmCurrency(blockchain);

    final slowGwei = (gasPriceGwei * 0.9).floor().clamp(1, gasPriceGwei);
    final avgGwei = gasPriceGwei.clamp(1, 10000);
    final fastGwei = (gasPriceGwei * 1.2).ceil().clamp(avgGwei, 100000);

    final slowFeeWei = (slowGwei * 1e9 * gasLimit).toInt();
    final avgFeeWei = (avgGwei * 1e9 * gasLimit).toInt();
    final fastFeeWei = (fastGwei * 1e9 * gasLimit).toInt();
    final feeEth = avgFeeWei / 1e18;

    return EstimateFeeResponse(
      fee: avgFeeWei,
      feeCurrency: feeCurrency,
      gasPrice: avgGwei,
      gasUsed: gasLimit,
      priorityOptions: PriorityOptions(
        slow: PriorityOption(fee: slowGwei, feeEth: slowFeeWei / 1e18),
        average: PriorityOption(fee: avgGwei, feeEth: feeEth),
        fast: PriorityOption(fee: fastGwei, feeEth: fastFeeWei / 1e18),
      ),
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      unit: 'WEI',
      usdPrice: null,
    );
  }

  // ── EVM ──────────────────────────────────────────────────

  Future<EstimateFeeResponse> _estimateEvmFee({
    required String blockchain,
    required String fromAddress,
    required String toAddress,
    String tokenContract = '',
  }) async {
    final rpc = WalletCoreConfig.evmRpcForBlockchain(blockchain);

    try {
      final gasPriceGwei = await _evmGasPrice(rpc);

      final gasLimit = await _evmEstimateGas(
        rpc: rpc,
        from: fromAddress,
        to: tokenContract.isNotEmpty ? tokenContract : toAddress,
        data: tokenContract.isNotEmpty ? _erc20TransferData(toAddress) : '0x',
      );

      final slowGwei = (gasPriceGwei * 0.9).floor().clamp(1, gasPriceGwei);
      final avgGwei = gasPriceGwei.clamp(1, 10000);
      final fastGwei = (gasPriceGwei * 1.2).ceil().clamp(avgGwei, 100000);

      final slowFeeWei = (slowGwei * 1e9 * gasLimit).toInt();
      final avgFeeWei = (avgGwei * 1e9 * gasLimit).toInt();
      final fastFeeWei = (fastGwei * 1e9 * gasLimit).toInt();

      final feeEth = avgFeeWei / 1e18;

      return EstimateFeeResponse(
        fee: avgFeeWei,
        feeCurrency: _evmCurrency(blockchain),
        gasPrice: avgGwei,
        gasUsed: gasLimit,
        priorityOptions: PriorityOptions(
          slow: PriorityOption(fee: slowGwei, feeEth: slowFeeWei / 1e18),
          average: PriorityOption(fee: avgGwei, feeEth: feeEth),
          fast: PriorityOption(fee: fastGwei, feeEth: fastFeeWei / 1e18),
        ),
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        unit: 'WEI',
        usdPrice: null, // caller can supply via PriceProvider
      );
    } catch (e) {
      SecureLog.w('LocalFeeEstimator: fee estimation failed, using fallback', error: e);
      return _fallbackFeeResponse();
    }
  }

  Future<int> _evmGasPrice(String rpc) async {
    final client = Web3Client(rpc, http.Client());
    try {
      final amount = await client.getGasPrice();
      // Return gas price in gwei as int
      return amount.getValueInUnit(EtherUnit.gwei).toInt();
    } finally {
      client.dispose();
    }
  }

  Future<int> _evmEstimateGas({
    required String rpc,
    required String from,
    required String to,
    String data = '0x',
  }) async {
    try {
      final body = jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'eth_estimateGas',
        'params': [
          {
            'from': from,
            'to': to,
            'data': data,
          }
        ],
      });
      final res = await http
          .post(Uri.parse(rpc),
              headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final map = jsonDecode(res.body) as Map<String, dynamic>;
        final hex = map['result'] as String?;
        if (hex != null && hex != '0x') {
          return int.parse(hex, radix: 16);
        }
      }
    } catch (e) {
      SecureLog.d('Error estimating EVM gas limit via RPC', error: e);
    }
    // Fallback gas limits
    return data.isNotEmpty && data != '0x' ? 120000 : 21000;
  }

  String _erc20TransferData(String to) {
    // transfer(address to, uint256 amount) — amount omitted for estimation
    // 0xa9059cbb + padded recipient address
    final padded =
        '000000000000000000000000${to.replaceFirst('0x', '').toLowerCase()}';
    return '0xa9059cbb$padded'
        '0000000000000000000000000000000000000000000000000000000000000001';
  }

  static String _evmCurrency(String blockchain) {
    final n = blockchain.toLowerCase();
    if (n.contains('bsc') || n.contains('binance')) return 'BNB';
    if (n.contains('polygon')) return 'MATIC';
    if (n.contains('avalanche')) return 'AVAX';
    if (n.contains('arbitrum')) return 'ETH';
    return 'ETH';
  }

  // ── Bitcoin ────────────────────────────────────────────────

  Future<EstimateFeeResponse> _estimateBtcFee() async {
    try {
      // Mempool.space fee estimates (free, no API key)
      final res = await http
          .get(Uri.parse('https://mempool.space/api/v1/fees/recommended'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final map = jsonDecode(res.body) as Map<String, dynamic>;
        final slow = (map['economyFee'] as num?)?.toInt() ?? 5;
        final avg = (map['halfHourFee'] as num?)?.toInt() ?? 10;
        final fast = (map['fastestFee'] as num?)?.toInt() ?? 20;

        // Approx: ~140 vbytes for a typical tx
        const vbytes = 140;
        return EstimateFeeResponse(
          fee: avg * vbytes,
          feeCurrency: 'BTC',
          gasPrice: avg,
          gasUsed: vbytes,
          priorityOptions: PriorityOptions(
            slow: PriorityOption(fee: slow, feeEth: (slow * vbytes) / 1e8),
            average: PriorityOption(fee: avg, feeEth: (avg * vbytes) / 1e8),
            fast: PriorityOption(fee: fast, feeEth: (fast * vbytes) / 1e8),
          ),
          timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          unit: 'sat/vB',
          usdPrice: null,
        );
      }
    } catch (e) {
      SecureLog.d('Error estimating BTC fee via mempool.space', error: e);
    }
    return _fallbackFeeResponse();
  }

  // ── Tron ──────────────────────────────────────────────────

  Future<EstimateFeeResponse> _estimateTronFee() async {
    // Tron uses bandwidth + energy; a typical TRC20 transfer uses ~65k energy.
    // Return a reasonable default estimate.
    return EstimateFeeResponse(
      fee: 65000,
      feeCurrency: 'TRX',
      gasPrice: 1,
      gasUsed: 65000,
      priorityOptions: const PriorityOptions(
        slow: PriorityOption(fee: 1, feeEth: 0.0001),
        average: PriorityOption(fee: 2, feeEth: 0.0002),
        fast: PriorityOption(fee: 3, feeEth: 0.0003),
      ),
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      unit: 'ENERGY',
      usdPrice: null,
    );
  }

  // ── Fallback ──────────────────────────────────────────────

  EstimateFeeResponse _fallbackFeeResponse() {
    return EstimateFeeResponse(
      fee: 21000,
      feeCurrency: 'ETH',
      gasPrice: 20,
      gasUsed: 21000,
      priorityOptions: const PriorityOptions(
        slow: PriorityOption(fee: 10, feeEth: 0.0001),
        average: PriorityOption(fee: 20, feeEth: 0.0002),
        fast: PriorityOption(fee: 30, feeEth: 0.0003),
      ),
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      unit: 'WEI',
      usdPrice: null,
    );
  }
}
