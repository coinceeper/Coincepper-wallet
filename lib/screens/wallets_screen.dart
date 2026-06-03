import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../navigation/app_navigation.dart';
import '../navigation/route_paths.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import '../layout/main_layout.dart';
import 'wallet_screen.dart';
import 'inside_import_wallet_screen.dart';
import 'inside_new_wallet_screen.dart';
import '../services/secure_storage.dart';
import '../providers/app_provider.dart';

class Wallet {
  final String walletName;
  final String userId;
  final bool isBackedUp;

  Wallet({
    required this.walletName,
    required this.userId,
    this.isBackedUp = false,
  });
}

class WalletsScreen extends StatefulWidget {
  const WalletsScreen({super.key});

  @override
  State<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends State<WalletsScreen> {
  List<Wallet> wallets = [];
  String selectedWalletName = '';

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
    _loadWallets();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh wallets list when screen comes into focus
    _loadWallets();
  }

  void _loadWallets() async {
    // Load wallets from SecureStorage
    final storedWallets = await SecureStorage.instance.getWalletsList();
    print('Wallets loaded: $storedWallets');
    final selected = await SecureStorage.instance.getSelectedWallet();
    setState(() {
      wallets = storedWallets.map((w) => Wallet(
        walletName: w['walletName'] ?? '',
        userId: w['userID'] ?? '',
        isBackedUp: false, // You can update this if you track backup status
      )).toList();
      selectedWalletName = selected ?? (wallets.isNotEmpty ? wallets.first.walletName : '');
    });
    
    // Also refresh AppProvider wallets list
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    await appProvider.refreshWallets();
  }

  void _saveSelectedWallet(String walletName, String userId) async {
    // Save selected wallet to SecureStorage (مطابق با Kotlin)
    await SecureStorage.instance.saveSelectedWallet(walletName, userId);
    
    // Update AppProvider
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    await appProvider.selectWallet(walletName);
    
    setState(() {
      selectedWalletName = walletName;
    });
    
    print('💰 Selected wallet: $walletName with userId: $userId');
  }

  void _showWalletOptions(String walletName) {
    // Remove modal bottom sheet - wallet options removed
  }

  void _showAddWalletModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _AddWalletModalContent(
        onCreateNewWallet: _onCreateNewWallet,
        onAddExistingWallet: _onAddExistingWallet,
      ),
    );
  }

  void _onCreateNewWallet() async {
    Navigator.of(context).pop();
    final result = await context.push<bool?>(RoutePaths.insideNewWallet);
    // Refresh wallets list when returning from wallet creation
    if (result != null) {
      _loadWallets();
    }
  }

  void _onAddExistingWallet() async {
    Navigator.of(context).pop();
    final result = await context.push<bool?>(RoutePaths.insideImportWallet);
    // Refresh wallets list when returning from wallet import
    if (result != null) {
      _loadWallets();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              children: [
                const SizedBox(height: 8),
                // Header
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        _safeTranslate('wallets', 'Wallets'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    GestureDetector(
                      onTap: _showAddWalletModal,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Image.asset(
                          'assets/images/plus.png',
                          width: 16,
                          height: 16,
                          color: const Color(0x99757575),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                // Wallets List
                Expanded(
                  child: ListView.builder(
                    itemCount: wallets.length,
                    itemBuilder: (context, index) {
                      final wallet = wallets[index];
                      final isDefault = wallet.walletName == selectedWalletName;
                      return _WalletItem(
                        wallet: wallet,
                        isDefault: isDefault,
                        onWalletClick: () {
                          _saveSelectedWallet(wallet.walletName, wallet.userId);
                          AppNavigation.pushReplacementNamed(context, '/home');
                        },
                        onMoreOptionsClick: () {
                          AppNavigation.pushNamed(
                            context,
                            RoutePaths.walletDetail,
                            arguments: {'walletName': wallet.walletName},
                          );
                        },
                        onBackupClick: () {
                          // TODO: Navigate to backup page
                        },
                      );
                    },
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

class _WalletItem extends StatelessWidget {
  final Wallet wallet;
  final bool isDefault;
  final VoidCallback onWalletClick;
  final VoidCallback onMoreOptionsClick;
  final VoidCallback onBackupClick;

  const _WalletItem({
    required this.wallet,
    required this.isDefault,
    required this.onWalletClick,
    required this.onMoreOptionsClick,
    required this.onBackupClick,
  });

  String _safeTranslate(BuildContext context, String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onWalletClick,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/images/wallet.png',
                      width: 32,
                      height: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        wallet.walletName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    if (isDefault)
                      Image.asset(
                        'assets/images/badge.png',
                        width: 28,
                        height: 28,
                        color: const Color(0xFF17D27C),
                      ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onMoreOptionsClick,
                      child: Image.asset(
                        'assets/images/more.png',
                        width: 24,
                        height: 24,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: onBackupClick,
                  child: Text(
                    _safeTranslate(context, 'back_up_now', 'Back up now'),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF007AFF),
                      fontWeight: FontWeight.bold,
                    ),
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

class _AddWalletModalContent extends StatelessWidget {
  final VoidCallback onCreateNewWallet;
  final VoidCallback onAddExistingWallet;

  const _AddWalletModalContent({
    required this.onCreateNewWallet,
    required this.onAddExistingWallet,
  });

  String _safeTranslate(BuildContext context, String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/cryptowallet.png',
            width: 140,
            height: 140,
          ),
          const SizedBox(height: 16),
          _WalletOptionTile(
            icon: Icons.auto_awesome,
            title: _safeTranslate(context, 'create_new_wallet', 'Create new wallet'),
            subtitle: _safeTranslate(context, 'secret_phrase_or_biometric', 'Secret phrase or FaceID / fingerprint'),
            onTap: onCreateNewWallet,
          ),
          const SizedBox(height: 12),
          _WalletOptionTile(
            icon: Icons.add_circle_outline,
            title: _safeTranslate(context, 'add_existing_wallet', 'Add existing wallet'),
            subtitle: _safeTranslate(context, 'secret_phrase_google_drive', 'Secret phrase, Google Drive or view-only'),
            onTap: onAddExistingWallet,
          ),
        ],
      ),
    );
  }
}

class _WalletOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _WalletOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF6FFFA),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF4C70D0), size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFFB2B2B2))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
} 