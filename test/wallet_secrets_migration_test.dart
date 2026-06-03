import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/services/wallet_secrets_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ensureMigratedFromLegacyPrefs skips work when migration flag is set', () async {
    SharedPreferences.setMockInitialValues({
      'wallet_secrets_migrated_v1': true,
      'passcode_hash': 'left_in_prefs',
    });

    await WalletSecretsStore.ensureMigratedFromLegacyPrefs();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('wallet_secrets_migrated_v1'), isTrue);
    expect(prefs.getString('passcode_hash'), 'left_in_prefs');
  });
}
