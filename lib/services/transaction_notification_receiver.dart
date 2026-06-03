import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import 'notification_helper.dart';

/// معادل Flutter برای TransactionNotificationReceiver
/// مدیریت نوتیفیکیشن‌های تراکنش با Stream
class TransactionNotificationReceiver {
  static final TransactionNotificationReceiver _instance = TransactionNotificationReceiver._internal();
  static TransactionNotificationReceiver get instance => _instance;
  
  TransactionNotificationReceiver._internal();
  
  // Stream برای مدیریت نوتیفیکیشن‌های تراکنش
  final StreamController<TransactionNotification> _notificationController = 
      StreamController<TransactionNotification>.broadcast();
  
  Stream<TransactionNotification> get notificationStream => _notificationController.stream;
  
  /// ارسال نوتیفیکیشن تراکنش تایید شده
  void notifyTransactionConfirmed(String transactionId) {
    _notificationController.add(
      TransactionNotification(
        type: TransactionNotificationType.confirmed,
        transactionId: transactionId,
        timestamp: DateTime.now(),
      ),
    );
    
    print('🔔 Transaction confirmed: $transactionId');
  }
  
  /// ارسال نوتیفیکیشن تراکنش در انتظار
  void notifyTransactionPending(String transactionId) {
    _notificationController.add(
      TransactionNotification(
        type: TransactionNotificationType.pending,
        transactionId: transactionId,
        timestamp: DateTime.now(),
      ),
    );
    
    print('⏳ Transaction pending: $transactionId');
  }
  
  /// ارسال نوتیفیکیشن تراکنش ناموفق
  void notifyTransactionFailed(String transactionId, String error) {
    _notificationController.add(
      TransactionNotification(
        type: TransactionNotificationType.failed,
        transactionId: transactionId,
        error: error,
        timestamp: DateTime.now(),
      ),
    );
    
    print('❌ Transaction failed: $transactionId - $error');
  }
  
  /// حذف تراکنش در انتظار از تاریخچه
  void removePendingTransaction(String transactionId, BuildContext context) {
    // استفاده از Provider برای حذف تراکنش
    final provider = Provider.of<AppProvider>(context, listen: false);
    // اینجا می‌توانید متد حذف تراکنش را از AppProvider فراخوانی کنید
    // provider.removePendingTransaction(transactionId);
    
    print('🗑️ Removed pending transaction: $transactionId');
  }
  
  /// شروع گوش دادن به نوتیفیکیشن‌ها
  void startListening(BuildContext context) {
    notificationStream.listen((notification) {
      switch (notification.type) {
        case TransactionNotificationType.confirmed:
          _handleConfirmedTransaction(notification, context);
          break;
        case TransactionNotificationType.pending:
          _handlePendingTransaction(notification, context);
          break;
        case TransactionNotificationType.failed:
          _handleFailedTransaction(notification, context);
          break;
      }
    });
    
    print('👂 Transaction notification listener started');
  }
  
  /// مدیریت تراکنش تایید شده
  void _handleConfirmedTransaction(TransactionNotification notification, BuildContext context) {
    // حذف از لیست تراکنش‌های در انتظار
    removePendingTransaction(notification.transactionId, context);

    // نمایش نوتیفیکیشن موفقیت
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تراکنش ${notification.transactionId} با موفقیت تایید شد'),
        backgroundColor: Colors.green,
      ),
    );
  }
  
  /// مدیریت تراکنش در انتظار
  void _handlePendingTransaction(TransactionNotification notification, BuildContext context) {
    unawaited(NotificationHelper.showNotification(
      channelId: NotificationHelper.sendChannelId,
      title: 'Transaction pending',
      body: notification.transactionId,
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تراکنش ${notification.transactionId} در حال پردازش است'),
        backgroundColor: Colors.orange,
      ),
    );
  }
  
  /// مدیریت تراکنش ناموفق
  void _handleFailedTransaction(TransactionNotification notification, BuildContext context) {
    unawaited(NotificationHelper.showNotification(
      channelId: NotificationHelper.sendChannelId,
      title: 'Transaction failed',
      body:
          '${notification.transactionId}${notification.error != null ? ' — ${notification.error}' : ''}',
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تراکنش ${notification.transactionId} ناموفق بود: ${notification.error}'),
        backgroundColor: Colors.red,
      ),
    );
  }
  
  /// توقف گوش دادن
  void dispose() {
    _notificationController.close();
    print('🔇 Transaction notification listener stopped');
  }
}

/// نوع نوتیفیکیشن تراکنش
enum TransactionNotificationType {
  confirmed,
  pending,
  failed,
}

/// مدل نوتیفیکیشن تراکنش
class TransactionNotification {
  final TransactionNotificationType type;
  final String transactionId;
  final DateTime timestamp;
  final String? error;
  
  TransactionNotification({
    required this.type,
    required this.transactionId,
    required this.timestamp,
    this.error,
  });
  
  @override
  String toString() {
    return 'TransactionNotification(type: $type, transactionId: $transactionId, timestamp: $timestamp, error: $error)';
  }
} 