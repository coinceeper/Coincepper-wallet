import '../../wallet/transactions/local_send_facade.dart';
import '../../wallet/address_registry.dart';
import '../../services/secure_storage.dart';
import '../../services/api_models.dart';
import '../../services/transaction_notification_receiver.dart';
import '../../services/notification_helper.dart';
import '../../models/transaction.dart' as models;
import '../interfaces/transaction_history.dart';
import 'fee_estimation_service.dart';
import '../../di/service_locator.dart';
import '../../utils/secure_log.dart';

/// سرویس عملیات ارز (Send Transaction)
///
/// این سرویس مسئول:
/// - آماده‌سازی تراکنش (prepare)
/// - تأیید و امضای تراکنش (confirm)
/// - مدیریت تاریخچه تراکنش‌های در انتظار
/// - بررسی موجودی و اعتبارسنجی مبلغ
///
/// از [ITransactionHistory] به جای HistoryProvider استفاده می‌کند
/// تا وابستگی به لایه presentation نداشته باشد (Clean Architecture).
class SendTransactionService {
  static SendTransactionService get instance => ServiceLocator.get<SendTransactionService>();
  SendTransactionService._();
  SendTransactionService();

  final FeeEstimationService _feeService = ServiceLocator.get<FeeEstimationService>();

  // ==================== GET SENDER ADDRESS ====================
  Future<String> getSenderAddress(String userId, String? blockchainName) async {
    final normalizedBlockchain = _feeService.normalizeBlockchainName(blockchainName);
    final addresses = await ServiceLocator.get<AddressRegistry>().loadForWallet(userId);
    final senderAddress = addresses[normalizedBlockchain] ?? addresses[blockchainName ?? ''] ?? '';
    return senderAddress;
  }

  // ==================== PREPARE TRANSACTION ====================
  Future<PrepareTransactionResponse> prepareTransaction({
    required String userId,
    required String? blockchainName,
    required String senderAddress,
    required String recipientAddress,
    required String amount,
    required String? smartContractAddress,
  }) async {
    final walletName = await ServiceLocator.get<SecureStorage>().getSelectedWallet();
    if (walletName == null || walletName.isEmpty) {
      throw StateError('No wallet selected. Please select a wallet first.');
    }

    return await ServiceLocator.get<LocalSendFacade>().prepare(
      walletName: walletName,
      userId: userId,
      blockchainName: blockchainName ?? _feeService.normalizeBlockchainName(blockchainName),
      senderAddress: senderAddress,
      recipientAddress: recipientAddress,
      amount: amount,
      smartContractAddress: smartContractAddress ?? '',
    );
  }

  // ==================== CONFIRM TRANSACTION (Double-Spend Safe) ====================
  ///
  /// ## 🛡️ Double-Spend Prevention
  ///
  /// This method signs ONCE and lets the inner broadcast layer handle retries
  /// with the SAME signed bytes. Retrying the same signed transaction is
  /// idempotent — submitting it N times only produces one on-chain effect.
  ///
  /// If broadcast fails after all inner retries:
  /// - The signed transaction data is preserved in [LocalSendFacade]'s pending
  ///   store, so the user can retry via [LocalSendFacade.retryBroadcast]
  ///   WITHOUT re-signing (the "sign once, broadcast many" pattern).
  /// - The user is shown a "Try Again" option instead of an automatic retry
  ///   that would re-sign with a new nonce and cause double-spend.
  ///
  /// ⚠️ NEVER add an outer retry loop here. The [confirm] method must only
  /// be called once per transaction. Any retry must use the same signed bytes
  /// via [LocalSendFacade.retryBroadcast].
  Future<({bool success, String? hash, String? message})> confirmTransaction({
    required String walletName,
    required String userId,
    required String? blockchainName,
    required String? recipientAddress,
    required String? amount,
    required String? smartContractAddress,
    required String transactionId,
  }) async {
    if (!await ServiceLocator.get<LocalSendFacade>().shouldUseLocalSend()) {
      throw StateError('Custodial server signing is disabled.');
    }

    final hash = await ServiceLocator.get<LocalSendFacade>().confirm(
      walletName: walletName,
      userId: userId,
      blockchainName: blockchainName ?? '',
      recipientAddress: recipientAddress ?? '',
      amount: amount ?? '0',
      smartContractAddress: smartContractAddress ?? '',
      transactionId: transactionId,
    );

    final success = hash != null && hash.isNotEmpty;
    return (
      success: success,
      hash: hash,
      message: success ? 'broadcast_ok' : 'broadcast_failed',
    );
  }

