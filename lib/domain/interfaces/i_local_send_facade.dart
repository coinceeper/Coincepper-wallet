/// Pure domain interface for local send operations (non-custodial signing).
///
/// Implemented by [LocalSendFacade] in the wallet layer.
/// Domain services depend on this interface instead of directly
/// depending on concrete implementations.
abstract class ILocalSendFacade {
  Future<Map<String, dynamic>> prepare({
    required String walletName,
    required String userId,
    required String blockchainName,
    required String senderAddress,
    required String recipientAddress,
    required String amount,
    required String smartContractAddress,
  });

  Future<String?> confirm({
    required String walletName,
    required String userId,
    required String blockchainName,
    required String recipientAddress,
    required String amount,
    required String smartContractAddress,
    required String transactionId,
  });

  Future<bool> shouldUseLocalSend();
  Future<String?> retryBroadcast(String transactionId);
}
