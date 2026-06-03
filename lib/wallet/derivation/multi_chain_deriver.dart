import '../core/wallet_core_bridge.dart';
import 'dart_multi_chain_deriver.dart';
import 'derived_key_material.dart';

/// Facade: Trust Wallet Core when ready, else pure-Dart derivation.
class MultiChainDeriver {
  const MultiChainDeriver();

  Future<Map<String, DerivedKeyMaterial>> deriveAll(String mnemonic) async {
    if (WalletCoreBridge.instance.isReady) {
      try {
        return await WalletCoreBridge.instance.deriveAll(mnemonic);
      } catch (_) {
        // fall through
      }
    }
    return const DartMultiChainDeriver().deriveAll(mnemonic);
  }
}
