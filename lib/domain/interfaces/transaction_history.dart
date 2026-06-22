import '../../models/transaction.dart';

/// Pure domain interface for managing transaction history.
///
/// Implemented by [HistoryProvider] in the presentation layer.
/// Domain services depend on this interface instead of directly
/// importing presentation-layer providers.
abstract class ITransactionHistory {
  void addPendingTransaction(Transaction transaction);

  void updatePendingTransactionStatus(String transactionId, String newStatus);
}
