import 'package:flutter/material.dart';
import 'dart:async';
import '../di/service_locator.dart';
import 'secure_storage.dart';
import 'secure_memory_cache.dart';
import '../utils/secure_log.dart';

/// مدیریت چرخه حیات اپلیکیشن برای تمام پلتفرم‌ها
class LifecycleManager {
  LifecycleManager();

  LifecycleManager._();

  static LifecycleManager get instance => ServiceLocator.get<LifecycleManager>();
  
  Timer? _autoLockTimer;
  DateTime? _lastBackgroundTime;
  bool _isLocked = false;
  int _autoLockTimeoutMinutes = 5; // پیش‌فرض 5 دقیقه
  
  // Callbacks
  VoidCallback? _onLock;
  VoidCallback? _onUnlock;
  VoidCallback? _onBackground;
  VoidCallback? _onForeground;
  
  /// مقداردهی اولیه
  Future<void> initialize({
    VoidCallback? onLock,
    VoidCallback? onUnlock,
    VoidCallback? onBackground,
    VoidCallback? onForeground,
  }) async {
    _onLock = onLock;
    _onUnlock = onUnlock;
    _onBackground = onBackground;
    _onForeground = onForeground;
    
    // بارگذاری تنظیمات قفل خودکار
    await _loadAutoLockSettings();
    
    SecureLog.i('LifecycleManager initialized with ${_autoLockTimeoutMinutes}min timeout');
  }
  
  /// تنظیم timeout قفل خودکار
  Future<void> setAutoLockTimeout(int minutes) async {
    _autoLockTimeoutMinutes = minutes;
    await ServiceLocator.get<SecureStorage>().saveSecureData('auto_lock_timeout', minutes.toString());
    SecureLog.i('Auto-lock timeout set to $minutes minutes');
  }
  
  /// دریافت timeout قفل خودکار
  int get autoLockTimeout => _autoLockTimeoutMinutes;
  
  /// بررسی وضعیت قفل
  bool get isLocked => _isLocked;
  
  /// قفل کردن اپلیکیشن
  void lockApp() {
    if (!_isLocked) {
      // 🛡️ پاک‌سازی فوری کش حافظه قبل از قفل
      ServiceLocator.get<SecureStorage>().clearMemoryCache();
      ServiceLocator.get<SecureMemoryCache>().evictAll();

      _isLocked = true;
      _onLock?.call();
      SecureLog.i('App locked — memory cache cleared');
    }
  }
  
  /// باز کردن قفل اپلیکیشن
  void unlockApp() {
    if (_isLocked) {
      _isLocked = false;
      _onUnlock?.call();
      SecureLog.i('App unlocked');
    }
  }
  
  /// مدیریت ورود به پس‌زمینه
  void onBackground() {
    _lastBackgroundTime = DateTime.now();
    // 🛡️ پاک‌سازی کش حافظه هنگام رفتن به پس‌زمینه
    ServiceLocator.get<SecureStorage>().clearMemoryCache();
    ServiceLocator.get<SecureMemoryCache>().evictAll();
    _onBackground?.call();
    _startAutoLockTimer();
    SecureLog.i('App went to background at $_lastBackgroundTime — memory cache cleared');
  }
  
  /// مدیریت ورود به پیش‌زمینه
  void onForeground() {
    _stopAutoLockTimer();
    // 🛡️ پاک‌سازی ورودی‌های منقضی شده کش
    ServiceLocator.get<SecureMemoryCache>().clearExpired();
    _onForeground?.call();
    
    if (_lastBackgroundTime != null) {
      final timeInBackground = DateTime.now().difference(_lastBackgroundTime!);
      final timeoutDuration = Duration(minutes: _autoLockTimeoutMinutes);
      
      if (timeInBackground >= timeoutDuration) {
        lockApp();
        SecureLog.i('Auto-lock triggered after ${timeInBackground.inMinutes} minutes');
      } else {
        SecureLog.i('App returned to foreground, no auto-lock needed');
      }
    }
  }
  
  /// شروع تایمر قفل خودکار
  void _startAutoLockTimer() {
    _stopAutoLockTimer();
    
    if (_autoLockTimeoutMinutes > 0) {
      _autoLockTimer = Timer(
        Duration(minutes: _autoLockTimeoutMinutes),
        () {
          if (_lastBackgroundTime != null) {
            lockApp();
            SecureLog.i('Auto-lock timer expired');
          }
        },
      );
    }
  }
  
