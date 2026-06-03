import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/secure_storage.dart';
import 'route_paths.dart';

/// Blocks system back when a wallet already exists; shows a confirmation
/// dialog explaining why back navigation is blocked and offers to go home.
class OnboardingWalletGuardScope extends StatelessWidget {
  const OnboardingWalletGuardScope({
    super.key,
    required this.child,
    this.allowPopWhenNoWallets = true,
  });

  final Widget child;
  final bool allowPopWhenNoWallets;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final wallets = await SecureStorage.instance.getWalletsList();
        final walletCount = wallets.length;

        if (walletCount == 0) {
          // No wallet exists — safe to pop
          if (context.mounted && context.canPop()) {
            context.pop(result);
          }
          return;
        }

        // Wallet exists — explain and offer going home
        if (!context.mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF005FEE)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Wallet Already Exists',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
              content: const Text(
                'You already have a wallet on this device. '
                'Going back to the previous screen is not possible from here. '
                'Would you like to go to the Home screen instead?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text(
                    'Stay Here',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF005FEE),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Go to Home'),
                ),
              ],
            );
          },
        );

        if (confirmed == true && context.mounted) {
          context.go(RoutePaths.home);
        }
      },
      child: child,
    );
  }
}
