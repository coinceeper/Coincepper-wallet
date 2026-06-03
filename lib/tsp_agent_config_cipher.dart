// رمزگشایی config agent (TSP1) — همان [scripts/encrypt_tsp_agent_config.py] با کلید مشتق از رشتهٔ ساختمانی.
// برای production: TSP_KDF_SECRET را عوض کنید و دوباره .enc بسازید.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as c;

const String _kKdf = String.fromEnvironment(
  'TSP_KDF_SECRET',
  defaultValue: 'tsp-asset-tsp1-kdf-v1-rotated-by-build',
);

const List<int> _kMagic = [0x54, 0x53, 0x50, 0x31]; // TSP1

/// رمزگشایی UTF-8 (YAML) اگر [blob] هدر TSP1 داشته باشد؛ وگرنه خطا
Future<String> decryptTsp1ConfigBlob(Uint8List blob) async {
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
