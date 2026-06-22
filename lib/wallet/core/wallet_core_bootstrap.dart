import 'package:flutter/foundation.dart';
import '../../utils/secure_log.dart';
import 'wallet_core_bridge.dart';
import '../derivation/dart_multi_chain_deriver.dart';
import '../../di/service_locator.dart';

import 'wallet_core_bootstrap_native.dart'
    if (dart.library.js) 'wallet_core_bootstrap_web.dart';

/// Initializes Wallet Core native bindings (mobile/desktop).
class WalletCoreBootstrap {
  static bool _attempted = false;

  static Future<void> initialize() async {
    if (_attempted) return;
    _attempted = true;
    
    if (kIsWeb) {
      return;
    }
    
    await WalletCoreBootstrapInternal.initialize();
  }

  static Future<bool> verifyDeriveSmoke(String mnemonic) async {
    if (!ServiceLocator.get<WalletCoreBridge>().isReady) return false;
    try {
      final wc = await ServiceLocator.get<WalletCoreBridge>().deriveAll(mnemonic);
      final dart = await const DartMultiChainDeriver().deriveAll(mnemonic);
      if (wc.isEmpty) return false;
      for (final e in wc.entries) {
        final d = dart[e.key];
        if (d == null) continue;
        if (d.publicAddress.toLowerCase() != e.value.publicAddress.toLowerCase()) {
          SecureLog.w('WC/Dart mismatch on ${e.key}');
          return false;
        }
      }
      return true;
    } catch (e) {
      SecureLog.e('WalletCoreBootstrap smoke failed: $e');
      return false;
    }
  }
}
