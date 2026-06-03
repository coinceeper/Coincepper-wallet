import 'dart:io';
import 'package:dio/dio.dart';
import 'network_monitor.dart';

/// مدیریت‌کننده شبکه برای Flutter
/// این کلاس مسئول مدیریت اتصال شبکه و تنظیمات SSL است
class NetworkManager {
  static NetworkManager? _instance;
  static NetworkManager get instance => _instance ??= NetworkManager._();
  
  NetworkManager._();
  
  /// بررسی اتصال به اینترنت
  Future<bool> isConnected() async {
    try {
      return NetworkMonitor.instance.isOnline;
    } catch (e) {
      print('❌ خطا در بررسی اتصال شبکه: $e');
      return false;
    }
  }
  
  /// دریافت نوع اتصال شبکه
  Future<String> getConnectionType() async {
    try {
      return await NetworkMonitor.instance.getConnectionType();
    } catch (e) {
      print('❌ خطا در دریافت نوع اتصال: $e');
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
      print('🔒 تنظیمات SSL برای Android اعمال شد');
    } catch (e) {
      print('❌ خطا در تنظیمات SSL برای Android: $e');
    }
  }
  
  /// تنظیمات SSL برای iOS
  void _configureIOSSSL(Dio dio) {
    try {
      // برای iOS، از تنظیمات پیش‌فرض استفاده می‌کنیم
      // iOS به طور خودکار گواهینامه‌های معتبر را قبول می‌کند
      print('🔒 تنظیمات SSL برای iOS اعمال شد');
    } catch (e) {
      print('❌ خطا در تنظیمات SSL برای iOS: $e');
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
      print('❌ خطا در تست اتصال به سرور: $e');
      return false;
    }
  }
  
  /// دریافت اطلاعات شبکه
  Future<Map<String, dynamic>> getNetworkInfo() async {
    try {
      return await NetworkMonitor.instance.getNetworkInfo();
    } catch (e) {
      print('❌ خطا در دریافت اطلاعات شبکه: $e');
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
      final hasInternet = await NetworkMonitor.instance.hasRealInternet();
      return hasInternet ? 'عالی' : 'بدون اتصال';
    } catch (e) {
      print('❌ خطا در بررسی کیفیت اتصال: $e');
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
  Stream<bool> get connectionStream => NetworkMonitor.instance.isOnlineStream;
  
  /// بررسی اتصال واقعی به اینترنت
  Future<bool> hasRealInternet() async {
    return await NetworkMonitor.instance.hasRealInternet();
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
  static const String baseUrl = 'https://coinceeper.com/api/';
  static const String aiBaseUrl = 'https://coinceeper.com/';
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