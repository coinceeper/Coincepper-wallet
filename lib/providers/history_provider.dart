import 'package:flutter/material.dart';
import '../models/transaction.dart';

/// Provider مدیریت تاریخچه تراکنش‌ها (معادل HistoryViewModel.kt در اندروید)
class HistoryProvider extends ChangeNotifier {
  final List<Transaction> _pendingTransactions = [];
  List<Transaction> _transactionsFromServer = [];

  // Getters
  List<Transaction> get pendingTransactions => _pendingTransactions;
  List<Transaction> get transactionsFromServer => _transactionsFromServer;
  
  /// تمام تراکنش‌ها (pending + server) مرتب شده بر اساس timestamp
  List<Transaction> get allTransactions {
    final all = [..._pendingTransactions, ..._transactionsFromServer];
    all.sort((a, b) {
      try {
        final aTime = DateTime.parse(a.timestamp);
        final bTime = DateTime.parse(b.timestamp);
        return bTime.compareTo(aTime); // نزولی (جدیدترین اول)
      } catch (e) {
        return 0;
      }
    });
    return all;
  }

  /// اضافه کردن تراکنش pending
  void addPendingTransaction(Transaction transaction) {
    _pendingTransactions.add(transaction);
    notifyListeners();
  }

  /// حذف تراکنش pending بر اساس transactionId
  void removePendingTransaction(String transactionId) {
    _pendingTransactions.removeWhere((transaction) => transaction.txHash == transactionId);
    notifyListeners();
  }

  /// به‌روزرسانی تراکنش‌های سرور
  void updateServerTransactions(List<Transaction> transactions) {
    _transactionsFromServer = transactions;
    notifyListeners();
  }

  /// پاک کردن تمام تراکنش‌های pending
  void clearPendingTransactions() {
    _pendingTransactions.clear();
    notifyListeners();
  }

  /// پاک کردن تمام تراکنش‌های سرور
  void clearServerTransactions() {
    _transactionsFromServer.clear();
    notifyListeners();
  }

  /// پاک کردن تمام تراکنش‌ها
  void clearAllTransactions() {
    _pendingTransactions.clear();
    _transactionsFromServer.clear();
    notifyListeners();
  }

  /// دریافت تراکنش بر اساس ID
  Transaction? getTransactionById(String transactionId) {
    try {
      return allTransactions.firstWhere(
        (transaction) => transaction.txHash == transactionId,
      );
    } catch (e) {
      return null;
    }
  }

  /// بررسی اینکه آیا تراکنش pending است
  bool isPendingTransaction(String transactionId) {
    return _pendingTransactions.any((transaction) => transaction.txHash == transactionId);
  }

  /// دریافت تعداد تراکنش‌های pending
  int get pendingTransactionCount => _pendingTransactions.length;

  /// دریافت تعداد تراکنش‌های سرور
  int get serverTransactionCount => _transactionsFromServer.length;

  /// دریافت تعداد کل تراکنش‌ها
  int get totalTransactionCount => allTransactions.length;

  /// فیلتر کردن تراکنش‌ها بر اساس وضعیت
  List<Transaction> getTransactionsByStatus(String status) {
    return allTransactions.where((transaction) => transaction.status == status).toList();
  }

  /// فیلتر کردن تراکنش‌ها بر اساس نماد
  List<Transaction> getTransactionsBySymbol(String symbol) {
    return allTransactions.where((transaction) => transaction.tokenSymbol == symbol).toList();
  }

  /// فیلتر کردن تراکنش‌ها بر اساس بلاکچین
  List<Transaction> getTransactionsByBlockchain(String blockchainName) {
    return allTransactions.where((transaction) => transaction.blockchainName == blockchainName).toList();
  }

  /// دریافت تراکنش‌های امروز
  List<Transaction> getTodayTransactions() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return allTransactions.where((transaction) {
      try {
        final transactionTime = DateTime.parse(transaction.timestamp);
        return transactionTime.isAfter(startOfDay) && 
               transactionTime.isBefore(endOfDay);
      } catch (e) {
        return false;
      }
    }).toList();
  }

  /// دریافت تراکنش‌های هفته گذشته
  List<Transaction> getLastWeekTransactions() {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));

    return allTransactions.where((transaction) {
      try {
        final transactionTime = DateTime.parse(transaction.timestamp);
        return transactionTime.isAfter(weekAgo);
      } catch (e) {
        return false;
      }
    }).toList();
  }

  /// دریافت تراکنش‌های ماه گذشته
  List<Transaction> getLastMonthTransactions() {
    final now = DateTime.now();
    final monthAgo = DateTime(now.year, now.month - 1, now.day);

    return allTransactions.where((transaction) {
      try {
        final transactionTime = DateTime.parse(transaction.timestamp);
        return transactionTime.isAfter(monthAgo);
      } catch (e) {
        return false;
      }
    }).toList();
  }

  /// محاسبه آمار تراکنش‌ها
  Map<String, dynamic> getTransactionStatistics() {
    final total = allTransactions.length;
    final pending = _pendingTransactions.length;
    final completed = _transactionsFromServer.where((t) => t.status == 'completed').length;
    final failed = _transactionsFromServer.where((t) => t.status == 'failed').length;

    // گروه‌بندی بر اساس نماد
    final symbolGroups = <String, int>{};
    for (final transaction in allTransactions) {
      symbolGroups[transaction.tokenSymbol] = (symbolGroups[transaction.tokenSymbol] ?? 0) + 1;
    }

    // گروه‌بندی بر اساس بلاکچین
    final blockchainGroups = <String, int>{};
    for (final transaction in allTransactions) {
      blockchainGroups[transaction.blockchainName] = (blockchainGroups[transaction.blockchainName] ?? 0) + 1;
    }

    return {
      'total': total,
      'pending': pending,
      'completed': completed,
      'failed': failed,
      'symbolDistribution': symbolGroups,
      'blockchainDistribution': blockchainGroups,
      'successRate': total > 0 ? (completed / total * 100).roundToDouble() : 0.0,
    };
  }

  /// بررسی تغییرات در تراکنش‌ها
  bool hasTransactionsChanged() {
    // در اینجا می‌توان منطق پیچیده‌تری برای تشخیص تغییرات اضافه کرد
    return _pendingTransactions.isNotEmpty || _transactionsFromServer.isNotEmpty;
  }

  /// به‌روزرسانی وضعیت تراکنش pending به completed
  void updatePendingTransactionStatus(String transactionId, String newStatus) {
    final index = _pendingTransactions.indexWhere((t) => t.txHash == transactionId);
    if (index != -1) {
      final transaction = _pendingTransactions[index];
      
      // ایجاد تراکنش جدید با وضعیت به‌روزرسانی شده
      final updatedTransaction = Transaction(
        txHash: transaction.txHash,
        from: transaction.from,
        to: transaction.to,
        amount: transaction.amount,
        tokenSymbol: transaction.tokenSymbol,
        direction: transaction.direction,
        status: newStatus,
        timestamp: transaction.timestamp,
        blockchainName: transaction.blockchainName,
        price: transaction.price,
        temporaryId: transaction.temporaryId,
      );
      
      // حذف از pending و اضافه به server
      _pendingTransactions.removeAt(index);
      _transactionsFromServer.add(updatedTransaction);
      
      notifyListeners();
    }
  }
} 