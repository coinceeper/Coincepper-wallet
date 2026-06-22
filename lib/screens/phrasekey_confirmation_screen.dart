import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'passcode_screen.dart';
import 'phrasekey_screen.dart';
import '../services/secure_storage.dart';
import '../services/security_settings_manager.dart';

class PhraseKeyConfirmationScreen extends StatefulWidget {
  final String walletName;
  final bool isFromWalletCreation; // پارامتر جدید برای تشخیص مسیر
  
  const PhraseKeyConfirmationScreen({
    super.key, 
    required this.walletName,
    this.isFromWalletCreation = false, // default false برای مسیر manual
  });

  @override
  State<PhraseKeyConfirmationScreen> createState() => _PhraseKeyConfirmationScreenState();
}

class _PhraseKeyConfirmationScreenState extends State<PhraseKeyConfirmationScreen> {
  bool checkbox1 = false;
  bool checkbox2 = false;
  bool checkbox3 = false;

  final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  // تابع برای هدایت به صفحه بعدی
  void _navigateToNextScreen() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => _PhraseKeyScreenWithMnemonic(
          walletName: widget.walletName,
          isFromWalletCreation: widget.isFromWalletCreation,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allChecked = checkbox1 && checkbox2 && checkbox3;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          widget.isFromWalletCreation ? _safeTranslate('generate_new_wallet', 'Generate new wallet') : _safeTranslate('backup_wallet', 'Backup Wallet'),
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Image.asset(
                'assets/images/shild.png',
                width: 180,
                height: 180,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              _CheckBoxWithText(
                isChecked: checkbox1,
                text: _safeTranslate('coinceeper_wallet_no_copy', 'Coinceeper Wallet does not keep a copy of your secret phrase.'),
                onChanged: (v) => setState(() => checkbox1 = v),
              ),
              _CheckBoxWithText(
                isChecked: checkbox2,
                text: _safeTranslate('saving_digitally_not_recommended', 'Saving this digitally in plain text is NOT recommended.'),
                onChanged: (v) => setState(() => checkbox2 = v),
              ),
              _CheckBoxWithText(
                isChecked: checkbox3,
                text: _safeTranslate('write_down_secret_phrase', 'Write down your secret phrase and store it in a secure offline location.'),
                onChanged: (v) => setState(() => checkbox3 = v),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: allChecked
                      ? () async {
                          // بررسی فعال بودن passcode
                          final isPasscodeEnabled = await _securityManager.isPasscodeEnabled();
                          
                          if (isPasscodeEnabled) {
                            // اگر passcode فعال است، ابتدا احراز هویت کن
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PasscodeScreen(
                                  title: _safeTranslate('enter_passcode', 'Enter Passcode'),
                                  walletName: widget.walletName,
                                  onSuccess: () {
                                    // بعد از تایید passcode، به phrasekey برو
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => _PhraseKeyScreenWithMnemonic(
                                          walletName: widget.walletName,
                                          isFromWalletCreation: widget.isFromWalletCreation,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          } else {
                            // اگر passcode غیرفعال است، مستقیم به phrasekey برو
                            _navigateToNextScreen();
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: allChecked ? const Color(0xFF005FEE) : Colors.grey,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(_safeTranslate('continue', 'Continue'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
            ),
    );
  }
}

/// کلاس کمکی برای بارگذاری mnemonic و نمایش آن
class _PhraseKeyScreenWithMnemonic extends StatefulWidget {
  final String walletName;
  final bool isFromWalletCreation;
  
  const _PhraseKeyScreenWithMnemonic({
    required this.walletName,
    this.isFromWalletCreation = false,
  });

  @override
  State<_PhraseKeyScreenWithMnemonic> createState() => _PhraseKeyScreenWithMnemonicState();
}

class _PhraseKeyScreenWithMnemonicState extends State<_PhraseKeyScreenWithMnemonic> {
  String? mnemonic;
  bool isLoading = true;
  String? errorMessage;

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
    _loadMnemonic();
  }

  Future<void> _loadMnemonic() async {
    try {
      // **اصلاح مهم**: استفاده مستقیم از کیف پول مورد نظر کاربر (نه selected wallet)
      final targetWalletName = widget.walletName;
      final targetUserId = await SecureStorage.instance.getUserIdForWallet(targetWalletName);
      
      print('🔍 Loading mnemonic for target wallet: $targetWalletName with userId: $targetUserId');

      if (targetUserId != null && targetWalletName.isNotEmpty) {
        final mnemonicData = await SecureStorage.instance.getMnemonic(targetWalletName, targetUserId);
        
        if (mnemonicData != null && mnemonicData.isNotEmpty) {
          setState(() {
            mnemonic = mnemonicData;
            isLoading = false;
          });
          print('💰 Successfully loaded mnemonic for wallet: $targetWalletName');
        } else {
          setState(() {
            errorMessage = _safeTranslate('mnemonic_not_found_for_wallet', 'Mnemonic not found for wallet: $targetWalletName');
            isLoading = false;
          });
          print('❌ Mnemonic not found for wallet: $targetWalletName with userId: $targetUserId');
        }
      } else {
        setState(() {
          errorMessage = _safeTranslate('mnemonic_not_found_for_wallet', 'User ID not found for wallet: $targetWalletName');
          isLoading = false;
        });
        print('❌ User ID not found for wallet: $targetWalletName');
      }
    } catch (e) {
      setState(() {
        errorMessage = '${_safeTranslate('error', 'Error loading mnemonic')}: $e';
        isLoading = false;
      });
      print('❌ Error loading mnemonic: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF08C495),
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          title: Text(_safeTranslate('error', 'Error'), style: const TextStyle(color: Colors.black)),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                errorMessage!,
                style: const TextStyle(fontSize: 16, color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_safeTranslate('go_back', 'Go Back')),
              ),
            ],
          ),
        ),
      );
    }

    if (mnemonic == null || mnemonic!.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          title: Text(_safeTranslate('mnemonic_not_found', 'Mnemonic Not Found'), style: const TextStyle(color: Colors.black)),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_outlined, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              Text(
                _safeTranslate('mnemonic_not_found_for_wallet', 'Mnemonic not found for the selected wallet'),
                style: const TextStyle(fontSize: 16, color: Colors.orange),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // نمایش صفحه phrasekey با mnemonic دریافت شده
    return PhraseKeyScreen(
      walletName: widget.walletName,
      mnemonic: mnemonic!,
      showCopy: true, // اجازه کپی کردن را بده
      isFromWalletCreation: widget.isFromWalletCreation, // این از مسیر ایجاد کیف پول جدید است
    );
  }
}

class _CheckBoxWithText extends StatelessWidget {
  final bool isChecked;
  final String text;
  final ValueChanged<bool> onChanged;
  const _CheckBoxWithText({required this.isChecked, required this.text, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!isChecked),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: isChecked ? const Color(0x0D16B369) : const Color(0x43CBCBCB),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isChecked ? const Color(0xFF1CC89F) : Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: isChecked
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 14, color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 