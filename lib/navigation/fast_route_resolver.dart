import 'package:flutter/foundation.dart';
import '../services/security_settings_manager.dart';
import '../services/startup_cache.dart';
import '../services/wallet_state_manager.dart';
import '../utils/secure_log.dart';
import 'route_paths.dart';
import '../di/service_locator.dart';

/// Resolves the initial route with minimal startup reads.
///
/// All storage checks run in parallel via [Future.wait] so the caller
/// (main.dart) can set the correct [GoRouter.initialLocation] *before*
/// [runApp], eliminating the splash-or-wrong-screen flash.
///
/// Also warms [StartupCache] so downstream code avoids redundant reads.
class FastRouteResolver {
  /// Maximum time for the full resolution (including worst-case platform
  /// channel round-trips).
  static const _timeout = Duration(seconds: 5);

  /// Returns the route string the app should start on.
  ///
  /// Never throws -- returns [RoutePaths.importCreate] on error
  /// (the safest fallback for a wallet).
  static Future<String> resolve() async {
    try {
      // 🚀 Performance optimization: Run all critical checks in parallel with a strict timeout.
      final results = await Future.wait([
        ServiceLocator.get<WalletStateManager>().hasValidWallet().catchError((e) {
          SecureLog.w('FastRouteResolver: hasValidWallet error', error: e);
          return false;
        }),
        ServiceLocator.get<WalletStateManager>().hasPasscode().catchError((e) {
          SecureLog.w('FastRouteResolver: hasPasscode error', error: e);
          return false;
        }),
        ServiceLocator.get<SecuritySettingsManager>().isPasscodeEnabled().catchError((e) {
          SecureLog.w('FastRouteResolver: isPasscodeEnabled error', error: e);
          return true; // Default to enabled for safety
        }),
      ]).timeout(const Duration(seconds: 4));

      bool hasValidWallet = results[0];
      bool hasPasscode = results[1];
      bool isPasscodeEnabled = results[2];

      // Warm StartupCache immediately so other components can use these results.
      StartupCache.warmFromFastResolver(
        hasValidWallet: hasValidWallet,
        hasPasscode: hasPasscode,
        isPasscodeEnabled: isPasscodeEnabled,
      );

      // Routing logic:
      if (hasValidWallet) {
        if (isPasscodeEnabled && hasPasscode) {
          return RoutePaths.enterPasscode;
        } else if (!hasPasscode) {
          return RoutePaths.passcodeSetup;
        } else {
          return RoutePaths.home;
        }
      }

      // Fallback for cases where hasValidWallet is false but passcode exists (e.g. data corruption)
      if (hasPasscode) {
        return RoutePaths.enterPasscode;
      }

      return RoutePaths.importCreate;
    } catch (e) {
      SecureLog.w('FastRouteResolver: Timeout or error. Using failsafe routing.', error: e);
      // Fallback: check only the most essential flag (passcode) with a very short timeout
      try {
        final hasPasscode = await ServiceLocator.get<WalletStateManager>().hasPasscode().timeout(const Duration(seconds: 1));
        if (hasPasscode) return RoutePaths.enterPasscode;
      } catch (e) {
        SecureLog.w('FastRouteResolver: Fallback passcode check failed', error: e);
      }
      return RoutePaths.importCreate;
    }
  }
}
