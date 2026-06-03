import 'package:wallet_core_bindings/wallet_core_bindings.dart';

/// Maps backend [BlockchainAddressGenerator] names to Trust Wallet Core types.
class WalletCoreCoinMap {
  static TWCoinType? coinTypeForBlockchain(String name) {
    switch (name) {
      case 'Bitcoin':
        return TWCoinType.Bitcoin;
      case 'Ethereum':
        return TWCoinType.Ethereum;
      case 'Tron':
        return TWCoinType.Tron;
      case 'Binance Smart Chain':
        return TWCoinType.SmartChain;
      case 'Polygon':
        return TWCoinType.Polygon;
      case 'Avalanche':
        return TWCoinType.AvalancheCChain;
      case 'Arbitrum':
        return TWCoinType.Arbitrum;
      case 'Solana':
        return TWCoinType.Solana;
      case 'XRP':
        return TWCoinType.XRP;
      case 'Polkadot':
        return TWCoinType.Polkadot;
      default:
        return null;
    }
  }

  static TWDerivation derivationForBlockchain(String name) {
    if (name == 'Bitcoin') {
      return TWDerivation.BitcoinSegwit;
    }
    return TWDerivation.Default;
  }
}
