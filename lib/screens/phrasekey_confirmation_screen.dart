import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import '../navigation/passcode_navigation.dart';
import '../navigation/route_paths.dart';
import '../navigation/wallet_onboarding_navigation.dart';
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

  Future<void> _navigateToBackupFlow() async {
    if (!mounted) return;
    final isPasscodeEnabled = await _securityManager.isPasscodeEnabled();
    if (!mounted) return;
    // Navigate to Backup screen which will then flow to Passcode → Home
    goToBackupAfterPhraseConfirm(
      context: context,
      walletName: widget.walletName,
      isPasscodeEnabled: isPasscodeEnabled,
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
                          await _navigateToBackupFlow();
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