import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/security_settings_manager.dart';
import 'app_navigation_state.dart';
import 'app_router.dart';
import 'backup_navigation.dart';
import 'route_paths.dart';
import 'session_lock_coordinator.dart';
import 'wallet_session.dart';

void goPasscodeConfirm(
  BuildContext context, {
  required String firstPasscode,
  String? walletName,
}) {
  context.pushReplacement(
    RoutePaths.passcodeConfirm,
    extra: {
      'firstPasscode': firstPasscode,
      'walletName': walletName,
    },
  );
}

Future<void> completePasscodeSetupSuccess(BuildContext context) async {
  // 🛑 CRITICAL FIX: Clear background time & reset activity timer BEFORE
  // releasing the session lock. Otherwise the GoRouter redirect guard
  // fires on setSessionLockRequired(false), sees the old background time,
  // and redirects back to enter-passcode — creating an infinite loop.
  await SecuritySettingsManager.instance.clearLastBackgroundTime();
  await SecuritySettingsManager.instance.resetActivityTimer();
  AppNavigationState.instance.setSessionLockRequired(false);

  final callback = WalletSession.instance.consumePasscodeOnSuccess();
  if (callback != null) {
    callback();
    return;
  }
  
  // Try to get return URI from SessionLockCoordinator first
  final returnUri = await SessionLockCoordinator.consumeReturnUri();
  final postAuth = returnUri ?? WalletSession.instance.consumePostAuthRoute();

  WalletSession.instance.clear();

  // Use AppRouter.router.go() instead of context.go() for robustness:
  // the passcode screen context may be stale after pushReplacement.
  final route = postAuth ?? RoutePaths.home;
  AppRouter.router.go(route);
}

void goPasscodeGateForRoute(BuildContext context, String destination) {
  WalletSession.instance.postAuthRoute = destination;
  context.push(RoutePaths.enterPasscode);
}

void goEnterPasscodeWithCallback(
  BuildContext context,
  VoidCallback onUnlocked, {
  bool isFromBackground = false,
}) {
  WalletSession.instance.passcodeOnSuccess = onUnlocked;
  context.push(
    RoutePaths.enterPasscode,
    extra: {'isFromBackground': isFromBackground},
  );
}

void goBackupAfterPasscodeConfirm(BuildContext context) {
  final name = WalletSession.instance.pendingWalletName ?? 'Unknown Wallet';
  goToBackupScreen(
    context,
    walletName: name,
    mnemonic: WalletSession.instance.pendingMnemonic ?? '',
    userId: WalletSession.instance.pendingUserId,
    walletId: WalletSession.instance.pendingWalletId,
  );
}
