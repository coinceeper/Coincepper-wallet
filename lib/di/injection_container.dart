import '../navigation/app_navigation_state.dart';
import '../navigation/sensitive_route_observer.dart';
import '../navigation/wallet_session.dart';
import '../providers/notification_provider.dart';
import '../providers/session_provider.dart';
import '../utils/secure_log.dart';
import '../domain/interfaces/wallet_data_source.dart';
import '../domain/interfaces/settings_data_source.dart';
import '../domain/interfaces/i_security_manager.dart';
import '../domain/interfaces/i_fee_estimator.dart';
import '../domain/interfaces/i_address_book.dart';
import '../domain/interfaces/i_balance_manager.dart';
import '../domain/interfaces/i_error_service.dart';
import '../domain/interfaces/i_transaction_notifier.dart';
import '../domain/services/app_settings_service.dart';
import '../domain/services/fee_estimation_service.dart';
import '../domain/services/send_transaction_service.dart';
import '../domain/services/wallet_service.dart';
import '../domain/services/address_validation_service.dart';
import '../domain/services/security_service.dart';
import '../domain/services/token_provider_coordinator.dart';
import '../services/backend_proxy_service.dart';
import '../services/geo_proxy_service.dart';
import '../services/balance_display_manager.dart';
import '../services/balance_manager.dart';
import '../services/broadcast_service.dart';
import '../services/chart_data_manager.dart';
import '../services/chart_data_service.dart';
import '../services/claim_coordinator.dart';
import '../services/client_auth_service.dart';
import '../services/client_panel_service.dart';
import '../services/auth_interceptor.dart';
import '../services/session_manager.dart';
import '../services/coingecko_service.dart';
import '../services/device_auth_service.dart';
import '../services/device_fingerprint_service.dart';
import '../services/device_registration_manager.dart';
import '../services/dex_service.dart';
import '../services/enhanced_network_manager.dart';
import '../services/error_service.dart';
import '../services/firebase_messaging_service.dart';
import '../services/lifecycle_manager.dart';
import '../services/locale_manager.dart';
import '../services/local_fee_estimator.dart';
import '../services/network_manager.dart';
import '../services/network_monitor.dart';
import '../services/on_chain_balance_service.dart';
import '../utils/performance_cache.dart';
import '../services/permission_manager.dart';
import '../services/platform_storage_manager.dart';
import '../services/portfolio_service.dart';
import '../services/screen_cache_manager.dart';
import '../services/secure_memory_cache.dart';
import '../services/secure_storage.dart';
import '../services/address_book_service.dart';
import '../services/security_settings_manager.dart';
import '../services/service_provider.dart';
import '../services/transaction_notification_receiver.dart';
import '../services/unified_cache_manager.dart';
import '../services/v2_notification_poller.dart';
import '../services/wallet_state_manager.dart';
import '../services/web3_service.dart';
import '../wallet/address_registry.dart';
import '../wallet/core/wallet_core_bridge_native.dart';
import '../wallet/history/history_db.dart';
import '../wallet/history/history_indexer.dart';
import '../wallet/keys/secure_key_vault.dart';
import '../wallet/migration/wallet_migration_service.dart';
import '../wallet/tokens/token_metadata_service.dart';
import '../wallet/transactions/local_send_facade.dart';
import '../wallet/wallet_repository.dart';
import 'service_locator.dart';

/// ماژول DI مرکزی پروژه
///
/// ## فلسفه طراحی
///
/// این کلاس سرویس‌های اصلی پروژه را در یک نقطه مرکزی و با ترتیب مشخص
/// ثبت می‌کند. ترتیب ثبت بر اساس گراف وابستگی از پایین به بالا است:
///
/// لایه 0: Infrastructure (ابزارهای پایه، بدون وابستگی)
/// لایه 1: Storage (ذخیره‌سازی)
/// لایه 2: Utility Services (سرویس‌های ابزاری)
/// لایه 3: Core Services (سرویس‌های اصلی)
/// لایه 4: Domain Services (سرویس‌های دامنه)
/// لایه 5: Wallet Services (سرویس‌های کیف پول)
/// لایه 6: Navigation & UI Services
///
/// ## نکات مهم
/// - تمام سرویس‌ها از طریق DI container مدیریت می‌شوند
/// - به جای استفاده از `ClassName.instance` از `ServiceLocator.get<ClassName>()` استفاده کنید
/// - سرویس‌هایی که نیاز به مقداردهی اولیه دارند (مانند `initialize()`) 
///   پس از ثبت در container باید جداگانه فراخوانی شوند
class InjectionContainer {
  InjectionContainer._();

  static bool _initialized = false;

  /// آیا DI مقداردهی شده است
  static bool get isInitialized => _initialized;

