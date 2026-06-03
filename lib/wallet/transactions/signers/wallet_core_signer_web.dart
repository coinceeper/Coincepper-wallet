/// Signs and broadcasts via Trust Wallet Core (Web stub).
class WalletCoreSigner {
  const WalletCoreSigner();

  Future<String?> send({
    required String mnemonic,
    required String blockchainName,
    required String senderAddress,
    required String recipient,
    required String amount,
    required String smartContractAddress,
  }) async {
    throw UnsupportedError('WalletCore signing is not supported on Web');
  }
}
