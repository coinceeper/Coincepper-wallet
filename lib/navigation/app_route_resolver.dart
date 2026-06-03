import '../services/security_settings_manager.dart';
import '../services/wallet_state_manager.dart';
import 'route_paths.dart';

/// Cold-start route resolution (no sensitive logging).
class AppRouteResolver {
  static Future<String> resolveInitialRoute() async {
    final security = SecuritySettingsManager.instance;
    final hasWallet = await WalletStateManager.instance.hasWallet();
    final hasValidWallet = await WalletStateManager.instance.hasValidWallet();
    final hasPasscode = await WalletStateManager.instance.hasPasscode();
    final isPasscodeEnabled = await security.isPasscodeEnabled();
    final isFreshInstall =
        await WalletStateManager.instance.isEnhancedFreshInstall();

    print('🔍 ROUTE RESOLVER: fresh=$isFreshInstall, wallet=$hasWallet, validWallet=$hasValidWallet, passcode=$hasPasscode, passEnabled=$isPasscodeEnabled');

    if (isFreshInstall) {
      print('🆕 FRESH INSTALL -> /import-create');
      return RoutePaths.importCreate;
    }

    final shouldShowPasscode = await security.shouldShowPasscodeOnStartup();
    print('🔍 ROUTE RESOLVER: shouldShowPasscode=$shouldShowPasscode');

    // اولویت 1: اگر کیف پول معتبر + passcode فعال + passcode دارد → enter-passcode
    if (hasValidWallet && shouldShowPasscode && hasPasscode) {
      print('🔒 VALID WALLET + PASSCODE ENABLED + HAS PASSCODE -> /enter-passcode');
      return RoutePaths.enterPasscode;
    }
    // اولویت 2: اگر کیف پول معتبر + passcode دارد + passcode غیرفعال → home
    if (hasValidWallet && hasPasscode && !isPasscodeEnabled) {
      print('🏠 VALID WALLET + PASSCODE EXISTS BUT DISABLED -> /home');
      return RoutePaths.home;
    }
    // اولویت 3: اگر کیف پول معتبر + passcode ندارد → passcode-setup
    if (hasValidWallet && !hasPasscode) {
      print('🔑 VALID WALLET + NO PASSCODE -> /passcode-setup');
      return RoutePaths.passcodeSetup;
    }
    // اولویت 4: اگر کیف پول ندارد + passcode دارد (passcode یتیم) → import-create
    if (!hasValidWallet && hasPasscode) {
      print('⚠️ ORPHAN PASSCODE (no wallet) -> /import-create');
      return RoutePaths.importCreate;
    }

    print('🔍 ROUTE RESOLVER: falling back to WalletStateManager.getInitialScreen()');
    final fallback = await WalletStateManager.instance.getInitialScreen();
    if (!hasWallet && fallback == RoutePaths.home) {
      print('⚠️ No wallet but fallback wants home -> /import-create');
      return RoutePaths.importCreate;
    }
    print('🔍 ROUTE RESOLVER: fallback -> $fallback');
    return fallback;
  }
}
