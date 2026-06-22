import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import '../di/service_locator.dart';
import '../domain/interfaces/i_security_manager.dart';
import '../utils/secure_log.dart';
import 'passcode_manager.dart';
import 'wallet_state_manager.dart';

class SecuritySettingsManager implements ISecurityManager {
  static SecuritySettingsManager get instance => ServiceLocator.get<SecuritySettingsManager>();
  
  SecuritySettingsManager._();
  /// DI constructor. Use [instance] for singleton access.
  SecuritySettingsManager();

  static const String _passcodeEnabledKey = 'passcode_enabled';
  static const String _autoLockDurationKey = 'auto_lock_duration';
  static const String _lockMethodKey = 'lock_method';
  static const String _lastBackgroundTimeKey = 'last_background_time';
  static const String _lastActivityTimeKey = 'last_activity_time';
  static const String _lastActivityElapsedKey = 'last_activity_elapsed';
  static const String _lastBootCountKey = 'last_boot_count';
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _securityInitializedKey = 'security_initialized';

  final LocalAuthentication _localAuth = LocalAuthentication();

  /// TRUST WALLET STANDARD: Security-first initialization
  @override
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // TRUST WALLET STANDARD: Always default to TRUE (security first)
      // Only becomes false when user explicitly disables it
      if (!prefs.containsKey(_passcodeEnabledKey)) {
        await prefs.setBool(_passcodeEnabledKey, true);
        SecureLog.i('Set default passcode_enabled = TRUE (security first)');
      } else {
        // TRUST WALLET FIX: If passcode exists but toggle is OFF, reset to ON
        final hasPasscode = await PasscodeManager.isPasscodeSet();
        final currentToggle = prefs.getBool(_passcodeEnabledKey) ?? true;
        
        if (hasPasscode && !currentToggle) {
          await prefs.setBool(_passcodeEnabledKey, true);
          SecureLog.w('Passcode exists but toggle was OFF - reset to ON');
        }
      }
      
      if (!prefs.containsKey(_autoLockDurationKey)) {
        await prefs.setInt(_autoLockDurationKey, AutoLockDuration.immediate.index);
        SecureLog.i('Set default auto_lock_duration: immediate');
      }
      
      if (!prefs.containsKey(_lockMethodKey)) {
        await prefs.setInt(_lockMethodKey, LockMethod.passcodeAndBiometric.index);
        SecureLog.i('Set default lock_method: passcodeAndBiometric');
      }
      
