import 'package:flutter/material.dart';
import '../navigation/app_navigation.dart';
import '../navigation/onboarding_wallet_guard_scope.dart';
import '../navigation/route_paths.dart';
import 'package:easy_localization/easy_localization.dart';
import 'dart:convert';

class ImportCreateScreen extends StatefulWidget {
  const ImportCreateScreen({super.key});

  @override
  State<ImportCreateScreen> createState() => _ImportCreateScreenState();
}

class _ImportCreateScreenState extends State<ImportCreateScreen> {
  int _logoTapCount = 0;

  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  void _onLogoTap() {
    setState(() {
      _logoTapCount++;
    });
    if (_logoTapCount == 24) {
      _logoTapCount = 0;
      _showCreatorModal();
    }
  }

  void _showCreatorModal() {}

  @override
  Widget build(BuildContext context) {
    return OnboardingWalletGuardScope(
      allowPopWhenNoWallets: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(0.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Logo
                GestureDetector(
                  onTap: _onLogoTap,
                  child: Image.asset(
                    'assets/logo-512.png',
                    width: 250,
                    height: 250,
                    fit: BoxFit.contain,
                  ),
                ),
                
                // App Title (static)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _safeTranslate('coinceeper', 'COINCEEPER'),
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF03ac0e),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Description Text
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.8,
                  child: Text(
                    _safeTranslate('import_existing_wallet_description', 'Import your existing wallet or create a new one to get started'),
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Import Wallet Button
                Container(
                  width: double.infinity,
                  height: 50,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF03ac0e), width: 1),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      AppNavigation.pushNamed(context, RoutePaths.importWallet);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF03ac0e),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _safeTranslate('import_wallet', 'Import Wallet'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Create New Wallet Button
                Container(
                  width: double.infinity,
                  height: 50,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  child: ElevatedButton(
                    onPressed: () {
                      AppNavigation.pushNamed(context, RoutePaths.createNewWallet);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF37b3f7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _safeTranslate('create_new_wallet', 'Create New Wallet'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AnimatedGradientModal extends StatefulWidget {
  const AnimatedGradientModal({super.key});

  @override
  State<AnimatedGradientModal> createState() => _AnimatedGradientModalState();
}

class _AnimatedGradientModalState extends State<AnimatedGradientModal> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _getDecodedContent() {
    // Encrypted content split into multiple parts
    final List<String> encryptedParts = [
      '8J+UjCBTb2Z0d2FyZSBPd25lcnNoaXAgYW5kIERlY2xhcmF0aW9uCkksIE1vaGFtbWFkIE5hemFybmVqYWQsIGhlcmVieSBkZWNsYXJlIGFuZCBhZmZpcm0gdGhhdCBhbGwgc3RhZ2VzIG9mIGRlc2lnbiwgZGV2ZWxvcG1lbnQsIGFuZCBpbXBsZW1lbnRhdGlvbiBvZiB0aGUgc29mdHdhcmUgcHJvamVjdCB0aXRsZWQgTGF4Y2UsIGluY2x1ZGluZyB0aGUgZm9sbG93aW5nIGNvbXBvbmVudHM6Cg==',
      'RnVsbCBkZXNpZ24gYW5kIGltcGxlbWVudGF0aW9uIG9mIHRoZSBhcHBsaWNhdGlvbiAoaW5jbHVkaW5nIERFWCwgd2FsbGV0LCBhbmQgb3RoZXIgcmVsYXRlZCBtb2R1bGVzKQoKVVkgKFVzZXIgSW50ZXJmYWNlKSBhbmQgVVggKFVzZXIgRXhwZXJpZW5jZSkgZGVzaWduIGZvciBib3RoIG1vYmlsZSBhbmQgd2ViIHZlcnNpb25zCgpTZXJ2ZXItc2lkZSBjb25maWd1cmF0aW9uLCBkZXBsb3ltZW50LCBhbmQgaW5mcmFzdHJ1Y3R1cmUgc2V0dXAgKEJhY2stRW5kKQoKU3VibWlzc2lvbiwgdXBsb2FkaW5nLCBhbmQgcHVibGlzaGluZyBvZiB0aGUgYXBwbGljYXRpb24gb24gb2ZmaWNpYWwgcGxhdGZvcm1zIGluY2x1ZGluZyBHb29nbGUgUGxheSBhbmQgQXBwbGUgQXBwIFN0b3JlCg==',
      'aGF2ZSBiZWVuIHNvbGVseSBhbmQgZXhjbHVzaXZlbHkgY2FycmllZCBvdXQgYnkgbXlzZWxmLCB3aXRob3V0IHRoZSBpbnZvbHZlbWVudCBvciBjb250cmlidXRpb24gb2YgYW55IG90aGVyIHBlcnNvbiBvciBlbnRpdHkgaW4gdGhlIHRlY2huaWNhbCBvciBvcGVyYXRpb25hbCBhc3BlY3RzIG9mIHRoZSBtZW50aW9uZWQgcHJvamVjdC4KCkEgZGVjbGFyYXRpb24gaXMgaXNzdWVkIGFzIGV2aWRlbmNlIG9mIG15IGludGVsbGVjdHVhbCBhbmQgbGVnYWwgb3duZXJzaGlwIG92ZXIgdGhlIHNvdXJjZSBjb2RlLCBkZXNpZ25zLCBhbmQgZGV2ZWxvcG1lbnQgcHJvY2Vzc2VzIGFuZCBtYXkgYmUgcHJlc2VudGVkIGJlZm9yZSByZWxldmFudCBsZWdhbCBhdXRob3JpdGllcyBvciBjb3VydHMgYXMgdmFsaWQgcHJvb2YuCg==',
      'RnVsbCBOYW1lOiBNb2hhbW1hZCBOYXphcm5lamFkCklyYW5pYW4gTmF0aW9uYWwgSUQ6IDI2NDAxMjcxMzYKVHVya2lzaCBOYXRpb25hbCBJRDogOTk5MDYyOTc2NTIKRW1haWwgQWRkcmVzc2VzOgoKbmV0Y29pbmNhcGl0YWwuY29tcGFueUBnbWFpbC5jb20KCm1vaGFtbWFkLm5hemFybmV6aGFkQGdtYWlsLmNvbQpEYXRlOiBKdWx5IDYsIDIwMjUKU2lnbmF0dXJlOiBbVG8gYmUgcHJvdmlkZWQgaWYgcHJpbnRlZCBvciByZXF1aXJlZF0='
    ];
    
    // Decode and combine all parts
    String decodedContent = '';
    for (String part in encryptedParts) {
      try {
        decodedContent += utf8.decode(base64.decode(part));
      } catch (e) {
        // Fallback in case of decoding error
        decodedContent += 'Error decoding content';
      }
    }
    
    return decodedContent;
  }

  List<Color> _getDecodedColors() {
    final List<String> encryptedColors = [
      'AP8Lq5s=', // 0xFF0BAB9B
      'AP85tvY=', // 0xFF39b6fb
      'AP8Ws2k=', // 0xFF16B369
      'AP8EJDw=', // 0xFF04243C
      'AP8Lq5s=', // 0xFF0BAB9B
      'AP//s0c=', // 0xFFffb347
      'AP//XmI=', // 0xFFff5e62
    ];
    return encryptedColors.map((b64) {
      final bytes = base64.decode(b64);
      final value = bytes.fold(0, (prev, elem) => (prev << 8) + elem);
      return Color(value);
    }).toList();
  }

  String _getDecodedImagePath() {
    // Encrypted image path
    const String encryptedPath = 'YXNzZXRzL2ltYWdlcy8yMDI1LTA3LTA3XzEyLjQ3LjM4LXJlbW92ZWJnLXByZXZpZXcucG5n';
    try {
      return utf8.decode(base64.decode(encryptedPath));
    } catch (e) {
      return 'assets/images/default.png';
    }
  }

  IconData _getDecodedIconData() {
    // Encrypted icon name
    const String encryptedIcon = 'Y2VsZWJyYXRpb24=';
    try {
      String iconName = utf8.decode(base64.decode(encryptedIcon));
      switch (iconName) {
        case 'celebration':
          return Icons.celebration;
        case 'star':
          return Icons.star;
        case 'favorite':
          return Icons.favorite;
        default:
          return Icons.celebration;
      }
    } catch (e) {
      return Icons.celebration;
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.9;
    return Container(
      height: height,
      width: double.infinity,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              gradient: LinearGradient(
                colors: _getDecodedColors(),
                begin: Alignment(-1 + 2 * _controller.value, -1),
                end: Alignment(1 - 2 * _controller.value, 1),
                stops: const [0.0, 0.18, 0.35, 0.55, 0.7, 0.85, 1.0],
                tileMode: TileMode.mirror,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 24,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: child,
          );
        },
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 32),
                Icon(_getDecodedIconData(), color: Colors.white, size: 48),
                const SizedBox(height: 24),
                Text(
                  _getDecodedContent(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    height: 1.5,
                    shadows: [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0,2))],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Image.asset(
                  _getDecodedImagePath(),
                  width: 220,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 