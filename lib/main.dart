import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'utils/secure_log.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/scheduler.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';

import 'di/injection_container.dart';
import 'di/service_locator.dart';
import 'services/service_provider.dart';
import 'services/notification_helper.dart';
import 'services/secure_storage.dart';
import 'services/wallet_state_manager.dart';
import 'services/session_manager.dart';
import 'wallet/migration/wallet_migration_service.dart';
import 'services/language_manager.dart';
import 'services/security_settings_manager.dart';
import 'services/screen_cache_manager.dart';
import 'services/v2_notification_poller.dart';
import 'services/firebase_messaging_service.dart';
import 'providers/history_provider.dart';
import 'providers/network_provider.dart';
import 'providers/app_provider.dart';
import 'providers/price_provider.dart';
import 'providers/client_panel_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/session_provider.dart';
import 'layout/network_overlay.dart';
import 'widgets/global_error_listener.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/passcode_manager.dart';
import 'services/tsp_agent_bootstrap.dart';
import 'navigation/app_navigator.dart';
import 'navigation/app_navigation_state.dart';
import 'navigation/app_router.dart';
import 'navigation/fast_route_resolver.dart';
import 'navigation/route_paths.dart';
import 'navigation/session_lock_coordinator.dart';
import 'services/build_secrets.dart';
import 'services/wallet_secrets_store.dart';
import 'wallet/core/wallet_core_bootstrap.dart';
import 'theme/app_theme.dart';
import 'theme/app_theme_notifier.dart';
import 'services/version_check_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

const Duration _kStartupTimeout = Duration(seconds: 12);

/// Heavy startup (Keychain, TspAgent, Wallet Core) — must not block [runApp].
Future<void> runDeferredMainBootstrap() async {
  if (kIsWeb) return;
  await Future.wait([
    bootstrapTspAgent().timeout(_kStartupTimeout).catchError((e, st) {
      SecureLog.e('bootstrapTspAgent deferred failed: $e\n$st');
    }),
    WalletCoreBootstrap.initialize().timeout(_kStartupTimeout).catchError((e, st) {
      SecureLog.e('WalletCoreBootstrap deferred failed: $e\n$st');
    }),
    WalletSecretsStore.ensureMigratedFromLegacyPrefs()
        .timeout(_kStartupTimeout)
        .catchError((e, st) {
      SecureLog.e('WalletSecretsStore migration deferred failed: $e\n$st');
    }),
  ]);
  try {
    BuildSecrets.validateForCurrentMode();
  } catch (e, st) {
    SecureLog.e('BuildSecrets validation: $e\n$st');
  }
}

/// Run this BEFORE FastRouteResolver so the resolver sees a consistent,
/// cleaned-up storage state.
Future<void> _clearOrphanedSecureStorageIfFreshInstall() async {
  try {
    final prefs = await SharedPreferences.getInstance();

    // If version history exists this is NOT a fresh install → skip.
    if (prefs.containsKey('last_known_version') ||
        prefs.containsKey('last_known_build')) {
      SecureLog.i('Version history exists → not a fresh install, skipping cleanup');
      return;
    }

    // SharedPreferences is empty (wiped on uninstall) but SecureStorage
    // / Keychain may still hold orphaned data from a previous install.
    SecureLog.i('No version history — checking SecureStorage for orphaned data...');

    final walletManager = ServiceLocator.get<WalletStateManager>();
    final hasWallet = await walletManager.hasWallet();
    final hasValidWallet = await walletManager.hasValidWallet();
    final hasPasscode = await walletManager.hasPasscode();

    SecureLog.i('Orphan check — hasWallet=$hasWallet, hasValidWallet=$hasValidWallet, hasPasscode=$hasPasscode');

    // GUARD: If a valid wallet exists, NEVER touch SecureStorage.
    if (hasValidWallet) {
      SecureLog.i('Valid wallet detected — preserving ALL data');
      await prefs.setBool('_fresh_install_cleanup_done', true);
      return;
    }

    // GUARD: If passcode is set without a valid wallet wallet,
    // treat cautiously — the user likely has a wallet but the
    // wallets-list JSON was lost. DO NOT delete anything.
    if (hasPasscode) {
      SecureLog.w('Passcode exists without valid wallet — treating cautiously, preserving data');
      await prefs.setBool('_fresh_install_cleanup_done', true);
      return;
    }

    // SAFETY: If any wallet-related keys exist, NEVER delete SecureStorage data.
    // On iOS, hasValidWallet() may intermittently return false due to Keychain
    // timing, but hasWallet() returning true means real wallet data IS present.
    // Deleting would permanently lose the user's funds.
    if (hasWallet) {
      SecureLog.w('Wallet keys found but no valid wallet — preserving data to prevent loss');
      await prefs.setBool('_fresh_install_cleanup_done', true);
      return;
    }

    // Only delete if we have ABSOLUTELY nothing — clean fresh install.
    SecureLog.i('Truly fresh install — nothing to clean');
    await prefs.setBool('_fresh_install_cleanup_done', true);
    return;
  } catch (e) {
    SecureLog.e('_clearOrphanedSecureStorageIfFreshInstall error', error: e);
  }
}

