import '../interfaces/settings_data_source.dart';
import '../../di/service_locator.dart';
import '../../utils/secure_log.dart';

/// سرویس مدیریت تنظیمات اپلیکیشن (زبان، ارز، نوتیفیکیشن)
///
/// این سرویس مسئول مدیریت تنظیمات کلی اپلیکیشن است.
///
/// طبق Clean Architecture:
/// - وابسته به [ISettingsDataSource] به جای SecureStorage مستقیم
/// - از ChangeNotifier استفاده نمی‌کند (pure Dart)
/// - تغییرات از طریق callback به لایه presentation منتقل می‌شود
class AppSettingsService {
  // ==================== CALLBACK ====================
  ServiceChangeCallback? _onChange;

  /// تنظیم callback برای اطلاع‌رسانی تغییرات به لایه presentation
  void setOnChange(ServiceChangeCallback? callback) {
    _onChange = callback;
  }

  // ==================== SINGLETON ====================
  static AppSettingsService get instance => ServiceLocator.get<AppSettingsService>();
  AppSettingsService._();
  AppSettingsService();

  ISettingsDataSource get _storage => ServiceLocator.get<ISettingsDataSource>();

  // ==================== STATE ====================
  String _currentLanguage = 'en';
  String _currentCurrency = 'USD';
  bool _pushNotificationsEnabled = true;
  String? _deviceToken;
  bool _isInitialized = false;

  // ==================== GETTERS ====================
  String get currentLanguage => _currentLanguage;
  String get currentCurrency => _currentCurrency;
  bool get pushNotificationsEnabled => _pushNotificationsEnabled;
  String? get deviceToken => _deviceToken;
  bool get isInitialized => _isInitialized;

  // ==================== INITIALIZATION ====================
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      _currentLanguage = await _storage.getSecureData('current_language') ?? 'en';
      _currentCurrency = await _storage.getSecureData('current_currency') ?? 'USD';
      _deviceToken = await _storage.getDeviceToken();
      _isInitialized = true;
    } catch (e) {
      SecureLog.w('Error initializing app settings', error: e);
    }
  }

  // ==================== LANGUAGE ====================
  Future<void> setLanguage(String language) async {
    _currentLanguage = language;
    await _storage.saveSecureData('current_language', language);
    _notifyChange();
  }

  // ==================== CURRENCY ====================
  Future<void> setCurrency(String currency) async {
    _currentCurrency = currency;
    await _storage.saveSecureData('current_currency', currency);
    _notifyChange();
  }

  // ==================== NOTIFICATIONS ====================
  Future<void> setPushNotificationsEnabled(bool enabled) async {
    _pushNotificationsEnabled = enabled;
    await _storage.saveSecureData('push_notifications_enabled', enabled.toString());
    _notifyChange();
  }

  Future<void> setDeviceToken(String token) async {
    _deviceToken = token;
    await _storage.saveDeviceToken(token);
    _notifyChange();
  }

  // ==================== INTERNAL ====================
  void _notifyChange() {
    _onChange?.call();
  }
}

/// Type definition for no-parameter callback
typedef ServiceChangeCallback = void Function();
