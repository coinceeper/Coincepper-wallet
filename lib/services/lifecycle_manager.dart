import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'secure_storage.dart';

/// مدیریت چرخه حیات اپلیکیشن برای تمام پلتفرم‌ها
class LifecycleManager {
  static LifecycleManager? _instance;
  static LifecycleManager get instance => _instance ??= LifecycleManager._();
  
  LifecycleManager._();
  
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
    
    print('🔒 LifecycleManager initialized with ${_autoLockTimeoutMinutes}min timeout');
  }
  
  /// تنظیم timeout قفل خودکار
  Future<void> setAutoLockTimeout(int minutes) async {
    _autoLockTimeoutMinutes = minutes;
    await SecureStorage.instance.saveSecureData('auto_lock_timeout', minutes.toString());
    print('🔒 Auto-lock timeout set to $minutes minutes');
  }
  
  /// دریافت timeout قفل خودکار
  int get autoLockTimeout => _autoLockTimeoutMinutes;
  
  /// بررسی وضعیت قفل
  bool get isLocked => _isLocked;
  
  /// قفل کردن اپلیکیشن
  void lockApp() {
    if (!_isLocked) {
      _isLocked = true;
      _onLock?.call();
      print('🔒 App locked');
    }
  }
  
  /// باز کردن قفل اپلیکیشن
  void unlockApp() {
    if (_isLocked) {
      _isLocked = false;
      _onUnlock?.call();
      print('🔓 App unlocked');
    }
  }
  
  /// مدیریت ورود به پس‌زمینه
  void onBackground() {
    _lastBackgroundTime = DateTime.now();
    _onBackground?.call();
    _startAutoLockTimer();
    print('📱 App went to background at $_lastBackgroundTime');
  }
  
  /// مدیریت ورود به پیش‌زمینه
  void onForeground() {
    _stopAutoLockTimer();
    _onForeground?.call();
    
    if (_lastBackgroundTime != null) {
      final timeInBackground = DateTime.now().difference(_lastBackgroundTime!);
      final timeoutDuration = Duration(minutes: _autoLockTimeoutMinutes);
      
      if (timeInBackground >= timeoutDuration) {
        lockApp();
        print('🔒 Auto-lock triggered after ${timeInBackground.inMinutes} minutes');
      } else {
        print('📱 App returned to foreground, no auto-lock needed');
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
            print('🔒 Auto-lock timer expired');
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
      final timeoutString = await SecureStorage.instance.getSecureData('auto_lock_timeout');
      if (timeoutString != null) {
        _autoLockTimeoutMinutes = int.tryParse(timeoutString) ?? 5;
      }
    } catch (e) {
      print('Error loading auto-lock settings: $e');
    }
  }
  
  /// ذخیره زمان آخرین ورود به پس‌زمینه
  Future<void> saveLastBackgroundTime() async {
    if (_lastBackgroundTime != null) {
      await SecureStorage.instance.saveSecureData(
        'last_background_time',
        _lastBackgroundTime!.millisecondsSinceEpoch.toString(),
      );
    }
  }
  
  /// بارگذاری زمان آخرین ورود به پس‌زمینه
  Future<DateTime?> loadLastBackgroundTime() async {
    try {
      final timestampString = await SecureStorage.instance.getSecureData('last_background_time');
      if (timestampString != null) {
        final timestamp = int.tryParse(timestampString);
        if (timestamp != null) {
          return DateTime.fromMillisecondsSinceEpoch(timestamp);
        }
      }
    } catch (e) {
      print('Error loading last background time: $e');
    }
    return null;
  }
  
  /// پاک کردن داده‌های lifecycle
  Future<void> clearLifecycleData() async {
    await SecureStorage.instance.deleteSecureData('last_background_time');
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
    LifecycleManager.instance.initialize(
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
        LifecycleManager.instance.onBackground();
        break;
      case AppLifecycleState.resumed:
        LifecycleManager.instance.onForeground();
        break;
      case AppLifecycleState.detached:
        // اپلیکیشن بسته شده
        break;
      case AppLifecycleState.hidden:
        // اپلیکیشن مخفی شده (iOS)
        LifecycleManager.instance.onBackground();
        break;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
} 