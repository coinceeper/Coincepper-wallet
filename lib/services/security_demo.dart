import 'package:flutter/material.dart';
import 'security_settings_manager.dart';
import '../di/service_locator.dart';
import '../domain/interfaces/i_security_manager.dart';
import '../utils/secure_log.dart';

/// نمونه استفاده از SecuritySettingsManager
class SecurityDemo {
  static final SecuritySettingsManager _securityManager = ServiceLocator.get<SecuritySettingsManager>();

  /// نمایش چگونگی استفاده از تنظیمات امنیتی
  static Future<void> demonstrateSecuritySettings() async {
    SecureLog.i('Security Settings Demo');
    SecureLog.i('========================');

    // 1. تنظیم passcode
    SecureLog.i('1. Setting up passcode...');
    await _securityManager.setPasscodeEnabled(true);
    SecureLog.i('Passcode enabled');

    // 2. تنظیم auto-lock
    SecureLog.i('2. Setting up auto-lock...');
    await _securityManager.setAutoLockDuration(AutoLockDuration.fiveMinutes);
    SecureLog.i('Auto-lock set to 5 minutes');

    // 3. تنظیم lock method
    SecureLog.i('3. Setting up lock method...');
    final biometricAvailable = await _securityManager.isBiometricAvailable();
    if (biometricAvailable) {
      await _securityManager.setLockMethod(LockMethod.passcodeAndBiometric);
      SecureLog.i('Lock method set to Passcode + Biometric');
    } else {
      await _securityManager.setLockMethod(LockMethod.passcodeOnly);
      SecureLog.i('Lock method set to Passcode Only (biometric not available)');
    }

    // 4. نمایش خلاصه تنظیمات
    SecureLog.i('4. Security Settings Summary:');
    final summary = await _securityManager.getSecuritySettingsSummary();
    SecureLog.i('Passcode Enabled: ${summary['passcodeEnabled']}');
    SecureLog.i('Auto-lock: ${summary['autoLockDurationText']}');
    SecureLog.i('Lock Method: ${summary['lockMethodText']}');
    SecureLog.i('Biometric Available: ${summary['biometricAvailable']}');
    SecureLog.i('Passcode Set: ${summary['passcodeSet']}');
  }

  /// نمایش چگونگی استفاده از lifecycle
  static Future<void> demonstrateLifecycleHandling() async {
    SecureLog.i('Lifecycle Demo');
    SecureLog.i('==================');

    // شبیه‌سازی رفتن به پس‌زمینه
    SecureLog.i('1. App goes to background...');
    await _securityManager.saveLastBackgroundTime();
    SecureLog.i('Background time saved');

    // شبیه‌سازی بازگشت از پس‌زمینه
    SecureLog.i('2. App returns from background...');
    await Future.delayed(const Duration(seconds: 2)); // شبیه‌سازی مدت زمان در پس‌زمینه
    
    final shouldShowPasscode = await _securityManager.shouldShowPasscodeAfterBackground();
    SecureLog.i('Should show passcode: $shouldShowPasscode');

    if (shouldShowPasscode) {
      SecureLog.i('Passcode screen should be shown');
    } else {
      SecureLog.i('No passcode needed');
    }
  }

  /// نمایش چگونگی احراز هویت
  static Future<void> demonstrateAuthentication() async {
    SecureLog.i('Authentication Demo');
    SecureLog.i('=====================');

    // بررسی روش‌های احراز هویت موجود
    final canUseBiometric = await _securityManager.canUseBiometricInCurrentLockMethod();
    final canUsePasscode = await _securityManager.canUsePasscodeInCurrentLockMethod();
    
    SecureLog.i('Can use biometric: $canUseBiometric');
    SecureLog.i('Can use passcode: $canUsePasscode');

    // بررسی نیاز به passcode در startup
    final shouldShowOnStartup = await _securityManager.shouldShowPasscodeOnStartup();
    SecureLog.i('Should show passcode on startup: $shouldShowOnStartup');

    // تست احراز هویت biometric (اگر موجود باشد)
    if (canUseBiometric) {
      SecureLog.i('Testing biometric authentication...');
      final biometricResult = await _securityManager.authenticateWithBiometric();
      SecureLog.i('Biometric auth result: $biometricResult');
    }
  }

  /// تست کامل سیستم
  static Future<void> runCompleteDemo() async {
    try {
      await demonstrateSecuritySettings();
      await demonstrateLifecycleHandling();
      await demonstrateAuthentication();
      
      SecureLog.i('Security demo completed successfully!');
    } catch (e) {
      SecureLog.e('Security demo failed', error: e);
    }
  }
}

/// Widget مثال برای نمایش استفاده در UI
class SecurityDemoWidget extends StatefulWidget {
  const SecurityDemoWidget({super.key});

  @override
  _SecurityDemoWidgetState createState() => _SecurityDemoWidgetState();
}

class _SecurityDemoWidgetState extends State<SecurityDemoWidget> {
  final SecuritySettingsManager _securityManager = ServiceLocator.get<SecuritySettingsManager>();
  bool _isLoading = false;
  String _status = 'Ready';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security Demo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_status),
            const SizedBox(height: 20),
            if (_isLoading) const CircularProgressIndicator(),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isLoading ? null : _runDemo,
              child: const Text('Run Security Demo'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isLoading ? null : _testBiometric,
              child: const Text('Test Biometric'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isLoading ? null : _testAutoLock,
              child: const Text('Test Auto-Lock'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runDemo() async {
    setState(() {
      _isLoading = true;
      _status = 'Running demo...';
    });

    try {
      await SecurityDemo.runCompleteDemo();
      setState(() {
        _status = 'Demo completed successfully!';
      });
    } catch (e) {
      setState(() {
        _status = 'Demo failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testBiometric() async {
    setState(() {
      _isLoading = true;
      _status = 'Testing biometric...';
    });

    try {
      final isAvailable = await _securityManager.isBiometricAvailable();
      if (isAvailable) {
        final result = await _securityManager.authenticateWithBiometric();
        setState(() {
          _status = 'Biometric test result: $result';
        });
      } else {
        setState(() {
          _status = 'Biometric not available';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Biometric test failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testAutoLock() async {
    setState(() {
      _isLoading = true;
      _status = 'Testing auto-lock...';
    });

    try {
      // تنظیم auto-lock روی immediate
      await _securityManager.setAutoLockDuration(AutoLockDuration.immediate);
      
      // شبیه‌سازی background
      await _securityManager.saveLastBackgroundTime();
      
      // بررسی نیاز به passcode
      final shouldShow = await _securityManager.shouldShowPasscodeAfterBackground();
      
      setState(() {
        _status = 'Auto-lock test: Should show passcode = $shouldShow';
      });
    } catch (e) {
      setState(() {
        _status = 'Auto-lock test failed: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
} 