// رمزگشایی config agent (TSP1) — همان [scripts/encrypt_tsp_agent_config.py] با کلید مشتق از KDF.
//
// ⚠️  امنیت: TSP_KDF_SECRET اجباری است. بدون آن اسکریپت در runtime fail می‌شود.
//   هر بیلد باید کلید منحصربه‌فرد خود را از طریق --dart-define=TSP_KDF_SECRET=<hex> دریافت کند.
//   از fallback استفاده نمی‌شود — fallback بودن معادل نداشتن رمزنگاری است.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as c;

import 'utils/secure_log.dart';

// بدون defaultValue: اگر --dart-define=TSP_KDF_SECRET=... داده نشود، خالی می‌ماند.
const String _kKdf = String.fromEnvironment('TSP_KDF_SECRET');

const List<int> _kMagic = [0x54, 0x53, 0x50, 0x31]; // TSP1

/// رمزگشایی UTF-8 (YAML) اگر [blob] هدر TSP1 داشته باشد؛ وگرنه خطا.
///
/// نیاز دارد معمار `--dart-define=TSP_KDF_SECRET=<hex>` را هنگام بیلد تنظیم کرده باشد.
/// اگر تنظیم نشده باشد، [StateError] با توضیح پرتاب می‌کند.
Future<String> decryptTsp1ConfigBlob(Uint8List blob) async {
  // [CRASH-FIX] All crypto operations wrapped in try-catch.
  // Wrong key, corrupted data, or invalid nonce/MAC will throw.
  try {
    if (_kKdf.isEmpty) {
      throw StateError(
        'TSP_KDF_SECRET dart-define is required but was not set at build time.\n'
        '  Pass --dart-define=TSP_KDF_SECRET=<your-64-char-hex> to flutter build.\n'
        '  Generate a secret: python3 -c "import secrets; print(secrets.token_hex(32))"',
      );
    }
    if (blob.length < 4 + 12 + 17) {
      throw StateError('tsp1: too short');
    }
    for (var i = 0; i < 4; i++) {
      if (blob[i] != _kMagic[i]) {
        throw StateError('tsp1: bad magic');
      }
    }
    final h = sha256.convert(utf8.encode(_kKdf));
    final gcm = c.AesGcm.with256bits();
    final secretKey = await gcm.newSecretKeyFromBytes(Uint8List.fromList(h.bytes));
    final nonce = blob.sublist(4, 16);
    final ctm = blob.sublist(16);
    if (ctm.length < 17) {
      throw StateError('tsp1: bad ciphertext');
    }
    const tagLen = 16;
    final mac = c.Mac(ctm.sublist(ctm.length - tagLen));
    final ctext = ctm.sublist(0, ctm.length - tagLen);
    final box = c.SecretBox(ctext, mac: mac, nonce: nonce);
    final plain = await gcm.decrypt(box, secretKey: secretKey);
    return utf8.decode(plain, allowMalformed: false);
  } catch (e) {
    SecureLog.e('TspAgent: config decrypt failed', error: e);
    rethrow; // Caller handles fallback to default_agent.yml
  }
}

bool isTsp1Encrypted(Uint8List? blob) {
  if (blob == null || blob.length < 4) {
    return false;
  }
  for (var i = 0; i < 4; i++) {
    if (blob[i] != _kMagic[i]) {
      return false;
    }
  }
  return true;
}
