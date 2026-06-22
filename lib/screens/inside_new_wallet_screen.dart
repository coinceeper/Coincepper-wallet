import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import '../layout/bottom_menu_with_siri.dart';
import '../navigation/route_paths.dart';
import '../navigation/route_extras.dart';
import '../services/api_service.dart';
import '../services/service_provider.dart';
import '../services/wallet_state_manager.dart';
import '../services/secure_storage.dart';
import '../providers/app_provider.dart';
import '../services/device_registration_manager.dart';
import '../services/security_settings_manager.dart';
import 'passcode_screen.dart';
import 'dart:async'; // اضافه کردن برای Completer
import '../services/update_balance_helper.dart';
import '../navigation/wallet_session.dart';
import '../di/service_locator.dart';
import '../wallet/wallet_repository.dart';
import '../wallet/wallet_models.dart';

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
  late ApiService _apiService;
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
    _checkExistingWallet();
    _apiService = ServiceProvider.instance.apiService;
    _suggestNextWalletName();
  }

  /// Check if wallet exists and redirect to home if it does
  Future<void> _checkExistingWallet() async {
    try {
      final wallets = await SecureStorage.instance.getWalletsList();
      if (wallets.isNotEmpty) {
        print('🔄 Existing wallet found, redirecting to home...');
        if (mounted) {
          context.go(RoutePaths.home);
        }
      }
    } catch (e) {
      print('❌ Error checking existing wallet: $e');
    }
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
      print('🔧 DEBUG: Creating wallet locally via WalletRepository...');
      
      // Update progress
      setState(() {
        loadingMessage = 'Creating wallet on device...';
      });
      
      // Non-custodial: create wallet on-device via WalletRepository
      final created = await WalletRepository.instance.createWallet(
        walletName: newWalletName,
        activeTokens: ['BTC', 'ETH', 'TRX'],
      );
      print('🔧 DEBUG: Wallet created on-device: id=${created.walletId}');
      
      // Update progress
      setState(() {
        loadingMessage = 'Saving wallet securely...';
      });
      
      // WalletRepository._saveWalletRecord already saved to SecureStorage.
      // Set legacy SharedPreferences for compatibility with old UI code.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('UserID', created.walletId);
      await prefs.setString('WalletID', created.walletId);
      await prefs.setString('walletName', newWalletName);

      // Refresh AppProvider wallets list first
      if (mounted) {
        try {
          final appProvider = Provider.of<AppProvider>(context, listen: false);
          await appProvider.refreshWallets();

          // Update TokenProvider through AppProvider
          final tokenProvider = appProvider.tokenProvider;
          if (tokenProvider != null) {
            tokenProvider.updateUserId(created.walletId);
            print('✅ TokenProvider updated with userId: ${created.walletId}');
          } else {
            print('⚠️ TokenProvider is null');
          }
        } catch (e) {
          print('❌ Error accessing AppProvider: $e');
        }
      }

      // Update progress
      setState(() {
        loadingMessage = 'Finalizing wallet setup...';
      });
      
      print('🔄 Wallet generation successful, starting optimized background operations');
      
      // ⚡ OPTIMIZED: Move time-consuming operations to background
      
      // Start background operations (non-blocking)
      print('🚀 Starting background operations for better performance...');
      
      // 1. Background balance update
      UpdateBalanceHelper.updateBalanceInBackground(created.walletId);
      
      // 2. Background device registration (reduced delay)
      DeviceRegistrationManager.instance.registerDeviceInBackground();
      
      print('✅ Background operations initiated - wallet ready for immediate use!');

      if (mounted) {
        // بررسی فعال بودن passcode
        final isPasscodeEnabled = await _securityManager.isPasscodeEnabled();
        
        final session = ServiceLocator.get<WalletSession>();
        session.pendingWalletName = newWalletName;
        session.pendingUserId = created.walletId;

        if (isPasscodeEnabled) {
          // اگر passcode فعال است، به passcode screen برو
          context.push(
            RoutePaths.passcodeSetup,
            extra: {'walletName': newWalletName},
          );
        } else {
          // اگر passcode غیرفعال است، مستقیم به backup screen برو
          context.go(
            RoutePaths.backup,
            extra: BackupRouteExtra(
              walletName: newWalletName,
              userId: created.walletId,
              isPasscodeEnabled: false,
            ),
          );
        }
      }
    } catch (e) {
      print('🔧 DEBUG: Exception caught: $e');
      setState(() {
        if (e.toString().contains('server security restrictions') || 
            e.toString().contains('Cloudflare')) {
          errorMessage = _safeTranslate('server_security_restriction', 'Device registration failed due to server security restrictions. This may be caused by Cloudflare protection blocking mobile app requests. Please contact support or try again later.');
        } else if (e.toString().contains('timeout') || 
                   e.toString().contains('connection')) {
          errorMessage = _safeTranslate('connection_error', 'Error connecting to server. Please check your internet connection.');
        } else {
          errorMessage = '${_safeTranslate('error_creating_wallet', 'Error creating wallet')}: ${e.toString()}';
        }
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
            onPressed: () => context.pop(),
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