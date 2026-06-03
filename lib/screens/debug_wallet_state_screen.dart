import 'package:flutter/foundation.dart';
import '../navigation/app_navigation.dart';
import '../navigation/route_paths.dart';
import 'package:flutter/material.dart';
import '../services/secure_storage.dart';
import '../services/wallet_state_manager.dart';
import '../services/passcode_manager.dart';

/// Debug screen to inspect wallet state and force navigation
/// Only available in debug mode
class DebugWalletStateScreen extends StatefulWidget {
  const DebugWalletStateScreen({super.key});

  @override
  State<DebugWalletStateScreen> createState() => _DebugWalletStateScreenState();
}

class _DebugWalletStateScreenState extends State<DebugWalletStateScreen> {
  Map<String, dynamic> _debugInfo = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDebugInfo();
  }

  Future<void> _loadDebugInfo() async {
    setState(() => _isLoading = true);
    
    try {
      final info = <String, dynamic>{};
      
      // Wallet checks
      info['hasWallet'] = await WalletStateManager.instance.hasWallet();
      info['hasValidWallet'] = await WalletStateManager.instance.hasValidWallet();
      info['hasPasscode'] = await WalletStateManager.instance.hasPasscode();
      info['isFreshInstall'] = await WalletStateManager.instance.isFreshInstall();
      info['initialScreen'] = await WalletStateManager.instance.getInitialScreen();
      
      // Passcode checks
      info['passcodeSet'] = await PasscodeManager.isPasscodeSet();
      info['passcodeIsLocked'] = await PasscodeManager.isLocked();
      
      // Wallet list
      try {
        final wallets = await SecureStorage.instance.getWalletsList();
        info['walletCount'] = wallets.length;
        info['wallets'] = wallets;
        
        // Check mnemonic for each wallet
        final walletDetails = <Map<String, dynamic>>[];
        for (int i = 0; i < wallets.length; i++) {
          final wallet = wallets[i];
          final walletName = wallet['walletName'];
          final userId = wallet['userID'];
          
          final detail = {
            'index': i,
            'name': walletName,
            'userId': userId,
            'hasMnemonic': false,
          };
          
          if (walletName != null && userId != null) {
            try {
              final mnemonic = await SecureStorage.instance.getMnemonic(walletName, userId);
              detail['hasMnemonic'] = mnemonic != null && mnemonic.isNotEmpty;
            } catch (e) {
              detail['mnemonicError'] = e.toString();
            }
          }
          
          walletDetails.add(detail);
        }
        info['walletDetails'] = walletDetails;
        
      } catch (e) {
        info['walletError'] = e.toString();
      }
      
      // All keys
      try {
        final allKeys = await SecureStorage.instance.getAllKeys();
        info['totalKeys'] = allKeys.length;
        info['sampleKeys'] = allKeys.take(20).toList();
      } catch (e) {
        info['keysError'] = e.toString();
      }
      
      setState(() {
        _debugInfo = info;
        _isLoading = false;
      });
      
    } catch (e) {
      setState(() {
        _debugInfo = {'error': e.toString()};
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('Debug')),
        body: const Center(
          child: Text('Debug screen only available in debug mode'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Wallet State'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDebugInfo,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick Actions
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Quick Actions',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    AppNavigation.pushReplacementNamed(context, RoutePaths.enterPasscode);
                                  },
                                  child: const Text('Force Enter Passcode'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    AppNavigation.pushReplacementNamed(context, RoutePaths.home);
                                  },
                                  child: const Text('Force Home'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    AppNavigation.pushReplacementNamed(context, RoutePaths.importCreate);
                                  },
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                                  child: const Text('Force Import Create'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _clearAllData,
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                  child: const Text('Clear All Data'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Debug Info
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Wallet State Info',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          ..._buildDebugInfo(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> _buildDebugInfo() {
    final widgets = <Widget>[];
    
    _debugInfo.forEach((key, value) {
      if (key == 'walletDetails') {
        widgets.add(_buildWalletDetails(value));
      } else if (key == 'wallets') {
        // Skip raw wallets as we show walletDetails
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  '$key:',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              Expanded(
                child: Text(
                  value.toString(),
                  style: TextStyle(
                    color: _getValueColor(key, value),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ));
      }
    });
    
    return widgets;
  }

  Widget _buildWalletDetails(List<dynamic> walletDetails) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Wallet Details:',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        ...walletDetails.map((detail) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Wallet ${detail['index']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('Name: ${detail['name']}'),
                Text('UserID: ${detail['userId']}'),
                Text(
                  'Has Mnemonic: ${detail['hasMnemonic']}',
                  style: TextStyle(
                    color: detail['hasMnemonic'] == true ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (detail['mnemonicError'] != null)
                  Text('Error: ${detail['mnemonicError']}', style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
        )),
      ],
    );
  }

  Color _getValueColor(String key, dynamic value) {
    if (key.contains('Error') || key.contains('error')) {
      return Colors.red;
    }
    
    if (value is bool) {
      return value ? Colors.green : Colors.red;
    }
    
    if (key == 'initialScreen') {
      switch (value) {
        case RoutePaths.enterPasscode:
          return Colors.green;
        case RoutePaths.home:
          return Colors.blue;
        case RoutePaths.importCreate:
          return Colors.orange;
        default:
          return Colors.grey;
      }
    }
    
    return Colors.black87;
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text('This will remove all wallets, passcodes, and app data. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await SecureStorage.instance.clearAllSecureData();
        await PasscodeManager.clearPasscode();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All data cleared. Restart app.')),
          );
          
          // Reload debug info
          _loadDebugInfo();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error clearing data: $e')),
          );
        }
      }
    }
  }
}
