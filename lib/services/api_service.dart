import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_models.dart';
import '../models/notification_models.dart' as notif;
import 'secure_storage.dart';
import 'device_auth_service.dart';
import 'enhanced_network_manager.dart';

/// API service for server communication with enhanced network handling
/// This class manages all API requests with intelligent retry and timeout handling
///
/// 🏛️ معماری Non-Custodial:
/// ──────────────────────
/// V1 (Deprecated): endpointهای قدیمی با UserID — برای backward compatibility
/// V2 (Active):     endpointهای عمومی بدون UserID — Cache Proxy روی سرور
/// ──────────────────────
/// مستندات V2: https://coinceeper.com/api-docs/#/v2
class ApiService {
  static const String _baseUrl = 'https://coinceeper.com/api/';
  static const String _baseUrlV2 = 'https://coinceeper.com/api/v2/';
  
  late final Dio _dio;
  late final Dio _dioV2;
  final EnhancedNetworkManager _networkManager = EnhancedNetworkManager.instance;
  
  ApiService() {
    _initializeDio();
    _initializeDioV2();
  }
  
  /// مقداردهی اولیه Dio برای HTTP requests با Enhanced Network Manager
  void _initializeDio() {
    // استفاده از Enhanced Network Manager برای timeout های هوشمند
    _dio = _networkManager.createAdaptiveDio(baseUrl: _baseUrl);
    
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: false,
        responseBody: false,
        logPrint: (obj) => print('🌐 API: $obj'),
      ));
    }
  }

  /// مقداردهی اولیه Dio V2 — بدون UserID، عمومی
  void _initializeDioV2() {
    _dioV2 = Dio(BaseOptions(
      baseUrl: _baseUrlV2,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 5),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'Flutter-App/1.0',
      },
    ));

    if (kDebugMode) {
      _dioV2.interceptors.add(LogInterceptor(
        requestBody: false,
        responseBody: false,
        logPrint: (obj) => print('🌐 API V2: $obj'),
      ));
    }
  }
  
  /// دریافت UserID از SecureStorage (مطابق با AppProvider)
  Future<String?> _getUserId() async {
    try {
      // First try to get from SecureStorage (current selected wallet)
      final userId = await SecureStorage.instance.getUserIdForSelectedWallet();
      if (userId != null && userId.isNotEmpty) {
        return userId;
      }
      
      // Fallback to SharedPreferences for compatibility
      final prefs = await SharedPreferences.getInstance();
      final sharedPrefsUserId = prefs.getString('UserID');
      
      print('🔍 ApiService: SecureStorage UserID: $userId');
      print('🔍 ApiService: SharedPreferences UserID: $sharedPrefsUserId');
      
      return sharedPrefsUserId;
    } catch (e) {
      print('Error getting User ID: $e');
      return null;
    }
  }
  
  /// همگام‌سازی UserID بین SecureStorage و SharedPreferences
  Future<void> syncUserIdToSharedPreferences(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('UserID', userId);
      print('✅ ApiService: Synced UserID to SharedPreferences: $userId');
    } catch (e) {
      print('❌ ApiService: Error syncing UserID to SharedPreferences: $e');
    }
  }

  /// اضافه کردن UserID به headers اگر موجود باشد
  Future<Map<String, String>> _getHeaders() async {
    final userId = await _getUserId();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': 'Flutter-App/1.0',
    };
    
    if (userId != null) {
      headers['UserID'] = userId;
      print('🔍 ApiService: Using UserID in headers: $userId');
      final deviceToken = await DeviceAuthService.instance.getToken();
      if (deviceToken != null && deviceToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $deviceToken';
      }
    } else {
      print('⚠️ ApiService: No UserID found for headers');
    }
    
    return headers;
  }
  
  /// Handle API errors
  void _handleError(DioException e) {
    print('❌ API Error: ${e.message}');
    if (e.response != null) {
      print('📊 Status Code: ${e.response!.statusCode}');
      print('📄 Response Data: ${e.response!.data}');
    }
    throw Exception('Server communication error: ${e.message}');
  }
  
  // ==================== PRICE & BALANCE OPERATIONS ====================
  
  /// دریافت قیمت‌های ارزها با Enhanced Network Handling
  /// [symbols]: لیست نمادهای ارز
  /// [fiatCurrencies]: لیست ارزهای فیات
  /// @deprecated استفاده از getPricesV2() — عمومی و بدون UserID
  @Deprecated('Use getPricesV2() — anonymous, no UserID, backed by cache proxy')
  Future<PricesResponse> getPrices(List<String> symbols, List<String> fiatCurrencies) async {
    return await _networkManager.executeRequest<PricesResponse>(
      () async {
        final request = PricesRequest(symbol: symbols, fiatCurrencies: fiatCurrencies);
        final response = await _dio.post(
          'prices',
          data: request.toJson(),
          options: Options(headers: await _getHeaders()),
        );
        
        return PricesResponse.fromJson(response.data);
      },
      operationName: 'getPrices',
    );
  }
  
  /// دریافت موجودی کاربر (فرمت جدید برای ایمپورت کیف پول)
  /// [userId]: شناسه کاربر
  /// [currencyNames]: لیست نام‌های ارز
  /// @deprecated موجودی از OnChainBalanceService خوانده می‌شود
  @Deprecated('Use OnChainBalanceService.instance.balancesForActiveTokens()')
  Future<GetUserBalanceResponse> getUserBalance(
    String userId, 
    List<String> currencyNames,
  ) async {
    try {
      print('🔄 API Service - Starting getUserBalance request');
      print('📝 UserID: $userId');
      print('📝 CurrencyNames: $currencyNames');
      
      final request = GetUserBalanceRequest(
        userID: userId,
        currencyName: currencyNames,
      );
      
      final headers = await _getHeaders();
      
      print('📤 Request Data: ${request.toJson()}');
      print('📋 Headers: $headers');
      print('🌐 Making POST request to: ${_baseUrl}balance');
      
      final response = await _dio.post(
        'balance',
        data: request.toJson(),
        options: Options(headers: headers),
      );
      
      print('📥 getUserBalance Response received:');
      print('   Status Code: ${response.statusCode}');
      print('   Response Data: ${response.data}');
      
      return GetUserBalanceResponse.fromJson(response.data);
    } on DioException catch (e) {
      print('❌ Error in getUserBalance: ${e.message}');
      _handleError(e);
      rethrow;
    }
  }
  
  /// دریافت کارمزد گاز برای بلاکچین‌های مختلف
  /// @deprecated استفاده از getGasV2() — عمومی و بدون UserID
  @Deprecated('Use getGasV2() — anonymous, no UserID, backed by cache proxy')
  Future<GasFeeResponse> getGasFee() async {
    try {
      final response = await _dio.get(
        'gasfee',
        options: Options(headers: await _getHeaders()),
      );
      
      return GasFeeResponse.fromJson(response.data);
    } on DioException catch (e) {
      _handleError(e);
      rethrow;
    }
  }
  
  /// نگاشت سمبل‌های معروف به بلاکچین مبدأ — V2 API فیلد blockchain را ندارد
  static const Map<String, String> _knownBlockchains = {
    'BTC': 'Bitcoin',
    'ETH': 'Ethereum',
    'TRX': 'Tron',
    'SOL': 'Solana',
    'XRP': 'XRP',
    'BNB': 'Binance Smart Chain',
    'ADA': 'Cardano',
    'DOT': 'Polkadot',
    'AVAX': 'Avalanche',
    'MATIC': 'Polygon',
    'ARB': 'Arbitrum',
    'ATOM': 'Cosmos',
    'NEAR': 'NEAR Protocol',
    'FIL': 'Filecoin',
    'APT': 'Aptos',
    'LTC': 'Litecoin',
    'DOGE': 'Dogecoin',
    'LINK': 'Chainlink',
    'UNI': 'Uniswap',
  };

  /// تبدیل مقادیر مختلف (int, bool, String) به bool? — جهت جلوگیری از خطای type cast
  static bool? _toBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return null;
  }

  /// دریافت blockchainName با fallback به نگاشت سمبل‌های معروف
  static String? _resolveBlockchain(Map<String, dynamic> raw, String symbol) {
    final direct = raw['blockchain']?.toString() ?? raw['platform']?.toString();
    if (direct != null && direct.isNotEmpty && direct != 'null') return direct;
    // Fallback به نگاشت داخلی
    return _knownBlockchains[symbol.toUpperCase()];
  }

  /// دریافت تمام ارزهای موجود — non-custodial, بدون UserID
  /// Primary: https://coinceeper.com/api/all-currencies (۱,۱۲۹ ارز با ساختار کامل)
  /// Fallback: API V2 cache proxy
  Future<ApiResponse> getAllCurrencies() async {
    try {
      // Primary: V1 all-currencies — دیتای کامل‌تر با IsToken از نوع bool واقعی
      final v1Response = await _dio.get('all-currencies');
      if (v1Response.statusCode == 200 && v1Response.data is Map) {
        final body = v1Response.data as Map<String, dynamic>;
        final rawList = body['currencies'];
        if (rawList is List && rawList.isNotEmpty) {
          final currencies = rawList.map((raw) {
            final c = raw as Map<String, dynamic>;
            return ApiCurrency(
              currencyId: c['CurrencyID']?.toString(),
              currencyName: c['CurrencyName']?.toString(),
              symbol: (c['Symbol']?.toString() ?? '').toUpperCase().isEmpty
                  ? null
                  : c['Symbol']?.toString(),
              blockchainName: c['BlockchainName']?.toString(),
              icon: c['Icon']?.toString(),
              // IsToken از API واقعاً boolean است — خطای int→bool دیگر رخ نمی‌دهد
              isToken: c['IsToken'] is bool
                  ? c['IsToken'] as bool
                  : _toBool(c['IsToken']),
              smartContractAddress: c['SmartContractAddress']?.toString(),
            );
          }).toList();
          print('✅ getAllCurrencies: Loaded ${currencies.length} currencies from V1');
          return ApiResponse(currencies: currencies, success: true);
        }
      }
      print('⚠️ getAllCurrencies: V1 empty/error, falling back to V2');
      // Fallback: V2 cache proxy
      return _getAllCurrenciesV2Fallback();
    } catch (e) {
      print('⚠️ getAllCurrencies: V1 failed ($e), falling back to V2');
      return _getAllCurrenciesV2Fallback();
    }
  }

  /// Fallback: V2 cache proxy
  Future<ApiResponse> _getAllCurrenciesV2Fallback() async {
    try {
      final v2Coins = await getCoinsV2();
      if (v2Coins.isNotEmpty) {
        final currencies = v2Coins.map((raw) {
          final c = raw as Map<String, dynamic>;
          final sym = (c['symbol']?.toString() ?? '').toUpperCase();
          return ApiCurrency(
            currencyId: c['id']?.toString(),
            currencyName: c['name']?.toString(),
            symbol: sym.isEmpty ? null : sym,
            blockchainName: _resolveBlockchain(c, sym),
            icon: c['image']?.toString() ?? c['icon']?.toString(),
            isToken: _toBool(c['is_token'] ?? c['isToken']),
            smartContractAddress: c['contract_address']?.toString(),
          );
        }).toList();
        return ApiResponse(currencies: currencies, success: true);
      }
      return const ApiResponse(currencies: [], success: false);
    } catch (e) {
      print('⚠️ V2 fallback failed: $e');
      return const ApiResponse(currencies: [], success: false);
    }
  }
  
  /// تخمین کارمزد تراکنش
  /// [userID]: شناسه کاربر
  /// [blockchain]: نام بلاکچین
  /// [fromAddress]: آدرس فرستنده
  /// [toAddress]: آدرس گیرنده
  /// [amount]: مقدار
  /// [type]: نوع تراکنش (اختیاری)
  /// [tokenContract]: آدرس توکن (اختیاری)
  Future<EstimateFeeResponse> estimateFee({
    required String userID,
    required String blockchain,
    required String fromAddress,
    required String toAddress,
    required double amount,
    String? type,
    String tokenContract = '',
  }) async {
    try {
      final request = EstimateFeeRequest(
        userID: userID,
        blockchain: blockchain,
        fromAddress: fromAddress,
        toAddress: toAddress,
        amount: amount,
        type: type,
        tokenContract: tokenContract,
      );
      
      print('🔧 DEBUG: EstimateFee Request:');
      print('   UserID: $userID');
      print('   Blockchain: $blockchain');
      print('   From: $fromAddress');
      print('   To: $toAddress');
      print('   Amount: $amount');
      print('   Token Contract: $tokenContract');
      print('   JSON: ${request.toJson()}');
      
      final response = await _dio.post(
        'estimate-fee',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      
      print('✅ EstimateFee Response: ${response.data}');
      
      return EstimateFeeResponse.fromJson(response.data);
    } on DioException catch (e) {
      print('❌ EstimateFee DioException: ${e.response?.statusCode} - ${e.response?.data}');
      _handleError(e);
      rethrow;
    } catch (e) {
      print('❌ EstimateFee Exception: $e');
      throw Exception('Error estimating fee: $e');
    }
  }
  
  
  
  // ==================== V2 ENDPOINTS (Non-Custodial, بدون UserID) ====================

  /// دریافت قیمت لحظه‌ای از Cache Proxy V2 — بدون UserID
  /// GET /api/v2/prices
  Future<Map<String, Map<String, double>>> getPricesV2() async {
    try {
      final response = await _dioV2.get('prices');
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['prices'] != null) {
          return _parseV2Prices(data['prices']);
        }
      }
      return {};
    } catch (e) {
      print('⚠️ V2 prices failed: $e');
      return {};
    }
  }

  /// دریافت قیمت یک ارز خاص از V2
  /// GET /api/v2/prices/{symbol}
  Future<double?> getPriceV2(String symbol) async {
    try {
      final response = await _dioV2.get('prices/$symbol');
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['price'] != null) {
          return (data['price'] as num).toDouble();
        }
      }
      return null;
    } catch (e) {
      print('⚠️ V2 price for $symbol failed: $e');
      return null;
    }
  }

  /// دریافت داده‌های نمودار از Cache Proxy V2 — بدون UserID
  /// GET /api/v2/chart?symbol=BTC&days=7
  Future<List<ChartDataPointV2>?> getChartV2({
    required String symbol,
    int days = 7,
  }) async {
    try {
      final response = await _dioV2.get('chart', queryParameters: {
        'symbol': symbol.toUpperCase(),
        'days': days.toString(),
      });
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          final rawList = data['data'] as List;
          return rawList.map((item) {
            final arr = item as List;
            return ChartDataPointV2(
              timestamp: DateTime.fromMillisecondsSinceEpoch(arr[0].toInt()),
              price: (arr[1] as num).toDouble(),
            );
          }).toList();
        }
      }
      return null;
    } catch (e) {
      print('⚠️ V2 chart for $symbol failed: $e');
      return null;
    }
  }

  /// دریافت کارمزد شبکه‌ها از Cache Proxy V2 — بدون UserID
  /// GET /api/v2/gas
  Future<Map<String, dynamic>?> getGasV2() async {
    try {
      final response = await _dioV2.get('gas');
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['gas'] != null) {
          return data['gas'] as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      print('⚠️ V2 gas fees failed: $e');
      return null;
    }
  }

  /// دریافت لیست کامل ارزها از Cache Proxy V2 — بدون UserID
  /// GET /api/v2/coins?per_page=200  (حداکثر ۲۰۰ کوین در هر صفحه)
  /// ⚠️ این API ۱۷,۰۰۰+ کوین را صفحه‌بندی کرده برمی‌گرداند.
  ///     ما فقط صفحه اول را می‌گیریم (مرتب‌شده بر اساس الفبا) و
  ///     BTC/ETH/TRX را در TokenProvider تضمین می‌کنیم.
  Future<List<dynamic>> getCoinsV2({int perPage = 200}) async {
    try {
      final response = await _dioV2.get('coins', queryParameters: {
        'per_page': perPage.toString(),
      });
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        if (data['success'] == true && data['coins'] != null) {
          return data['coins'] as List;
        }
      }
      return [];
    } catch (e) {
      print('⚠️ V2 coins list failed: $e');
      return [];
    }
  }

  /// بررسی وضعیت Cache Proxy
  /// GET /api/v2/health
  Future<bool> isV2Healthy() async {
    try {
      final response = await _dioV2.get('health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Parse V2 prices response to {symbol: {currency: value}} format
  Map<String, Map<String, double>> _parseV2Prices(dynamic rawPrices) {
    final result = <String, Map<String, double>>{};
    if (rawPrices is! Map) return result;
    rawPrices.forEach((coinId, data) {
      if (data is Map) {
        final usd = (data['usd'] as num?)?.toDouble();
        final change = (data['usd_24h_change'] as num?)?.toDouble();
        if (usd != null) {
          result[coinId.toUpperCase()] = {'USD': usd, 'change_24h': change ?? 0};
        }
      }
    });
    return result;
  }

  // ==================== V2 NOTIFICATION (Active Address Registry) ====================
  /// دریافت تراکنش‌های جدید برای آدرس‌های مشخص — بدون UserID
  /// آدرس‌ها به صورت خودکار در Active Address Registry ثبت می‌شوند
  /// GET /api/v2/notifications?addresses=0xabc,0xdef
  Future<V2NotificationResponse?> checkNotificationsV2({
    required List<String> addresses,
  }) async {
    if (addresses.isEmpty) return null;
    try {
      final response = await _dioV2.get('notifications', queryParameters: {
        'addresses': addresses.join(','),
      });
      if (response.statusCode == 200 && response.data is Map) {
        return V2NotificationResponse.fromJson(
            response.data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ V2 notifications failed: $e');
      return null;
    }
  }

  /// بررسی سلامت V2 Cache Proxy
  /// GET /api/v2/health
  Future<V2HealthResponse?> checkHealthV2() async {
    try {
      final response = await _dioV2.get('health');
      if (response.statusCode == 200 && response.data is Map) {
        return V2HealthResponse.fromJson(
            response.data as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ V2 health check failed: $e');
      return null;
    }
  }

  // ==================== NOTIFICATION OPERATIONS ====================
  
  /// ثبت دستگاه برای دریافت اعلان‌های Push از طریق FCM
  /// [userId]: شناسه کاربر
  /// [walletId]: شناسه کیف پول
  /// [deviceToken]: توکن FCM دستگاه
  /// [deviceName]: نام دستگاه
  /// [deviceType]: نوع دستگاه (android / ios)
  Future<RegisterDeviceResponse> registerDevice({
    required String userId,
    required String walletId,
    required String deviceToken,
    required String deviceName,
    String deviceType = 'android',
  }) async {
    try {
      final request = RegisterDeviceRequest(
        userId: userId,
        walletId: walletId,
        deviceToken: deviceToken,
        deviceName: deviceName,
        deviceType: deviceType,
      );
      final response = await _dio.post(
        'notifications/register-device',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      
      return RegisterDeviceResponse.fromJson(response.data);
    } on DioException catch (e) {
      _handleError(e);
      rethrow;
    }
  }
  
  
  /// Get current network status for debugging and user information
  Map<String, dynamic> getNetworkStatus() {
    return _networkManager.getConnectionStatus();
  }
  
  /// Check if network is suitable for critical operations (like transactions)
  bool isNetworkSuitableForCriticalOps() {
    final status = _networkManager.getConnectionStatus();
    final quality = status['quality'] as String;
    
    // Allow critical operations only on good connections
    return ['excellent', 'good'].contains(quality);
  }

  // ===========================================================================
  // 🚨 NOTIFICATION SYSTEM — FULL API (P1–P5)
  // ===========================================================================

  // ─── Device Registration (Prerequisite) ──────────────────────────────────

  /// Register device for push notifications.
  /// Must be called every time the app starts.
  /// Uses the documented API contract:
  ///   POST /api/notifications/register-device
  Future<notif.NotificationApiResponse> registerDeviceV2({
    required String deviceToken,
    required String platform,
    required String walletId,
    required String userId,
    String deviceName = '',
  }) async {
    try {
      final body = notif.RegisterDeviceRequest(
        deviceToken: deviceToken,
        deviceType: platform,
        walletId: walletId,
        userId: userId,
        deviceName: deviceName,
      );
      final response = await _dio.post(
        'notifications/register-device',
        data: body.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      return notif.NotificationApiResponse.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('⚠️ registerDeviceV2 failed: $e');
      return const notif.NotificationApiResponse(success: false, message: 'Network error');
    }
  }

  // ─── P2: Security Notifications ──────────────────────────────────────────

  /// Notify backend of a new login from a new device/location.
  Future<notif.NotificationApiResponse> notifySecurityLogin(
    notif.SecurityLoginRequest request,
  ) async {
    try {
      final response = await _dio.post(
        'notifications/security/login',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      return notif.NotificationApiResponse.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('⚠️ notifySecurityLogin failed: $e');
      return const notif.NotificationApiResponse(success: false, message: 'Network error');
    }
  }

  /// Notify backend of a security setting change.
  Future<notif.NotificationApiResponse> notifySecurityChange(
    notif.SecurityChangeRequest request,
  ) async {
    try {
      final response = await _dio.post(
        'notifications/security/change',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      return notif.NotificationApiResponse.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('⚠️ notifySecurityChange failed: $e');
      return const notif.NotificationApiResponse(success: false, message: 'Network error');
    }
  }

  /// Notify backend of suspicious activity.
  Future<notif.NotificationApiResponse> notifySecuritySuspicious(
    notif.SecuritySuspiciousRequest request,
  ) async {
    try {
      final response = await _dio.post(
        'notifications/security/suspicious',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      return notif.NotificationApiResponse.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('⚠️ notifySecuritySuspicious failed: $e');
      return const notif.NotificationApiResponse(success: false, message: 'Network error');
    }
  }

  // ─── P3: Price Alerts ────────────────────────────────────────────────────

  /// Execute notification API requests with retry from EnhancedNetworkManager.
  /// Notification endpoints don't use executeRequest by default, so we wrap them.
  Future<T> _executeNotifRequest<T>(
    Future<T> Function() request, {
    String operationName = 'notification',
    bool enableRetry = true,
  }) async {
    // For notification operations, use the network manager's retry logic
    return _networkManager.executeRequest<T>(
      request,
      operationName: operationName,
      enableRetry: enableRetry,
    );
  }

  /// Create a new price alert.
  Future<notif.NotificationApiResponse> createPriceAlert(
    notif.PriceAlertRequest request,
  ) async {
    return _executeNotifRequest<notif.NotificationApiResponse>(
      () async {
        try {
          final response = await _dio.post(
            'notifications/price-alert',
            data: request.toJson(),
            options: Options(headers: await _getHeaders()),
          );
          return notif.NotificationApiResponse.fromJson(response.data);
        } on DioException catch (e) {
          debugPrint('⚠️ createPriceAlert failed: $e');
          return const notif.NotificationApiResponse(success: false, message: 'Network error');
        }
      },
      operationName: 'createPriceAlert',
    );
  }

  /// Get all price alerts for a user.
  Future<notif.PriceAlertsResponse> getPriceAlerts(String userId) async {
    return _executeNotifRequest<notif.PriceAlertsResponse>(
      () async {
        try {
          final response = await _dio.get(
            'notifications/price-alerts/$userId',
            options: Options(headers: await _getHeaders()),
          );
          return notif.PriceAlertsResponse.fromJson(response.data);
        } on DioException catch (e) {
          debugPrint('⚠️ getPriceAlerts failed: $e');
          return const notif.PriceAlertsResponse(success: false);
        }
      },
      operationName: 'getPriceAlerts',
    );
  }

  /// Delete a price alert.
  Future<notif.NotificationApiResponse> deletePriceAlert(
    notif.DeletePriceAlertRequest request,
  ) async {
    return _executeNotifRequest<notif.NotificationApiResponse>(
      () async {
        try {
          final response = await _dio.delete(
            'notifications/price-alert',
            data: request.toJson(),
            options: Options(headers: await _getHeaders()),
          );
          return notif.NotificationApiResponse.fromJson(response.data);
        } on DioException catch (e) {
          debugPrint('⚠️ deletePriceAlert failed: $e');
          return const notif.NotificationApiResponse(success: false, message: 'Network error');
        }
      },
      operationName: 'deletePriceAlert',
    );
  }

  /// Bulk price lookup — avoids N+1 requests.
  /// GET /api/notifications/price-alerts/prices?symbols=BTC,ETH
  Future<notif.BulkPricesResponse> getBulkPrices(List<String> symbols) async {
    return _executeNotifRequest<notif.BulkPricesResponse>(
      () async {
        try {
          final joined = symbols.map((s) => s.toUpperCase().trim()).join(',');
          final response = await _dio.get(
            'notifications/price-alerts/prices',
            queryParameters: {'symbols': joined},
            options: Options(headers: await _getHeaders()),
          );
          return notif.BulkPricesResponse.fromJson(response.data);
        } on DioException catch (e) {
          debugPrint('⚠️ getBulkPrices failed: $e');
          return const notif.BulkPricesResponse(success: false);
        }
      },
      operationName: 'getBulkPrices',
    );
  }

  // ─── P4: Network & Gas (Admin) ───────────────────────────────────────────

  /// Send network status notification (admin).
  Future<notif.NotificationApiResponse> adminNotifyNetworkStatus(
    notif.NetworkStatusRequest request,
  ) async {
    try {
      final response = await _dio.post(
        'admin/notifications/network-status',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      return notif.NotificationApiResponse.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('⚠️ adminNotifyNetworkStatus failed: $e');
      return const notif.NotificationApiResponse(success: false, message: 'Network error');
    }
  }

  /// Send network upgrade notification (admin).
  Future<notif.NotificationApiResponse> adminNotifyNetworkUpgrade(
    notif.NetworkUpgradeRequest request,
  ) async {
    try {
      final response = await _dio.post(
        'admin/notifications/network-upgrade',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      return notif.NotificationApiResponse.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('⚠️ adminNotifyNetworkUpgrade failed: $e');
      return const notif.NotificationApiResponse(success: false, message: 'Network error');
    }
  }

  /// Trigger portfolio summary notification for a user (admin).
  Future<notif.NotificationApiResponse> adminSendPortfolioSummary(String userId) async {
    try {
      final response = await _dio.post(
        'admin/notifications/portfolio-summary/$userId',
        options: Options(headers: await _getHeaders()),
      );
      return notif.NotificationApiResponse.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('⚠️ adminSendPortfolioSummary failed: $e');
      return const notif.NotificationApiResponse(success: false, message: 'Network error');
    }
  }

  // ─── P5: Engagement & Features (Admin) ───────────────────────────────────

  /// Notify about a new coin listing (admin).
  Future<notif.NotificationApiResponse> adminNotifyNewListing(
    notif.NewListingRequest request,
  ) async {
    try {
      final response = await _dio.post(
        'admin/notifications/new-listing',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      return notif.NotificationApiResponse.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('⚠️ adminNotifyNewListing failed: $e');
      return const notif.NotificationApiResponse(success: false, message: 'Network error');
    }
  }

  /// Send breaking news notification (admin).
  Future<notif.NotificationApiResponse> adminSendBreakingNews(
    notif.BreakingNewsRequest request,
  ) async {
    try {
      final response = await _dio.post(
        'admin/notifications/breaking-news',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      return notif.NotificationApiResponse.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('⚠️ adminSendBreakingNews failed: $e');
      return const notif.NotificationApiResponse(success: false, message: 'Network error');
    }
  }

  /// Send app update notification (admin).
  Future<notif.NotificationApiResponse> adminNotifyAppUpdate(
    notif.AppUpdateRequest request,
  ) async {
    try {
      final response = await _dio.post(
        'admin/notifications/app-update',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      return notif.NotificationApiResponse.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('⚠️ adminNotifyAppUpdate failed: $e');
      return const notif.NotificationApiResponse(success: false, message: 'Network error');
    }
  }

  /// Send reward/airdrop notification (admin).
  Future<notif.NotificationApiResponse> adminSendReward(
    notif.RewardRequest request,
  ) async {
    try {
      final response = await _dio.post(
        'admin/notifications/reward',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      return notif.NotificationApiResponse.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('⚠️ adminSendReward failed: $e');
      return const notif.NotificationApiResponse(success: false, message: 'Network error');
    }
  }

  /// Send broadcast notification to all users (admin).
  Future<notif.NotificationApiResponse> adminSendBroadcast(
    notif.BroadcastRequest request,
  ) async {
    try {
      final response = await _dio.post(
        'admin/notifications/broadcast',
        data: request.toJson(),
        options: Options(headers: await _getHeaders()),
      );
      return notif.NotificationApiResponse.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('⚠️ adminSendBroadcast failed: $e');
      return const notif.NotificationApiResponse(success: false, message: 'Network error');
    }
  }
}

/// 📊 مدل داده نقطه نمودار V2 — از Cache Proxy دریافت می‌شود
class ChartDataPointV2 {
  final DateTime timestamp;
  final double price;

  ChartDataPointV2({required this.timestamp, required this.price});
} 