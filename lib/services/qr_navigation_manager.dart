import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../navigation/route_paths.dart';
import '../navigation/wallet_session.dart';

class QRNavigationManager {
  /// Process QR scan result and navigate (no persistence of scan content).
  static Future<void> processQRScanResult(
    BuildContext context,
    String scanResult,
    String returnScreen,
  ) async {
    try {
      final navigationResult =
          await _processScanContent(scanResult, returnScreen);

      if (navigationResult != null) {
        await _navigateToScreen(context, navigationResult);
      }
    } catch (e) {
      _showErrorSnackBar(context, 'Error processing QR code');
    }
  }

  static Future<NavigationResult?> _processScanContent(
    String scanResult,
    String returnScreen,
  ) async {
    if (_isWalletAddress(scanResult)) {
      return NavigationResult(
        route: RoutePaths.send,
        arguments: {'address': scanResult, 'returnScreen': returnScreen},
        message: 'Wallet address detected',
      );
    }

    if (_isSeedPhrase(scanResult)) {
      WalletSession.instance.setPendingWallet(
        mnemonic: scanResult.trim(),
        walletName: '',
      );
      return NavigationResult(
        route: RoutePaths.importWallet,
        arguments: {'fromQr': true, 'returnScreen': returnScreen},
        message: 'Seed phrase detected',
      );
    }

    if (_isPaymentURL(scanResult)) {
      return NavigationResult(
        route: RoutePaths.send,
        arguments: {'paymentUrl': scanResult, 'returnScreen': returnScreen},
        message: 'Payment URL detected',
      );
    }

    if (_isTokenTransfer(scanResult)) {
      return NavigationResult(
        route: RoutePaths.send,
        arguments: {'tokenTransfer': scanResult, 'returnScreen': returnScreen},
        message: 'Token transfer detected',
      );
    }

    return NavigationResult(
      route: RoutePaths.send,
      arguments: {'text': scanResult, 'returnScreen': returnScreen},
      message: 'Text content detected',
    );
  }

  static Future<void> _navigateToScreen(
    BuildContext context,
    NavigationResult result,
  ) async {
    _showSuccessSnackBar(context, result.message);
    if (result.arguments != null) {
      context.push(result.route, extra: result.arguments);
    } else {
      context.push(result.route);
    }
  }

  static bool _isWalletAddress(String content) {
    final ethereumPattern = RegExp(r'^0x[a-fA-F0-9]{40}$');
    final bitcoinPattern =
        RegExp(r'^[13][a-km-zA-HJ-NP-Z1-9]{25,34}$|^bc1[a-z0-9]{39,59}$');
    return ethereumPattern.hasMatch(content) ||
        bitcoinPattern.hasMatch(content);
  }

  static bool _isSeedPhrase(String content) {
    final words = content.trim().split(RegExp(r'\s+'));
    return words.length >= 12 &&
        words.length <= 24 &&
        words.length % 3 == 0;
  }

  static bool _isPaymentURL(String content) {
    final paymentPatterns = [
      RegExp(r'^bitcoin:', caseSensitive: false),
      RegExp(r'^ethereum:', caseSensitive: false),
      RegExp(r'^litecoin:', caseSensitive: false),
      RegExp(r'^ripple:', caseSensitive: false),
      RegExp(r'^pay:', caseSensitive: false),
    ];
    return paymentPatterns.any((pattern) => pattern.hasMatch(content));
  }

  static bool _isTokenTransfer(String content) {
    return content.contains('transfer') ||
        content.contains('token') ||
        content.contains('contract');
  }

  static void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF16B369),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  static Future<void> handleQRScannerResult(
    BuildContext context,
    String scanResult,
    String returnScreen,
  ) async {
    if (scanResult.isNotEmpty) {
      await processQRScanResult(context, scanResult, returnScreen);
    } else {
      _showErrorSnackBar(context, 'No QR code content detected');
    }
  }
}

class NavigationResult {
  final String route;
  final Map<String, dynamic>? arguments;
  final String message;

  NavigationResult({
    required this.route,
    this.arguments,
    required this.message,
  });
}