  /// مقداردهی اولیه سرویس‌ها
  ///
  /// این متد باید **یک بار** در ابتدای `main()` صدا زده شود،
  /// قبل از هر دسترسی به سرویس‌ها.
  static Future<void> initialize() async {
    if (_initialized) return;

    SecureLog.d('🏗️ Injecting all dependencies...');

    _registerInfrastructure();
    _registerStorage();
    _registerUtilityServices();
    _registerCoreServices();
    _registerDomainServices();
    _registerWalletServices();
    _registerNavigationAndUiServices();

    _initialized = true;
    SecureLog.d('✅ DI container initialized with all services registered');
  }

  // ─── Layer 0: Infrastructure ────────────────────────────────

  static void _registerInfrastructure() {
    ServiceLocator.registerSingleton<SecureMemoryCache>(
      () => SecureMemoryCache(),
    );
    ServiceLocator.registerSingleton<NetworkMonitor>(
      () => NetworkMonitor(),
    );
    ServiceLocator.registerLazySingleton<BackendProxyService>(
      () => BackendProxyService(),
    );
    ServiceLocator.registerSingleton<GeoProxyService>(
      () => GeoProxyService(),
    );
    ServiceLocator.registerSingleton<PerformanceCache>(
      () => PerformanceCache(),
    );
    ServiceLocator.registerSingleton<UnifiedCacheManager>(
      () => UnifiedCacheManager(),
    );
    ServiceLocator.registerSingleton<PlatformStorageManager>(
      () => PlatformStorageManager(),
    );
  }

  // ─── Layer 1: Storage ───────────────────────────────────────

  static void _registerStorage() {
    final secureStorage = SecureStorage();
    ServiceLocator.registerSingleton<SecureStorage>(
      () => secureStorage,
    );
    // Interface registrations for Clean Architecture
    ServiceLocator.registerSingletonWithInstance<IWalletDataSource>(secureStorage);
    ServiceLocator.registerSingletonWithInstance<ISettingsDataSource>(secureStorage);
    ServiceLocator.registerSingleton<ScreenCacheManager>(
      () => ScreenCacheManager(),
    );
    ServiceLocator.registerSingleton<SecureKeyVault>(
      () => SecureKeyVault(),
    );
    ServiceLocator.registerSingleton<HistoryDb>(
      () => HistoryDb(),
    );
  }

  // ─── Layer 2: Utility Services ──────────────────────────────

  static void _registerUtilityServices() {
    final errorService = ErrorService();
    ServiceLocator.registerSingleton<ErrorService>(
      () => errorService,
    );
    ServiceLocator.registerSingletonWithInstance<IErrorService>(errorService);
    ServiceLocator.registerSingleton<DeviceRegistrationManager>(
      () => DeviceRegistrationManager(),
    );
    ServiceLocator.registerSingleton<PermissionManager>(
      () => PermissionManager(),
    );
    ServiceLocator.registerLazySingleton<Web3Service>(
      () => Web3Service(),
    );
    ServiceLocator.registerLazySingleton<DexService>(
      () => DexService(),
    );
    ServiceLocator.registerSingleton<NetworkManager>(
      () => NetworkManager(),
    );
    ServiceLocator.registerSingleton<EnhancedNetworkManager>(
      () => EnhancedNetworkManager(),
    );
    ServiceLocator.registerSingleton<ChartDataService>(
      () => ChartDataService(),
    );
    ServiceLocator.registerSingleton<ChartDataManager>(
      () => ChartDataManager(),
    );
    ServiceLocator.registerSingleton<LocaleManager>(
      () => LocaleManager(),
    );
    ServiceLocator.registerSingleton<LifecycleManager>(
      () => LifecycleManager(),
    );
    ServiceLocator.registerSingleton<DeviceAuthService>(
      () => DeviceAuthService(),
    );
    final feeEstimator = LocalFeeEstimator();
    ServiceLocator.registerSingleton<LocalFeeEstimator>(
      () => feeEstimator,
    );
    ServiceLocator.registerSingletonWithInstance<IFeeEstimator>(feeEstimator);
    ServiceLocator.registerSingleton<BroadcastService>(
      () => BroadcastService(),
    );
    ServiceLocator.registerSingleton<ClaimCoordinator>(
      () => ClaimCoordinator(),
    );
    ServiceLocator.registerSingleton<IAddressBookService>(
      () => AddressBookService(),
    );
  }

  // ─── Layer 3: Core Services ─────────────────────────────────