void main() async {
  final stopwatch = Stopwatch()..start();
  
  // 🛡️ Global zone to catch any unhandled async errors that might hang startup
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 🔒 Lock orientation to portrait
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // 1. Initialize Firebase FIRST.
    // Firebase.initializeApp() MUST be called before FirebaseMessagingService
    // is constructed (inside InjectionContainer), because its instance field
    // accesses FirebaseMessaging.instance (which calls Firebase.app()).
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 8));
      SecureLog.d('Firebase initialized');
    } catch (e) {
      SecureLog.e('Firebase initialization failed: $e');
      // Continue anyway, app might still work without push notifications
    }

    // 🏗️ Initialize Dependency Injection container SECOND.
    // This registers all services in the correct order before any
    // .instance calls. All singleton getters delegate to GetIt.
    await InjectionContainer.initialize();
    SecureLog.d('DI container initialized');

    // 2. Parallelize initializations.
    // We run FastRouteResolver and other essential services in parallel.
    final initialRouteFuture = FastRouteResolver.resolve();
    final essentialInitFuture = Future.wait([
      EasyLocalization.ensureInitialized().catchError((e) => SecureLog.e('EasyLocalization init: $e')),
      Future.sync(() => ServiceLocator.get<ServiceProvider>().initialize()),
    ]);

    // Also check for app updates in parallel.
    final versionCheckFuture = Future(() async {
      if (kDebugMode) {
        // 🧪 DEBUG MODE: No mock forced update — only show update screen
        // when the server reports a version mismatch (like release builds).
        // To test the force-update UI locally, temporarily change
        // UpdateType.none → UpdateType.force or UpdateType.optional.
        SecureLog.d('DEBUG: version check skipped (no mock forced update)');
        return VersionStatus(type: UpdateType.none);
      }
      return await VersionCheckService.checkVersion();
    }).catchError((e) {
      SecureLog.e('Version check failed: $e');
      return VersionStatus(type: UpdateType.none);
    });

    try {
      // Wait for essential services and initial route location.
      // 10 seconds is plenty for local storage reads and basic service init.
      await Future.wait([
        essentialInitFuture,
        initialRouteFuture,
        versionCheckFuture,
      ]).timeout(const Duration(seconds: 12));
      
      final initialRoute = await initialRouteFuture;
      final versionStatus = await versionCheckFuture;

      // 🚨 If a force update is required, go directly to the update screen
      // — no flash of passcode / home / splash. The initial location
      // is set before runApp so the first frame shows the right page.
      if (versionStatus.type == UpdateType.force) {
        AppRouter.pendingVersionStatus = versionStatus;
        AppRouter.setInitialLocation(RoutePaths.forceUpdate);
        SecureLog.d('Force update required — initial route: /force-update');
      } else {
        AppRouter.setInitialLocation(initialRoute);
        SecureLog.d('Essential startup completed in ${stopwatch.elapsedMilliseconds}ms. Route: $initialRoute');
      }
      
      // 3. Kick off secondary services in background without blocking runApp.
      unawaited(Future.wait([
        NotificationHelper.initialize().catchError((e) => SecureLog.e('NotificationHelper init: $e')),
        // Only access instance if Firebase might be ready
        ServiceLocator.get<FirebaseMessagingService>().initialize().catchError((e) => SecureLog.e('FirebaseMessagingService init: $e')),
        _clearOrphanedSecureStorageIfFreshInstall().catchError((e) => SecureLog.e('Orphan check failed: $e')),
      ]));
      
    } catch (e) {
      SecureLog.w('Startup timed out or failed: $e. Falling back to default route.');
      AppRouter.setInitialLocation(RoutePaths.importCreate);
    }

    runApp(
      EasyLocalization(
        supportedLocales: const [
          Locale('en'),
          Locale('fa'),
          Locale('tr'),
          Locale('ar'),
          Locale('zh'),
          Locale('es'),
        ],
        path: 'assets/locales',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        child: const MyApp(),
      ),
    );
  }, (error, stack) {
    SecureLog.e('CRITICAL startup error: $error\n$stack');
    
    // Only show the fatal error screen if the app hasn't fully started yet.
    // If it has started, we don't want to replace the whole UI for a potentially
    // non-fatal async error (like setState after dispose).
    if (!ServiceLocator.get<AppNavigationState>().bootstrapComplete) {
      try {
        runApp(const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'App failed to start. Please restart.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ));
      } catch (e) {
        SecureLog.e('Error showing error dialog', error: e);
      }
    }
  });
}

