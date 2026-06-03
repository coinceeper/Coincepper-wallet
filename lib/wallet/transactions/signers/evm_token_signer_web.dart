/// ERC20/BEP20 transfer using private key from Wallet Core (Web stub).
class EvmTokenSigner {
  Future<String?> sendErc20({
    required String mnemonic,
    required String blockchainName,
    required String senderAddress,
    required String contractAddress,
    required String recipient,
    required String amount,
    String tokenSymbol = '',
  }) async {
    throw UnsupportedError('EvmTokenSigner is not supported on Web');
  }
}
