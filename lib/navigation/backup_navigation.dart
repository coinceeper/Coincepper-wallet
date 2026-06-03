import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'route_paths.dart';
import 'wallet_session.dart';

void goToBackupScreen(
  BuildContext context, {
  required String walletName,
  required String mnemonic,
  String? userId,
  String? walletId,
}) {
  WalletSession.instance.setPendingWallet(
    mnemonic: mnemonic,
    walletName: walletName,
    userId: userId,
    walletId: walletId,
  );
  context.go(
    RoutePaths.backup,
    extra: {
      'walletName': walletName,
      if (userId != null) 'userID': userId,
      if (walletId != null) 'walletID': walletId,
    },
  );
}
