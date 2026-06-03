import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../navigation/app_navigation.dart';
import '../navigation/passcode_navigation.dart';
import '../navigation/route_paths.dart';
import '../navigation/wallet_session.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/security_settings_manager.dart';
import '../services/wallet_state_manager.dart';
import '../services/passcode_manager.dart';
import 'passcode_screen.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
// kDebugMode import removed to avoid showing debug UI in production
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // Added for SecureStorage

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> with WidgetsBindingObserver {
  final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;
  
  bool _isLoading = true;
  bool _passcodeEnabled = true;
  AutoLockDuration _autoLockDuration = AutoLockDuration.immediate;
  LockMethod _lockMethod = LockMethod.passcodeAndBiometric;
  bool _biometricAvailable = false;
  bool _passcodeSet = false;
  bool _walletBlocksPasscodeDisable = false;
  
  // Auto-lock variables
  DateTime? _backgroundTime;
  bool _isInBackground = false;

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
    WidgetsBinding.instance.addObserver(this);
    _initializeAndLoadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// App lifecycle handler for auto-lock
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _handleAppGoingToBackground();
        break;
      case AppLifecycleState.resumed:
        _handleAppComingToForeground();
        break;
      default:
        break;
    }
  }

  /// Handle app going to background
  void _handleAppGoingToBackground() {
    if (_passcodeEnabled && _passcodeSet) {
      _backgroundTime = DateTime.now();
      _isInBackground = true;
      print('🔒 App went to background at: $_backgroundTime');
    }
  }

  /// Handle app coming to foreground
  void _handleAppComingToForeground() {
    if (_isInBackground && _backgroundTime != null && _passcodeEnabled && _passcodeSet) {
      _isInBackground = false;
      final currentTime = DateTime.now();
      final elapsedTime = currentTime.difference(_backgroundTime!);
      
      print('🔓 App came to foreground. Elapsed time: ${elapsedTime.inSeconds}s');
      
      // Check if auto-lock should be triggered
      if (_shouldLockApp(elapsedTime)) {
        _triggerAutoLock();
      }
      
      _backgroundTime = null;
    }
  }

  /// Determine if app should be locked based on elapsed time
  bool _shouldLockApp(Duration elapsedTime) {
    switch (_autoLockDuration) {
      case AutoLockDuration.immediate:
        return true; // Always lock immediately
      case AutoLockDuration.oneMinute:
        return elapsedTime.inMinutes >= 1;
      case AutoLockDuration.fiveMinutes:
        return elapsedTime.inMinutes >= 5;
      case AutoLockDuration.tenMinutes:
        return elapsedTime.inMinutes >= 10;
      case AutoLockDuration.fifteenMinutes:
        return elapsedTime.inMinutes >= 15;
      default:
        return false;
    }
  }

  /// Trigger auto-lock by showing passcode screen
  void _triggerAutoLock() {
    if (!mounted) return;
    
    print('🔒 Triggering auto-lock...');
    
    goEnterPasscodeWithCallback(
      context,
      () {
        if (context.canPop()) {
          context.pop();
        }
        print('🔓 Auto-lock passcode entered successfully');
      },
      isFromBackground: true,
    );
  }

  /// مقداردهی و بارگذاری تنظیمات
  Future<void> _initializeAndLoadSettings() async {
    try {
      // مقداردهی SecuritySettingsManager
      await _securityManager.initialize();
      
      // بارگذاری تنظیمات
      await _loadSecuritySettings();
      
      // Check if this is the first time accessing security screen
      // We want passcode to be enabled by default (user requirement)
      final prefs = await SharedPreferences.getInstance();
      const securityScreenAccessedKey = 'security_screen_accessed';
      
      // If this is the first time accessing security screen
      final hasAccessedBefore = prefs.getBool(securityScreenAccessedKey) ?? false;
      if (!hasAccessedBefore) {
        // Check if passcode is already set
        final passcodeAlreadySet = await PasscodeManager.isPasscodeSet();
        
        if (passcodeAlreadySet) {
          // 🔒 CRITICAL FIX: Don't override user's passcode enabled setting
          // Just mark as accessed - SecuritySettingsManager handles the smart default
          await prefs.setBool(securityScreenAccessedKey, true);
          print('🔒 Passcode already set - letting SecuritySettingsManager handle enabled state');
        } else {
          // If passcode is not set, show setup dialog
          _showInitialPasscodeSetupDialog();
        }
        
        // Reload settings after potential changes
        await _loadSecuritySettings();
      }
    } catch (e) {
      print('❌ Error initializing security screen: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// نمایش dialog اولیه برای تنظیم passcode
  void _showInitialPasscodeSetupDialog() {
    // Remove dialog - initial passcode setup dialog removed
  }

  /// بارگذاری تنظیمات امنیتی
  Future<void> _loadSecuritySettings() async {
    try {
      final settings = await _securityManager.getSecuritySettingsSummary();
      final hasWallet = await WalletStateManager.instance.hasValidWallet();

      if (mounted) {
        setState(() {
          _walletBlocksPasscodeDisable = hasWallet;
          // 🔒 CRITICAL FIX: No default override - trust SecuritySettingsManager
          _passcodeEnabled = settings['passcodeEnabled'] ?? false; // Use SecuritySettingsManager's logic
          _autoLockDuration = settings['autoLockDuration'] ?? AutoLockDuration.immediate;
          _lockMethod = settings['lockMethod'] ?? LockMethod.passcodeAndBiometric;
          _biometricAvailable = settings['biometricAvailable'] ?? false;
          _passcodeSet = settings['passcodeSet'] ?? false;
          _isLoading = false;
        });
        
        // 🔍 DEBUG: Log the actual loaded values
        print('🔒 Security Screen loaded settings:');
        print('   _passcodeEnabled: $_passcodeEnabled');
        print('   _passcodeSet: $_passcodeSet');
        print('   settings[passcodeEnabled]: ${settings['passcodeEnabled']}');
      }
    } catch (e) {
      print('❌ Error loading security settings: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// تغییر وضعیت passcode
  Future<void> _togglePasscode(bool enabled) async {
    try {
      if (!enabled && _walletBlocksPasscodeDisable) {
        await _loadSecuritySettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _safeTranslate(
                  'passcode_cannot_disable_with_wallet',
                  'Passcode cannot be disabled while a wallet is on this device.',
                ),
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      if (enabled && !_passcodeSet) {
        // اگر passcode تنظیم نشده، به صفحه تنظیم passcode هدایت کن
        WalletSession.instance.passcodeOnSuccess = () async {
          await _securityManager.setPasscodeEnabled(true);
          await _loadSecuritySettings();
          if (mounted) {
            if (context.canPop()) {
              context.pop();
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _safeTranslate(
                    'passcode_set_successfully',
                    'Passcode set and enabled successfully',
                  ),
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        };
        await AppNavigation.pushNamed(context, RoutePaths.passcodeSetup);
        await _loadSecuritySettings();
        return;
      }
      
      if (!enabled) {
        // اگر کاربر می‌خواهد passcode را غیرفعال کند
        final confirmDisable = await _showConfirmDisableDialog();
        if (!confirmDisable) {
          await _loadSecuritySettings(); // Reset toggle to previous state
          return;
        }
      }

      final success = await _securityManager.setPasscodeEnabled(enabled);
      if (success) {
        await _loadSecuritySettings();
        
        // Reset auto-lock tracking when passcode is disabled
        if (!enabled) {
          _backgroundTime = null;
          _isInBackground = false;
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                enabled 
                  ? _safeTranslate('passcode_enabled', 'Passcode enabled successfully')
                  : _safeTranslate('passcode_disabled', 'Passcode disabled successfully')
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                enabled 
                  ? _safeTranslate('passcode_enable_failed', 'Failed to enable passcode')
                  : _safeTranslate('passcode_disable_failed', 'Failed to disable passcode. Biometric authentication not available.')
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        
        // Reset toggle to previous state on failure
        await _loadSecuritySettings();
      }
    } catch (e) {
      print('❌ Error toggling passcode: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_safeTranslate('error_occurred', 'An error occurred: {error}').replaceAll('{error}', e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
      
      // Reset toggle to previous state on error
      await _loadSecuritySettings();
    }
  }

  /// نمایش تأیید غیرفعال کردن passcode با modal زیبا
  Future<bool> _showConfirmDisableDialog() async {
    return await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Warning Icon & Title
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Security Warning',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Are you sure you want to disable passcode protection?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            
            // Security Risks Section
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.security, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Security Risks:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildRiskItem('Anyone can access your wallet', Icons.person_outline),
                  _buildRiskItem('Your crypto assets will be unprotected', Icons.account_balance_wallet_outlined),
                  _buildRiskItem('Unauthorized transactions possible', Icons.swap_horiz),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Warning Message
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This action will remove all security protection from your crypto wallet.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Action Buttons
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Disable Passcode',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ) ?? false;
  }
  
  /// Build risk item widget
  Widget _buildRiskItem(String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// نمایش dialog انتخاب auto-lock duration
  Future<void> _showAutoLockDialog() async {
    final selectedDuration = await showModalBottomSheet<AutoLockDuration>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Text(
                _safeTranslate('auto_lock_duration', 'Auto-lock Duration'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            
            // Options
            _buildAutoLockOption(
              AutoLockDuration.immediate,
              _safeTranslate('immediate', 'Immediate'),
              _safeTranslate('lock_immediately_desc', 'Lock as soon as app goes to background'),
              Icons.flash_on,
              Colors.red,
            ),
            
            _buildAutoLockOption(
              AutoLockDuration.fiveMinutes,
              _safeTranslate('5_minutes', '5 Minutes'),
              _safeTranslate('lock_after_5min_desc', 'Lock after 5 minutes in background'),
              Icons.timer,
              Colors.orange,
            ),
            
            _buildAutoLockOption(
              AutoLockDuration.tenMinutes,
              _safeTranslate('10_minutes', '10 Minutes'),
              _safeTranslate('lock_after_10min_desc', 'Lock after 10 minutes in background'),
              Icons.access_time,
              Colors.blue,
            ),
            
            _buildAutoLockOption(
              AutoLockDuration.fifteenMinutes,
              _safeTranslate('15_minutes', '15 Minutes'),
              _safeTranslate('lock_after_15min_desc', 'Lock after 15 minutes in background'),
              Icons.schedule,
              Colors.green,
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
    
    if (selectedDuration != null && selectedDuration != _autoLockDuration) {
      await _securityManager.setAutoLockDuration(selectedDuration);
      await _loadSecuritySettings();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _safeTranslate('auto_lock_updated', 'Auto-lock duration updated to {duration}')
                  .replaceAll('{duration}', _securityManager.getAutoLockDurationText(selectedDuration))
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }
  
  /// Build auto-lock option widget
  Widget _buildAutoLockOption(
    AutoLockDuration duration,
    String title,
    String description,
    IconData icon,
    Color color,
  ) {
    final isSelected = _autoLockDuration == duration;
    
    return InkWell(
      onTap: () => Navigator.pop(context, duration),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? color : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? color.withOpacity(0.8) : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color, size: 24),
          ],
        ),
      ),
    );
  }

  /// نمایش dialog انتخاب lock method
  Future<void> _showLockMethodDialog() async {
    // Remove modal bottom sheet - lock method dialog removed
  }

  /// Get description for auto-lock duration
  String _getAutoLockDescription(AutoLockDuration duration) {
    switch (duration) {
      case AutoLockDuration.immediate:
        return _safeTranslate('lock_immediately_desc', 'Lock as soon as app goes to background');
      case AutoLockDuration.oneMinute:
        return _safeTranslate('lock_after_1min_desc', 'Lock after 1 minute in background');
      case AutoLockDuration.fiveMinutes:
        return _safeTranslate('lock_after_5min_desc', 'Lock after 5 minutes in background');
      case AutoLockDuration.tenMinutes:
        return _safeTranslate('lock_after_10min_desc', 'Lock after 10 minutes in background');
      case AutoLockDuration.fifteenMinutes:
        return _safeTranslate('lock_after_15min_desc', 'Lock after 15 minutes in background');
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_safeTranslate('security', 'Security'), style: const TextStyle(color: Colors.black)),
          backgroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.black),
          elevation: 0,
        ),
        backgroundColor: Colors.white,
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_safeTranslate('security', 'Security'), style: const TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            
            // گزینه اول: Passcode Toggle
            _SettingItemWithSwitch(
              title: _safeTranslate('passcode', 'Passcode'),
              subtitle: _walletBlocksPasscodeDisable
                  ? _safeTranslate(
                      'passcode_required_with_wallet',
                      'Required while a wallet exists on this device',
                    )
                  : _getPasscodeStatusText(),
              value: _passcodeEnabled,
              onChanged: _togglePasscode,
              switchEnabled: !_walletBlocksPasscodeDisable || _passcodeEnabled,
            ),
            
            const SizedBox(height: 16),
            
            // گزینه دوم: Auto-lock Duration
            _SettingItem(
              title: _safeTranslate('auto_lock', 'Auto-lock'),
              subtitle: _getAutoLockStatusText(),
              onTap: _passcodeEnabled ? _showAutoLockDialog : null,
              isDisabled: !_passcodeEnabled,
              trailing: _passcodeEnabled ? _buildAutoLockIndicator() : null,
            ),
            
            const SizedBox(height: 16),
            
            // گزینه سوم: Lock Method
            _SettingItem(
              title: _safeTranslate('lock_method', 'Lock method'),
              subtitle: _getLockMethodStatusText(),
              onTap: _passcodeEnabled ? _showLockMethodDialog : null,
              isDisabled: !_passcodeEnabled,
              trailing: _passcodeEnabled ? _buildLockMethodIndicator() : null,
            ),
            
            const SizedBox(height: 24),
            
            const SizedBox(height: 24),
            
            // Debug cards removed for release UI
          ],
        ),
      ),
    );
  }
  
  /// Test SharedPreferences persistence
  Future<void> _testSharedPreferencesPersistence() async {
    await _securityManager.testSharedPreferencesPersistence();
  }

  /// Debug Android storage behavior
  Future<void> _debugAndroidStorageBehavior() async {
    await _securityManager.debugAndroidStorageBehavior();
  }

  /// Force re-initialization for debugging
  Future<void> _forceReinitialization() async {
    print('🔧 === FORCING RE-INITIALIZATION ===');
    SecuritySettingsManager.forceReinitialization();
    await _securityManager.initialize();
    await _loadSecuritySettings();
    print('🔧 === RE-INITIALIZATION COMPLETED ===');
  }

  /// Comprehensive persistence test
  Future<void> _comprehensivePersistenceTest() async {
    await _securityManager.comprehensivePersistenceTest();
  }

  /// Debug method to test passcode state
  Future<void> _debugPasscodeState() async {
    try {
      print('🔍 === MANUAL PASSCODE DEBUG ===');
      
      // Check SharedPreferences directly
      final prefs = await SharedPreferences.getInstance();
      final passcodeHash = prefs.getString('passcode_hash');
      final passcodeSalt = prefs.getString('passcode_salt');
      print('🔑 SharedPreferences passcode_hash = ${passcodeHash != null ? "EXISTS" : "NULL"}');
      print('🔑 SharedPreferences passcode_salt = ${passcodeSalt != null ? "EXISTS" : "NULL"}');
      
      // Check SecureStorage backup
      const secureStorage = FlutterSecureStorage();
      final secureHash = await secureStorage.read(key: 'passcode_hash_secure');
      final secureSalt = await secureStorage.read(key: 'passcode_salt_secure');
      print('🔑 SecureStorage passcode_hash_secure = ${secureHash != null ? "EXISTS" : "NULL"}');
      print('🔑 SecureStorage passcode_salt_secure = ${secureSalt != null ? "EXISTS" : "NULL"}');
      
      // Use PasscodeManager to check
      final isPasscodeSet = await PasscodeManager.isPasscodeSet();
      print('🔑 PasscodeManager.isPasscodeSet() = $isPasscodeSet');
      
      // Check if enabled in settings
      final isPasscodeEnabled = await _securityManager.isPasscodeEnabled();
      print('🔑 SecuritySettingsManager.isPasscodeEnabled() = $isPasscodeEnabled');
      
      print('🔍 === END MANUAL DEBUG ===');
      
      // Show dialog with results
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Passcode Debug Results'),
            content: Text(
              'SharedPreferences:\n'
              'passcode_hash: ${passcodeHash != null ? "EXISTS" : "NULL"}\n'
              'passcode_salt: ${passcodeSalt != null ? "EXISTS" : "NULL"}\n\n'
              'SecureStorage:\n'
              'passcode_hash_secure: ${secureHash != null ? "EXISTS" : "NULL"}\n'
              'passcode_salt_secure: ${secureSalt != null ? "EXISTS" : "NULL"}\n\n'
              'PasscodeManager.isPasscodeSet(): $isPasscodeSet\n'
              'SecurityManager.isPasscodeEnabled(): $isPasscodeEnabled',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('❌ Error in debug: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Debug error: $e')),
        );
      }
    }
  }

  /// Get passcode status text
  String _getPasscodeStatusText() {
    if (!_passcodeEnabled) {
      return _safeTranslate('passcode_disabled_description', 'App will open without passcode');
    }
    
    if (_passcodeSet) {
      return _safeTranslate('passcode_enabled_description', 'App will require passcode to unlock');
    }
    
    return _safeTranslate('passcode_not_set_description', 'Passcode not configured yet');
  }

  /// Get auto-lock status text
  String _getAutoLockStatusText() {
    if (!_passcodeEnabled) {
      return _safeTranslate('auto_lock_disabled_description', 'Enable passcode to use auto-lock');
    }
    
    final durationText = _securityManager.getAutoLockDurationText(_autoLockDuration);
    return _safeTranslate('auto_lock_enabled_description', 'Lock after: {duration}').replaceAll('{duration}', durationText);
  }

  /// Get lock method status text
  String _getLockMethodStatusText() {
    if (!_passcodeEnabled) {
      return _safeTranslate('lock_method_disabled_description', 'Enable passcode to select lock method');
    }
    
    return _securityManager.getLockMethodText(_lockMethod);
  }

  /// Build auto-lock indicator
  Widget _buildAutoLockIndicator() {
    Color color;
    switch (_autoLockDuration) {
      case AutoLockDuration.immediate:
        color = Colors.green;
        break;
      case AutoLockDuration.oneMinute:
        color = Colors.orange;
        break;
      default:
        color = Colors.red;
    }
    
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  /// Build lock method indicator
  Widget _buildLockMethodIndicator() {
    IconData icon;
    Color color;
    
    switch (_lockMethod) {
      case LockMethod.passcodeAndBiometric:
        icon = Icons.security;
        color = Colors.green;
        break;
      case LockMethod.passcodeOnly:
        icon = Icons.lock;
        color = Colors.orange;
        break;
      case LockMethod.biometricOnly:
        icon = Icons.fingerprint;
        color = Colors.blue;
        break;
    }
    
    return Icon(icon, color: color, size: 16);
  }

  /// Build auto-lock status card
  Widget _buildAutoLockStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isInBackground ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isInBackground ? Colors.orange.withOpacity(0.3) : Colors.green.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isInBackground ? Icons.pause_circle : Icons.play_circle,
                color: _isInBackground ? Colors.orange : Colors.green,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _safeTranslate('auto_lock_status', 'Auto-lock Status'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _isInBackground ? Colors.orange : Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _isInBackground 
              ? _safeTranslate('app_in_background', 'App is in background - auto-lock timer is running')
              : _safeTranslate('app_in_foreground', 'App is active - auto-lock timer is paused'),
            style: TextStyle(
              fontSize: 14,
              color: _isInBackground ? Colors.orange : Colors.green,
            ),
          ),
          if (_backgroundTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _safeTranslate('background_since', 'Background since: {time}').replaceAll(
                  '{time}', 
                  DateFormat('HH:mm:ss').format(_backgroundTime!),
                ),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingItemWithSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool switchEnabled;

  const _SettingItemWithSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.switchEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: switchEnabled ? onChanged : null,
            activeColor: const Color(0xFF0BAB9B),
          ),
        ],
      ),
    );
  }
}

class _SettingItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isDisabled;
  final Widget? trailing; // Added trailing widget
  
  const _SettingItem({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDisabled = false,
    this.trailing, // Initialize trailing
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isDisabled ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDisabled ? Colors.grey : Colors.black,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDisabled ? Colors.grey.withOpacity(0.7) : Colors.grey,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
                const SizedBox(width: 8),
              ],
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: isDisabled ? Colors.grey.withOpacity(0.5) : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
} 