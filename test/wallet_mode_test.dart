import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/wallet/wallet_mode.dart';

void main() {
  test('custodial balance APIs are disabled', () async {
    expect(await WalletModePreferences.usesCustodialBalanceApis(), isFalse);
  });
}
