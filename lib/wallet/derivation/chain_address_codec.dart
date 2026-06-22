import 'dart:typed_data';

import 'package:bech32/bech32.dart';
import 'package:bs58/bs58.dart';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import 'package:web3dart/web3dart.dart';

/// Encoders for addresses matching backend [BlockchainAddressGenerator].
class ChainAddressCodec {
  static String evmFromPrivateKeyHex(String privHex) {
    final normalized =
        privHex.startsWith('0x') ? privHex.substring(2) : privHex;
    final key = EthPrivateKey.fromHex(normalized);
    return key.address.hexEip55;
  }

  static String tronFromPrivateKeyHex(String privHex) {
    final eth = evmFromPrivateKeyHex(privHex);
    final hexBody = eth.startsWith('0x') ? eth.substring(2) : eth;
    final payload = Uint8List.fromList([0x41, ...HEX.decode(hexBody)]);
    return base58CheckEncode(payload);
  }

  static String bitcoinBech32FromHash160(Uint8List hash160) {
    return const SegwitCodec().encode(Segwit('bc', 0, hash160));
  }

  static String bitcoinWifFromPrivateKey(Uint8List priv32) {
    final extended = Uint8List.fromList([0x80, ...priv32, 0x01]);
    return base58CheckEncode(extended);
  }

  static String solanaFromEd25519Public(Uint8List publicKey32) {
    return base58.encode(publicKey32);
  }

  static String base58CheckEncode(Uint8List payload) {
    final first = sha256.convert(payload).bytes;
    final second = sha256.convert(first).bytes;
    final checksum = second.sublist(0, 4);
    return base58.encode(Uint8List.fromList([...payload, ...checksum]));
  }
}
