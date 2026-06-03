import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_navigator.dart';
import 'app_shell_scaffold.dart';
import 'route_back_policy.dart';
import 'route_extras.dart';
import 'sensitive_screen_scope.dart';
import 'session_lock_coordinator.dart';
import 'wallet_session.dart';
import '../screens/add_token_screen.dart';
import '../screens/backup_screen.dart';
import '../screens/create_new_wallet_screen.dart';
import '../screens/dex_screen.dart';
import '../screens/fiat_currencies_screen.dart';
import '../screens/history_screen.dart';
import '../screens/home_screen.dart';
import '../screens/import_create_screen.dart';
import '../screens/import_wallet_screen.dart';
import '../screens/languages_screen.dart';
import '../screens/notification_management_screen.dart';
import '../screens/passcode_screen.dart';
import '../screens/phrasekey_screen.dart';
import '../screens/phrasekey_confirmation_screen.dart';
import '../screens/inside_new_wallet_screen.dart';
import '../screens/inside_import_wallet_screen.dart';
import '../screens/address_book_screen.dart';
import '../screens/mining_screen.dart';
import '../screens/webview_screen.dart';
import '../screens/preferences_screen.dart';
import '../screens/qr_scanner_screen.dart';
import '../screens/receive_screen.dart';
import '../screens/security_screen.dart';
import '../screens/send_detail_screen.dart';
import '../screens/send_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/transaction_detail_screen.dart';
import '../screens/panel/panel_screen.dart';
import '../screens/wallets_screen.dart';
import '../screens/wallet_screen.dart';
import '../screens/crypto_details_screen.dart';
import '../screens/receive_wallet_screen.dart';
import '../screens/add_address_screen.dart';
import '../screens/edit_address_book_screen.dart';
import '../screens/price_alerts_screen.dart';
import '../screens/security_notifications_screen.dart';
import '../screens/admin_notifications_screen.dart';
import '../screens/splash_loading_screen.dart';
import '../services/security_settings_manager.dart';
import 'app_navigation_state.dart';
import 'platform_page.dart';
import 'route_paths.dart';
import 'sensitive_route_observer.dart';

class AppRouter {
  AppRouter._();

  /// Set before the first access to [router] so the correct route is
  /// shown on the very first frame (no flash).
  static String _initialLocation = RoutePaths.splash;
  static void setInitialLocation(String loc) => _initialLocation = loc;

  static Future<void> _onUnlockSuccess() async {
    // 🛑 CRITICAL FIX: Clear background time BEFORE releasing the session
    // lock. The GoRouter redirect guard (refreshListenable) fires
    // synchronously when setSessionLockRequired(false) is called, and
    // checks shouldShowPasscodeAfterBackground(). If lastBackgroundTime
    // is still set, it returns true and the guard redirects right back
    // to enter-passcode — creating an infinite loop.
    //
    // Clearing lastBackgroundTime first ensures the guard sees a clean
    // state and allows the navigation to proceed.
    await SecuritySettingsManager.instance.clearLastBackgroundTime();

    AppNavigationState.instance.setSessionLockRequired(false);
    await SecuritySettingsManager.instance.resetActivityTimer();

    final returnUri = await SessionLockCoordinator.consumeReturnUri();

    if (returnUri != null && returnUri.isNotEmpty) {
      router.go(returnUri);
    } else {
      router.go(RoutePaths.home);
    }
  }

