/// Public result of HD derivation for one blockchain.
///
/// ⚠️ این کلاس هرگز کلید خصوصی را ذخیره نمی‌کند.
/// کلیدهای خصوصی فقط در حافظه بومی (Native C++ TWPrivateKey) نگهداری
/// می‌شوند و از طریق [WalletCoreBridge.withPrivateKeyHex] در دسترس قرار
/// می‌گیرند.
class DerivedKeyMaterial {
  final String blockchainName;
  final String publicAddress;

  const DerivedKeyMaterial({
    required this.blockchainName,
    required this.publicAddress,
  });
}
