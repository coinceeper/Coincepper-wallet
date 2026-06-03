import '../models/transaction.dart';

class TransactionCache {
  static final List<Transaction> _pendingTransactions = [];
  static final Map<String, Transaction> _transactionsById = {};

  static List<Transaction> get pendingTransactions => List.unmodifiable(_pendingTransactions);

  static void addPendingTransaction(Transaction transaction) {
    _pendingTransactions.add(transaction);
  }

  static void updateById(String txHash, Transaction transaction) {
    _transactionsById[txHash] = transaction;
  }

  static void matchAndReplacePending(Transaction serverTransaction) {
    final index = _pendingTransactions.indexWhere((tx) => tx.txHash == serverTransaction.txHash);
    if (index != -1) {
      _pendingTransactions.removeAt(index);
    }
  }

  static void clearPendingTransactions() {
    _pendingTransactions.clear();
  }

  static void clearAll() {
    _pendingTransactions.clear();
    _transactionsById.clear();
  }

  static Transaction? getById(String txHash) {
    return _transactionsById[txHash];
  }

  static List<Transaction> getAllTransactions() {
    return [..._pendingTransactions, ..._transactionsById.values];
  }
} 