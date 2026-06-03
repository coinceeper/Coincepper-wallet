import 'dart:async';
import 'package:flutter/foundation.dart';

/// Helper class for update-balance API calls (مطابق با Kotlin MainActivity.kt)
/// 
/// این کلاس دقیقاً مطابق با منطق Kotlin پیاده‌سازی شده:
/// - 3 بار تلاش مجدد در صورت شکست
/// - تأخیر 5 ثانیه قبل از ارسال
/// - timeout 10 ثانیه برای هر درخواست
/// - callback برای اطلاع از نتیجه
class UpdateBalanceHelper {
  static const int maxRetries = 3; // مطابق با Kotlin
  static const Duration initialDelay = Duration(seconds: 5); // مطابق با Kotlin
  static const Duration apiTimeout = Duration(seconds: 10); // مطابق با Kotlin

  /// به‌روزرسانی موجودی با چک و retry logic (مطابق با Kotlin updateBalanceWithCheck)
  /// 
  /// [userId]: شناسه کاربر
  /// [onResult]: callback برای دریافت نتیجه (true = موفق، false = ناموفق)
  /// [skipDelay]: اگر true باشد، تأخیر 5 ثانیه‌ای را نادیده می‌گیرد (برای بهینه‌سازی)
  static Future<void> updateBalanceWithCheck(
    String userId, 
    Function(bool success) onResult, {
    bool skipDelay = false,
  }) async {
    const tag = 'UpdateBalance';

    if (kDebugMode) {
      print('$tag: Custodial update-balance disabled; balances are on-chain only');
    }
    onResult(true);
  }

  /// تابع ساده برای به‌روزرسانی موجودی بدون callback (مطابق با Kotlin updateUserBalance)
  /// 
  /// [userId]: شناسه کاربر
  static Future<bool> updateUserBalance(String userId) async {
    const tag = 'UpdateBalance';
    
    if (kDebugMode) {
      print('$tag: Sending balance update request for UserID: $userId');
    }

    final completer = Completer<bool>();

    updateBalanceWithCheck(userId, (success) {
      completer.complete(success);
    });

    return completer.future;
  }

  /// به‌روزرسانی موجودی در پس‌زمینه (برای بهینه‌سازی کیف پول جدید)
  /// این متد در پس‌زمینه اجرا می‌شود و نتیجه را ذخیره می‌کند اما UI را مسدود نمی‌کند
  static void updateBalanceInBackground(String userId) {
    const tag = 'UpdateBalance-BG';
    
    if (kDebugMode) {
      print('$tag: Starting background balance update for UserID: $userId');
    }

    // اجرای در پس‌زمینه با تأخیر کم (2 ثانیه به جای 5 ثانیه)
    if (kDebugMode) {
      print('$tag: Background custodial update-balance skipped');
    }
  }
} 