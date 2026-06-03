/// Public result of HD derivation for one blockchain.
class DerivedKeyMaterial {
  final String blockchainName;
  final String publicAddress;
  final String privateKeyHexOrWif;

  const DerivedKeyMaterial({
    required this.blockchainName,
    required this.publicAddress,
    required this.privateKeyHexOrWif,
  });

  Map<String, String> toJson() => {
        'blockchainName': blockchainName,
        'publicAddress': publicAddress,
      };
}
