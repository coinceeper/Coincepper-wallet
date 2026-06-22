import 'package:wallet_core_bindings_native/wallet_core_bindings_native.dart';
import '../../utils/secure_log.dart';
import 'wallet_core_bridge.dart';
import '../../di/service_locator.dart';

class WalletCoreBootstrapInternal {
  static Future<void> initialize() async {
    try {
      await WalletCoreBindingsNativeImpl().initialize();
      ServiceLocator.get<WalletCoreBridge>().markReady();
    } catch (e) {
      SecureLog.e('WalletCoreBootstrap: native init failed: $e');
    }
  }
}
