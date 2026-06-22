import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';

class PhraseKeyScreen extends StatefulWidget {
  final String walletName;
  final bool showCopy;
  final String mnemonic;
  final bool isFromWalletCreation; // پارامتر جدید برای تشخیص مسیر
  
  const PhraseKeyScreen({
    super.key, 
    required this.walletName, 
    required this.mnemonic, 
    this.showCopy = false,
    this.isFromWalletCreation = false, // default false برای مسیر manual
  });

  @override
  State<PhraseKeyScreen> createState() => _PhraseKeyScreenState();
}

class _PhraseKeyScreenState extends State<PhraseKeyScreen> {
  bool copied = false;

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mnemonicWords = widget.mnemonic.trim().split(RegExp(r'\s+'));
    
    // تصمیم‌گیری برای نمایش دکمه Copy بر اساس مسیر
    final shouldShowCopyButton = widget.isFromWalletCreation || widget.showCopy;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.isFromWalletCreation 
            ? _safeTranslate('secret_recovery_phrase', 'Secret Recovery Phrase')
            : _safeTranslate('mnemonic_for_wallet', 'Mnemonic for {walletName}').replaceAll('{walletName}', widget.walletName), 
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // اضافه کردن متن توضیحی برای مسیر ایجاد کیف پول
            if (widget.isFromWalletCreation) ...[
              Text(
                _safeTranslate('write_down_secret_recovery_phrase', "Write down your secret recovery phrase and keep it in a safe place. You'll need it to recover your wallet."),
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Show mnemonic words in two columns
                    for (int i = 0; i < mnemonicWords.length; i += 2)
                      Row(
                        children: [
                          Expanded(
                            child: _PhraseCard(number: i + 1, word: mnemonicWords[i]),
                          ),
                          if (i + 1 < mnemonicWords.length)
                            const SizedBox(width: 8),
                          if (i + 1 < mnemonicWords.length)
                            Expanded(
                              child: _PhraseCard(number: i + 2, word: mnemonicWords[i + 1]),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            // نمایش دکمه Copy فقط در مسیر ایجاد کیف پول
            if (shouldShowCopyButton)
              Padding(
                padding: const EdgeInsets.only(top: 15.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: widget.mnemonic));
                      setState(() { copied = true; });
                      Future.delayed(const Duration(seconds: 2), () => setState(() => copied = false));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF08C495),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      elevation: 0,
                    ),
                    child: Text(
                      copied 
                        ? _safeTranslate('copied', 'Copied!') 
                        : _safeTranslate('copy_mnemonic', 'Copy Mnemonic'), 
                      style: const TextStyle(fontWeight: FontWeight.bold)
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset('assets/images/danger.png', width: 20, height: 20, color: const Color(0xFFFFAA00)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.isFromWalletCreation 
                        ? _safeTranslate('never_share_secret_phrase', 'Never share your secret phrase with anyone, and store it securely!')
                        : _safeTranslate('wallet_secret_recovery_phrase_warning', "This is your wallet's secret recovery phrase. Keep it safe and never share it with anyone!"),
                      style: const TextStyle(fontSize: 12, color: Colors.black),
                    ),
                  ),
                  if (widget.isFromWalletCreation)
                    IconButton(
                      icon: Image.asset('assets/images/rightarrow.png', width: 20, height: 20),
                      onPressed: () {
                        // Navigate to next step in wallet creation
                        Navigator.pushReplacementNamed(context, '/home');
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhraseCard extends StatelessWidget {
  final int number;
  final String word;
  const _PhraseCard({required this.number, required this.word});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text('$number. $word', style: const TextStyle(fontSize: 12, color: Colors.black)),
      ),
    );
  }
} 