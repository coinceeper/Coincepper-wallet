import 'package:flutter/material.dart';
import '../services/security_settings_manager.dart';
import '../services/passcode_manager.dart';
import 'package:easy_localization/easy_localization.dart';

class SecurityTestScreen extends StatefulWidget {
  const SecurityTestScreen({super.key});

  @override
  State<SecurityTestScreen> createState() => _SecurityTestScreenState();
}

class _SecurityTestScreenState extends State<SecurityTestScreen> {
  final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;
  String _testOutput = 'Ready to test security system...\n';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security System Test'),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              height: 300,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _testOutput,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_isLoading) 
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
              ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton(
                  onPressed: _isLoading ? null : _testInitialization,
                  child: const Text('Test Initialization'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _testPasscodeToggle,
                  child: const Text('Test Passcode Toggle'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _testAutoLock,
                  child: const Text('Test Auto-Lock'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _testLockMethod,
                  child: const Text('Test Lock Method'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _testBiometric,
                  child: const Text('Test Biometric'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _testLifecycle,
                  child: const Text('Test Lifecycle'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _clearTests,
                  child: const Text('Clear Output'),
                ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _runAllTests,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0BAB9B),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Run All Tests'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _addToOutput(String message) {
    setState(() {
      _testOutput += '${DateTime.now().toIso8601String().substring(11, 19)}: $message\n';
    });
  }

  void _clearTests() {
    setState(() {
      _testOutput = 'Output cleared...\n';
    });
  }

  Future<void> _testInitialization() async {
    setState(() => _isLoading = true);
    
    try {
      _addToOutput('🔒 Testing SecuritySettingsManager initialization...');
      
      await _securityManager.initialize();
      _addToOutput('✅ SecuritySettingsManager initialized successfully');
      
      final summary = await _securityManager.getSecuritySettingsSummary();
      _addToOutput('📋 Current settings:');
      _addToOutput('   Passcode Enabled: ${summary['passcodeEnabled']}');
      _addToOutput('   Auto-lock: ${summary['autoLockDurationText']}');
      _addToOutput('   Lock Method: ${summary['lockMethodText']}');
      _addToOutput('   Biometric Available: ${summary['biometricAvailable']}');
      _addToOutput('   Passcode Set: ${summary['passcodeSet']}');
      
    } catch (e) {
      _addToOutput('❌ Initialization test failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testPasscodeToggle() async {
    setState(() => _isLoading = true);
    
    try {
      _addToOutput('🔐 Testing passcode toggle...');
      
      // Test enabling passcode
      final enableResult = await _securityManager.setPasscodeEnabled(true);
      _addToOutput('✅ Passcode enable result: $enableResult');
      
      final isEnabled = await _securityManager.isPasscodeEnabled();
      _addToOutput('📋 Passcode enabled check: $isEnabled');
      
      // Test disabling passcode (might fail if biometric not available)
      final disableResult = await _securityManager.setPasscodeEnabled(false);
      _addToOutput('⚠️ Passcode disable result: $disableResult');
      
      final isDisabled = await _securityManager.isPasscodeEnabled();
      _addToOutput('📋 Passcode enabled check after disable: $isDisabled');
      
      // Re-enable for safety
      await _securityManager.setPasscodeEnabled(true);
      _addToOutput('🔒 Passcode re-enabled for safety');
      
    } catch (e) {
      _addToOutput('❌ Passcode toggle test failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testAutoLock() async {
    setState(() => _isLoading = true);
    
    try {
      _addToOutput('⏰ Testing auto-lock settings...');
      
      // Test all auto-lock durations
      final durations = [
        AutoLockDuration.immediate,
        AutoLockDuration.oneMinute,
        AutoLockDuration.fiveMinutes,
        AutoLockDuration.tenMinutes,
        AutoLockDuration.fifteenMinutes,
      ];
      
      for (final duration in durations) {
        await _securityManager.setAutoLockDuration(duration);
        final currentDuration = await _securityManager.getAutoLockDuration();
        final text = _securityManager.getAutoLockDurationText(currentDuration);
        _addToOutput('✅ Auto-lock set to: $text');
      }
      
      // Test background logic
      _addToOutput('📱 Testing background time logic...');
      await _securityManager.saveLastBackgroundTime();
      _addToOutput('✅ Background time saved');
      
      // Test immediate lock
      await _securityManager.setAutoLockDuration(AutoLockDuration.immediate);
      final shouldShowImmediate = await _securityManager.shouldShowPasscodeAfterBackground();
      _addToOutput('🔒 Should show passcode (immediate): $shouldShowImmediate');
      
      // Test 5-minute lock
      await _securityManager.setAutoLockDuration(AutoLockDuration.fiveMinutes);
      final shouldShow5Min = await _securityManager.shouldShowPasscodeAfterBackground();
      _addToOutput('🔒 Should show passcode (5 min): $shouldShow5Min');
      
    } catch (e) {
      _addToOutput('❌ Auto-lock test failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testLockMethod() async {
    setState(() => _isLoading = true);
    
    try {
      _addToOutput('🔐 Testing lock methods...');
      
      final lockMethods = [
        LockMethod.passcodeAndBiometric,
        LockMethod.passcodeOnly,
        LockMethod.biometricOnly,
      ];
      
      for (final method in lockMethods) {
        final result = await _securityManager.setLockMethod(method);
        if (result) {
          final currentMethod = await _securityManager.getLockMethod();
          final text = _securityManager.getLockMethodText(currentMethod);
          _addToOutput('✅ Lock method set to: $text');
        } else {
          final text = _securityManager.getLockMethodText(method);
          _addToOutput('❌ Could not set lock method to: $text');
        }
      }
      
      // Test capability checks
      final canUseBiometric = await _securityManager.canUseBiometricInCurrentLockMethod();
      final canUsePasscode = await _securityManager.canUsePasscodeInCurrentLockMethod();
      _addToOutput('📋 Can use biometric: $canUseBiometric');
      _addToOutput('📋 Can use passcode: $canUsePasscode');
      
    } catch (e) {
      _addToOutput('❌ Lock method test failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testBiometric() async {
    setState(() => _isLoading = true);
    
    try {
      _addToOutput('👆 Testing biometric authentication...');
      
      final isAvailable = await _securityManager.isBiometricAvailable();
      _addToOutput('📋 Biometric available: $isAvailable');
      
      if (isAvailable) {
        final biometrics = await _securityManager.getAvailableBiometrics();
        _addToOutput('📋 Available biometrics: ${biometrics.map((b) => b.name).join(', ')}');
        
        _addToOutput('🔒 Testing biometric authentication (will prompt)...');
        final authResult = await _securityManager.authenticateWithBiometric(
          reason: 'Testing biometric authentication in security test',
        );
        _addToOutput('🔒 Biometric auth result: $authResult');
      } else {
        _addToOutput('⚠️ Biometric not available on this device');
      }
      
    } catch (e) {
      _addToOutput('❌ Biometric test failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testLifecycle() async {
    setState(() => _isLoading = true);
    
    try {
      _addToOutput('🔄 Testing lifecycle management...');
      
      // Test startup check
      final shouldShowOnStartup = await _securityManager.shouldShowPasscodeOnStartup();
      _addToOutput('🚀 Should show passcode on startup: $shouldShowOnStartup');
      
      // Test background logic
      _addToOutput('📱 Simulating app going to background...');
      await _securityManager.saveLastBackgroundTime();
      _addToOutput('✅ Background time saved');
      
      // Simulate immediate return
      final shouldShowAfterBackground = await _securityManager.shouldShowPasscodeAfterBackground();
      _addToOutput('🔒 Should show passcode after background: $shouldShowAfterBackground');
      
      // Test authentication flow
      final canAuthenticate = await _securityManager.authenticate(reason: 'Testing authentication flow');
      _addToOutput('🔐 Authentication flow result: $canAuthenticate');
      
    } catch (e) {
      _addToOutput('❌ Lifecycle test failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _runAllTests() async {
    setState(() => _isLoading = true);
    
    try {
      _addToOutput('🧪 Running all security tests...');
      _addToOutput('=====================================');
      
      await _testInitialization();
      await Future.delayed(const Duration(milliseconds: 500));
      
      await _testPasscodeToggle();
      await Future.delayed(const Duration(milliseconds: 500));
      
      await _testAutoLock();
      await Future.delayed(const Duration(milliseconds: 500));
      
      await _testLockMethod();
      await Future.delayed(const Duration(milliseconds: 500));
      
      await _testBiometric();
      await Future.delayed(const Duration(milliseconds: 500));
      
      await _testLifecycle();
      
      _addToOutput('=====================================');
      _addToOutput('✅ All tests completed!');
      
    } catch (e) {
      _addToOutput('❌ Test suite failed: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
} 