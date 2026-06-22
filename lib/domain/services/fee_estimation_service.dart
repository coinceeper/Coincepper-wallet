import '../interfaces/i_fee_estimator.dart';
import '../../di/service_locator.dart';

/// سرویس تخمین کارمزد تراکنش
///
/// این سرویس مسئول:
/// - تخمین کارمزد با استفاده از [IFeeEstimator]
/// - Fallback به مقادیر پیش‌فرض برای بلاکچین‌های مختلف
/// - تبدیل نام بلاکچین به فرمت مناسب برای تخمین کارمزد
///
/// از [IFeeEstimator] به جای [LocalFeeEstimator] مستقیم استفاده می‌کند
/// تا وابستگی به لایه infrastructure نداشته باشد.
class FeeEstimationService {
  static FeeEstimationService get instance => ServiceLocator.get<FeeEstimationService>();
  FeeEstimationService._();
  FeeEstimationService();

  final IFeeEstimator _feeEstimator = ServiceLocator.get<IFeeEstimator>();

  // ==================== FEE ESTIMATION ====================

  /// تخمین کارمزد. از طریق [IFeeEstimator] کد را از infrastructure جدا نگه می‌دارد.
  Future<Map<String, dynamic>> estimateFee({
    required String blockchainName,
    required String fromAddress,
    required String toAddress,
    required double amount,
    required String tokenContract,
  }) async {
    final feeBlockchain = _getFeeEstimationBlockchain(blockchainName);

    return await _feeEstimator.estimateRaw(
      blockchain: feeBlockchain,
      fromAddress: fromAddress,
      toAddress: toAddress,
      amount: amount,
      tokenContract: tokenContract,
    );
  }

  // ==================== FALLBACK FEE OPTIONS ====================
  Map<String, Map<String, dynamic>> getDefaultFeesForBlockchain(String? blockchainName) {
    final chain = (blockchainName ?? '').toLowerCase();

    if (chain.contains('tron')) {
      return {
        'slow': {'gasPrice': 1, 'feeEth': 0.0001},
        'average': {'gasPrice': 2, 'feeEth': 0.0002},
        'fast': {'gasPrice': 3, 'feeEth': 0.0003},
      };
    }

    if (chain.contains('bitcoin')) {
      return {
        'slow': {'gasPrice': 5, 'feeEth': 0.0005},
        'average': {'gasPrice': 10, 'feeEth': 0.001},
        'fast': {'gasPrice': 20, 'feeEth': 0.002},
      };
    }

    if (chain.contains('binance') || chain.contains('bsc')) {
      return {
        'slow': {'gasPrice': 3, 'feeEth': 0.0003},
        'average': {'gasPrice': 5, 'feeEth': 0.0005},
        'fast': {'gasPrice': 10, 'feeEth': 0.001},
      };
    }

    // Default (Ethereum-like)
    return {
      'slow': {'gasPrice': 10, 'feeEth': 0.0001},
      'average': {'gasPrice': 20, 'feeEth': 0.0002},
      'fast': {'gasPrice': 30, 'feeEth': 0.0003},
    };
  }

  // ==================== BLOCKCHAIN NAME HELPERS ====================
  String getFeeEstimationBlockchain(String? name) {
    return _getFeeEstimationBlockchain(name);
  }

  String _getFeeEstimationBlockchain(String? name) {
    if (name == null) return '';
    final normalized = name.toLowerCase();
    if (normalized.contains('binance') || normalized.contains('bsc') || normalized.contains('bnb')) return 'bsc';
    if (normalized.contains('tron')) return 'tron';
    if (normalized.contains('ethereum') || normalized.contains('polygon') || normalized.contains('matic')) return 'polygon';
    if (normalized.contains('bitcoin')) return 'bitcoin';
    if (normalized.contains('avalanche') || normalized.contains('avax')) return 'avalanche';
    if (normalized.contains('arbitrum') || normalized.contains('arb')) return 'arbitrum';
    return name.toLowerCase();
  }

  String getBlockchainCurrency(String? blockchainName) {
    if (blockchainName == null) return 'ETH';
    final normalized = blockchainName.toLowerCase();
    if (normalized.contains('tron')) return 'TRX';
    if (normalized.contains('binance') || normalized.contains('bsc') || normalized.contains('bnb')) return 'BNB';
    if (normalized.contains('bitcoin')) return 'BTC';
    return 'ETH';
  }

  String normalizeBlockchainName(String? name) {
    if (name == null) return '';
    final normalized = name.toLowerCase();
    if (normalized.contains('binance') || normalized.contains('bsc') || normalized.contains('bnb')) return 'bsc';
    if (normalized.contains('tron')) return 'tron';
    if (normalized.contains('ethereum') || normalized.contains('polygon') || normalized.contains('matic')) return 'polygon';
    if (normalized.contains('bitcoin')) return 'bitcoin';
    return name.toLowerCase();
  }
}
