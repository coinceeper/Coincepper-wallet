import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:my_flutter_app/services/api_models.dart';
import '../navigation/wallet_onboarding_navigation.dart';
import '../layout/bottom_menu_with_siri.dart';
import '../services/secure_storage.dart';
import '../wallet/wallet_repository.dart';
import '../wallet/local_import_adapter.dart';
import '../services/wallet_state_manager.dart';
import '../services/security_settings_manager.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

class InsideImportWalletScreen extends StatefulWidget {
  const InsideImportWalletScreen({super.key});

  @override
  State<InsideImportWalletScreen> createState() => _InsideImportWalletScreenState();
}

class _InsideImportWalletScreenState extends State<InsideImportWalletScreen> {
  final TextEditingController _secretPhraseController = TextEditingController();
  String errorMessage = '';
  bool isLoading = false;
  bool showErrorModal = false;

  // فرض: نام کیف پول جدید به صورت خودکار تولید می‌شود
  String walletName = 'Import 1';
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
    _suggestNextImportedWalletName();
  }

  Future<void> _suggestNextImportedWalletName() async {
    final wallets = await SecureStorage.instance.getWalletsList();
    int maxNum = 0;
    final regex = RegExp(r'^Imported wallet (\d+) 0?$');
    for (final w in wallets) {
      final name = w['walletName'] ?? w['name'] ?? '';
      final match = regex.firstMatch(name);
      if (match != null) {
        final num = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (num > maxNum) maxNum = num;
      }
    }
    setState(() {
      walletName = 'Imported wallet ${maxNum + 1}';
    });
  }

  @override
  void dispose() {
    _secretPhraseController.dispose();
    super.dispose();
  }

  bool validateSecretPhrase(String input) {
    final words = input.trim().split(RegExp(r'\s+'));
    return [12, 18, 24].contains(words.length);
  }

  /// Normalize mnemonic for comparison
  String _normalizeMnemonic(String mnemonic) {
    return mnemonic.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Check if mnemonic already exists in any wallet
  Future<bool> _checkMnemonicExists(String mnemonic) async {
    try {
      final wallets = await SecureStorage.instance.getWalletsList();
      
      for (final wallet in wallets) {
        final walletName = wallet['walletName'] ?? wallet['name'] ?? '';
        final userId = wallet['userID'] ?? wallet['userId'] ?? '';
        
        if (walletName.isNotEmpty) {
          // Try to get mnemonic for this wallet (check both with and without userId)
          String? existingMnemonic;
          
          if (userId.isNotEmpty) {
            existingMnemonic = await SecureStorage.instance.getMnemonic(walletName, userId);
          } else {
            // For wallets without userId, try with empty string
            existingMnemonic = await SecureStorage.instance.getMnemonic(walletName, '');
          }
          
          if (existingMnemonic != null && _normalizeMnemonic(existingMnemonic) == _normalizeMnemonic(mnemonic)) {
            print('🔍 Mnemonic already exists in wallet: $walletName (userId: $userId)');
            return true;
          }
        }
      }
      
      return false;
    } catch (e) {
      print('❌ Error checking mnemonic existence: $e');
      return false;
    }
  }

  void _restoreWallet() async {
    print('🔧 DEBUG: _restoreWallet called');
    
    final phrase = _secretPhraseController.text.trim();
    print('🔧 DEBUG: Phrase length: ${phrase.length}');
    
    if (!validateSecretPhrase(phrase)) {
      print('🔧 DEBUG: Invalid secret phrase');
      setState(() {
        errorMessage = _safeTranslate('secret_phrase_must_contain', 'Secret phrase must contain 12, 18, or 24 words.');
        showErrorModal = true;
      });
      return;
    }

    // Check if mnemonic already exists before making API call
    print('🔍 Checking if mnemonic already exists...');
    final mnemonicExists = await _checkMnemonicExists(phrase);
    
    if (mnemonicExists) {
      print('⚠️ Mnemonic already exists, showing error modal');
      setState(() {
        errorMessage = 'This wallet has already been imported. Please use a different seed phrase.';
        showErrorModal = true;
      });
      return;
    }
    
    print('✅ Mnemonic check passed, proceeding with import...');

    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    print('🔧 DEBUG: Loading state set to true');

    // Always fetch the latest wallet list from SecureStorage
    final wallets = await SecureStorage.instance.getWalletsList();
    int maxNum = 0;
    final regex = RegExp(r'^Imported wallet (\d+) 0?$');
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
      newWalletName = 'Imported wallet ${++maxNum}';
    } while (wallets.any((w) => (w['walletName'] ?? w['name'] ?? '') == newWalletName));

    print('🔧 DEBUG: Generated wallet name: $newWalletName');

    print('🚀 Starting wallet import process...');
    print('📝 Seed phrase length: ${phrase.length}');
    
    late final ImportWalletResponse response; // تعریف response خارج از try-catch
    
    try {
      final mnemonic = phrase; // Use phrase variable defined earlier
      
      final imported = await WalletRepository.instance.importWallet(
        walletName: newWalletName,
        mnemonic: mnemonic,
      );
      response = LocalImportAdapter.toImportResponse(imported);
      
      print('📥 API Response received:');
      print('   Status: ${response.status}');
      print('   Message: ${response.message}');
      print('   Has Data: ${response.data != null}');
      print('   Full Response: $response');
      print('   Response Type: ${response.runtimeType}');
      
      // Log detailed server response
      print('🌐 SERVER RESPONSE DETAILS:');
      print('   📊 Status: ${response.status}');
      print('   💬 Message: ${response.message}');
      print('   📦 Has Data: ${response.data != null}');
      
      if (response.data != null) {
        print('   👤 UserID from server: ${response.data!.userID}');
        print('   🆔 WalletID from server: ${response.data!.walletID}');
        print('   📝 Mnemonic from server: ${response.data!.mnemonic != null ? "RECEIVED" : "NOT RECEIVED"}');
        print('   🏠 Addresses count: ${response.data!.addresses.length}');
        
        // Log addresses received from server
        print('   🏠 ADDRESSES FROM SERVER:');
        for (int i = 0; i < response.data!.addresses.length; i++) {
          final address = response.data!.addresses[i];
          print('     ${i + 1}. ${address.blockchainName}: ${address.publicAddress}');
        }
      }
      
      // Save response to a file for debugging
      try {
        final responseJson = response.toJson();
        print('💾 Response JSON: $responseJson');
      } catch (e) {
        print('❌ Error converting response to JSON: $e');
      }
      
      if (response.data != null) {
        print('📊 Wallet Data Details:');
        print('   UserID: ${response.data!.userID}');
        print('   WalletID: ${response.data!.walletID}');
        print('   Has Mnemonic: ${response.data!.mnemonic != null}');
        print('   Mnemonic Length: ${response.data!.mnemonic?.length ?? 0}');
      }
      
      if (response.status == 'success' && response.data != null) {
        final walletData = response.data!;
        
        print('✅ SUCCESS PATH ENTERED - Saving wallet info...');
        print('   UserID to save: ${walletData.userID}');
        print('   WalletID to save: ${walletData.walletID}');
        print('   Wallet name: $newWalletName');
        
        // Save wallet information securely
        await WalletStateManager.instance.saveWalletInfo(
          walletName: newWalletName,
          userId: walletData.userID ?? '',
          walletId: walletData.walletID ?? '',
          mnemonic: walletData.mnemonic ?? mnemonic, // مطمئن می‌شویم که mnemonic ذخیره شود
          activeTokens: ['BTC', 'ETH', 'TRX'], // ✅ Default active tokens for imported wallet
        );
        if (walletData.walletID != null && walletData.walletID!.isNotEmpty) {
          await SecureStorage.instance.saveWalletIdForWallet(newWalletName, walletData.walletID!);
        }
        
        // **اطمینان از ذخیره mnemonic**: در صورت عدم ذخیره، مستقیماً ذخیره می‌کنیم
        if (walletData.userID != null && (walletData.mnemonic != null || mnemonic.isNotEmpty)) {
          final mnemonicToSave = walletData.mnemonic ?? mnemonic;
          await SecureStorage.instance.saveMnemonic(newWalletName, walletData.userID!, mnemonicToSave);
          print('✅ Mnemonic saved in SecureStorage with key: Mnemonic_${walletData.userID!}_$newWalletName');
        }
        final debugWallets = await SecureStorage.instance.getWalletsList();
        print('Wallets after add: $debugWallets');
        
        print('💾 Wallet info saved successfully');

        // Refresh AppProvider wallets list
        final appProvider = Provider.of<AppProvider>(context, listen: false);
        await appProvider.refreshWallets();
        
        // Get user balance for imported wallet
        print('💰 Getting user balance for imported wallet...');
        try {
          // توضیح: در Kotlin این کار انجام نمی‌شود، فقط wallet import می‌شود
          // موجودی‌ها باید توسط TokenProvider در Home screen بارگذاری شوند
          print('ℹ️ Skipping balance fetch - will be handled by TokenProvider in Home screen');
          
        } catch (e) {
          print('⚠️ Error getting balance (continuing anyway): $e');
          // Continue with import process even if balance retrieval fails
        }
        
        print('🔄 Wallet import successful');
        print('💫 ABOUT TO START NAVIGATION PROCESS...');
        
        // Show success message with server data
        if (mounted) {
          // Remove success message - wallet imported silently
        }
        
        // Update app provider with new wallet info
        if (mounted) {
          await appProvider.setCurrentWallet(newWalletName);
          
          // بروزرسانی TokenProvider با userId جدید through AppProvider
          final tokenProvider = appProvider.tokenProvider;
          if (tokenProvider != null) {
            final userIdToUpdate = walletData.userID ?? '';
            print('🔄 Updating TokenProvider with userId: $userIdToUpdate');
            tokenProvider.updateUserId(userIdToUpdate);
          } else {
            print('⚠️ TokenProvider is null in AppProvider');
          }
        }
        
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
        
        if (mounted) {
          print('🎯 Navigating to passcode screen...');
          // بررسی فعال بودن passcode
          final isPasscodeEnabled = await _securityManager.isPasscodeEnabled();
          print('🔐 Passcode enabled: $isPasscodeEnabled');
          
          await goThroughOnboardingFlow(
            context: context,
            isFromWalletCreation: false,
            isPasscodeEnabled: isPasscodeEnabled,
            walletName: newWalletName,
            mnemonic: walletData.mnemonic ?? mnemonic,
            userId: walletData.userID ?? '',
            walletId: walletData.walletID ?? '',
          );
        }
      } else if (response.status != 'success') {
        print('❌ API returned non-success status');
        print('   Status: ${response.status}');
        print('   Message: ${response.message}');
        // فقط اگر واقعا خطا بود
        throw Exception(response.message ?? 'Import failed');
      } else {
        print('⚠️ Response status is success but no data received');
        print('   Status: ${response.status}');
        print('   Has Data: ${response.data != null}');
      }
    } catch (e) {
      final errorMsg = e.toString();
      print('💥 Exception caught: $errorMsg');
      
      if (errorMsg.contains('successfully imported')) {
        print('🔄 Fallback path - Wallet imported but no data received');
        final mnemonic = phrase; // Use phrase variable defined earlier
        
        // بررسی اینکه آیا response تعریف شده و دارای data است یا نه
        try {
          if (response.data != null) {
            print('✅ Response data exists in fallback, using actual UserID');
            final walletData = response.data!;
            
            // Save wallet information securely with actual data
            await WalletStateManager.instance.saveWalletInfo(
              walletName: newWalletName,
              userId: walletData.userID ?? '',
              walletId: walletData.walletID ?? '',
              mnemonic: walletData.mnemonic ?? mnemonic,
              activeTokens: ['BTC', 'ETH', 'TRX'], // ✅ Default active tokens for imported wallet
            );
            
            print('✅ Fallback: Saved wallet with actual UserID: ${walletData.userID}');
            
            // اطمینان از ذخیره mnemonic با UserID واقعی
            if (walletData.userID != null && (walletData.mnemonic != null || mnemonic.isNotEmpty)) {
              final mnemonicToSave = walletData.mnemonic ?? mnemonic;
              await SecureStorage.instance.saveMnemonic(newWalletName, walletData.userID!, mnemonicToSave);
              print('✅ Mnemonic saved in SecureStorage (fallback) with key: Mnemonic_${walletData.userID!}_$newWalletName');
            }
          } else {
            print('⚠️ No response data in fallback, using empty UserID');
            
            await WalletStateManager.instance.saveWalletInfo(
              walletName: newWalletName,
              userId: '',
              walletId: '',
              mnemonic: mnemonic,
              activeTokens: ['BTC', 'ETH', 'TRX'], // ✅ Default active tokens for imported wallet
            );
            
            // اطمینان از ذخیره mnemonic در fallback path
            if (mnemonic.isNotEmpty) {
              await SecureStorage.instance.saveMnemonic(newWalletName, '', mnemonic);
              print('✅ Mnemonic saved in SecureStorage (fallback) with key: Mnemonic__$newWalletName');
            }
          }
        } catch (responseError) {
          print('⚠️ Error accessing response in fallback: $responseError');
          print('⚠️ Using empty UserID as fallback');
          
          await WalletStateManager.instance.saveWalletInfo(
            walletName: newWalletName,
            userId: '',
            walletId: '',
            mnemonic: mnemonic,
            activeTokens: ['BTC', 'ETH', 'TRX'], // ✅ Default active tokens for imported wallet
          );
          
          // اطمینان از ذخیره mnemonic در fallback path
          if (mnemonic.isNotEmpty) {
            await SecureStorage.instance.saveMnemonic(newWalletName, '', mnemonic);
            print('✅ Mnemonic saved in SecureStorage (fallback) with key: Mnemonic__$newWalletName');
          }
        }
        if (mounted) {
          final fallbackAppProvider = Provider.of<AppProvider>(context, listen: false);
          await fallbackAppProvider.setCurrentWallet(newWalletName);
          
          // بروزرسانی TokenProvider با userId صحیح through AppProvider
          final tokenProvider = fallbackAppProvider.tokenProvider;
          if (tokenProvider != null) {
            try {
              if (response.data != null) {
                final userIdToUpdate = response.data!.userID ?? '';
                print('🔄 Updating TokenProvider with userId (fallback): $userIdToUpdate');
                tokenProvider.updateUserId(userIdToUpdate);
              }
            } catch (responseError) {
              print('⚠️ Error accessing response for TokenProvider update: $responseError');
            }
          } else {
            print('⚠️ TokenProvider is null in AppProvider (fallback)');
          }
        }
        
        if (mounted) {
          setState(() {
            isLoading = false;
            showErrorModal = false;
          });
        }
        
        if (mounted) {
          print('🎯 Navigating after import (fallback path)...');
          String userIdForBackup = '';
          String walletIdForBackup = '';
          String mnemonicForBackup = phrase;
          try {
            userIdForBackup = response.data?.userID ?? '';
            walletIdForBackup = response.data?.walletID ?? '';
            mnemonicForBackup = response.data?.mnemonic ?? phrase;
          } catch (responseError) {
            print('⚠️ Error accessing response for backup navigation: $responseError');
          }
          final isPasscodeEnabled =
              await _securityManager.isPasscodeEnabled();
          await goThroughOnboardingFlow(
            context: context,
            isFromWalletCreation: false,
            isPasscodeEnabled: isPasscodeEnabled,
            walletName: newWalletName,
            mnemonic: mnemonicForBackup,
            userId: userIdForBackup,
            walletId: walletIdForBackup,
          );
        }
      } else {
        print('❌ Error path - Showing error modal');
        if (mounted) {
          setState(() {
            isLoading = false;
            showErrorModal = true;
            errorMessage = '${_safeTranslate('error_importing_wallet', 'Error importing wallet')}: ${e.toString()}';
          });
        }
      }
    }
  }

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null) {
      setState(() {
        _secretPhraseController.text = data.text!.trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isValid = validateSecretPhrase(_secretPhraseController.text);
    final scaffold = WillPopScope(
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
          title: Text(_safeTranslate('multi_coin_wallet', 'Multi-coin wallet'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
          iconTheme: const IconThemeData(color: Colors.black),
        ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Secret phrase label
              Text(_safeTranslate('secret_phrase', 'Secret phrase'), style: const TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 8),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  TextField(
                    controller: _secretPhraseController,
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: _safeTranslate('enter_secret_phrase', 'Enter your secret phrase'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF16B369)),
                      ),
                    ),
                    style: const TextStyle(fontSize: 16),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextButton(
                    onPressed: _pasteFromClipboard,
                    child: Text(_safeTranslate('paste', 'Paste'), style: const TextStyle(color: Color(0xFF16B369), fontSize: 14)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (errorMessage.isNotEmpty)
                Text(errorMessage, style: const TextStyle(color: Colors.red, fontSize: 14)),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: isValid && !isLoading ? () {
                    print('🔧 DEBUG: Restore wallet button pressed');
                    _restoreWallet();
                  } : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isValid ? const Color(0xFF16B369) : Colors.grey[300],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    elevation: 0,
                  ),
                  child: isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(_safeTranslate('restore_wallet', 'Restore wallet'), style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: () {},
                  child: Text(_safeTranslate('what_is_secret_phrase', 'What is a secret phrase?'), style: const TextStyle(fontSize: 14, color: Color(0xFF16B369))),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
              ),
        bottomNavigationBar: const BottomMenuWithSiri(),
      ),
    );

    return showErrorModal
        ? Stack(
            children: [
              scaffold,
              _ErrorModal(
                message: errorMessage,
                onDismiss: () => setState(() => showErrorModal = false),
              ),
            ],
          )
        : scaffold;
  }
}

class _ErrorModal extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorModal({required this.message, required this.onDismiss});

  // Safe translate method with fallback
  String _safeTranslate(BuildContext context, String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.black.withOpacity(0.6),
        child: Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.8,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error, color: Color(0xFFFF1961), size: 48),
                const SizedBox(height: 16),
                Text(
                  _safeTranslate(context, 'error', 'Error'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: onDismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF1961),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                    child: Text(_safeTranslate(context, 'ok', 'OK'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 