import 'package:flutter/material.dart';
import '../navigation/app_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import '../navigation/route_paths.dart';
import '../navigation/wallet_onboarding_navigation.dart';
import '../wallet/wallet_repository.dart';
import '../services/secure_storage.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/security_settings_manager.dart';

class CreateNewWalletScreen extends StatefulWidget {
  const CreateNewWalletScreen({super.key});

  @override
  State<CreateNewWalletScreen> createState() => _CreateNewWalletScreenState();
}

class _CreateNewWalletScreenState extends State<CreateNewWalletScreen> {
  String? errorMessage;
  String walletName = '';
  bool showErrorModal = false;
  bool isLoading = false;
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
    _suggestNextWalletName();
  }

  /// Check if wallet exists and redirect to home if it does
  Future<void> _checkExistingWallet() async {
    try {
      final wallets = await SecureStorage.instance.getWalletsList();
      if (wallets.isNotEmpty) {
        print('🔄 Existing wallet found, redirecting to home...');
        if (mounted) {
          AppNavigation.pushNamedAndRemoveUntil(
            context,
            RoutePaths.home,
            (route) => false,
          );
        }
      }
    } catch (e) {
      print('❌ Error checking existing wallet: $e');
    }
  }

  Future<void> _suggestNextWalletName() async {
    final wallets = await SecureStorage.instance.getWalletsList();
    int maxNum = 0;
    final regex = RegExp(r'^New wallet (\d+)');
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
    if (isLoading) return;
    
    setState(() {
      isLoading = true;
      errorMessage = null;
      showErrorModal = false;
    });

    // Always fetch the latest wallet list from SecureStorage
    final wallets = await SecureStorage.instance.getWalletsList();
    int maxNum = 0;
    final regex = RegExp(r'^New wallet (\d+)');
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

    // Prevent empty wallet name
    if (newWalletName.trim().isEmpty) {
      setState(() {
        errorMessage = _safeTranslate('wallet_name_cannot_be_empty', 'Wallet name cannot be empty');
        showErrorModal = true;
        isLoading = false;
      });
      return;
    }

    try {
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
          final tokenProvider = appProvider.tokenProvider;
          if (tokenProvider != null) {
            tokenProvider.updateUserId(created.walletId);
          }
          await appProvider.refreshWallets();
        } catch (e) {
          print('Error refreshing wallets after local create: $e');
        }
      }

      if (mounted) {
        final isPasscodeEnabled =
            await SecuritySettingsManager.instance.isPasscodeEnabled();
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
      setState(() {
        errorMessage =
            '${_safeTranslate('error_creating_wallet', 'Error creating wallet. Please try again.')}: $e';
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
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header - مطابق با Kotlin
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                      },
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.black,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      _safeTranslate('generate_new_wallet', 'Generate new wallet'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Wallet Option Item - مطابق با Kotlin
                WalletOptionItemNew(
                  title: _safeTranslate('secret_phrase', 'Secret phrase'),
                  points: 100,
                  buttonText: _safeTranslate('generate', 'Generate'),
                  isLoading: isLoading,
                  onClickCreate: _generateWallet,
                  expandedContent: (context) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DetailRow(
                        label: _safeTranslate('security', 'Security'),
                        content: _safeTranslate('create_recover_description', 'Create and recover wallet with a 12, 18, or 24-word secret phrase. You must manually store this, or back up with Google Drive storage.'),
                      ),
                      const SizedBox(height: 12),
                      DetailRow(
                        label: _safeTranslate('transactions', 'Transaction'),
                        content: _safeTranslate('transaction_networks_description', 'Transactions are available on more networks (chains), but require more steps to complete.'),
                        showIcons: true,
                      ),
                      const SizedBox(height: 12),
                      DetailRow(
                        label: _safeTranslate('fee', 'Fees'),
                        content: _safeTranslate('fees_description', 'Pay network fee (gas) with native tokens only. For example, if your transaction is on the Ethereum network, you can only pay for this fee with ETH.'),
                      ),
                    ],
                  ),
                ),
                
                // Error Modal - مطابق با Kotlin
                if (showErrorModal)
                  CreateWalletErrorModal(
                    show: showErrorModal,
                    onDismiss: () => setState(() => showErrorModal = false),
                    message: errorMessage ?? _safeTranslate('error', 'Error'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class WalletOptionItemNew extends StatefulWidget {
  final String title;
  final int? points;
  final String buttonText;
  final bool isLoading;
  final Future<void> Function() onClickCreate;
  final WidgetBuilder? expandedContent;

  const WalletOptionItemNew({
    super.key,
    required this.title,
    this.points,
    required this.buttonText,
    required this.isLoading,
    required this.onClickCreate,
    this.expandedContent,
  });

  @override
  State<WalletOptionItemNew> createState() => _WalletOptionItemNewState();
}

class _WalletOptionItemNewState extends State<WalletOptionItemNew> {
  bool isExpanded = false;

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  void _onClick() async {
    if (widget.isLoading) return;
    await widget.onClickCreate();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0x0D03ac0e), // مطابق با Kotlin Color(0x0D03ac0e)
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              // Left side - Title and points
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        if (widget.points != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '+${widget.points} ${_safeTranslate('points', 'points')}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                                         GestureDetector(
                       onTap: () {
                         setState(() {
                           isExpanded = !isExpanded;
                         });
                       },
                       child: Text(
                         isExpanded ? 'Hide details ▲' : 'Show details ▼',
                         style: const TextStyle(
                           fontSize: 12,
                           color: Color(0xFF03ac0e),
                         ),
                       ),
                     ),
                  ],
                ),
              ),
              
              // Right side - Button مطابق با Kotlin
              SizedBox(
                width: 110,
                height: 36,
                child: OutlinedButton(
                  onPressed: widget.isLoading ? null : _onClick,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: const Color(0xFF03ac0e),
                    side: const BorderSide(color: Color(0xFF03ac0e), width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    elevation: 0,
                    padding: EdgeInsets.zero,
                  ),
                  child: widget.isLoading 
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Color(0xFF03ac0e),
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          widget.buttonText,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
          
          // Expanded content مطابق با Kotlin
          if (isExpanded && widget.expandedContent != null) ...[
            const SizedBox(height: 16),
            widget.expandedContent!(context),
          ],
        ],
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  final String label;
  final String content;
  final bool showIcons;

  const DetailRow({
    super.key,
    required this.label,
    required this.content,
    this.showIcons = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xA6000000), // مطابق با Kotlin
          ),
        ),
        const SizedBox(height: 4),
        Text(
          content,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            height: 1.4,
          ),
        ),
        if (showIcons) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _buildNetworkIcon('assets/images/btc.png'),
              const SizedBox(width: 8),
              _buildNetworkIcon('assets/images/ethereum_logo.png'),
              const SizedBox(width: 8),
              _buildNetworkIcon('assets/images/binance_logo.png'),
              const SizedBox(width: 8),
              _buildNetworkIcon('assets/images/tron.png'),
              const SizedBox(width: 8),
              const Text(
                '+ more chains',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildNetworkIcon(String assetPath) {
    return SizedBox(
      width: 24,
      height: 24,
      child: ClipOval(
        child: Image.asset(
          assetPath,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Colors.grey,
                shape: BoxShape.circle,
              ),
            );
          },
        ),
      ),
    );
  }
}

class CreateWalletErrorModal extends StatelessWidget {
  final bool show;
  final VoidCallback onDismiss;
  final String message;
  final String title;
  
  const CreateWalletErrorModal({
    super.key,
    required this.show,
    required this.onDismiss,
    required this.message,
    this.title = 'Error',
  });

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
    if (!show) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Error icon
          SizedBox(
            width: 48,
            height: 48,
            child: Image.asset(
              'assets/images/error.png',
              width: 48,
              height: 48,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.error,
                  size: 48,
                  color: Colors.red,
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          
          // Title
          Text(
            _safeTranslate(context, 'error', title),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          
          // Message
          Text(
            message,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          
          // OK Button مطابق با Kotlin
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
                elevation: 0,
              ),
              child: const Text(
                'OK',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 