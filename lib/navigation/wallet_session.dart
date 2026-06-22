import '../di/service_locator.dart';
import '../services/sensitive_data.dart';
import 'package:flutter/material.dart';

/// In-memory holder for sensitive onboarding data (never route arguments).
///
/// ## امنیت حافظه
///
/// - منیمونیک در [SensitiveString] نگهداری می‌شود
/// - پس از مصرف توسط [consumeMnemonic] یا [clear]، reference پاک می‌شود
/// - دسترسی مستقیم به [pendingMnemonic] منسوخ شده است — از [useMnemonic] استفاده کنید
/// - [SensitiveString.dispose] در [clear] فراخوانی می‌شود
class WalletSession {
  WalletSession._();
  WalletSession();
  static WalletSession get instance => ServiceLocator.get<WalletSession>();

  SensitiveString? _pendingMnemonic;

  /// @Deprecated('Use useMnemonic() callback-based API for better memory safety')
  String? get pendingMnemonic => _pendingMnemonic?.toStringValue();

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
    _pendingMnemonic?.dispose();
    _pendingMnemonic = SensitiveString.fromString(mnemonic);
    pendingWalletName = walletName;
    pendingUserId = userId;
    pendingWalletId = walletId;
  }

  /// دسترسی امن به منیمونیک از طریق callback.
  ///
  /// پس از بازگشت callback، reference داخلی پاک می‌شود.
  T useMnemonic<T>(T Function(String mnemonic) callback) {
    if (_pendingMnemonic == null || _pendingMnemonic!.isDisposed) {
      throw StateError('No pending mnemonic available');
    }
    return _pendingMnemonic!.use(callback);
  }

  /// مصرف منیمونیک (پس از مصرف، reference پاک می‌شود).
  String? consumeMnemonic() {
    if (_pendingMnemonic == null || _pendingMnemonic!.isDisposed) {
      return null;
    }
    final value = _pendingMnemonic!.toStringValue();
    _pendingMnemonic!.dispose();
    _pendingMnemonic = null;
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
    _pendingMnemonic?.dispose();
    _pendingMnemonic = null;
    pendingWalletName = null;
    pendingUserId = null;
    pendingWalletId = null;
    passcodeOnSuccess = null;
    postAuthRoute = null;
  }
}
