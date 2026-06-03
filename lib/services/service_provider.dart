import 'api_service.dart';
import 'network_monitor.dart';
import '../models/crypto_token.dart';

/// Provider for managing API services
/// This class uses the Singleton pattern
class ServiceProvider {
  static ServiceProvider? _instance;
  static ServiceProvider get instance => _instance ??= ServiceProvider._();
  
  ServiceProvider._();
  
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
    
    _networkManager = NetworkMonitor.instance;
    _apiService = ApiService();
    _isInitialized = true;
    
    print('🚀 API services initialized');
  }
  
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

  /// Get crypto token list from API
  static Future<List<CryptoToken>> getCryptoTokenListFromApi(ApiService apiService) async {
    try {
      final response = await apiService.getAllCurrencies();
      if (response.success) {
        return response.currencies.map((token) => CryptoToken(
          name: token.currencyName ?? '',
          symbol: token.symbol ?? '',
          blockchainName: token.blockchainName ?? '',
          iconUrl: (token.icon == null || token.icon!.isEmpty)
              ? 'https://coinceeper.com/defaultIcons/coin.png'
              : token.icon!,
          isEnabled: false,
          isToken: token.isToken ?? true,
          smartContractAddress: token.smartContractAddress ?? '',
        )).toList();
      }
    } catch (e) {
      print('Error getting crypto token list: $e');
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
  static const String apiBaseUrl = 'https://coinceeper.com/api/';
  
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