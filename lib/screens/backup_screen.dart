import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import '../navigation/route_paths.dart';
import '../navigation/wallet_onboarding_navigation.dart';
import '../navigation/wallet_session.dart';

class BackupScreen extends StatelessWidget {
  final String walletName;
  final String? userID;
  final String? walletID;
  final bool isPasscodeEnabled;
  final bool skipPhraseKey;

  const BackupScreen({
    super.key,
    required this.walletName,
    this.userID,
    this.walletID,
    this.isPasscodeEnabled = false,
    this.skipPhraseKey = false,
  });

  String _safeTranslate(BuildContext context, String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  void _continueToNext(BuildContext context) {
    goToPasscodeOrHomeAfterBackup(
      context: context,
      walletName: walletName,
      isPasscodeEnabled: isPasscodeEnabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  _safeTranslate(context, 'backup', 'Backup'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    _continueToNext(context);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0x1A13CE76),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Text(
                      _safeTranslate(context, 'skip', 'Skip'),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF16B369),
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),
            Center(
              child: Image.asset(
                'assets/images/backupimage.png',
                width: 220,
                height: 220,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.backup, size: 120, color: Color(0xFF16B369)),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              _safeTranslate(context, 'back_up_secret_phrase', 'Back up secret phrase'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _safeTranslate(context, 'protect_assets_backup', 'Protect your assets by backing up your seed phrase now.'),
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  final phrase = WalletSession.instance.pendingMnemonic ?? '';
                  context.push(
                    RoutePaths.phraseKey,
                    extra: {
                      'walletName': walletName,
                      'mnemonic': phrase,
                      'showCopy': true,
                      'isFromWalletCreation': false, // from backup → no continue arrow
                      'isPasscodeEnabled': isPasscodeEnabled,
                    },
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0x0D1FD092),
                  foregroundColor: const Color(0xFF16B369),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _safeTranslate(context, 'back_up_manually', 'Back up manually'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => _continueToNext(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005FEE),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _safeTranslate(context, 'continue', 'Continue'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
