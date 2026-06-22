import 'dart:io';
import 'package:dio/dio.dart';
import '../di/service_locator.dart';
import 'network_monitor.dart';
import '../utils/secure_log.dart';

/// مدیریت‌کننده شبکه برای Flutter
/// این کلاس مسئول مدیریت اتصال شبکه و تنظیمات SSL است
class NetworkManager {
  NetworkManager();

  NetworkManager._();

  static NetworkManager get instance => ServiceLocator.get<NetworkManager>();
  
  /// بررسی اتصال به اینترنت
  Future<bool> isConnected() async {
    try {
      return ServiceLocator.get<NetworkMonitor>().isOnline;
    } catch (e) {
      SecureLog.e('خطا در بررسی اتصال شبکه', error: e);
      return false;
    }
  }
  
  /// دریافت نوع اتصال شبکه
  Future<String> getConnectionType() async {
    try {
      return await ServiceLocator.get<NetworkMonitor>().getConnectionType();
    } catch (e) {
      SecureLog.e('خطا در دریافت نوع اتصال', error: e);
      return 'none';
    }
  }
  
  /// تنظیمات SSL برای Android و iOS
  /// این متد تنظیمات امنیتی SSL را برای هر دو پلتفرم اعمال می‌کند
  void configureSSL(Dio dio) {
    // تنظیمات SSL برای Android
    if (Platform.isAndroid) {
      _configureAndroidSSL(dio);
    }
    // تنظیمات SSL برای iOS
    else if (Platform.isIOS) {
      _configureIOSSSL(dio);
    }
  }
  
  /// تنظیمات SSL برای Android
  void _configureAndroidSSL(Dio dio) {
    try {
      // برای Android، از تنظیمات پیش‌فرض استفاده می‌کنیم
      // زیرا Android به طور خودکار گواهینامه‌های معتبر را قبول می‌کند
      SecureLog.i('تنظیمات SSL برای Android اعمال شد');
    } catch (e) {
      SecureLog.e('خطا در تنظیمات SSL برای Android', error: e);
    }
  }
  
  /// تنظیمات SSL برای iOS
  void _configureIOSSSL(Dio dio) {
    try {
      // برای iOS، از تنظیمات پیش‌فرض استفاده می‌کنیم
      // iOS به طور خودکار گواهینامه‌های معتبر را قبول می‌کند
      SecureLog.i('تنظیمات SSL برای iOS اعمال شد');
    } catch (e) {
      SecureLog.e('خطا در تنظیمات SSL برای iOS', error: e);
    }
  }
  
  /// تست اتصال به سرور
  Future<bool> testServerConnection(String url) async {
    try {
      final dio = Dio();
      final response = await dio.get(url, 
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        )
      );
      return response.statusCode == 200;
    } catch (e) {
      SecureLog.e('خطا در تست اتصال به سرور', error: e);
      return false;
    }
  }
  
  /// دریافت اطلاعات شبکه
  Future<Map<String, dynamic>> getNetworkInfo() async {
    try {
      return await ServiceLocator.get<NetworkMonitor>().getNetworkInfo();
    } catch (e) {
      SecureLog.e('خطا در دریافت اطلاعات شبکه', error: e);
      return {
        'isConnected': false,
        'connectionType': 'unknown',
        'platform': Platform.operatingSystem,
        'platformVersion': Platform.operatingSystemVersion,
      };
    }
  }
  
  /// بررسی کیفیت اتصال
  Future<String> getConnectionQuality() async {
    try {
      final hasInternet = await ServiceLocator.get<NetworkMonitor>().hasRealInternet();
      return hasInternet ? 'عالی' : 'بدون اتصال';
    } catch (e) {
      SecureLog.e('خطا در بررسی کیفیت اتصال', error: e);
      return 'نامشخص';
    }
  }
  
  /// تنظیم timeout برای درخواست‌ها
  Duration getRequestTimeout() {
    // تنظیم timeout بر اساس نوع اتصال
    return const Duration(seconds: 30);
  }
  
  /// تنظیم retry برای درخواست‌های ناموفق
  int getRetryCount() {
    return 3; // تعداد تلاش مجدد
  }
  
  /// تنظیم delay بین retry ها
  Duration getRetryDelay() {
    return const Duration(seconds: 2);
  }
  
  /// Stream برای گوش دادن به تغییرات اتصال
  Stream<bool> get connectionStream => ServiceLocator.get<NetworkMonitor>().isOnlineStream;
  
  /// بررسی اتصال واقعی به اینترنت
  Future<bool> hasRealInternet() async {
    return await ServiceLocator.get<NetworkMonitor>().hasRealInternet();
  }
}

/// کلاس برای مدیریت خطاهای شبکه
class NetworkException implements Exception {
  final String message;
  final int? statusCode;
  final String? url;
  
  NetworkException({
    required this.message,
    this.statusCode,
    this.url,
  });
  
  @override
  String toString() {
    return 'NetworkException: $message (Status: $statusCode, URL: $url)';
  }
}

/// کلاس برای مدیریت تنظیمات شبکه
class NetworkConfig {
  static const String baseUrl = 'https://api.coingecko.com/api/v3/';
  static const String aiBaseUrl = 'https://api.coingecko.com/';
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
  
  // Headers پیش‌فرض
  static Map<String, String> get defaultHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'User-Agent': 'Flutter-App/1.0',
  };
  
  // تنظیمات SSL
  static bool get enableSSLVerification => true;
  
  // تنظیمات logging
  static bool get enableLogging => true;
}
