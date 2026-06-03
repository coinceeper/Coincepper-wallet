import '../services/api_models.dart';

class LocalWalletCreated {
  final String walletId;
  final String walletName;
  final String mnemonic;
  final Map<String, String> addressesByChain;

  LocalWalletCreated({
    required this.walletId,
    required this.walletName,
    required this.mnemonic,
    required this.addressesByChain,
  });
}

class LocalWalletImported {
  final String walletId;
  final String walletName;
  final String mnemonic;
  final Map<String, String> addressesByChain;

  LocalWalletImported({
    required this.walletId,
    required this.walletName,
    required this.mnemonic,
    required this.addressesByChain,
  });

  List<BlockchainAddress> toBlockchainAddresses() {
    return addressesByChain.entries
        .map(
          (e) => BlockchainAddress(
            blockchainName: e.key,
            publicAddress: e.value,
          ),
        )
        .toList();
  }
}
