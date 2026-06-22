import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/geo_models.dart';
import '../utils/secure_log.dart';
import 'geo_proxy_service.dart';

/// وضعیت سلامت بک‌اند پروکسی
enum BackendStatus { healthy, degraded, unavailable }

/// سرویس پروکسی بک‌اند با قابلیت:
/// 1. failover به درخواست مستقیم
/// 2. مسیریابی GEO-aware از طریق GeoProxyService
/// 3. توزیع هوشمند ترافیک بر اساس CPM منطقه
///
/// این سرویس به عنوان یک لایه واسط بین اپلیکیشن و APIهای بک‌اند عمل می‌کند.
/// در صورت عدم دسترسی به پروکسی، به طور خودکار به درخواست مستقیم (direct call) fallback می‌کند.
class BackendProxyService {
  static BackendProxyService? _instance;
  static BackendProxyService get instance =>
      _instance ??= _BackendProxyServiceFactory.create();

  BackendProxyService._();
  BackendProxyService();

  String? _baseUrl;
  BackendStatus _status = BackendStatus.healthy;
  int _consecutiveFailures = 0;
  static const int _maxFailuresBeforeUnavailable = 3;

  /// وضعیت فعلی بک‌اند
  BackendStatus get backendStatus => _status;

  /// مقداردهی اولیه با آدرس پایه
  void initialize({required String baseUrl}) {
    _baseUrl = baseUrl;
    _status = BackendStatus.healthy;
    _consecutiveFailures = 0;
    SecureLog.i('BackendProxyService initialized with baseUrl: $baseUrl');
  }

  /// مسیریابی هوشمند: تلاش پروکسی، در صورت شکست fallback به direct
  Future<T> route<T>({
    required String endpoint,
    required Future<T> Function() proxyCall,
    required Future<T> Function() directCall,
  }) async {
    if (_status == BackendStatus.unavailable) {
      SecureLog.d('Proxy unavailable — calling direct for $endpoint');
      return await directCall();
    }

    try {
      final result = await proxyCall().timeout(const Duration(seconds: 10));
      _recordSuccess();
      return result;
    } catch (e) {
      SecureLog.w('Proxy call failed for $endpoint: $e — falling back to direct');
      _recordFailure();
      return await directCall();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // GEO-Aware Routing — مسیریابی با توزیع جغرافیایی هوشمند
  // ═══════════════════════════════════════════════════════════════

  /// مسیریابی GEO-aware با انتخاب پراکسی بر اساس بهترین GEO
  ///
  /// [endpoint]: نام endpoint برای لاگ
  /// [geoAwareCall]: تابع دریافت داده از طریق پراکسی GEO
  /// [directCall]: تابع fallback بدون پراکسی
  /// [preferredGeo]: منطقه ترجیحی (اختیاری)
  /// [bypassGeo]: اگر true باشد، GEO را در نظر نمی‌گیرد (مثلاً برای auth)
  Future<T> routeWithGeo<T>({
    required String endpoint,
    required Future<T> Function() geoAwareCall,
    required Future<T> Function() directCall,
    GeoRegion? preferredGeo,
    bool bypassGeo = false,
  }) async {
    if (_status == BackendStatus.unavailable) {
      SecureLog.d('Proxy unavailable — calling direct for $endpoint');
      return await directCall();
    }

    if (bypassGeo) {
      try {
        final result = await directCall().timeout(const Duration(seconds: 10));
        _recordSuccess();
        return result;
      } catch (e) {
        _recordFailure();
        rethrow;
      }
    }

    try {
      final result = await geoAwareCall().timeout(const Duration(seconds: 15));
      _recordSuccess();
      return result;
    } catch (e) {
      SecureLog.w('GEO proxy failed for $endpoint: $e — falling back to direct');
      _recordFailure();
      return await directCall();
    }
  }

  /// درخواست GET از طریق پراکسی با انتخاب GEO هوشمند
  Future<http.Response> geoAwareGet(
    String path, {
    Map<String, String>? queryParams,
    GeoRegion? preferredGeo,
  }) async {
    if (_baseUrl == null) throw StateError('BackendProxyService not initialized');

    final geoService = GeoProxyService.instance;
    final proxy = geoService.getProxy(preferredGeo: preferredGeo);

    if (proxy == null) {
      return await _directGet(path, queryParams: queryParams);
    }

    final uri = Uri.parse('$_baseUrl/$path').replace(queryParameters: queryParams);
    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      if (proxy.username != null && proxy.password != null) {
        final credentials = base64Encode(
          utf8.encode('${proxy.username}:${proxy.password}'),
        );
        request.headers['Proxy-Authorization'] = 'Basic $credentials';
      }
      final streamedResponse = await client.send(request)
          .timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        geoService.recordCpm(proxy.region.code, 1.0);
      }
      return response;
    } finally {
      client.close();
    }
  }

  Future<http.Response> _directGet(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    if (_baseUrl == null) throw StateError('BackendProxyService not initialized');
    final uri = Uri.parse('$_baseUrl/$path').replace(queryParameters: queryParams);
    return await http.get(uri).timeout(const Duration(seconds: 15));
  }

  /// درخواست GET از طریق پروکسی
  Future<http.Response> proxyGet(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    if (_baseUrl == null) throw StateError('BackendProxyService not initialized');
    final uri = Uri.parse('$_baseUrl/$path').replace(queryParameters: queryParams);
    return await http.get(uri).timeout(const Duration(seconds: 15));
  }

  /// درخواست POST از طریق پروکسی
  Future<http.Response> proxyPost(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (_baseUrl == null) throw StateError('BackendProxyService not initialized');
    final uri = Uri.parse('$_baseUrl/$path');
    return await http
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body != null ? jsonEncode(body) : null)
        .timeout(const Duration(seconds: 15));
  }

  /// بررسی موفقیت‌آمیز بودن response
  static bool isSuccess(http.Response response) {
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  /// استخراج JSON از response (در صورت موفقیت)
  static Map<String, dynamic>? parseJson(http.Response response) {
    if (!isSuccess(response)) return null;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (e) {
      SecureLog.w('BackendProxy: failed to parse JSON response', error: e);
      return null;
    }
  }

  /// استخراج داده تایپ‌شده از JSON پاسخ
  static T? extractData<T>(Map<String, dynamic>? json) {
    if (json == null) return null;
    if (json['status'] != 'ok') return null;
    final data = json['data'];
    if (data is T) return data;
    return null;
  }

  void _recordSuccess() {
    _consecutiveFailures = 0;
    _status = BackendStatus.healthy;
  }

  void _recordFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= _maxFailuresBeforeUnavailable) {
      _status = BackendStatus.unavailable;
    } else {
      _status = BackendStatus.degraded;
    }
  }

  /// پاک‌سازی و توقف مانیتورینگ
  void dispose() {
    _baseUrl = null;
    _status = BackendStatus.healthy;
    _consecutiveFailures = 0;
    SecureLog.i('BackendProxyService disposed');
  }
}

/// Factory helper برای DI container
class _BackendProxyServiceFactory {
  static BackendProxyService create() {
    final service = BackendProxyService();
    _BackendProxyServiceFactory._instance = service;
    return service;
  }

  static BackendProxyService? _instance;
}
