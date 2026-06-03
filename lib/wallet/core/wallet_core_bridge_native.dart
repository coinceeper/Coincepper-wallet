import 'package:hex/hex.dart';
import 'package:wallet_core_bindings/wallet_core_bindings.dart';

import '../derivation/derived_key_material.dart';
import 'wallet_core_coin_map.dart';

/// Trust Wallet Core derive/sign bridge (Native implementation).
class WalletCoreBridge {
  WalletCoreBridge._();
  static final WalletCoreBridge instance = WalletCoreBridge._();

  static const blockchainNames = [
    'Bitcoin',
    'Ethereum',
    'Tron',
    'Binance Smart Chain',
    'Polygon',
    'Avalanche',
    'Arbitrum',
    'Solana',
    'XRP',
    'Polkadot',
  ];

  bool _ready = false;
  bool get isReady => _ready;

  void markReady() => _ready = true;

  Future<Map<String, DerivedKeyMaterial>> deriveAll(String mnemonic) async {
    final trimmed = mnemonic.trim();
    final wallet = TWHDWallet.createWithMnemonic(trimmed);
    try {
      final out = <String, DerivedKeyMaterial>{};
      for (final name in blockchainNames) {
        final coin = WalletCoreCoinMap.coinTypeForBlockchain(name);
        if (coin == null) continue;
        final derivation = WalletCoreCoinMap.derivationForBlockchain(name);
        final address = name == 'Bitcoin'
            ? wallet.getAddressDerivation(coin, derivation)
            : wallet.getAddressForCoin(coin);
        final privKey = wallet.getKeyDerivation(coin, derivation);
        final privHex = HEX.encode(privKey.data);
        String storedKey = privHex;
        if (name == 'Bitcoin') {
          storedKey = privHex;
        }
        out[name] = DerivedKeyMaterial(
          blockchainName: name,
          publicAddress: address,
          privateKeyHexOrWif: storedKey,
        );
        privKey.delete();
      }
      if (out.containsKey('Ethereum') && !out.containsKey('Binance Smart Chain')) {
        final eth = out['Ethereum']!;
        out['Binance Smart Chain'] = DerivedKeyMaterial(
          blockchainName: 'Binance Smart Chain',
          publicAddress: eth.publicAddress,
          privateKeyHexOrWif: eth.privateKeyHexOrWif,
        );
      }
      return out;
    } finally {
      wallet.delete();
    }
  }

  TWPrivateKey privateKeyForCoin(TWHDWallet wallet, String blockchainName) {
    final coin = WalletCoreCoinMap.coinTypeForBlockchain(blockchainName);
    if (coin == null) {
      throw ArgumentError('Unsupported chain: $blockchainName');
    }
    final derivation = WalletCoreCoinMap.derivationForBlockchain(blockchainName);
    return wallet.getKeyDerivation(coin, derivation);
  }

  TWHDWallet openWallet(String mnemonic) =>
      TWHDWallet.createWithMnemonic(mnemonic.trim());
}
