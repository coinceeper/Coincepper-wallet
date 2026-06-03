import '../derivation/derived_key_material.dart';

/// Trust Wallet Core derive/sign bridge (Web stub implementation).
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

  bool get isReady => false;

  void markReady() {}

  Future<Map<String, DerivedKeyMaterial>> deriveAll(String mnemonic) async {
    return {};
  }

  dynamic privateKeyForCoin(dynamic wallet, String blockchainName) {
    throw UnimplementedError('WalletCore is not supported on Web');
  }

  dynamic openWallet(String mnemonic) {
    throw UnimplementedError('WalletCore is not supported on Web');
  }
}