  /// توقف تایمر قفل خودکار
  void _stopAutoLockTimer() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
  }
  
  /// بارگذاری تنظیمات قفل خودکار
  Future<void> _loadAutoLockSettings() async {
    try {
      final timeoutString = await ServiceLocator.get<SecureStorage>().getSecureData('auto_lock_timeout');
      if (timeoutString != null) {
        _autoLockTimeoutMinutes = int.tryParse(timeoutString) ?? 5;
      }
    } catch (e) {
      SecureLog.e('Error loading auto-lock settings', error: e);
    }
  }
  
  /// ذخیره زمان آخرین ورود به پس‌زمینه
  Future<void> saveLastBackgroundTime() async {
    if (_lastBackgroundTime != null) {
      await ServiceLocator.get<SecureStorage>().saveSecureData(
        'last_background_time',
        _lastBackgroundTime!.millisecondsSinceEpoch.toString(),
      );
    }
  }
  
  /// بارگذاری زمان آخرین ورود به پس‌زمینه
  Future<DateTime?> loadLastBackgroundTime() async {
    try {
      final timestampString = await ServiceLocator.get<SecureStorage>().getSecureData('last_background_time');
      if (timestampString != null) {
        final timestamp = int.tryParse(timestampString);
        if (timestamp != null) {
          return DateTime.fromMillisecondsSinceEpoch(timestamp);
        }
      }
    } catch (e) {
      SecureLog.e('Error loading last background time', error: e);
    }
    return null;
  }
  
  /// پاک کردن داده‌های lifecycle
  Future<void> clearLifecycleData() async {
    await ServiceLocator.get<SecureStorage>().deleteSecureData('last_background_time');
    _lastBackgroundTime = null;
    _stopAutoLockTimer();
  }
  
  /// بررسی نیاز به قفل خودکار
  Future<bool> shouldAutoLock() async {
    if (_autoLockTimeoutMinutes <= 0) return false;
    
    final lastTime = await loadLastBackgroundTime();
    if (lastTime != null) {
      final timeSinceBackground = DateTime.now().difference(lastTime);
      final timeoutDuration = Duration(minutes: _autoLockTimeoutMinutes);
      return timeSinceBackground >= timeoutDuration;
    }
    return false;
  }
  
  /// دریافت زمان باقی‌مانده تا قفل خودکار
  Duration? getTimeUntilAutoLock() {
    if (_lastBackgroundTime == null || _autoLockTimeoutMinutes <= 0) {
      return null;
    }
    
    final timeInBackground = DateTime.now().difference(_lastBackgroundTime!);
    final timeoutDuration = Duration(minutes: _autoLockTimeoutMinutes);
    
    if (timeInBackground >= timeoutDuration) {
      return Duration.zero;
    } else {
      return timeoutDuration - timeInBackground;
    }
  }
  
  /// پاک کردن منابع
  void dispose() {
    _stopAutoLockTimer();
    _onLock = null;
    _onUnlock = null;
    _onBackground = null;
    _onForeground = null;
  }
}

/// Widget برای مدیریت lifecycle
class LifecycleWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback? onLock;
  final VoidCallback? onUnlock;
  final VoidCallback? onBackground;
  final VoidCallback? onForeground;
  
  const LifecycleWidget({
    super.key,
    required this.child,
    this.onLock,
    this.onUnlock,
    this.onBackground,
    this.onForeground,
  });
  
  @override
  State<LifecycleWidget> createState() => _LifecycleWidgetState();
}

class _LifecycleWidgetState extends State<LifecycleWidget> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // مقداردهی LifecycleManager
    ServiceLocator.get<LifecycleManager>().initialize(
      onLock: widget.onLock,
      onUnlock: widget.onUnlock,
      onBackground: widget.onBackground,
      onForeground: widget.onForeground,
    );
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        ServiceLocator.get<LifecycleManager>().onBackground();
        break;
      case AppLifecycleState.resumed:
        ServiceLocator.get<LifecycleManager>().onForeground();
        break;
      case AppLifecycleState.detached:
        // اپلیکیشن بسته شده
        break;
      case AppLifecycleState.hidden:
        // اپلیکیشن مخفی شده (iOS)
        ServiceLocator.get<LifecycleManager>().onBackground();
        break;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
