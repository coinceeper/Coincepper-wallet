/// Pure domain interface for transaction notifications.
///
/// Implemented by [TransactionNotificationReceiver] in the infrastructure layer.
/// Domain services depend on this interface instead of directly
/// depending on concrete implementations.
abstract class ITransactionNotifier {
  void notifyTransactionConfirmed(String transactionId);
}
