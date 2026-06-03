import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/scheduler.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_core/firebase_core.dart';

import 'services/service_provider.dart';
import 'services/network_monitor.dart';
import 'services/notification_helper.dart';
import 'services/secure_storage.dart';
import 'services/wallet_state_manager.dart';
import 'wallet/migration/wallet_migration_service.dart';
import 'services/language_manager.dart';
import 'services/security_settings_manager.dart';
import 'services/screen_cache_manager.dart';
import 'services/uninstall_data_manager.dart';
import 'services/v2_notification_poller.dart';
import 'services/firebase_messaging_service.dart';
import 'providers/history_provider.dart';
import 'providers/network_provider.dart';
import 'providers/app_provider.dart';
import 'providers/price_provider.dart';
import 'providers/client_panel_provider.dart';
import 'providers/notification_provider.dart';
import 'layout/network_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/passcode_manager.dart';
import 'services/tsp_agent_bootstrap.dart';
import 'navigation/app_navigator.dart';
import 'navigation/app_navigation_state.dart';
import 'navigation/app_router.dart';
import 'navigation/fast_route_resolver.dart';
import 'navigation/route_paths.dart';
import 'services/startup_cache.dart';
import 'navigation/session_lock_coordinator.dart';
import 'services/build_secrets.dart';
import 'services/wallet_secrets_store.dart';
import 'wallet/core/wallet_core_bootstrap.dart';
import 'package:go_router/go_router.dart';
import 'theme/app_theme.dart';
import 'theme/app_theme_notifier.dart';

const Duration _kStartupTimeout = Duration(seconds: 5);

/// Heavy startup (Keychain, TspAgent, Wallet Core) — must not block [runApp].
Future<void> runDeferredMainBootstrap() async {
  if (kIsWeb) return;
  await Future.wait([
    bootstrapTspAgent().timeout(_kStartupTimeout).catchError((e, st) {
      debugPrint('bootstrapTspAgent deferred failed: $e\n$st');
    }),
    WalletCoreBootstrap.initialize().timeout(_kStartupTimeout).catchError((e, st) {
      debugPrint('WalletCoreBootstrap deferred failed: $e\n$st');
    }),
    WalletSecretsStore.ensureMigratedFromLegacyPrefs()
        .timeout(_kStartupTimeout)
        .catchError((e, st) {
      debugPrint('WalletSecretsStore migration deferred failed: $e\n$st');
    }),
  ]);
  try {
    BuildSecrets.validateForCurrentMode();
  } catch (e, st) {
    debugPrint('BuildSecrets validation: $e\n$st');
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
      print('🔍 Version history exists → not a fresh install, skipping cleanup');
      return;
    }

    // SharedPreferences is empty (wiped on uninstall) but SecureStorage
    // / Keychain may still hold orphaned data from a previous install.
    print('🔍 No version history — checking SecureStorage for orphaned data...');

    final walletManager = WalletStateManager.instance;
    final hasWallet = await walletManager.hasWallet();
    final hasValidWallet = await walletManager.hasValidWallet();
    final hasPasscode = await walletManager.hasPasscode();

    print('🔍 Orphan check — hasWallet=$hasWallet, hasValidWallet=$hasValidWallet, hasPasscode=$hasPasscode');

    // GUARD: If a valid wallet exists, NEVER touch SecureStorage.
    if (hasValidWallet) {
      print('✅ Valid wallet detected — preserving ALL data');
      await prefs.setBool('_fresh_install_cleanup_done', true);
      return;
    }

    // GUARD: If passcode is set without a valid wallet wallet,
    // treat cautiously — the user likely has a wallet but the
    // wallets-list JSON was lost. DO NOT delete anything.
    if (hasPasscode) {
      print('⚠️ Passcode exists without valid wallet — treating cautiously, preserving data');
      await prefs.setBool('_fresh_install_cleanup_done', true);
      return;
    }

    // Only delete if we have ABSOLUTELY nothing — clean fresh install.
    if (!hasWallet && !hasPasscode) {
      print('🆕 Truly fresh install — nothing to clean');
      await prefs.setBool('_fresh_install_cleanup_done', true);
      return;
    }

    // Has some orphaned keys but no useful data — safe to delete.
    print('🧹 Cleaning orphaned SecureStorage data...');
    await SecureStorage.instance.deleteAll();
    await prefs.setBool('_fresh_install_cleanup_done', true);
    print('✅ Orphaned data cleaned');
  } catch (e) {
    print('❌ _clearOrphanedSecureStorageIfFreshInstall error: $e');
  }
}

