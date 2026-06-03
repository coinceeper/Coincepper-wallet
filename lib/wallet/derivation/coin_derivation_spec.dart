/// BIP paths aligned with [BlockchainAddressGenerator] in backend cc.
class CoinDerivationSpec {
  final String blockchainName;
  final String path;
  final int? slip44CoinType;
  final bool useBip84;
  final bool ed25519Slip;

  const CoinDerivationSpec({
    required this.blockchainName,
    required this.path,
    this.slip44CoinType,
    this.useBip84 = false,
    this.ed25519Slip = false,
  });

  static const allSpecs = <CoinDerivationSpec>[
    CoinDerivationSpec(
      blockchainName: 'Bitcoin',
      path: "m/84'/0'/0'/0/0",
      useBip84: true,
    ),
    CoinDerivationSpec(
      blockchainName: 'Ethereum',
      path: "m/44'/60'/0'/0/0",
      slip44CoinType: 60,
    ),
    CoinDerivationSpec(
      blockchainName: 'Tron',
      path: "m/44'/195'/0'/0/0",
      slip44CoinType: 195,
    ),
    CoinDerivationSpec(
      blockchainName: 'Binance Smart Chain',
      path: "m/44'/60'/0'/0/0",
      slip44CoinType: 60,
    ),
    CoinDerivationSpec(
      blockchainName: 'Polygon',
      path: "m/44'/966'/0'/0/0",
      slip44CoinType: 966,
    ),
    CoinDerivationSpec(
      blockchainName: 'Avalanche',
      path: "m/44'/9000'/0'/0/0",
      slip44CoinType: 9000,
    ),
    CoinDerivationSpec(
      blockchainName: 'Arbitrum',
      path: "m/44'/42161'/0'/0/0",
      slip44CoinType: 42161,
    ),
    CoinDerivationSpec(
      blockchainName: 'Polkadot',
      path: "m/44'/354'/0'/0/0",
      slip44CoinType: 354,
      ed25519Slip: true,
    ),
    CoinDerivationSpec(
      blockchainName: 'XRP',
      path: "m/44'/144'/0'/0/0",
      slip44CoinType: 144,
    ),
    CoinDerivationSpec(
      blockchainName: 'Solana',
      path: "m/44'/501'/0'/0/0",
      slip44CoinType: 501,
      ed25519Slip: true,
    ),
  ];
}