  // ==================== PENDING TRANSACTION ====================
  models.Transaction createPendingTransaction({
    required String transactionId,
    required String senderAddress,
    required String recipientAddress,
    required String amount,
    required String? tokenSymbol,
    required String? blockchainName,
    PrepareTransactionResponse? prepareResponse,
  }) {
    return models.Transaction(
      txHash: transactionId,
      from: prepareResponse?.details.sender ?? senderAddress,
      to: prepareResponse?.details.recipient ?? recipientAddress,
      amount: prepareResponse?.details.amount ?? amount,
      tokenSymbol: tokenSymbol ?? '',
      direction: 'outbound',
      status: 'pending',
      timestamp: DateTime.now().toIso8601String(),
      blockchainName: blockchainName ?? '',
      price: null,
      temporaryId: null,
    );
  }

  // ==================== TRANSACTION AMOUNT VALIDATION ====================
  TransactionValidationResult validateTransactionAmount({
    required String amount,
    required double feeEth,
    required double tokenBalance,
    required String? smartContractAddress,
    required String tokenSymbol,
    required String? blockchainName,
  }) {
    try {
      final amountDouble = double.tryParse(amount);
      if (amountDouble == null) {
        return TransactionValidationResult(isValid: false, adjustedAmount: 0.0, message: 'Invalid amount format');
      }

      if (amountDouble > tokenBalance) {
        return TransactionValidationResult(
          isValid: false, adjustedAmount: 0.0,
          message: 'Insufficient balance. Available: ${tokenBalance.toStringAsFixed(8)} $tokenSymbol',
        );
      }

      final isNativeToken = smartContractAddress == null || smartContractAddress.isEmpty;

      if (isNativeToken) {
        final totalNeeded = amountDouble + feeEth;
        if (totalNeeded > tokenBalance) {
          final maxAmount = tokenBalance - feeEth;
          if (maxAmount <= 0) {
            return TransactionValidationResult(
              isValid: false, adjustedAmount: 0.0,
              message: 'Insufficient balance to cover network fee. Fee: ${feeEth.toStringAsFixed(8)} $tokenSymbol',
            );
          }
          return TransactionValidationResult(
            isValid: true, adjustedAmount: maxAmount,
            message: 'Amount adjusted to maximum available after fee deduction',
          );
        }
      }

      return TransactionValidationResult(isValid: true, adjustedAmount: amountDouble, message: 'Valid amount');
    } catch (e) {
      return TransactionValidationResult(isValid: false, adjustedAmount: 0.0, message: 'Error validating amount: $e');
    }
  }

  // ==================== SUCCESS HANDLING ====================
  Future<void> handleTransactionSuccess({
    required ITransactionHistory historyManager,
    required String transactionId,
    required double sentAmount,
    required String tokenSymbol,
  }) async {
    historyManager.updatePendingTransactionStatus(transactionId, 'completed');
    ServiceLocator.get<TransactionNotificationReceiver>().notifyTransactionConfirmed(transactionId);
    try {
      await NotificationHelper.showSendNotification(sentAmount, tokenSymbol);
    } catch (e) {
      SecureLog.w('Error showing send notification', error: e);
    }
  }
}

class TransactionValidationResult {
  final bool isValid;
  final double adjustedAmount;
  final String message;

  TransactionValidationResult({
    required this.isValid,
    required this.adjustedAmount,
    required this.message,
  });
}
