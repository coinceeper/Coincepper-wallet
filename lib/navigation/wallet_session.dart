import 'package:flutter/material.dart';

/// In-memory holder for sensitive onboarding data (never route arguments).
class WalletSession {
  WalletSession._();

  static final WalletSession instance = WalletSession._();

  String? pendingMnemonic;
  String? pendingWalletName;
  String? pendingUserId;
  String? pendingWalletId;

  VoidCallback? passcodeOnSuccess;
  String? postAuthRoute;

  void setPendingWallet({
    required String mnemonic,
    required String walletName,
    String? userId,
    String? walletId,
  }) {
    pendingMnemonic = mnemonic;
    pendingWalletName = walletName;
    pendingUserId = userId;
    pendingWalletId = walletId;
  }

  String? consumeMnemonic() {
    final value = pendingMnemonic;
    pendingMnemonic = null;
    return value;
  }

  VoidCallback? consumePasscodeOnSuccess() {
    final cb = passcodeOnSuccess;
    passcodeOnSuccess = null;
    return cb;
  }

  String? consumePostAuthRoute() {
    final route = postAuthRoute;
    postAuthRoute = null;
    return route;
  }

  void clear() {
    pendingMnemonic = null;
    pendingWalletName = null;
    pendingUserId = null;
    pendingWalletId = null;
    passcodeOnSuccess = null;
    postAuthRoute = null;
  }
}
