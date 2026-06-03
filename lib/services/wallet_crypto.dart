import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:flutter/foundation.dart';

/// PBKDF2 + AES-GCM for passcode-protected blobs.
class WalletCrypto {
  WalletCrypto._();

  static const int pbkdf2Iterations = 120000;
  static const int _keyLength = 32;

  static String generateSaltBase64() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  /// Internal helper for Isolate execution
  static Uint8List _deriveKeyBytesSync(Map<String, dynamic> params) {
    final String passcode = params['passcode'];
    final String saltBase64 = params['saltBase64'];
    final int iterations = params['iterations'];

    final salt = base64Decode(saltBase64);
    final passBytes = utf8.encode(passcode);
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(salt, iterations, _keyLength));
    return derivator.process(passBytes);
  }

  static Future<Uint8List> deriveKeyBytes(String passcode, String saltBase64) async {
    return compute(_deriveKeyBytesSync, {
      'passcode': passcode,
      'saltBase64': saltBase64,
      'iterations': pbkdf2Iterations,
    });
  }

  static Future<String> hashPasscode(String passcode, String saltBase64) async {
    final key = await deriveKeyBytes(passcode, saltBase64);
    return base64Encode(key);
  }

  static Future<String> encryptAesGcm(String plaintext, String passcode) async {
    final salt = generateSaltBase64();
    final secretKey = SecretKey(await deriveKeyBytes(passcode, salt));
    final algorithm = AesGcm.with256bits();
    final secretBox = await algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
    );
    return base64Encode(
      utf8.encode(
        jsonEncode({
          'v': 2,
          'salt': salt,
          'nonce': base64Encode(secretBox.nonce),
          'cipher': base64Encode(secretBox.cipherText),
          'mac': base64Encode(secretBox.mac.bytes),
        }),
      ),
    );
  }

  static Future<String> decryptAesGcm(
    String payloadBase64,
    String passcode,
  ) async {
    final outer = jsonDecode(utf8.decode(base64Decode(payloadBase64)));
    if (outer is! Map<String, dynamic>) {
      throw const FormatException('Invalid encrypted payload');
    }

    final version = outer['v'];
    if (version == 2) {
      final salt = outer['salt'] as String;
      final secretKey = SecretKey(await deriveKeyBytes(passcode, salt));
      final algorithm = AesGcm.with256bits();
      final secretBox = SecretBox(
        base64Decode(outer['cipher'] as String),
        nonce: base64Decode(outer['nonce'] as String),
        mac: Mac(base64Decode(outer['mac'] as String)),
      );
      final clear = await algorithm.decrypt(secretBox, secretKey: secretKey);
      return utf8.decode(clear);
    }

    // Legacy v1: XOR + sha256-derived string key (passcode_manager format).
    final salt = outer['salt'] as String;
    final encrypted = outer['encrypted'] as String;
    final keyStr = _legacyDeriveKeyString(passcode, salt);
    return _legacyXorDecrypt(encrypted, keyStr);
  }

  static String _legacyDeriveKeyString(String passcode, String salt) {
    final data = utf8.encode('$passcode$salt' 'key_derivation');
    return crypto.sha256.convert(data).toString();
  }

  static String _legacyXorDecrypt(String encrypted, String key) {
    final encryptedBytes = base64Decode(encrypted);
    final keyBytes = utf8.encode(key);
    final decrypted = List<int>.generate(
      encryptedBytes.length,
      (i) => encryptedBytes[i] ^ keyBytes[i % keyBytes.length],
    );
    return utf8.decode(decrypted);
  }
}
