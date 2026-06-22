import 'package:hex/hex.dart';
import 'package:wallet_core_bindings/wallet_core_bindings.dart';

import '../../services/sensitive_data.dart';
import '../derivation/derived_key_material.dart';
import 'wallet_core_coin_map.dart';
import '../../di/service_locator.dart';

/// Trust Wallet Core derive/sign bridge (Native implementation).
///
/// ## امنیت کلید خصوصی
///
/// - **لایه بومی**: کلیدهای خصوصی به صورت `TWPrivateKey` (C++ native object)
///   در حافظه امن مدیریت می‌شوند.
/// - **عدم استخراج به Dart**: متد [deriveAll] فقط آدرس‌های عمومی را برمی‌گرداند.
/// - **دسترسی امن**: برای موارد نادری که به هگز کلید نیاز است
///   (سازگاری با web3dart)، از [withPrivateKeyHex] استفاده کنید.
/// - **پاکسازی**: پس از اتمام کار، `priv.delete()` و `privData.secureWipe()`
///   فراخوانی می‌شوند.
class WalletCoreBridge {
  WalletCoreBridge._();
  WalletCoreBridge();
  static WalletCoreBridge get instance => ServiceLocator.get<WalletCoreBridge>();

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

  /// استخراج فقط آدرس‌های عمومی (بدون کلید خصوصی).
  ///
  /// این متد هرگز کلید خصوصی را به Dart heap نشت نمی‌دهد.
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
        out[name] = DerivedKeyMaterial(
          blockchainName: name,
          publicAddress: address,
        );
      }
      if (out.containsKey('Ethereum') && !out.containsKey('Binance Smart Chain')) {
        final eth = out['Ethereum']!;
        out['Binance Smart Chain'] = DerivedKeyMaterial(
          blockchainName: 'Binance Smart Chain',
          publicAddress: eth.publicAddress,
        );
      }
      return out;
    } finally {
      wallet.delete();
    }
  }

  /// دسترسی امن به هگز کلید خصوصی برای سازگاری با web3dart.
  ///
  /// این متد:
  /// 1. کیف پول را باز می‌کند
  /// 2. کلید خصوصی را به صورت `TWPrivateKey` استخراج می‌کند
  /// 3. داده را به `Uint8List` تبدیل می‌کند
  /// 4. به هگز تبدیل کرده و به callback می‌دهد
  /// 5. پس از بازگشت callback، native key را حذف و بایت‌ها را صفر می‌کند
  ///
  /// فقط برای موارد ضروری که web3dart هگز نیاز دارد استفاده کنید.
  Future<T> withPrivateKeyHex<T>({
    required String mnemonic,
    required String blockchainName,
    required Future<T> Function(String hexPrivateKey) callback,
  }) async {
    final trimmed = mnemonic.trim();
    final wallet = TWHDWallet.createWithMnemonic(trimmed);
    try {
      final coin = WalletCoreCoinMap.coinTypeForBlockchain(blockchainName);
      if (coin == null) {
        throw ArgumentError('Unsupported blockchain: $blockchainName');
      }
      final derivation = WalletCoreCoinMap.derivationForBlockchain(blockchainName);
      final privKey = wallet.getKeyDerivation(coin, derivation);
      final privData = privKey.data; // Uint8List copy from native

      try {
        final hex = HEX.encode(privData);
        return await callback(hex);
      } finally {
        // پاکسازی native key و Dart copy
        privKey.delete();
        privData.secureWipe();
      }
    } finally {
      wallet.delete();
    }
  }

  /// باز کردن کیف پول با دسترسی به native TWHDWallet.
  ///
  /// برای امضای تراکنش از طریق Wallet Core (نه web3dart) استفاده کنید.
  /// پس از اتمام کار، حتماً `wallet.delete()` را فراخوانی کنید.
  TWHDWallet openWallet(String mnemonic) =>
      TWHDWallet.createWithMnemonic(mnemonic.trim());

  /// استخراج TWPrivateKey برای یک بلاکچین خاص.
  ///
  /// مسئولیت caller است که `privKey.delete()` و `privData.secureWipe()`
  /// را فراخوانی کند.
  TWPrivateKey privateKeyForCoin(TWHDWallet wallet, String blockchainName) {
    final coin = WalletCoreCoinMap.coinTypeForBlockchain(blockchainName);
    if (coin == null) {
      throw ArgumentError('Unsupported chain: $blockchainName');
    }
    final derivation = WalletCoreCoinMap.derivationForBlockchain(blockchainName);
    return wallet.getKeyDerivation(coin, derivation);
  }
}