  static final GoRouter router = GoRouter(
    navigatorKey: appNavigatorKey,
    initialLocation: _initialLocation,
    refreshListenable: AppNavigationState.instance,
    observers: [SensitiveRouteObserver.instance],
    redirect: _redirect,
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Navigation error: ${state.error}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
    routes: [
      // Splash / loading screen (shown briefly during startup)
      GoRoute(
        path: RoutePaths.splash,
        pageBuilder: (c, s) => platformPage(
          child: const SplashLoadingScreen(),
          state: s,
        ),
      ),
      GoRoute(
        path: RoutePaths.importCreate,
        pageBuilder: (c, s) => platformPage(
          child: RouteBackScope(
            matchedLocation: s.matchedLocation,
            child: const ImportCreateScreen(),
          ),
          state: s,
        ),
      ),
      GoRoute(
        path: RoutePaths.importWallet,
        pageBuilder: (c, s) {
          final args = s.extra as Map<String, dynamic>?;
          return platformPage(
            child: SensitiveScreenScope(
              child: RouteBackScope(
                matchedLocation: s.matchedLocation,
                child: ImportWalletScreen(qrArguments: args),
              ),
            ),
            state: s,
          );
        },
      ),
      GoRoute(
        path: RoutePaths.createNewWallet,
        pageBuilder: (c, s) => platformPage(
          child: RouteBackScope(
            matchedLocation: s.matchedLocation,
            child: const CreateNewWalletScreen(),
          ),
          state: s,
        ),
      ),
      GoRoute(
        path: RoutePaths.passcodeSetup,
        pageBuilder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return platformPage(
            child: SensitiveScreenScope(
              child: PasscodeScreen(
                title: 'Choose Passcode',
                walletName: extra?['walletName'] as String?,
              ),
            ),
            state: s,
            fullscreenDialog: true,
          );
        },
      ),
      GoRoute(
        path: RoutePaths.passcodeConfirm,
        pageBuilder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return platformPage(
            child: SensitiveScreenScope(
              child: PasscodeScreen(
                title: 'Confirm Passcode',
                walletName: extra?['walletName'] as String?,
                firstPasscode: extra?['firstPasscode'] as String?,
              ),
            ),
            state: s,
            fullscreenDialog: true,
          );
        },
      ),
      GoRoute(
        path: RoutePaths.enterPasscode,
        pageBuilder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return platformPage(
            child: SensitiveScreenScope(
              child: PasscodeScreen(
                title: 'Enter Passcode',
                isFromBackground: extra?['isFromBackground'] as bool? ?? false,
                onSuccess: () {
                  final callback =
                      WalletSession.instance.consumePasscodeOnSuccess();
                  if (callback != null) {
                    callback();
                    return;
                  }
                  _onUnlockSuccess();
                },
              ),
            ),
            state: s,
            fullscreenDialog: true,
          );
        },
      ),
      GoRoute(
        path: RoutePaths.backup,
        pageBuilder: (c, s) {
          final extra = BackupRouteExtra.from(s.extra);
          return platformPage(
            child: SensitiveScreenScope(
              child: BackupScreen(
                walletName: extra?.walletName ?? 'Unknown Wallet',
                userID: extra?.userId,
                walletID: extra?.walletId,
                isPasscodeEnabled: extra?.isPasscodeEnabled ?? false,
                skipPhraseKey: extra?.skipPhraseKey ?? false,
              ),
            ),
            state: s,
            fullscreenDialog: true,
          );
        },
      ),
      GoRoute(
        path: RoutePaths.phraseKeyConfirm,
        pageBuilder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return platformPage(
            child: SensitiveScreenScope(
              child: PhraseKeyConfirmationScreen(
                walletName: extra?['walletName'] as String? ?? '',
                isFromWalletCreation:
                    extra?['isFromWalletCreation'] as bool? ?? false,
              ),
            ),
            state: s,
            fullscreenDialog: true,
          );
        },
      ),
      GoRoute(
        path: RoutePaths.insideNewWallet,
        pageBuilder: (c, s) => platformPage(
          child: const InsideNewWalletScreen(),
          state: s,
        ),
      ),
      GoRoute(
        path: RoutePaths.insideImportWallet,
        pageBuilder: (c, s) => platformPage(
          child: const InsideImportWalletScreen(),
          state: s,
        ),
      ),
      GoRoute(
        path: RoutePaths.addressBook,
        pageBuilder: (c, s) => platformPage(
          child: const AddressBookScreen(),
          state: s,
        ),
      ),
      GoRoute(
        path: RoutePaths.mining,
        pageBuilder: (c, s) => platformPage(
          child: const MiningScreen(),
          state: s,
        ),
      ),
      GoRoute(
        path: RoutePaths.webView,
        pageBuilder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return platformPage(
            child: WebViewScreen(
              url: extra?['url'] as String? ?? '',
              title: extra?['title'] as String? ?? '',
            ),
            state: s,
          );
        },
      ),
      GoRoute(
        path: RoutePaths.phraseKey,
        pageBuilder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          final mnemonic = WalletSession.instance.consumeMnemonic() ??
              (extra?['mnemonic'] as String? ?? '');
          return platformPage(
            child: SensitiveScreenScope(
              child: PhraseKeyScreen(
                walletName: extra?['walletName'] as String? ?? '',
                mnemonic: mnemonic,
                showCopy: extra?['showCopy'] as bool? ?? true,
                isFromWalletCreation:
                    extra?['isFromWalletCreation'] as bool? ?? true,
              ),
            ),
            state: s,
            fullscreenDialog: true,
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShellScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.home,
                pageBuilder: (c, s) => platformPage(
                  child: RouteBackScope(
                    matchedLocation: s.matchedLocation,
                    child: const HomeScreen(),
                  ),
                  state: s,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.panel,
                pageBuilder: (c, s) => platformPage(
                  child: const PanelScreen(),
                  state: s,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.settings,
                pageBuilder: (c, s) => platformPage(
                  child: const SettingsScreen(),
                  state: s,
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.wallets,
        pageBuilder: (c, s) => platformPage(child: const WalletsScreen(), state: s),
      ),
      GoRoute(
        path: RoutePaths.walletDetail,
        pageBuilder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return platformPage(
            child: WalletScreen(
              walletName: extra?['walletName'] as String? ?? '',
            ),
            state: s,
          );
        },
      ),
      GoRoute(
        path: RoutePaths.addAddress,
        pageBuilder: (c, s) =>
            platformPage(child: const AddAddressScreen(), state: s),
      ),
      GoRoute(
        path: RoutePaths.editAddress,
        pageBuilder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return platformPage(
            child: EditAddressBookScreen(
              walletName: extra?['walletName'] as String? ?? '',
              walletAddress: extra?['walletAddress'] as String? ?? '',
            ),
            state: s,
          );
        },
      ),
      GoRoute(
        path: RoutePaths.cryptoDetails,
        pageBuilder: (c, s) {
          final extra = CryptoDetailsExtra.from(s.extra);
          return platformPage(
            child: CryptoDetailsScreen(
              tokenName: extra?.tokenName ?? '',
              tokenSymbol: extra?.tokenSymbol ?? '',
              iconUrl: extra?.iconUrl ?? '',
              isToken: extra?.isToken ?? false,
              blockchainName: extra?.blockchainName ?? '',
              gasFee: extra?.gasFee ?? 0.0,
            ),
            state: s,
          );
        },
      ),
      GoRoute(
        path: RoutePaths.receiveWallet,
        pageBuilder: (c, s) {
          final extra = ReceiveWalletExtra.from(s.extra);
          return platformPage(
            child: ReceiveWalletScreen(
              cryptoName: extra?.cryptoName ?? '',
              blockchainName: extra?.blockchainName ?? '',
              address: extra?.address ?? '',
              symbol: extra?.symbol ?? '',
            ),
            state: s,
          );
        },
      ),
      GoRoute(
        path: RoutePaths.addToken,
        pageBuilder: (c, s) => platformPage(child: const AddTokenScreen(), state: s),
      ),
      GoRoute(
        path: RoutePaths.security,
        pageBuilder: (c, s) => platformPage(child: const SecurityScreen(), state: s),
      ),
      GoRoute(
        path: RoutePaths.qrScanner,
        pageBuilder: (c, s) {
          final extra = QrScannerExtra.from(s.extra);
          return platformPage(
            child: QrScannerScreen(returnScreen: extra.returnScreen),
            state: s,
          );
        },
      ),
      GoRoute(
        path: RoutePaths.history,
        pageBuilder: (c, s) => platformPage(child: const HistoryScreen(), state: s),
      ),
      GoRoute(
        path: RoutePaths.preferences,
        pageBuilder: (c, s) => platformPage(child: const PreferencesScreen(), state: s),
      ),
      GoRoute(
        path: RoutePaths.fiatCurrencies,
        pageBuilder: (c, s) =>
            platformPage(child: const FiatCurrenciesScreen(), state: s),
      ),
      GoRoute(
        path: RoutePaths.languages,
        pageBuilder: (c, s) => platformPage(child: const LanguagesScreen(), state: s),
      ),
      GoRoute(
        path: RoutePaths.notificationManagement,
        pageBuilder: (c, s) => platformPage(
          child: const NotificationManagementScreen(),
          state: s,
        ),
      ),
      GoRoute(
        path: RoutePaths.priceAlerts,
        pageBuilder: (c, s) => platformPage(
          child: const PriceAlertsScreen(),
          state: s,
        ),
      ),
      GoRoute(
        path: RoutePaths.securityNotifications,
        pageBuilder: (c, s) => platformPage(
          child: const SecurityNotificationsScreen(),
          state: s,
        ),
      ),
      GoRoute(
        path: RoutePaths.adminNotifications,
        pageBuilder: (c, s) => platformPage(
          child: const AdminNotificationsScreen(),
          state: s,
        ),
      ),
      GoRoute(
        path: RoutePaths.receive,
        pageBuilder: (c, s) => platformPage(child: const ReceiveScreen(), state: s),
      ),
      GoRoute(
        path: RoutePaths.send,
        pageBuilder: (c, s) {
          final extra = SendRouteExtra.from(s.extra);
          return platformPage(
            child: SendScreen(qrArguments: extra?.qrArguments),
            state: s,
          );
        },
      ),
      GoRoute(
        path: RoutePaths.dex,
        pageBuilder: (c, s) => platformPage(child: const DexScreen(), state: s),
      ),
      GoRoute(
        path: RoutePaths.dexCreatePool,
        pageBuilder: (c, s) =>
            platformPage(child: const DexCreatePoolScreen(), state: s),
      ),
      GoRoute(
        path: '${RoutePaths.sendDetailBase}/:tokenJson',
        pageBuilder: (c, s) => platformPage(
          child: SendDetailScreen(tokenJson: s.pathParameters['tokenJson']!),
          state: s,
        ),
      ),
      GoRoute(
        path: RoutePaths.transactionDetail,
        pageBuilder: (c, s) {
          final extra = TransactionDetailExtra.from(s.extra);
          return platformPage(
            child: TransactionDetailScreen(
              transactionId: extra?.transactionId,
            ),
            state: s,
          );
        },
      ),
    ],
  );

  static Future<String?> _redirect(BuildContext context, GoRouterState state) async {
    final nav = AppNavigationState.instance;
    final loc = state.uri.toString();
    final matched = state.matchedLocation;
    
    // No redirect until bootstrap is complete — the correct route
    // was already set as initialLocation (see FastRouteResolver).
    if (!nav.bootstrapComplete) {
      return null;
    }

    if (nav.sessionLockRequired && matched != RoutePaths.enterPasscode) {
      debugPrint('🔄 ROUTER REDIRECT: Session lock required -> redirect to enter-passcode');
      await SessionLockCoordinator.saveReturnUri(loc);
      return RoutePaths.enterPasscode;
    }

    final security = SecuritySettingsManager.instance;
    final shouldLock = await security.shouldShowPasscodeAfterBackground();
    if (shouldLock &&
        matched != RoutePaths.enterPasscode &&
        !RoutePaths.publicRoutes.contains(matched)) {
      debugPrint('🔄 ROUTER REDIRECT: Background lock required -> redirect to enter-passcode');
      await SessionLockCoordinator.saveReturnUri(loc);
      return RoutePaths.enterPasscode;
    }
    return null;
  }

  static void goHome(BuildContext context) => context.go(RoutePaths.home);
}