  static void _registerCoreServices() {
    ServiceLocator.registerSingleton<CoinGeckoService>(
      () => CoinGeckoService(),
    );
    ServiceLocator.registerSingleton<OnChainBalanceService>(
      () => OnChainBalanceService(),
    );
    ServiceLocator.registerSingleton<ServiceProvider>(
      () => ServiceProvider(),
    );
    ServiceLocator.registerSingleton<WalletStateManager>(
      () => WalletStateManager(),
    );
    ServiceLocator.registerLazySingleton<BalanceManager>(
      () => BalanceManager(),
    );
    ServiceLocator.registerLazySingleton<IBalanceManager>(
      () => ServiceLocator.get<BalanceManager>(),
    );
    final securitySettingsManager = SecuritySettingsManager();
    ServiceLocator.registerSingleton<SecuritySettingsManager>(
      () => securitySettingsManager,
    );
    ServiceLocator.registerSingletonWithInstance<ISecurityManager>(securitySettingsManager);
    ServiceLocator.registerSingleton<DeviceFingerprintService>(
      () => DeviceFingerprintService(),
    );
    ServiceLocator.registerSingleton<SessionManager>(
      () => SessionManager(),
    );
    ServiceLocator.registerSingleton<ClientPanelAuthInterceptor>(
      () => ClientPanelAuthInterceptor(),
    );
    ServiceLocator.registerSingleton<SessionProvider>(
      () => SessionProvider(),
    );
    ServiceLocator.registerLazySingleton<ClientPanelService>(
      () => ClientPanelService(),
    );
    ServiceLocator.registerLazySingleton<ClientAuthService>(
      () => ClientAuthService(),
    );
    ServiceLocator.registerLazySingleton<V2NotificationPoller>(
      () => V2NotificationPoller(),
    );
    ServiceLocator.registerSingleton<FirebaseMessagingService>(
      () => FirebaseMessagingService(),
    );
    final txnNotifier = TransactionNotificationReceiver();
    ServiceLocator.registerSingleton<TransactionNotificationReceiver>(
      () => txnNotifier,
    );
    ServiceLocator.registerSingletonWithInstance<ITransactionNotifier>(txnNotifier);
    ServiceLocator.registerSingleton<BalanceDisplayManager>(
      () => BalanceDisplayManager(),
    );
    ServiceLocator.registerSingleton<PortfolioService>(
      () => PortfolioService(),
    );
  }

  // ─── Layer 4: Domain Services ───────────────────────────────

  static void _registerDomainServices() {
    ServiceLocator.registerSingleton<AppSettingsService>(
      () => AppSettingsService(),
    );
    ServiceLocator.registerSingleton<WalletService>(
      () => WalletService(),
    );
    ServiceLocator.registerSingleton<SecurityService>(
      () => SecurityService(),
    );
    ServiceLocator.registerSingleton<TokenProviderCoordinator>(
      () => TokenProviderCoordinator(),
    );
    ServiceLocator.registerSingleton<FeeEstimationService>(
      () => FeeEstimationService(),
    );
    ServiceLocator.registerSingleton<SendTransactionService>(
      () => SendTransactionService(),
    );
    ServiceLocator.registerSingleton<AddressValidationService>(
      () => AddressValidationService(),
    );
  }

  // ─── Layer 5: Wallet Services ───────────────────────────────

  static void _registerWalletServices() {
    ServiceLocator.registerSingleton<WalletCoreBridge>(
      () => WalletCoreBridge(),
    );
    ServiceLocator.registerSingleton<TokenMetadataService>(
      () => TokenMetadataService(),
    );
    ServiceLocator.registerSingleton<WalletMigrationService>(
      () => WalletMigrationService(),
    );
    ServiceLocator.registerSingleton<HistoryIndexer>(
      () => HistoryIndexer(),
    );
    ServiceLocator.registerSingleton<AddressRegistry>(
      () => AddressRegistry(),
    );
    ServiceLocator.registerSingleton<WalletRepository>(
      () => WalletRepository(),
    );
    ServiceLocator.registerSingleton<LocalSendFacade>(
      () => LocalSendFacade(),
    );
  }

  // ─── Layer 6: Navigation & UI Services ──────────────────────

  static void _registerNavigationAndUiServices() {
    ServiceLocator.registerSingleton<SensitiveRouteObserver>(
      () => SensitiveRouteObserver(),
    );
    ServiceLocator.registerSingleton<WalletSession>(
      () => WalletSession(),
    );
    ServiceLocator.registerSingleton<AppNavigationState>(
      () => AppNavigationState(),
    );
    ServiceLocator.registerLazySingleton<NotificationProvider>(
      () => NotificationProvider(),
    );
  }

  /// بازنشانی همه سرویس‌ها (برای تست‌ها)
  static Future<void> reset() async {
    ServiceLocator.reset();
    _initialized = false;
    SecureLog.d('🔄 DI container reset');
  }
}
