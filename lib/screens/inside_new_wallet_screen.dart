import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import '../layout/bottom_menu_with_siri.dart';
import '../wallet/wallet_repository.dart';
import '../services/secure_storage.dart';
import '../providers/app_provider.dart';
import '../services/security_settings_manager.dart';
import '../navigation/wallet_onboarding_navigation.dart';

class InsideNewWalletScreen extends StatefulWidget {
  const InsideNewWalletScreen({super.key});

  @override
  State<InsideNewWalletScreen> createState() => _InsideNewWalletScreenState();
}

class _InsideNewWalletScreenState extends State<InsideNewWalletScreen> {
  bool isLoading = false;
  String errorMessage = '';
  bool showErrorModal = false;
  String loadingMessage = 'Generating wallet...'; // Progress feedback
  String walletName = 'New 1';
  final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    _suggestNextWalletName();
  }

  Future<void> _suggestNextWalletName() async {
    final wallets = await SecureStorage.instance.getWalletsList();
    int maxNum = 0;
    final regex = RegExp(r'^New wallet (\d+) 0?$');
    for (final w in wallets) {
      final name = w['walletName'] ?? w['name'] ?? '';
      final match = regex.firstMatch(name);
      if (match != null) {
        final num = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (num > maxNum) maxNum = num;
      }
    }
    setState(() {
      walletName = 'New wallet ${maxNum + 1}';
    });
  }

  Future<void> _generateWallet() async {
    print('🔧 DEBUG: _generateWallet called');
    
    setState(() {
      isLoading = true;
      errorMessage = '';
      showErrorModal = false;
      loadingMessage = 'Preparing wallet...';
    });

    print('🔧 DEBUG: Loading state set to true');

    // Always fetch the latest wallet list from SecureStorage
    final wallets = await SecureStorage.instance.getWalletsList();
    int maxNum = 0;
    final regex = RegExp(r'^New wallet (\d+) 0?$');
    for (final w in wallets) {
      final name = w['walletName'] ?? w['name'] ?? '';
      final match = regex.firstMatch(name);
      if (match != null) {
        final num = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (num > maxNum) maxNum = num;
      }
    }
    String newWalletName;
    // Ensure uniqueness in case of duplicate names
    do {
      newWalletName = 'New wallet ${++maxNum}';
    } while (wallets.any((w) => (w['walletName'] ?? w['name'] ?? '') == newWalletName));

    print('🔧 DEBUG: Generated wallet name: $newWalletName');

    if (newWalletName.trim().isEmpty) {
      setState(() {
        errorMessage = _safeTranslate('wallet_name_cannot_be_empty', 'Wallet name cannot be empty!');
        showErrorModal = true;
        isLoading = false;
      });
      return;
    }

    try {
      setState(() {
        loadingMessage = 'Generating wallet on device...';
      });
      final created = await WalletRepository.instance.createWallet(
        walletName: newWalletName,
        activeTokens: const ['BTC', 'ETH', 'TRX'],
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('UserID', created.walletId);
      await prefs.setString('WalletID', created.walletId);
      await SecureStorage.instance.saveWalletIdForWallet(
        newWalletName,
        created.walletId,
      );
      await prefs.setString('walletName', newWalletName);

      if (mounted) {
        try {
          final appProvider = Provider.of<AppProvider>(context, listen: false);
          await appProvider.refreshWallets();
          appProvider.tokenProvider?.updateUserId(created.walletId);
        } catch (e) {
          print('Error refreshing wallets: $e');
        }
      }

      if (mounted) {
        final isPasscodeEnabled = await _securityManager.isPasscodeEnabled();
        await goThroughOnboardingFlow(
          context: context,
          isFromWalletCreation: true,
          isPasscodeEnabled: isPasscodeEnabled,
          walletName: newWalletName,
          mnemonic: created.mnemonic,
          userId: created.walletId,
          walletId: created.walletId,
        );
      }
    } catch (e) {
      print('🔧 DEBUG: Exception caught: $e');
      setState(() {
        errorMessage = '${_safeTranslate('error_creating_wallet', 'Error creating wallet')}: ${e.toString()}';
        showErrorModal = true;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Check if wallets exist, if so, don't allow back navigation
        try {
          final wallets = await SecureStorage.instance.getWalletsList();
          if (wallets.isNotEmpty) {
            print('🚫 Back navigation blocked - wallet exists');
            return false;
          }
        } catch (e) {
          print('❌ Error checking wallets for back navigation: $e');
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(_safeTranslate('generate_new_wallet', 'Generate new wallet'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20)),
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0x0D16B369),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_safeTranslate('secret_phrase', 'Secret phrase'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                            const SizedBox(height: 10),
                            Text(_safeTranslate('generate_new_secret_phrase', 'Generate a new secret phrase.'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        height: 36,
                        child: OutlinedButton(
                          onPressed: isLoading ? null : () {
                            print('🔧 DEBUG: Generate button pressed');
                            _generateWallet();
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF16B369)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            backgroundColor: isLoading ? Colors.grey : Colors.transparent,
                            foregroundColor: isLoading ? Colors.grey[200] : const Color(0xFF16B369),
                            padding: EdgeInsets.zero,
                          ),
                          child: isLoading
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF16B369)))
                              : Text(_safeTranslate('generate', 'Generate'), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF16B369))),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLoading)
                  Padding(
                    padding: const EdgeInsets.only(top: 12.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          loadingMessage,
                          style: const TextStyle(
                            color: Color(0xFF16B369),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF16B369)),
                          backgroundColor: Color(0xFFE0E0E0),
                        ),
                      ],
                    ),
                  ),
                if (errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(errorMessage, style: const TextStyle(color: Colors.red, fontSize: 14)),
                  ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: const BottomMenuWithSiri(),
      ),
    );
  }
} 