      SecureLog.i('SecuritySettingsManager initialize completed');
    } catch (e) {
      SecureLog.e('Error in SecuritySettingsManager.initialize', error: e);
    }
  }

  /// FORCE RE-INITIALIZATION (for debugging only)
  static void forceReinitialization() {
    SecureLog.i('FORCED re-initialization - this method is now simplified');
  }

  /// Reset security settings to default values
  Future<void> resetSecuritySettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // حذف تمام کلیدهای امنیتی
      await prefs.remove(_passcodeEnabledKey);
      await prefs.remove(_autoLockDurationKey);
      await prefs.remove(_lockMethodKey);
      await prefs.remove(_lastBackgroundTimeKey);
      await prefs.remove(_biometricEnabledKey);
      await prefs.remove(_securityInitializedKey);
      
      SecureLog.i('Security settings reset to defaults');
      
      // مجدداً initialize کن
      await initialize();
    } catch (e) {
      SecureLog.e('Error resetting security settings', error: e);
    }
  }

  /// نمایش تنظیمات فعلی برای debugging
  Future<void> _debugCurrentSettings() async {
    try {
      final summary = await getSecuritySettingsSummary();
      SecureLog.i('Current Security Settings - Passcode Enabled: ${summary['passcodeEnabled']}');
      SecureLog.d('Auto-lock: ${summary['autoLockDurationText']}');
      SecureLog.d('Lock Method: ${summary['lockMethodText']}');
      SecureLog.d('Biometric Available: ${summary['biometricAvailable']}');
      SecureLog.d('Passcode Set: ${summary['passcodeSet']}');
    } catch (e) {
      SecureLog.e('Error debugging settings', error: e);
    }
  }

  /// Debug method to check current security settings state
  Future<void> debugSecurityState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      SecureLog.d('SECURITY SETTINGS DEBUG ===');
      SecureLog.d('_passcodeEnabledKey exists: ${prefs.containsKey(_passcodeEnabledKey)}');
      SecureLog.d('_passcodeEnabledKey value: ${prefs.getBool(_passcodeEnabledKey)}');
      SecureLog.d('_securityInitializedKey: ${prefs.getBool(_securityInitializedKey)}');
      SecureLog.d('PasscodeManager.isPasscodeSet(): ${await PasscodeManager.isPasscodeSet()}');
      
      final isEnabled = await isPasscodeEnabled();
      SecureLog.d('Final isPasscodeEnabled(): $isEnabled');
      SecureLog.d('================================');
    } catch (e) {
      SecureLog.e('Error in debugSecurityState', error: e);
    }
  }

  // ================ PASSCODE TOGGLE ================
  
  /// فعال/غیرفعال کردن passcode
  @override
  Future<bool> setPasscodeEnabled(bool enabled) async {
    try {
      if (!enabled) {
        final hasWallet = await ServiceLocator.get<WalletStateManager>().hasValidWallet();
        if (hasWallet) {
          return false;
        }
      }
      SecureLog.i('Setting passcode enabled: $enabled');
      
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
      
      // DEBUG: Check before saving
      final oldValue = prefs.getBool(_passcodeEnabledKey);
      SecureLog.d('Old passcode enabled value: $oldValue');
      
      // CRITICAL: Force immediate write to disk with retry mechanism
      try {
        await prefs.setBool(_passcodeEnabledKey, enabled).timeout(const Duration(seconds: 3));
        SecureLog.d('setBool completed - automatically persisted');
      } catch (e) {
        SecureLog.e('First setBool attempt failed - retrying...', error: e);
        await Future.delayed(const Duration(milliseconds: 100));
        await prefs.setBool(_passcodeEnabledKey, enabled).timeout(const Duration(seconds: 3));
        SecureLog.d('setBool retry successful');
      }
      
      // DEBUG: Verify after saving
      final newValue = prefs.getBool(_passcodeEnabledKey);
      SecureLog.d('New passcode enabled value: $newValue (expected: $enabled)');
      
      // DEBUG: Ensure it's actually written
      await prefs.reload();
      final reloadedValue = prefs.getBool(_passcodeEnabledKey);
      SecureLog.d('Reloaded passcode enabled value: $reloadedValue');
      
      // EXTREME DEBUG: Check all keys
      final allKeys = prefs.getKeys();
      SecureLog.d('All SharedPreferences keys: $allKeys');
      SecureLog.d('Contains $_passcodeEnabledKey: ${allKeys.contains(_passcodeEnabledKey)}');
      
      // اگر passcode غیرفعال شد، lock method را مدیریت کن
      if (!enabled) {
        final lockMethod = await getLockMethod();
        final biometricAvailable = await isBiometricAvailable();
        
        if (lockMethod == LockMethod.passcodeOnly) {
          if (biometricAvailable) {
            // اگر biometric در دسترس است، به biometric only تغییر بده
            await setLockMethod(LockMethod.biometricOnly);
            SecureLog.i('Changed lock method to biometric only');
          } else {
            // اگر biometric در دسترس نیست، همچنان passcode را غیرفعال کن
            // در این حالت، اپلیکیشن بدون احراز هویت کار می‌کند
            SecureLog.i('Passcode disabled - app will work without authentication');
          }
        } else if (lockMethod == LockMethod.passcodeAndBiometric) {
          if (biometricAvailable) {
            // تغییر به biometric only
            await setLockMethod(LockMethod.biometricOnly);
            SecureLog.i('Changed lock method to biometric only');
          } else {
            // اگر biometric در دسترس نیست، همچنان passcode را غیرفعال کن
            SecureLog.i('Passcode disabled - app will work without authentication');
          }
        }
        // در هر حالت، passcode غیرفعال می‌ماند
      }
      
      SecureLog.d('Passcode enabled setting saved');
      await _debugCurrentSettings(); // نمایش تنظیمات بعد از تغییر
      return true;
    } catch (e) {
      SecureLog.e('Error setting passcode enabled', error: e);
      return false;
    }
  }

  /// TRUST WALLET STANDARD: Check if passcode toggle is enabled
  @override
  Future<bool> isPasscodeEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_passcodeEnabledKey) ?? true;
    } catch (e) {
      return true;
    }
  }

  // ================ AUTO-LOCK DURATION ================

  /// تنظیم مدت زمان auto-lock
  Future<void> setAutoLockDuration(AutoLockDuration duration) async {
    try {
      SecureLog.i('Setting auto-lock duration: ${getAutoLockDurationText(duration)}');
      
      final prefs = await SharedPreferences.getInstance();
      
      // DEBUG: Check before saving
      final oldValue = prefs.getInt(_autoLockDurationKey);
      SecureLog.d('Old auto-lock value: $oldValue');
      
      // CRITICAL: Force immediate write to disk
      await prefs.setInt(_autoLockDurationKey, duration.index);
      // Note: commit() is deprecated in newer Flutter versions - setInt already persists immediately
      SecureLog.d('setInt completed - automatically persisted');
      
      // DEBUG: Verify after saving
      final newValue = prefs.getInt(_autoLockDurationKey);
      SecureLog.d('New auto-lock value: $newValue (expected: ${duration.index})');
      
      // DEBUG: Ensure it's actually written
      await prefs.reload();
      final reloadedValue = prefs.getInt(_autoLockDurationKey);
      SecureLog.d('Reloaded auto-lock value: $reloadedValue');
      
      // EXTREME DEBUG: Check all keys
      final allKeys = prefs.getKeys();
      SecureLog.d('All SharedPreferences keys: $allKeys');
      SecureLog.d('Contains $_autoLockDurationKey: ${allKeys.contains(_autoLockDurationKey)}');
      
      SecureLog.i('Auto-lock duration saved: ${getAutoLockDurationText(duration)}');
      await _debugCurrentSettings(); // نمایش تنظیمات بعد از تغییر
    } catch (e) {
      SecureLog.e('Error setting auto-lock duration', error: e);
    }
  }

  /// دریافت مدت زمان auto-lock
  Future<AutoLockDuration> getAutoLockDuration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(_autoLockDurationKey) ?? AutoLockDuration.immediate.index;
      final duration = AutoLockDuration.values[index];
      SecureLog.i('Auto-lock duration check: ${getAutoLockDurationText(duration)}');
      return duration;
    } catch (e) {
      SecureLog.e('Error getting auto-lock duration', error: e);
      return AutoLockDuration.immediate;
    }
  }

  /// تبدیل AutoLockDuration به میلی‌ثانیه
  int getAutoLockDurationInMilliseconds(AutoLockDuration duration) {
    switch (duration) {
      case AutoLockDuration.immediate:
        return 0;
      case AutoLockDuration.oneMinute:
        return 60 * 1000;
      case AutoLockDuration.fiveMinutes:
        return 5 * 60 * 1000;
      case AutoLockDuration.tenMinutes:
        return 10 * 60 * 1000;
      case AutoLockDuration.fifteenMinutes:
        return 15 * 60 * 1000;
    }
  }

  /// تبدیل AutoLockDuration به متن قابل نمایش
  String getAutoLockDurationText(AutoLockDuration duration) {
    switch (duration) {
      case AutoLockDuration.immediate:
        return 'Immediate';
      case AutoLockDuration.oneMinute:
        return '1 Min';
      case AutoLockDuration.fiveMinutes:
        return '5 Min';
      case AutoLockDuration.tenMinutes:
        return '10 Min';
      case AutoLockDuration.fifteenMinutes:
        return '15 Min';
    }
  }

  // ================ LOCK METHOD ================

  /// تنظیم روش قفل
  Future<bool> setLockMethod(LockMethod method) async {
    try {
      SecureLog.d('Setting lock method: ${getLockMethodText(method)}');
      
      // بررسی در دسترس بودن biometric برای روش‌های مربوطه
      if (method == LockMethod.biometricOnly || method == LockMethod.passcodeAndBiometric) {
        final biometricAvailable = await isBiometricAvailable();
        if (!biometricAvailable) {
          SecureLog.e('Biometric not available, cannot set lock method to: $method');
          return false;
        }
      }

      // بررسی وجود passcode برای روش‌های مربوطه
      if (method == LockMethod.passcodeOnly || method == LockMethod.passcodeAndBiometric) {
        final passcodeSet = await PasscodeManager.isPasscodeSet();
        if (!passcodeSet) {
          SecureLog.w('Passcode not set, cannot set lock method to: $method');
          return false;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lockMethodKey, method.index);
      
      SecureLog.d('Lock method saved: ${getLockMethodText(method)}');
      await _debugCurrentSettings(); // نمایش تنظیمات بعد از تغییر
      return true;
    } catch (e) {
      SecureLog.e('Error setting lock method', error: e);
      return false;
    }
  }

  /// دریافت روش قفل
  Future<LockMethod> getLockMethod() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = prefs.getInt(_lockMethodKey) ?? LockMethod.passcodeAndBiometric.index;
      final method = LockMethod.values[index];
      SecureLog.d('Lock method check: ${getLockMethodText(method)}');
      return method;
    } catch (e) {
      SecureLog.e('Error getting lock method', error: e);
      return LockMethod.passcodeAndBiometric;
    }
  }

  /// تبدیل LockMethod به متن قابل نمایش
  String getLockMethodText(LockMethod method) {
    switch (method) {
      case LockMethod.passcodeAndBiometric:
        return 'Passcode / Biometric';
      case LockMethod.passcodeOnly:
        return 'Passcode Only';
      case LockMethod.biometricOnly:
        return 'Biometric Only';
    }
  }

  // ================ BIOMETRIC MANAGEMENT ================

  /// بررسی در دسترس بودن biometric
  @override
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      
      final available = canCheck && isDeviceSupported && availableBiometrics.isNotEmpty;
      SecureLog.d('Biometric availability check: $available');
      return available;
    } catch (e) {
      SecureLog.e('Error checking biometric availability', error: e);
      return false;
    }
  }

  /// دریافت نوع‌های biometric موجود
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      SecureLog.e('Error getting available biometrics', error: e);
      return [];
    }
  }

  /// احراز هویت biometric
  @override
  Future<bool> authenticateWithBiometric({String? reason}) async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        SecureLog.e('Biometric authentication not available');
        return false;
      }

      SecureLog.d('Starting biometric authentication...');
      final result = await _localAuth.authenticate(
        localizedReason: reason ?? 'Authenticate to access your wallet',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      
      SecureLog.d('Biometric authentication result: $result');
      return result;
    } catch (e) {
      SecureLog.e('Error authenticating with biometric', error: e);
      return false;
    }
  }

  // ================ AUTO-LOCK LOGIC ================

  /// ذخیره زمان رفتن به پس‌زمینه
  @override
  Future<void> saveLastBackgroundTime() async {
    try {
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastBackgroundTimeKey, currentTime);
      SecureLog.d('Background time saved');
    } catch (e) {
      SecureLog.e('Error saving last background time', error: e);
    }
  }

  /// After a successful unlock/setup, suppress auto-lock until the app backgrounds again.
  @override
  Future<void> clearLastBackgroundTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastBackgroundTimeKey);
      SecureLog.d('Cleared last background time (session unlocked)');
    } catch (e) {
      SecureLog.e('Error clearing last background time', error: e);
    }
  }

  /// بررسی نیاز به نمایش passcode بعد از بازگشت از پس‌زمینه
  @override
  Future<bool> shouldShowPasscodeAfterBackground() async {
    try {
      SecureLog.d('Checking if should show passcode after background...');
      
      // بررسی فعال بودن passcode
      final passcodeEnabled = await isPasscodeEnabled();
      if (!passcodeEnabled) {
        SecureLog.d('Passcode disabled, no need to show');
        return false;
      }

      if (!await PasscodeManager.isPasscodeSet()) {
        SecureLog.d('No passcode set, no need to show');
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      final lastBackgroundTime = prefs.getInt(_lastBackgroundTimeKey);

      if (lastBackgroundTime == null) {
        SecureLog.d('No background time recorded, no need to show passcode');
        return false;
      }

      // دریافت مدت زمان auto-lock
      final autoLockDuration = await getAutoLockDuration();
      final autoLockMs = getAutoLockDurationInMilliseconds(autoLockDuration);
      
      SecureLog.d('Auto-lock setting checked');

      final currentTime = DateTime.now().millisecondsSinceEpoch;
      final timeDiff = currentTime - lastBackgroundTime;
      
      SecureLog.d('Time in background checked');
      
      final shouldShow = timeDiff >= autoLockMs;
      SecureLog.d('Should show passcode: $shouldShow');
      
      return shouldShow;
    } catch (e) {
      SecureLog.e('Error checking should show passcode', error: e);
      return false;
    }
  }

  /// بررسی نیاز به نمایش passcode در startup
  Future<bool> shouldShowPasscodeOnStartup() async {
    try {
      final passcodeEnabled = await isPasscodeEnabled();
      return passcodeEnabled;
    } catch (e) {
      return true;
    }
  }

  // ================ AUTHENTICATION LOGIC ================

  /// احراز هویت بر اساس lock method انتخاب شده
  Future<bool> authenticate({String? reason}) async {
    try {
      final lockMethod = await getLockMethod();
      final passcodeEnabled = await isPasscodeEnabled();

      SecureLog.d('Authentication requested');

      // اگر passcode غیرفعال است، هیچ احراز هویتی نیاز نیست
      if (!passcodeEnabled) {
        SecureLog.d('Passcode disabled - authentication not required');
        return true;
      }

      switch (lockMethod) {
        case LockMethod.passcodeAndBiometric:
          // کاربر می‌تواند با هر دو روش احراز هویت کند
          // اینجا فقط true برمی‌گردانیم تا UI مناسب نمایش داده شود
          SecureLog.d('Passcode + Biometric method - UI should handle both');
          return true;
          
        case LockMethod.passcodeOnly:
          // فقط passcode screen نمایش داده می‌شود
          SecureLog.d('Passcode only method - UI should show passcode');
          return true;
          
        case LockMethod.biometricOnly:
          // فقط biometric احراز هویت
          SecureLog.d('Biometric only method - attempting biometric auth');
          return await authenticateWithBiometric(reason: reason);
      }
    } catch (e) {
      SecureLog.e('Error in authenticate', error: e);
      return false;
    }
  }

  /// بررسی امکان استفاده از biometric در lock method فعلی
  Future<bool> canUseBiometricInCurrentLockMethod() async {
    try {
      final lockMethod = await getLockMethod();
      final canUse = lockMethod == LockMethod.biometricOnly || 
             lockMethod == LockMethod.passcodeAndBiometric;
      SecureLog.d('Can use biometric in current method: $canUse');
      return canUse;
    } catch (e) {
      SecureLog.e('Error checking can use biometric', error: e);
      return false;
    }
  }

  /// بررسی امکان استفاده از passcode در lock method فعلی
  Future<bool> canUsePasscodeInCurrentLockMethod() async {
    try {
      final lockMethod = await getLockMethod();
      final canUse = lockMethod == LockMethod.passcodeOnly || 
             lockMethod == LockMethod.passcodeAndBiometric;
      SecureLog.d('Can use passcode in current method: $canUse');
      return canUse;
    } catch (e) {
      SecureLog.e('Error checking can use passcode', error: e);
      return false;
    }
  }

  // ================ ACTIVITY TIMER METHODS ================

  /// Reset activity timer - call this on real user interactions
  Future<void> resetActivityTimer() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
      final now = DateTime.now();
      final nowMillis = now.millisecondsSinceEpoch;
      
      // Save both wall clock and elapsed time for robust tracking
      await prefs.setInt(_lastActivityTimeKey, nowMillis)
          .timeout(const Duration(seconds: 2));
      
      SecureLog.d('Activity timer reset');
      SecureLog.d('Timestamp saved');
    } catch (e) {
      SecureLog.e('Error resetting activity timer', error: e);
      // Don't rethrow - let the app continue
    }
  }

  /// Get time since last activity in milliseconds
  Future<int> getTimeSinceLastActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastActivityTime = prefs.getInt(_lastActivityTimeKey);
      
      if (lastActivityTime == null) {
        SecureLog.d('No last activity time found - treating as expired');
        return Duration.millisecondsPerDay; // Force timeout
      }
      
      final now = DateTime.now().millisecondsSinceEpoch;
      final timeSince = now - lastActivityTime;
      
      SecureLog.d('Time since last activity checked');
      return timeSince;
    } catch (e) {
      SecureLog.e('Error getting time since last activity', error: e);
      return Duration.millisecondsPerDay; // Safe fallback - force timeout
    }
  }

  /// Get time since last background in milliseconds
  Future<int> getTimeSinceLastBackground() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastBackgroundTime = prefs.getInt(_lastBackgroundTimeKey);
      
      if (lastBackgroundTime == null) {
        SecureLog.d('No last background time found');
        return 0; // No background event recorded
      }
      
      final now = DateTime.now().millisecondsSinceEpoch;
      final timeSince = now - lastBackgroundTime;
      
      SecureLog.d('Time since last background checked');
      return timeSince;
    } catch (e) {
      SecureLog.e('Error getting time since last background', error: e);
      return 0;
    }
  }

  /// TRUST WALLET STANDARD: Check if passcode should be shown
  Future<bool> shouldShowPasscodeNow() async {
    try {
      final isPasscodeEnabled = await this.isPasscodeEnabled();
      final hasPasscode = await PasscodeManager.isPasscodeSet();
      
      SecureLog.d('TRUST WALLET: shouldShowPasscodeNow check');
      
      // TRUST WALLET LOGIC: Both conditions must be true
      if (!isPasscodeEnabled) {
        SecureLog.d('TRUST WALLET: Passcode disabled by user - skip protection');
        return false;
      }
      
      if (!hasPasscode) {
        SecureLog.w('TRUST WALLET: No passcode set - cannot protect');
        return false;
      }
      
      // TRUST WALLET: Show passcode when both enabled and set
      SecureLog.d('TRUST WALLET: Show passcode protection');
      return true;
      
    } catch (e) {
      SecureLog.e('Error in shouldShowPasscodeNow', error: e);
      return false; // TRUST WALLET: Safe fallback (no protection)
    }
  }

  /// Convert AutoLockDuration to milliseconds
  int _getAutoLockTimeoutMs(AutoLockDuration duration) {
    switch (duration) {
      case AutoLockDuration.immediate:
        return 0; // Immediate
      case AutoLockDuration.oneMinute:
        return 60 * 1000; // 1 minute
      case AutoLockDuration.fiveMinutes:
        return 5 * 60 * 1000; // 5 minutes
      case AutoLockDuration.tenMinutes:
        return 10 * 60 * 1000; // 10 minutes
      case AutoLockDuration.fifteenMinutes:
        return 15 * 60 * 1000; // 15 minutes
    }
  }

  // ================ UTILITY METHODS ================

  /// COMPREHENSIVE PERSISTENCE TEST
  Future<void> comprehensivePersistenceTest() async {
    try {
      SecureLog.d('=== COMPREHENSIVE PERSISTENCE TEST ===');
      
      final prefs = await SharedPreferences.getInstance();
      
      // Step 1: Show current values
      SecureLog.d('STEP 1: Current values');
      SecureLog.d('  passcode_enabled: ${prefs.getBool(_passcodeEnabledKey)}');
      SecureLog.d('  auto_lock_duration: ${prefs.getInt(_autoLockDurationKey)}');
      SecureLog.d('  lock_method: ${prefs.getInt(_lockMethodKey)}');
      
      // Step 2: Modify values to test values
      SecureLog.d('STEP 2: Setting test values');
      await prefs.setBool(_passcodeEnabledKey, false);
      await prefs.setInt(_autoLockDurationKey, AutoLockDuration.fiveMinutes.index);
      await prefs.setInt(_lockMethodKey, LockMethod.biometricOnly.index);
      
      // Step 3: Verify immediate read
      SecureLog.d('STEP 3: Verify immediate read');
      SecureLog.d('  passcode_enabled: ${prefs.getBool(_passcodeEnabledKey)} (expected: false)');
      SecureLog.d('  auto_lock_duration: ${prefs.getInt(_autoLockDurationKey)} (expected: ${AutoLockDuration.fiveMinutes.index})');
      SecureLog.d('  lock_method: ${prefs.getInt(_lockMethodKey)} (expected: ${LockMethod.biometricOnly.index})');
      
      // Step 4: Force reload from disk
      SecureLog.d('STEP 4: Force reload from disk');
      await prefs.reload();
      SecureLog.d('  passcode_enabled: ${prefs.getBool(_passcodeEnabledKey)} (after reload)');
      SecureLog.d('  auto_lock_duration: ${prefs.getInt(_autoLockDurationKey)} (after reload)');
      SecureLog.d('  lock_method: ${prefs.getInt(_lockMethodKey)} (after reload)');
      
      // Step 5: Test multiple initialize() calls
      SecureLog.d('STEP 5: Test multiple initialize() calls');
      SecuritySettingsManager.forceReinitialization();
      await initialize();
      SecureLog.d('  First init done');
      await initialize();
      SecureLog.d('  Second init done (should be skipped)');
      await initialize();
      SecureLog.d('  Third init done (should be skipped)');
      
      // Step 6: Final values check
      SecureLog.d('STEP 6: Final values check');
      SecureLog.d('  passcode_enabled: ${prefs.getBool(_passcodeEnabledKey)}');
      SecureLog.d('  auto_lock_duration: ${prefs.getInt(_autoLockDurationKey)}');
      SecureLog.d('  lock_method: ${prefs.getInt(_lockMethodKey)}');
      
      SecureLog.d('=== COMPREHENSIVE TEST COMPLETED ===');
      
    } catch (e) {
      SecureLog.e('Error in comprehensive persistence test', error: e);
    }
  }

  /// Advanced debugging for Android storage behavior
  Future<void> debugAndroidStorageBehavior() async {
    try {
      SecureLog.d('=== ANDROID STORAGE DEBUG ===');
      
      final prefs = await SharedPreferences.getInstance();
      
      // Create a persistent test value
      const testKey = 'android_persistence_test';
      final testValue = 'test_${DateTime.now().millisecondsSinceEpoch}';
      
      SecureLog.d('Setting test value');
      await prefs.setString(testKey, testValue);
      // Note: commit() is deprecated - setString already persists
      
      // Verify immediate read
      final immediateRead = prefs.getString(testKey);
      SecureLog.d('Immediate read checked');
      
      // Force reload from disk
      await prefs.reload();
      final reloadRead = prefs.getString(testKey);
      SecureLog.d('After reload checked');
      
      // Check SharedPreferences file path (Android specific)
      SecureLog.d('NOTE: Kill app now and restart to test persistence!');
      SecureLog.d('Expected value after restart');
      
      // Check all security values
      SecureLog.d('Current security values:');
      SecureLog.d('  - passcode_enabled: ${prefs.getBool(_passcodeEnabledKey)}');
      SecureLog.d('  - auto_lock_duration: ${prefs.getInt(_autoLockDurationKey)}');
      SecureLog.d('  - lock_method: ${prefs.getInt(_lockMethodKey)}');
      SecureLog.d('  - security_initialized: ${prefs.getBool(_securityInitializedKey)}');
      
      SecureLog.d('=== END ANDROID DEBUG ===');
    } catch (e) {
      SecureLog.e('Error in Android storage debug', error: e);
    }
  }

  /// Test SharedPreferences persistence for debugging
  Future<void> testSharedPreferencesPersistence() async {
    try {
      SecureLog.d('=== TESTING SHARED PREFERENCES PERSISTENCE ===');
      
      final prefs = await SharedPreferences.getInstance();
      
      // Test writing and reading a test value
      const testKey = 'test_persistence_key';
      const testValue = 'test_persistence_value';
      
      SecureLog.d('Writing test value...');
      await prefs.setString(testKey, testValue);
      // Note: commit() is deprecated - setString already persists
      
      SecureLog.d('Reading test value...');
      final readValue = prefs.getString(testKey);
      SecureLog.d('Read value verified');
      
      // Test reload
      SecureLog.d('Testing reload...');
      await prefs.reload();
      final reloadedValue = prefs.getString(testKey);
      SecureLog.d('Reloaded value verified');
      
      // Show all security keys
      SecureLog.d('All security keys:');
      SecureLog.d('   $_passcodeEnabledKey: ${prefs.getBool(_passcodeEnabledKey)}');
      SecureLog.d('   $_autoLockDurationKey: ${prefs.getInt(_autoLockDurationKey)}');
      SecureLog.d('   $_lockMethodKey: ${prefs.getInt(_lockMethodKey)}');
      SecureLog.d('   $_securityInitializedKey: ${prefs.getBool(_securityInitializedKey)}');
      
      // Show ALL keys (to see if there's interference)
      final allKeys = prefs.getKeys();
      SecureLog.d('ALL SharedPreferences keys checked');
      
      // Test immediate write stress test
      SecureLog.d('=== STRESS TEST: Write multiple values ===');
      const stressTestKey = 'stress_test_';
      for (int i = 0; i < 5; i++) {
        final key = '$stressTestKey$i';
        final value = 'value_$i';
        await prefs.setString(key, value);
        // Note: commit() is deprecated - setString already persists
        final readBack = prefs.getString(key);
        SecureLog.d('Stress test iteration completed');
      }
      
      // Clean up
      for (int i = 0; i < 5; i++) {
        await prefs.remove('$stressTestKey$i');
      }
      await prefs.remove(testKey);
      // Note: commit() is deprecated - remove already persists
      
      SecureLog.d('=== END SHARED PREFERENCES TEST ===');
      
    } catch (e) {
      SecureLog.e('Error testing SharedPreferences persistence', error: e);
    }
  }

  // ================ DOMAIN INTERFACE METHODS ================

  @override
  Future<void> setAutoLockTimeout(int minutes) async {
    AutoLockDuration duration;
    if (minutes <= 0) {
      duration = AutoLockDuration.immediate;
    } else if (minutes <= 1) {
      duration = AutoLockDuration.oneMinute;
    } else if (minutes <= 5) {
      duration = AutoLockDuration.fiveMinutes;
    } else if (minutes <= 10) {
      duration = AutoLockDuration.tenMinutes;
    } else {
      duration = AutoLockDuration.fifteenMinutes;
    }
    await setAutoLockDuration(duration);
  }

  @override
  Future<bool> isPasscodeSet() async {
    return PasscodeManager.isPasscodeSet();
  }

  @override
  Future<bool> isFaceIdSupported() async {
    try {
      final biometrics = await getAvailableBiometrics();
      return biometrics.any((b) => b == BiometricType.face);
    } catch (e) {
      return false;
    }
  }

  /// پاک کردن تمام تنظیمات امنیتی
  @override
  Future<void> clearSecuritySettings() async {
    try {
      SecureLog.d('Clearing all security settings...');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_passcodeEnabledKey);
      await prefs.remove(_autoLockDurationKey);
      await prefs.remove(_lockMethodKey);
      await prefs.remove(_lastBackgroundTimeKey);
      await prefs.remove(_biometricEnabledKey);
      await prefs.remove(_securityInitializedKey);
      
      // پاک کردن passcode
      await PasscodeManager.clearPasscode();
      
      SecureLog.d('All security settings cleared');
    } catch (e) {
      SecureLog.e('Error clearing security settings', error: e);
    }
  }

  /// دریافت خلاصه تنظیمات امنیتی
  @override
  Future<Map<String, dynamic>> getSecuritySettingsSummary() async {
    try {
      final passcodeEnabled = await isPasscodeEnabled();
      final autoLockDuration = await getAutoLockDuration();
      final lockMethod = await getLockMethod();
      final biometricAvailable = await isBiometricAvailable();
      final passcodeSet = await PasscodeManager.isPasscodeSet();

      return {
        'passcodeEnabled': passcodeEnabled,
        'autoLockDuration': autoLockDuration,
        'autoLockDurationText': getAutoLockDurationText(autoLockDuration),
        'lockMethod': lockMethod,
        'lockMethodText': getLockMethodText(lockMethod),
        'biometricAvailable': biometricAvailable,
        'passcodeSet': passcodeSet,
      };
    } catch (e) {
      SecureLog.e('Error getting security settings summary', error: e);
      return {};
    }
  }
}