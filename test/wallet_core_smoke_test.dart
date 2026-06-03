import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/wallet/core/wallet_core_bootstrap.dart';
import 'package:my_flutter_app/wallet/core/wallet_core_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wallet core bootstrap completes', () async {
    await WalletCoreBootstrap.initialize();
    expect(WalletCoreBridge.instance.isReady, isTrue);
  });

  test('wallet core derives ethereum address for test mnemonic', () async {
    await WalletCoreBootstrap.initialize();
    if (!WalletCoreBridge.instance.isReady) {
      return;
    }
    const mnemonic =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    final map = await WalletCoreBridge.instance.deriveAll(mnemonic);
    expect(map['Ethereum']?.publicAddress.toLowerCase(),
        '0x9858effd232b4033e47d90003d41ec34ecaeda25');
  });
}
