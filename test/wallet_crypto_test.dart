import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/services/wallet_crypto.dart';

void main() {
  test('PBKDF2 hash is stable for same passcode and salt', () {
    const passcode = '123456';
    final salt = WalletCrypto.generateSaltBase64();
    final a = WalletCrypto.hashPasscode(passcode, salt);
    final b = WalletCrypto.hashPasscode(passcode, salt);
    expect(a, b);
  });

  test('AES-GCM encrypt/decrypt roundtrip', () async {
    const plaintext = '{"keys":"test"}';
    const passcode = '654321';
    final blob = await WalletCrypto.encryptAesGcm(plaintext, passcode);
    final clear = await WalletCrypto.decryptAesGcm(blob, passcode);
    expect(clear, plaintext);
  });
}
