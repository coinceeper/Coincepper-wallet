import '../services/security_settings_manager.dart';
import '../services/wallet_state_manager.dart';
import 'route_paths.dart';
import '../di/service_locator.dart';
import '../utils/secure_log.dart';

/// Cold-start route resolution (no sensitive logging).
class AppRouteResolver {
  static Future<String> resolveInitialRoute() async {
    final security = ServiceLocator.get<SecuritySettingsManager>();
    final hasWallet = await ServiceLocator.get<WalletStateManager>().hasWallet();
    final hasValidWallet = await ServiceLocator.get<WalletStateManager>().hasValidWallet();
    final hasPasscode = await ServiceLocator.get<WalletStateManager>().hasPasscode();
    final isPasscodeEnabled = await security.isPasscodeEnabled();
    final isFreshInstall =
        await ServiceLocator.get<WalletStateManager>().isEnhancedFreshInstall();

    SecureLog.i('ROUTE RESOLVER: fresh=$isFreshInstall, wallet=$hasWallet, validWallet=$hasValidWallet, passcode=$hasPasscode, passEnabled=$isPasscodeEnabled');

    if (isFreshInstall) {
      SecureLog.i('FRESH INSTALL -> /import-create');
      return RoutePaths.importCreate;
    }

    final shouldShowPasscode = await security.shouldShowPasscodeOnStartup();
    SecureLog.i('ROUTE RESOLVER: shouldShowPasscode=$shouldShowPasscode');

    // اولویت 1: اگر کیف پول معتبر + passcode فعال + passcode دارد → enter-passcode
    if (hasValidWallet && shouldShowPasscode && hasPasscode) {
      SecureLog.i('VALID WALLET + PASSCODE ENABLED + HAS PASSCODE -> /enter-passcode');
      return RoutePaths.enterPasscode;
    }
    // اولویت 2: اگر کیف پول معتبر + passcode دارد + passcode غیرفعال → home
    if (hasValidWallet && hasPasscode && !isPasscodeEnabled) {
      SecureLog.i('VALID WALLET + PASSCODE EXISTS BUT DISABLED -> /home');
      return RoutePaths.home;
    }
    // اولویت 3: اگر کیف پول معتبر + passcode ندارد → passcode-setup
    if (hasValidWallet && !hasPasscode) {
      SecureLog.i('VALID WALLET + NO PASSCODE -> /passcode-setup');
      return RoutePaths.passcodeSetup;
    }
    // اولویت 4: اگر کیف پول ندارد + passcode دارد (passcode یتیم) → import-create
    if (!hasValidWallet && hasPasscode) {
      SecureLog.w('ORPHAN PASSCODE (no wallet) -> /import-create');
      return RoutePaths.importCreate;
    }

    SecureLog.i('ROUTE RESOLVER: falling back to WalletStateManager.getInitialScreen()');
    final fallback = await ServiceLocator.get<WalletStateManager>().getInitialScreen();
    if (!hasWallet && fallback == RoutePaths.home) {
      SecureLog.w('No wallet but fallback wants home -> /import-create');
      return RoutePaths.importCreate;
    }
    SecureLog.i('ROUTE RESOLVER: fallback -> $fallback');
    return fallback;
  }
}
