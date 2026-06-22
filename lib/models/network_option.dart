class NetworkOption {
  final String networkName;
  final String iconAsset;
  const NetworkOption(this.networkName, this.iconAsset);
}

const List<NetworkOption> networks = [
  NetworkOption('All Blockchains', 'assets/images/all.png'),
  NetworkOption('Ethereum', 'assets/images/ethereum_logo.png'),
  NetworkOption('Tron', 'assets/images/tron.png'),
  NetworkOption('Binance Smart Chain', 'assets/images/binance_logo.png'),
  NetworkOption('Polygon', 'assets/images/pol.png'),
  NetworkOption('Arbitrum', 'assets/images/arb.png'),
  NetworkOption('XRP', 'assets/images/xrp.png'),
  NetworkOption('Avalanche', 'assets/images/avax.png'),
  NetworkOption('Polkadot', 'assets/images/dot.png'),
  NetworkOption('Solana', 'assets/images/sol.png'),
]; 