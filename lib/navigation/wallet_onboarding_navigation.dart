import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'route_paths.dart';
import 'wallet_session.dart';

/// 🧭 مسیر ناوبری اصولی بعد از Create/Import Wallet
///
/// معماری استاندارد (Trust Wallet-like):
///
/// ┌─ CREATE FLOW ─────────────────────────────┐
/// │  inside-new-wallet                        │
/// │    → phrase-key (نمایش ۱۲ کلمه)           │
/// │    → phrase-key-confirm (تأیید کلمات)     │
/// │    → backup (یادآوری پشتیبان)            │
/// │    → passcode-setup (تنظیم رمز)          │
/// │    → passcode-confirm (تأیید رمز)        │
/// │    → 🏁 HOME                              │
/// └────────────────────────────────────────────┘
///
/// ┌─ IMPORT FLOW ──────────────────────────────┐
/// │  inside-import-wallet                      │
/// │    → backup (یادآوری پشتیبان - اختیاری)    │
/// │    → passcode-setup (تنظیم رمز)           │
/// │    → passcode-confirm (تأیید رمز)         │
/// │    → 🏁 HOME                               │
/// └────────────────────────────────────────────┘

/// شروع فرآیند Onboarding بعد از ساخت/ورود کیف پول
Future<void> goThroughOnboardingFlow({
  required BuildContext context,
  required bool isFromWalletCreation,
  required bool isPasscodeEnabled,
  required String walletName,
  required String mnemonic,
  String? userId,
  String? walletId,
}) async {
  WalletSession.instance.setPendingWallet(
    mnemonic: mnemonic,
    walletName: walletName,
    userId: userId,
    walletId: walletId,
  );

  if (!context.mounted) return;

  if (isFromWalletCreation) {
    // ─── CREATE FLOW: نمایش Seed Phrase ➔ تأیید ➔ بکاپ ➔ Passcode ➔ Home ───
    context.go(
      RoutePaths.phraseKey,
      extra: {
        'walletName': walletName,
        'isFromWalletCreation': true,
        'showCopy': true,
        'isPasscodeEnabled': isPasscodeEnabled,
      },
    );
  } else {
    // ─── IMPORT FLOW: بکاپ (اختیاری) ➔ Passcode ➔ Home ───
    context.go(
      RoutePaths.backup,
      extra: {
        'walletName': walletName,
        'isPasscodeEnabled': isPasscodeEnabled,
        'skipPhraseKey': true, // کاربر همین الان seed را paste کرده
      },
    );
  }
}

/// بعد از تأیید Seed Phrase: به Backup ➔ Passcode ➔ Home
Future<void> goToBackupAfterPhraseConfirm({
  required BuildContext context,
  required String walletName,
  required bool isPasscodeEnabled,
}) async {
  if (!context.mounted) return;
  context.go(
    RoutePaths.backup,
    extra: {
      'walletName': walletName,
      'isPasscodeEnabled': isPasscodeEnabled,
      'skipPhraseKey': false,
    },
  );
}

/// بعد از Backup: به Passcode ➔ Home
Future<void> goToPasscodeOrHomeAfterBackup({
  required BuildContext context,
  required String walletName,
  required bool isPasscodeEnabled,
}) async {
  if (!context.mounted) return;

  if (!isPasscodeEnabled) {
    // اگر Passcode فعال نیست، مستقیم به Home
    WalletSession.instance.clear();
    if (context.mounted) {
      context.go(RoutePaths.home);
    }
    return;
  }

  // تنظیم route بعد از تنظیم موفق Passcode (بدون callback — context قدیمی)
  WalletSession.instance.postAuthRoute = RoutePaths.home;

  if (context.mounted) {
    context.go(
      RoutePaths.passcodeSetup,
      extra: {'walletName': walletName},
    );
  }
}
