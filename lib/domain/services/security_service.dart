import 'package:flutter/foundation.dart';
import '../../di/service_locator.dart';
import '../interfaces/i_security_manager.dart';
import '../interfaces/wallet_data_source.dart';
import '../../utils/secure_log.dart';

/// Domain service for security-related operations.
///
/// Wraps [ISecurityManager] to provide a clean domain-level API.
/// Uses [IWalletDataSource] for memory cache purging on lock.
/// Uses callbacks to notify AppProvider of lock/unlock state changes.
class SecurityService {
  // ==================== CALLBACK ====================
  VoidCallback? _onChange;

  /// Set callback to notify upstream (AppProvider) of state changes.
  void setOnChange(VoidCallback? callback) {
    _onChange = callback;
  }

  // ==================== DEPENDENCIES ====================
  final ISecurityManager _securityManager;
  final IWalletDataSource _storage;

  SecurityService({
    ISecurityManager? securityManager,
  }) : _securityManager = securityManager ?? ServiceLocator.get<ISecurityManager>(),
       _storage = ServiceLocator.get<IWalletDataSource>();

  // ==================== STATE ====================
  bool _isLocked = false;
  bool _isBiometricEnabled = false;
  int _autoLockTimeout = 0;

  // ==================== GETTERS ====================
  bool get isLocked => _isLocked;
  bool get isBiometricEnabled => _isBiometricEnabled;
  int get autoLockTimeout => _autoLockTimeout;

  // ==================== INITIALIZATION ====================
  Future<void> initialize({
    VoidCallback? onLock,
    VoidCallback? onUnlock,
    VoidCallback? onBackground,
    VoidCallback? onForeground,
  }) async {
    try {
      await _securityManager.initialize();

      // Load initial state
      _isBiometricEnabled = await _securityManager.isBiometricAvailable();
      _autoLockTimeout = 0;

      SecureLog.d('SecurityService initialized');
    } catch (e) {
      SecureLog.e('Error initializing SecurityService', error: e);
    }
  }

  // ==================== LOCK / UNLOCK ====================
  void lockApp() {
    _isLocked = true;
    _storage.clearMemoryCache();
    _notifyChange();
  }

  void unlockApp() {
    _isLocked = false;
    _notifyChange();
  }

  // ==================== AUTO-LOCK TIMEOUT ====================
  Future<void> setAutoLockTimeout(int minutes) async {
    _autoLockTimeout = minutes;
    await _securityManager.setAutoLockTimeout(minutes);
    _notifyChange();
  }

  // ==================== BIOMETRIC ====================
  Future<void> setBiometricEnabled(bool enabled) async {
    _isBiometricEnabled = enabled;
    await _securityManager.setPasscodeEnabled(enabled);
    _notifyChange();
  }

  Future<bool> isBiometricSupported() async {
    return await _securityManager.isBiometricAvailable();
  }

  Future<bool> isFaceIdSupported() async {
    return await _securityManager.isFaceIdSupported();
  }

  // ==================== DEVICE INFO ====================
  Future<Map<String, dynamic>> getDeviceInfo() async {
    return await _securityManager.getSecuritySettingsSummary();
  }

  // ==================== DATA CLEAR ====================
  Future<void> clearData() async {
    await _securityManager.clearSecuritySettings();
    _isLocked = false;
    _isBiometricEnabled = false;
    _autoLockTimeout = 0;
    _notifyChange();
  }

  // ==================== PASSCODE ====================
  Future<bool> isPasscodeSet() async {
    return await _securityManager.isPasscodeSet();
  }

  Future<bool> shouldShowPasscodeAfterBackground() async {
    return await _securityManager.shouldShowPasscodeAfterBackground();
  }

  Future<void> saveLastBackgroundTime() async {
    await _securityManager.saveLastBackgroundTime();
  }

  Future<void> clearLastBackgroundTime() async {
    await _securityManager.clearLastBackgroundTime();
  }

  // ==================== INTERNAL ====================
  void _notifyChange() {
    _onChange?.call();
  }
}
