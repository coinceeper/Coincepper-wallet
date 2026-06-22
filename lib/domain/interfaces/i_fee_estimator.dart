/// Pure domain interface for fee estimation.
///
/// Implemented by [LocalFeeEstimator] in the infrastructure layer.
/// Domain services depend on this interface instead of directly
/// depending on concrete implementations.
abstract class IFeeEstimator {
  Future<Map<String, dynamic>> estimateRaw({
    required String blockchain,
    required String fromAddress,
    required String toAddress,
    required double amount,
    required String tokenContract,
  });
}