/// Get User ID from SecureStorage
Future<String?> _getUserId() async {
  try {
    return await SecureStorage.getUserId();
  } catch (e) {
    SecureLog.e('Error getting User ID', error: e);
    return null;
  }
}

/// Get Wallet ID from SecureStorage
Future<String?> _getWalletId() async {
  try {
    return await SecureStorage.getWalletId();
  } catch (e) {
    SecureLog.e('Error getting Wallet ID', error: e);
    return null;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  String? _userId;
  final bool _hasPasscode = false;
  DateTime? _lastBackgroundTime;
  final bool _isInitialized = false;
  
  late final SecuritySettingsManager _securityManager;
  // Guard flag: prevents the safety timer from calling completeBootstrap()
  // while startup tasks are still actively running (race condition fix).
  bool _startupInProgress = false;

  @override
  void initState() {
    super.initState();
    _securityManager = ServiceLocator.get<SecuritySettingsManager>();
    WidgetsBinding.instance.addObserver(this);
    
    // 🛡️ Safety fallback: Force complete bootstrap after 25 seconds
    // ONLY if startup is not actively in progress (prevents race condition
    // where completeBootstrap() fires during _initializeApp()).
    Timer(const Duration(seconds: 25), () {
      if (mounted && !ServiceLocator.get<AppNavigationState>().bootstrapComplete) {
        if (!_startupInProgress) {
          SecureLog.w('Safety fallback: Bootstrap was hanging, forcing completion');
          ServiceLocator.get<AppNavigationState>().completeBootstrap();
        } else {
          SecureLog.d('Safety fallback skipped: startup still in progress');
        }
      }
    });

    _startupInProgress = true;
    unawaited(_runAppStartup().whenComplete(() {
      _startupInProgress = false;
    }));
  }

  Future<void> _runAppStartup() async {
    try {
      // 1. Read version status (already checked in main()).
      final versionStatus = AppRouter.pendingVersionStatus;

      // If a force update was detected in main(), the initial route is
      // already /force-update — just block all bootstrap.
      if (versionStatus != null && versionStatus.type == UpdateType.force) {
        SecureLog.d('Force update in progress — bootstrap skipped');
        return;
      }

      await runDeferredMainBootstrap().timeout(const Duration(seconds: 15));
      await _initializeSecurityManager().timeout(const Duration(seconds: 5));
      SecureLog.i('SecuritySettingsManager initialized, now initializing app');
      await _initializeApp().timeout(const Duration(seconds: 15));

      // 2. If optional update, show it after the app is initialized
      if (versionStatus != null && versionStatus.type == UpdateType.optional) {
        if (appNavigatorKey.currentContext != null && mounted) {
          AppRouter.router.go(
            RoutePaths.forceUpdate,
            extra: versionStatus,
          );
        }
      }

      SecureLog.i('All initialization tasks completed in sequence');
    } catch (e, st) {
      SecureLog.e('Error in initialization sequence', error: e, stackTrace: st);
      if (mounted) {
        AppRouter.router.go(RoutePaths.importCreate);
        ServiceLocator.get<AppNavigationState>().completeBootstrap();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Listen to app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused) {
      // App goes to background
      final now = DateTime.now();
      _lastBackgroundTime = now;
      
      // Save background time using SecuritySettingsManager
      await _securityManager.saveLastBackgroundTime();
      
      // 🛡️ Defense-in-depth: Clear memory cache when app goes to background
      ServiceLocator.get<SecureStorage>().clearMemoryCache();
      
      SecureLog.i('App went to background — memory cache cleared');
    } else if (state == AppLifecycleState.resumed) {
      // App comes to foreground
      SecureLog.i('App resumed from background');
      
      // 🔒 CRITICAL: Check if passcode is enabled and set
      final isPasscodeEnabled = await _securityManager.isPasscodeEnabled();
      final hasPasscode = await PasscodeManager.isPasscodeSet();
      
      if (!isPasscodeEnabled) {
        SecureLog.w('SECURITY WARNING: Passcode disabled - crypto wallet unprotected!');
        return;
      }
      
      if (!hasPasscode) {
        SecureLog.w('SECURITY WARNING: No passcode set - crypto wallet unprotected!');
        return;
      }
      
      // 🔒 PRIORITY 1: Check if app passcode should be shown  
      final shouldShowPasscode = await _securityManager
          .shouldShowPasscodeAfterBackground()
          .timeout(const Duration(seconds: 4), onTimeout: () {
        SecureLog.w('Security Check TIMED OUT during resume');
        return false;
      });
      
      if (shouldShowPasscode) {
        final currentLoc = AppRouter.router.routerDelegate.currentConfiguration.uri.toString();
        if (currentLoc != RoutePaths.enterPasscode) {
          final uri = AppRouter.router.routerDelegate.currentConfiguration.uri
              .toString();
          await SessionLockCoordinator.saveReturnUri(uri);
          ServiceLocator.get<AppNavigationState>().setSessionLockRequired(true);
          SchedulerBinding.instance.addPostFrameCallback((_) {
            AppRouter.router.go(RoutePaths.enterPasscode);
          });
        } else {
          SecureLog.i('Already on passcode screen, not redirecting');
        }
      } else {
        SecureLog.i('SECURITY: Auto-lock not triggered - within configured time limit or disabled');
        
        // 🔄 IMPORTANT: If no lock required, reset activity timer for foreground event
        await _securityManager.resetActivityTimer();
      }
    }
  }

  Future<void> _initializeSecurityManager() async {
    try {
      // Initialize security settings with defaults
      await _securityManager.initialize();
      
      // Get summary after initialization
      final summary = await _securityManager.getSecuritySettingsSummary();
      SecureLog.i('Security settings initialized');
    } catch (e) {
      SecureLog.e('Error initializing security manager', error: e);
    }
  }

  /// اجرای تسک‌های پس‌زمینه که قبلاً در SplashScreen بود
  Future<void> _runBackgroundTasks() async {
    try {
      await ServiceLocator.get<WalletMigrationService>().runIfNeeded().timeout(const Duration(seconds: 10));
    } catch (e) {
      SecureLog.w('Error running background migration', error: e);
    }
  }

  /// Initial app setup — route is already correct (set via
  /// [FastRouteResolver] in main() before runApp).
  Future<void> _initializeApp() async {
    try {
      // NOTE: Orphaned-data cleanup already ran in main() before
      // FastRouteResolver. No need to repeat it here.

      // 🔄 Background tasks (wallet migration, etc.).
      await _runBackgroundTasks();

      // 🎯 Initialize SessionManager for persistent session state.
      await ServiceLocator.get<SessionManager>().initialize();

      // 🔄 Clear previous session lock so the redirect guard
      // does not re-route to enter-passcode unnecessarily.
      await _securityManager.clearLastBackgroundTime();
      ServiceLocator.get<AppNavigationState>().setSessionLockRequired(false);

      SecureLog.i('Bootstrap complete — completing navigation state');
      ServiceLocator.get<AppNavigationState>().completeBootstrap();
      SecureLog.i('completeBootstrap() called');

      // Track version in SharedPreferences so that
      // _clearOrphanedSecureStorageIfFreshInstall can skip its checks
      // on subsequent launches.
      unawaited(_saveVersionInfo().catchError((e) {
        SecureLog.w('Failed to save version info', error: e);
      }));

      // Language after first route (do not block initial paint).
      unawaited(
        LanguageManager.initializeLanguage(context).catchError((e) {
          SecureLog.e('Language init', error: e);
        }),
      );
      _userId = await _getUserId();

      // 🎯 Start V2 notification poller for non-custodial transaction alerts
      if (_userId != null && _userId!.isNotEmpty) {
        unawaited(
          ServiceLocator.get<V2NotificationPoller>().start(walletId: _userId!).catchError((e) {
            SecureLog.e('V2NotificationPoller start: $e');
          }),
        );
      }

      // Pre-load screen-cache data so subsequent screens
      // render from memory instead of showing spinners.
      if (_userId != null) {
        ServiceLocator.get<ScreenCacheManager>()
            .preloadCriticalData(_userId!, _userId!)
            .catchError((_) {});
      }

      // Non-critical operations in background (don't await)
      _testServerConnection().then((result) {
        SecureLog.i(result ? 'Server connection successful' : 'Server connection failed');
      });
      
      ServiceLocator.get<ServiceProvider>().showNetworkStatus().then((_) {
        SecureLog.i('Network status shown');
      });
      
      if (kDebugMode) {
        _checkPasscodeDebug();
      }
      
      SecureLog.i('All app initialization completed in parallel');
    } catch (e) {
      if (mounted) {
        AppRouter.router.go(RoutePaths.importCreate);
        ServiceLocator.get<AppNavigationState>().completeBootstrap();
      }
    }
  }
  
  /// Save the current app version to SharedPreferences so that
  /// _clearOrphanedSecureStorageIfFreshInstall skips its checks on relaunch.
  Future<void> _saveVersionInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_known_version', info.version);
      await prefs.setString('last_known_build', info.buildNumber);
      SecureLog.d('Saved version info: ${info.version} (build ${info.buildNumber})');
    } catch (e) {
      SecureLog.w('_saveVersionInfo error', error: e);
    }
  }

  /// Helper method for server connection testing
  Future<bool> _testServerConnection() async {
    SecureLog.i('Testing server connection...');
    final isConnected = await ServiceLocator.get<ServiceProvider>().testServerConnection('api.coingecko.com');
    if (isConnected) {
      SecureLog.i('Server connection successful');
    } else {
      SecureLog.w('Server connection failed - app will work with limited functionality');
    }
    return isConnected;
  }
  
  /// Debug iOS keychain access issues
  Future<void> _debugiOSKeychainAccess() async {
    if (!Platform.isIOS) return;
    
    try {
      SecureLog.d('=== iOS KEYCHAIN DEBUG ===');
      
      // Test direct keychain access
      const storage = FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock,
          synchronizable: false,
          accountName: 'com.coinceeper.app',
          groupId: null,
        ),
      );
      
      // Test write/read cycle
      final testKey = 'ios_keychain_test_${DateTime.now().millisecondsSinceEpoch}';
      final testValue = 'test_value_${DateTime.now().millisecondsSinceEpoch}';
      
      SecureLog.d('Testing keychain write...');
      await storage.write(key: testKey, value: testValue);
      
      SecureLog.d('Testing keychain read...');
      final readValue = await storage.read(key: testKey);
      
      if (readValue == testValue) {
        SecureLog.d('Keychain access working correctly');
      } else {
        SecureLog.d('Keychain access failed - read/write mismatch');
      }
      
      // Clean up test key
      await storage.delete(key: testKey);
      
      // Test SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final prefsTestKey = 'ios_prefs_test_${DateTime.now().millisecondsSinceEpoch}';
      final prefsTestValue = 'prefs_test_value_${DateTime.now().millisecondsSinceEpoch}';
      
      SecureLog.d('Testing SharedPreferences write...');
      await prefs.setString(prefsTestKey, prefsTestValue);
      
      SecureLog.d('Testing SharedPreferences read...');
      final prefsReadValue = prefs.getString(prefsTestKey);
      
      if (prefsReadValue == prefsTestValue) {
        SecureLog.d('SharedPreferences access working correctly');
      } else {
        SecureLog.d('SharedPreferences access failed - read/write mismatch');
      }
      
      // Clean up test key
      await prefs.remove(prefsTestKey);
      
      SecureLog.d('=== END iOS KEYCHAIN DEBUG ===');
      
    } catch (e) {
      SecureLog.e('iOS keychain debug error', error: e);
    }
  }

  /// Helper method for passcode debugging
  Future<void> _checkPasscodeDebug() async {
    try {
      // Debug: Enhanced passcode debugging for iOS issue
      SecureLog.d('=== ENHANCED PASSCODE DEBUGGING ===');
      
      // Check both SharedPreferences and SecureStorage
      final prefs = await SharedPreferences.getInstance();
      final passcodeHash = prefs.getString('passcode_hash');
      final passcodeSalt = prefs.getString('passcode_salt');
      SecureLog.d('SharedPreferences passcode_hash = ${passcodeHash != null ? "EXISTS" : "NULL"}');
      SecureLog.d('SharedPreferences passcode_salt = ${passcodeSalt != null ? "EXISTS" : "NULL"}');
      
      // Check SecureStorage backup
      const secureStorage = FlutterSecureStorage();
      final secureHash = await secureStorage.read(key: 'passcode_hash_secure');
      final secureSalt = await secureStorage.read(key: 'passcode_salt_secure');
      SecureLog.d('SecureStorage passcode_hash_secure = ${secureHash != null ? "EXISTS" : "NULL"}');
      SecureLog.d('SecureStorage passcode_salt_secure = ${secureSalt != null ? "EXISTS" : "NULL"}');
      
      // Use PasscodeManager to check (this will use the new backup logic)
      final isPasscodeSetResult = await PasscodeManager.isPasscodeSet();
      SecureLog.d('PasscodeManager.isPasscodeSet() = $isPasscodeSetResult');
      
      SecureLog.d('=== END PASSCODE DEBUGGING ===');
    } catch (e) {
      SecureLog.e('Error checking passcode debug', error: e);
    }
  }



  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) {
            final appProvider = AppProvider();
            // Initialize AppProvider after the widget tree is built
            WidgetsBinding.instance.addPostFrameCallback((_) {
              appProvider.initialize();
            });
            return appProvider;
          },
        ),
        ChangeNotifierProvider(
          create: (context) => HistoryProvider(),
        ),
        ChangeNotifierProvider(
          create: (context) => NetworkProvider(),
        ),
        ChangeNotifierProvider(
          create: (context) {
            final priceProvider = PriceProvider();
            // Initialize PriceProvider after the widget tree is built
            WidgetsBinding.instance.addPostFrameCallback((_) {
              priceProvider.loadSelectedCurrency();
            });
            return priceProvider;
          },
        ),
        ChangeNotifierProvider.value(
          value: ServiceLocator.get<ServiceProvider>().networkManager,
        ),
        ChangeNotifierProvider(
          create: (_) => ClientPanelProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) {
            final sp = ServiceLocator.get<SessionProvider>();
            sp.initialize();
            return sp;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final np = ServiceLocator.get<NotificationProvider>();
            np.initialize();
            return np;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final n = AppThemeNotifier();
            n.load();
            return n;
          },
        ),
      ],
      child: Consumer<AppThemeNotifier>(
        builder: (context, themeNotifier, _) {
          return MaterialApp.router(
          routerConfig: AppRouter.router,
          title: 'coinceeper',
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeNotifier.materialThemeMode,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final scaled = mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.35,
            );
            final routedChild = child ??
                const SizedBox.shrink(
                  key: ValueKey('bootstrap_fallback_loading'),
                );

            // Set system UI overlay style based on theme brightness
            final isDark = themeNotifier.materialThemeMode == ThemeMode.dark ||
                (themeNotifier.materialThemeMode == ThemeMode.system &&
                    mq.platformBrightness == Brightness.dark);

            final systemUiStyle = SystemUiOverlayStyle(
              statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
              statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
              systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            );

            return MediaQuery(
              data: mq.copyWith(textScaler: scaled),
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: systemUiStyle,
                child: NetworkOverlay(
                  child: GlobalErrorListener(child: routedChild),
                ),
              ),
            );
          },
        );
        },
      ),
    );
  }
}