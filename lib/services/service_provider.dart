import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../di/service_locator.dart';
import '../utils/secure_log.dart';
import 'api_service.dart';
import 'backend_proxy_service.dart';
import 'build_secrets.dart';
import 'network_monitor.dart';
import '../models/crypto_token.dart';

/// Provider for managing API services
/// This class uses the Singleton pattern
class ServiceProvider {
  static ServiceProvider get instance => ServiceLocator.get<ServiceProvider>();
  
  ServiceProvider._();
  /// DI constructor. Use [instance] for singleton access.
  ServiceProvider();
  
  // Main services
  late final ApiService _apiService;
  late final NetworkMonitor _networkManager;
  
  // Initialization status
  bool _isInitialized = false;
  
  /// Check if services are initialized
  bool get isInitialized => _isInitialized;
  
  /// Initialize services
  void initialize() {
    if (_isInitialized) return;
    
    _networkManager = ServiceLocator.get<NetworkMonitor>();
    _apiService = ApiService();

    // Initialize Backend Proxy if configured
    if (BuildSecrets.isProxyConfigured) {
      ServiceLocator.get<BackendProxyService>().initialize(
        baseUrl: BuildSecrets.proxyBaseUrl,
      );
      SecureLog.d('Backend proxy initialized');
    } else {
      SecureLog.d('Backend proxy not configured — using direct mode');
    }

    _isInitialized = true;
    
    SecureLog.d('All services initialized');
  }

  /// Check if backend proxy is available
  bool get isBackendProxyAvailable =>
      BuildSecrets.isProxyConfigured &&
      ServiceLocator.get<BackendProxyService>().backendStatus != BackendStatus.unavailable;
  
  /// Get API service
  ApiService get apiService => _apiService;
  
  /// Get network manager
  NetworkMonitor get networkManager => _networkManager;
  
  /// Check connection status
  bool get isConnected => _networkManager.isConnected;

  /// Check internet availability
  bool get isInternetAvailable => _networkManager.isInternetAvailable;

  /// Get connection type
  String get connectionType => _networkManager.connectionType;

  /// Get connection quality
  String get connectionQuality => _networkManager.connectionQuality;
  
  /// Get network information
  Map<String, dynamic> getNetworkStatus() {
    return _networkManager.getNetworkStatus();
  }
  
  /// Test server connection
  Future<bool> testServerConnection(String host) async {
    return await _networkManager.checkServerConnection(host);
  }
  
  /// Check internet connection
  Future<bool> checkInternetConnection() async {
    return await _networkManager.checkInternetConnection();
  }

  /// Get crypto token list from API (non-custodial: CoinGecko)
  static Future<List<CryptoToken>> getCryptoTokenListFromApi(ApiService apiService) async {
    try {
      final res = await http.get(
        Uri.parse('https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=100&page=1&sparkline=false'),
      ).timeout(const Duration(seconds: 15));
      
      if (res.statusCode == 200) {
        final List<dynamic> coins = json.decode(res.body);
        return coins.map((c) {
          final m = c as Map<String, dynamic>;
          final sym = (m['symbol']?.toString() ?? '').toUpperCase();
          return CryptoToken(
            name: m['name']?.toString() ?? '',
            symbol: sym,
            blockchainName: m['name']?.toString() ?? '',
            iconUrl: m['image']?.toString() ?? 'https://assets.coingecko.com/coins/images/1/small/bitcoin.png',
            isEnabled: false,
            isToken: true,
            smartContractAddress: null,
          );
        }).toList();
      }
    } catch (e) {
      SecureLog.e('Error getting crypto token list', error: e);
    }
    return [];
  }
  
  /// Check and display network status
  Future<void> showNetworkStatus() async {
    await _networkManager.showNetworkStatus();
  }
}

/// Class for managing application settings
class AppConfig {
  static const String appName = 'Coinceeper Wallet';
  static const String appVersion = '1.0.0';
  static const String buildNumber = '1';
  
  // API settings
  static const String apiBaseUrl = 'https://api.coingecko.com/api/v3/';
  
  // Network settings
  static const Duration requestTimeout = Duration(seconds: 30);
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
  
  // Security settings
  static const bool enableSSLVerification = true;
  static const bool enableCertificatePinning = false;
  
  // Logging settings
  static const bool enableApiLogging = true;
  static const bool enableNetworkLogging = true;
  static const bool enableErrorLogging = true;
  
  // Cache settings
  static const Duration cacheTimeout = Duration(minutes: 5);
  static const int maxCacheSize = 50; // MB
  
  // UI settings
  static const Duration animationDuration = Duration(milliseconds: 300);
  static const Duration loadingTimeout = Duration(seconds: 10);
  
  // Notification settings
  static const bool enablePushNotifications = true;
  static const bool enableLocalNotifications = true;
  
  // Security settings
  static const bool enableBiometricAuth = true;
  static const bool enablePinCode = true;
  static const int pinCodeLength = 6;
  
  // Wallet settings
  static const bool enableAutoBackup = true;
  static const bool enableTransactionHistory = true;
  static const int maxTransactionHistory = 100;
  
  // Currency settings
  static const List<String> supportedCurrencies = [
    'BTC', 'ETH', 'USDT', 'BNB', 'ADA', 'SOL', 'DOT', 'AVAX', 'MATIC', 'LINK'
  ];
  
  static const List<String> supportedFiatCurrencies = [
    'USD', 'EUR', 'GBP', 'JPY', 'KRW', 'CNY', 'INR', 'BRL', 'RUB', 'TRY'
  ];
  
  // Blockchain settings
  static const List<String> supportedBlockchains = [
    'Bitcoin', 'Ethereum', 'Binance', 'Polygon', 'Avalanche', 'Solana', 'Cardano', 'Polkadot', 'Tron', 'Arbitrum'
  ];
}

/// Class for managing errors
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic details;
  
  AppException({
    required this.message,
    this.code,
    this.details,
  });
  
  @override
  String toString() {
    return 'AppException: $message (Code: $code)';
  }
}

/// Class for managing API results
class ApiResult<T> {
  final bool success;
  final T? data;
  final String? message;
  final AppException? error;
  
  ApiResult.success(this.data, {this.message})
      : success = true,
        error = null;
  
  ApiResult.error(this.error, {this.message})
      : success = false,
        data = null;
  
  /// Convert to ApiResult from response
  factory ApiResult.fromResponse(T data, {String? message}) {
    return ApiResult.success(data, message: message);
  }
  
  /// Convert to ApiResult from error
  factory ApiResult.fromError(AppException error, {String? message}) {
    return ApiResult.error(error, message: message);
  }
  
  /// Check success
  bool get isSuccess => success;
  
  /// Check error
  bool get isError => !success;
  
  /// Get data with error checking
  T? get safeData => isSuccess ? data : null;
  
  /// Get message
  String get displayMessage {
    if (isSuccess) {
      return message ?? 'Operation completed successfully';
    } else {
      return message ?? error?.message ?? 'Operation error';
    }
  }
} 