void main() async {
  final stopwatch = Stopwatch()..start();
  
  // 🛡️ Global zone to catch any unhandled async errors that might hang startup
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Initialize Firebase first. 
    // This is required before accessing FirebaseMessagingService.instance.
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 8));
      debugPrint('🔥 Firebase initialized');
    } catch (e) {
      debugPrint('❌ Firebase initialization failed: $e');
      // Continue anyway, app might still work without push notifications
    }

    // 2. Parallelize initializations.
    // We run FastRouteResolver and other essential services in parallel.
    final initialRouteFuture = FastRouteResolver.resolve();
    final essentialInitFuture = Future.wait([
      EasyLocalization.ensureInitialized().catchError((e) => debugPrint('❌ EasyLocalization init: $e')),
      Future.sync(() => ServiceProvider.instance.initialize()),
    ]);

    try {
      // Wait for essential services and initial route location.
      // 10 seconds is plenty for local storage reads and basic service init.
      await Future.wait([
        essentialInitFuture,
        initialRouteFuture,
      ]).timeout(const Duration(seconds: 12));
      
      final initialRoute = await initialRouteFuture;
      AppRouter.setInitialLocation(initialRoute);
      
      debugPrint('🚀 Essential startup completed in ${stopwatch.elapsedMilliseconds}ms. Route: $initialRoute');
      
      // 3. Kick off secondary services in background without blocking runApp.
      unawaited(Future.wait([
        NotificationHelper.initialize().catchError((e) => debugPrint('❌ NotificationHelper init: $e')),
        // Only access instance if Firebase might be ready
        FirebaseMessagingService.instance.initialize().catchError((e) => debugPrint('❌ FirebaseMessagingService init: $e')),
        _clearOrphanedSecureStorageIfFreshInstall().catchError((e) => debugPrint('❌ Orphan check failed: $e')),
      ]));
      
    } catch (e) {
      debugPrint('⚠️ Startup timed out or failed: $e. Falling back to default route.');
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
    debugPrint('🚨 CRITICAL startup error: $error\n$stack');
    // Ensure we at least try to show something if main crashes
    try {
      runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('App failed to start. Please restart.')))));
    } catch (_) {}
  });
}

/// Get User ID from SecureStorage
Future<String?> _getUserId() async {
  try {
    return await SecureStorage.getUserId();
  } catch (e) {
    print('❌ Error getting User ID: $e');
    return null;
  }
}

