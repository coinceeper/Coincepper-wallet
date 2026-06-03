import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/secure_storage.dart';
import '../services/passcode_manager.dart';
import '../services/wallet_state_manager.dart';
import '../services/uninstall_data_manager.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Debug Panel برای بررسی و مدیریت داده‌های اپلیکیشن
class DebugDataPanel extends StatefulWidget {
  const DebugDataPanel({super.key});

  @override
  State<DebugDataPanel> createState() => _DebugDataPanelState();
}

class _DebugDataPanelState extends State<DebugDataPanel> {
  Map<String, dynamic> _dataStatus = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDataStatus();
  }

  Future<void> _loadDataStatus() async {
    setState(() => _isLoading = true);
    
    try {
      final status = await _getCompleteDataStatus();
      setState(() => _dataStatus = status);
    } catch (e) {
      print('❌ Error loading data status: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>> _getCompleteDataStatus() async {
    final Map<String, dynamic> status = {};

    // App Info
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      status['app_info'] = {
        'version': packageInfo.version,
        'build': packageInfo.buildNumber,
        'package': packageInfo.packageName,
      };
    } catch (e) {
      status['app_info'] = {'error': e.toString()};
    }

    // SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      status['shared_preferences'] = {
        'total_keys': keys.length,
        'keys': keys.take(20).toList(),
        'version_info': {
          'last_known_version': prefs.getString('last_known_version'),
          'last_known_build': prefs.getString('last_known_build'),
          'is_fresh_install': prefs.getBool('is_fresh_install'),
          'install_timestamp': prefs.getInt('install_timestamp'),
        },
        'wallet_keys': keys.where((k) => 
          k.contains('wallet') || k.contains('user_wallets') || k.contains('UserID')
        ).toList(),
        'token_keys': keys.where((k) => 
          k.contains('token') || k.contains('enabled_tokens')
        ).length,
      };
    } catch (e) {
      status['shared_preferences'] = {'error': e.toString()};
    }

    // SecureStorage
    try {
      final secureKeys = await SecureStorage.instance.getAllKeys();
      status['secure_storage'] = {
        'total_keys': secureKeys.length,
        'keys': secureKeys.take(20).toList(),
        'wallet_keys': secureKeys.where((k) => 
          k.contains('UserID') || k.contains('WalletID') || k.contains('Mnemonic')
        ).toList(),
        'passcode_keys': secureKeys.where((k) => 
          k.contains('passcode') || k.contains('biometric')
        ).toList(),
      };
    } catch (e) {
      status['secure_storage'] = {'error': e.toString()};
    }

    // Wallet State
    try {
      final hasWallet = await WalletStateManager.instance.hasWallet();
      final hasValidWallet = await WalletStateManager.instance.hasValidWallet();
      final hasPasscode = await WalletStateManager.instance.hasPasscode();
      final isFreshInstall = await WalletStateManager.instance.isEnhancedFreshInstall();
      
      status['wallet_state'] = {
        'has_wallet': hasWallet,
        'has_valid_wallet': hasValidWallet,
        'has_passcode': hasPasscode,
        'is_fresh_install': isFreshInstall,
      };
    } catch (e) {
      status['wallet_state'] = {'error': e.toString()};
    }

    // Passcode State
    try {
      final isPasscodeSet = await PasscodeManager.isPasscodeSet();
      status['passcode_state'] = {
        'is_set': isPasscodeSet,
      };
    } catch (e) {
      status['passcode_state'] = {'error': e.toString()};
    }

    return status;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug Data Panel'),
        backgroundColor: Colors.orange,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDataStatus,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildWarningCard(),
                const SizedBox(height: 16),
                ..._buildDataSections(),
                const SizedBox(height: 16),
                _buildActionButtons(),
              ],
            ),
    );
  }

  Widget _buildWarningCard() {
    return Card(
      color: Colors.red.shade50,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 32),
            SizedBox(height: 8),
            Text(
              '⚠️ DEBUG MODE',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'این پنل فقط برای debugging است. عملیات پاکسازی غیرقابل برگشت هستند!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDataSections() {
    return _dataStatus.entries.map((entry) {
      return Card(
        child: ExpansionTile(
          title: Text(
            entry.key.replaceAll('_', ' ').toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildDataContent(entry.value),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildDataContent(dynamic data) {
    if (data is Map<String, dynamic>) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: data.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    '${entry.key}:',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    entry.value.toString(),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }
    return Text(data.toString());
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        const Text(
          'عملیات پاکسازی',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _clearSharedPreferences,
                icon: const Icon(Icons.cleaning_services),
                label: const Text('پاک کردن SharedPreferences'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _clearSecureStorage,
                icon: const Icon(Icons.security),
                label: const Text('پاک کردن SecureStorage'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _performCompleteCleanup,
                icon: const Icon(Icons.delete_forever),
                label: const Text('پاکسازی کامل'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _simulateFreshInstall,
                icon: const Icon(Icons.refresh),
                label: const Text('شبیه‌سازی Fresh Install'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _clearSharedPreferences() async {
    final confirmed = await _showConfirmDialog(
      'پاک کردن SharedPreferences',
      'آیا مطمئن هستید که می‌خواهید تمام SharedPreferences را پاک کنید؟'
    );
    
    if (confirmed) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        _showSuccess('SharedPreferences پاک شد');
        _loadDataStatus();
      } catch (e) {
        _showError('خطا در پاک کردن SharedPreferences: $e');
      }
    }
  }

  Future<void> _clearSecureStorage() async {
    final confirmed = await _showConfirmDialog(
      'پاک کردن SecureStorage',
      'آیا مطمئن هستید که می‌خواهید تمام SecureStorage را پاک کنید؟'
    );
    
    if (confirmed) {
      try {
        await SecureStorage.instance.deleteAll();
        _showSuccess('SecureStorage پاک شد');
        _loadDataStatus();
      } catch (e) {
        _showError('خطا در پاک کردن SecureStorage: $e');
      }
    }
  }

  Future<void> _performCompleteCleanup() async {
    final confirmed = await _showConfirmDialog(
      'پاکسازی کامل',
      'آیا مطمئن هستید که می‌خواهید تمام داده‌های اپلیکیشن را پاک کنید؟ این عمل غیرقابل برگشت است!'
    );
    
    if (confirmed) {
      try {
        await UninstallDataManager.performCompleteDataCleanup(context);
        _showSuccess('پاکسازی کامل انجام شد');
        _loadDataStatus();
      } catch (e) {
        _showError('خطا در پاکسازی کامل: $e');
      }
    }
  }

  Future<void> _simulateFreshInstall() async {
    final confirmed = await _showConfirmDialog(
      'شبیه‌سازی Fresh Install',
      'این عمل تمام داده‌ها را پاک کرده و version tracking را reset می‌کند. ادامه می‌دهید؟'
    );
    
    if (confirmed) {
      try {
        // پاکسازی کامل
        await UninstallDataManager.performCompleteDataCleanup(context);
        
        // Reset version tracking
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('last_known_version');
        await prefs.remove('last_known_build');
        await prefs.remove('is_fresh_install');
        await prefs.remove('install_timestamp');
        
        _showSuccess('شبیه‌سازی Fresh Install انجام شد. اپلیکیشن را restart کنید.');
        _loadDataStatus();
      } catch (e) {
        _showError('خطا در شبیه‌سازی Fresh Install: $e');
      }
    }
  }

  Future<bool> _showConfirmDialog(String title, String content) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('لغو'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('تأیید'),
          ),
        ],
      ),
    ) ?? false;
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}
