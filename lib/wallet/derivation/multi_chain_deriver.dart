import '../core/wallet_core_bridge.dart';
import 'dart_multi_chain_deriver.dart';
import 'derived_key_material.dart';
import '../../di/service_locator.dart';
import '../../utils/secure_log.dart';

/// Facade: Trust Wallet Core when ready, else pure-Dart derivation.
class MultiChainDeriver {
  const MultiChainDeriver();

  Future<Map<String, DerivedKeyMaterial>> deriveAll(String mnemonic) async {
    if (ServiceLocator.get<WalletCoreBridge>().isReady) {
      try {
        return await ServiceLocator.get<WalletCoreBridge>().deriveAll(mnemonic);
      } catch (e) {
        SecureLog.w('MultiChainDeriver: Wallet Core derivation failed, falling back to Dart', error: e);
      }
    }
    return const DartMultiChainDeriver().deriveAll(mnemonic);
  }
}