/// Get Wallet ID from SecureStorage
Future<String?> _getWalletId() async {
  try {
    return await SecureStorage.getWalletId();
  } catch (e) {
    print('❌ Error getting Wallet ID: $e');
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
  
  final SecuritySettingsManager _securityManager = SecuritySettingsManager.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 🛡️ Safety fallback: Force complete bootstrap after 25 seconds if it's still hanging
    Timer(const Duration(seconds: 25), () {
      if (mounted && !AppNavigationState.instance.bootstrapComplete) {
        debugPrint('🚨 Safety fallback: Bootstrap was hanging, forcing completion');
        AppNavigationState.instance.completeBootstrap();
      }
    });

    unawaited(_runAppStartup());
  }

  Future<void> _runAppStartup() async {
    try {
      await runDeferredMainBootstrap().timeout(const Duration(seconds: 10));
      await _initializeSecurityManager().timeout(const Duration(seconds: 5));
      print('🔒 SecuritySettingsManager initialized, now initializing app');
      await _initializeApp().timeout(const Duration(seconds: 15));
      print('🚀 All initialization tasks completed in sequence');
    } catch (e, st) {
      print('❌ Error in initialization sequence: $e\n$st');
      if (mounted) {
        AppRouter.router.go(RoutePaths.importCreate);
        AppNavigationState.instance.completeBootstrap();
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
      
      print('📱 App went to background at: $now');
    } else if (state == AppLifecycleState.resumed) {
      // App comes to foreground
      print('📱 App resumed from background');
      
      // 🔒 CRITICAL: Check if passcode is enabled and set
      final isPasscodeEnabled = await _securityManager.isPasscodeEnabled();
      final hasPasscode = await PasscodeManager.isPasscodeSet();
      
      if (!isPasscodeEnabled) {
        print('⚠️ SECURITY WARNING: Passcode disabled - crypto wallet unprotected!');
        return;
      }
      
      if (!hasPasscode) {
        print('⚠️ SECURITY WARNING: No passcode set - crypto wallet unprotected!');
        return;
      }
      
      // 🔒 PRIORITY 1: Check if app passcode should be shown  
      final shouldShowPasscode = await _securityManager
          .shouldShowPasscodeAfterBackground()
          .timeout(const Duration(seconds: 4), onTimeout: () {
        print('⚠️ Security Check TIMED OUT during resume');
        return false;
      });
      
      if (shouldShowPasscode) {
        final currentLoc = AppRouter.router.routerDelegate.currentConfiguration.uri.toString();
        if (currentLoc != RoutePaths.enterPasscode) {
          final uri = AppRouter.router.routerDelegate.currentConfiguration.uri
              .toString();
          await SessionLockCoordinator.saveReturnUri(uri);
          AppNavigationState.instance.setSessionLockRequired(true);
          SchedulerBinding.instance.addPostFrameCallback((_) {
            AppRouter.router.go(RoutePaths.enterPasscode);
          });
        } else {
          print('📱 Already on passcode screen, not redirecting');
        }
      } else {
        print('🔓 SECURITY: Auto-lock not triggered - within configured time limit or disabled');
        
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
      print('🔒 Security settings initialized: ${summary['lockMethodText']} - ${summary['autoLockDurationText']}');
    } catch (e) {
      print('❌ Error initializing security manager: $e');
    }
  }

  /// اجرای تسک‌های پس‌زمینه که قبلاً در SplashScreen بود
  Future<void> _runBackgroundTasks() async {
    try {
      await WalletMigrationService.instance.runIfNeeded().timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Initial app setup — route is already correct (set via
  /// [FastRouteResolver] in main() before runApp).
  Future<void> _initializeApp() async {
    try {
      // NOTE: Orphaned-data cleanup already ran in main() before
      // FastRouteResolver. No need to repeat it here.

      // 🔄 Background tasks (wallet migration, etc.).
      await _runBackgroundTasks();

      // 🔄 Clear previous session lock so the redirect guard
      // does not re-route to enter-passcode unnecessarily.
      await _securityManager.clearLastBackgroundTime();
      AppNavigationState.instance.setSessionLockRequired(false);

      print('🔍 Bootstrap complete — completing navigation state');
      AppNavigationState.instance.completeBootstrap();
      print('🔄 completeBootstrap() called');

      // Language after first route (do not block initial paint).
      unawaited(
        LanguageManager.initializeLanguage(context).catchError((e) {
          print('❌ Language init: $e');
        }),
      );
      _userId = await _getUserId();

      // 🎯 Start V2 notification poller for non-custodial transaction alerts
      if (_userId != null && _userId!.isNotEmpty) {
        unawaited(
          V2NotificationPoller.instance.start(walletId: _userId!).catchError((e) {
            debugPrint('❌ V2NotificationPoller start: $e');
          }),
        );
      }

      // Pre-load screen-cache data so subsequent screens
      // render from memory instead of showing spinners.
      if (_userId != null) {
        ScreenCacheManager.instance
            .preloadCriticalData(_userId!, _userId!)
            .catchError((_) {});
      }

      // Non-critical operations in background (don't await)
      _testServerConnection().then((result) {
        print(result ? '✅ Server connection successful' : '⚠️ Server connection failed');
      });
      
      ServiceProvider.instance.showNetworkStatus().then((_) {
        print('✅ Network status shown');
      });
      
      if (kDebugMode) {
        _checkPasscodeDebug();
      }
      
      print('🚀 All app initialization completed in parallel');
    } catch (e) {
      if (mounted) {
        AppRouter.router.go(RoutePaths.importCreate);
        AppNavigationState.instance.completeBootstrap();
      }
    }
  }
  
  /// Helper method for server connection testing
  Future<bool> _testServerConnection() async {
    print('🌐 Testing server connection...');
    final isConnected = await ServiceProvider.instance.testServerConnection('coinceeper.com');
    if (isConnected) {
      print('✅ Server connection successful');
    } else {
      print('⚠️ Server connection failed - app will work with limited functionality');
    }
    return isConnected;
  }
  
  /// Debug iOS keychain access issues
  Future<void> _debugiOSKeychainAccess() async {
    if (!Platform.isIOS) return;
    
    try {
      print('🍎 === iOS KEYCHAIN DEBUG ===');
      
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
      
      print('🍎 Testing keychain write...');
      await storage.write(key: testKey, value: testValue);
      
      print('🍎 Testing keychain read...');
      final readValue = await storage.read(key: testKey);
      
      if (readValue == testValue) {
        print('🍎 ✅ Keychain access working correctly');
      } else {
        print('🍎 ❌ Keychain access failed - read: $readValue, expected: $testValue');
      }
      
      // Clean up test key
      await storage.delete(key: testKey);
      
      // Test SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final prefsTestKey = 'ios_prefs_test_${DateTime.now().millisecondsSinceEpoch}';
      final prefsTestValue = 'prefs_test_value_${DateTime.now().millisecondsSinceEpoch}';
      
      print('🍎 Testing SharedPreferences write...');
      await prefs.setString(prefsTestKey, prefsTestValue);
      
      print('🍎 Testing SharedPreferences read...');
      final prefsReadValue = prefs.getString(prefsTestKey);
      
      if (prefsReadValue == prefsTestValue) {
        print('🍎 ✅ SharedPreferences access working correctly');
      } else {
        print('🍎 ❌ SharedPreferences access failed - read: $prefsReadValue, expected: $prefsTestValue');
      }
      
      // Clean up test key
      await prefs.remove(prefsTestKey);
      
      print('🍎 === END iOS KEYCHAIN DEBUG ===');
      
    } catch (e) {
      print('🍎 ❌ iOS keychain debug error: $e');
    }
  }

  /// Helper method for passcode debugging
  Future<void> _checkPasscodeDebug() async {
    try {
      // Debug: Enhanced passcode debugging for iOS issue
      print('🔍 === ENHANCED PASSCODE DEBUGGING ===');
      
      // Check both SharedPreferences and SecureStorage
      final prefs = await SharedPreferences.getInstance();
      final passcodeHash = prefs.getString('passcode_hash');
      final passcodeSalt = prefs.getString('passcode_salt');
      print('🔑 SharedPreferences passcode_hash = ${passcodeHash != null ? "EXISTS" : "NULL"}');
      print('🔑 SharedPreferences passcode_salt = ${passcodeSalt != null ? "EXISTS" : "NULL"}');
      
      // Check SecureStorage backup
      const secureStorage = FlutterSecureStorage();
      final secureHash = await secureStorage.read(key: 'passcode_hash_secure');
      final secureSalt = await secureStorage.read(key: 'passcode_salt_secure');
      print('🔑 SecureStorage passcode_hash_secure = ${secureHash != null ? "EXISTS" : "NULL"}');
      print('🔑 SecureStorage passcode_salt_secure = ${secureSalt != null ? "EXISTS" : "NULL"}');
      
      // Use PasscodeManager to check (this will use the new backup logic)
      final isPasscodeSetResult = await PasscodeManager.isPasscodeSet();
      print('🔑 PasscodeManager.isPasscodeSet() = $isPasscodeSetResult');
      
      print('🔍 === END PASSCODE DEBUGGING ===');
    } catch (e) {
      print('❌ Error checking passcode debug: $e');
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
          value: ServiceProvider.instance.networkManager,
        ),
        ChangeNotifierProvider(
          create: (_) => ClientPanelProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) {
            final np = NotificationProvider.instance;
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
        builder: (context, themeNotifier, _) => MaterialApp.router(
        routerConfig: AppRouter.router,
        title: 'coinceeper',
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeNotifier.mode,
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
          return MediaQuery(
            data: mq.copyWith(textScaler: scaled),
            child: NetworkOverlay(child: routedChild),
          );
        },
      ),
      ),
    );
  }
}
