import 'package:flutter/foundation.dart';
import 'package:wallet_core_bindings_native/wallet_core_bindings_native.dart';
import 'wallet_core_bridge.dart';

class WalletCoreBootstrapInternal {
  static Future<void> initialize() async {
    try {
      await WalletCoreBindingsNativeImpl().initialize();
      WalletCoreBridge.instance.markReady();
    } catch (e) {
      debugPrint('WalletCoreBootstrap: native init failed: $e');
    }
  }
}
