import 'dart:typed_data';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:ed25519_hd_key/ed25519_hd_key.dart';
import 'package:hex/hex.dart';
import 'package:pointycastle/export.dart';

import 'chain_address_codec.dart';
import 'coin_derivation_spec.dart';
import 'derived_key_material.dart';

/// Pure-Dart HD derivation (fallback when Wallet Core is unavailable).
class DartMultiChainDeriver {
  const DartMultiChainDeriver();

  Future<Map<String, DerivedKeyMaterial>> deriveAll(String mnemonic) async {
    final trimmed = mnemonic.trim().toLowerCase();
    if (!bip39.validateMnemonic(trimmed)) {
      throw ArgumentError('Invalid BIP-39 mnemonic');
    }
    final seed = bip39.mnemonicToSeed(trimmed);
    final root = bip32.BIP32.fromSeed(seed);
    final out = <String, DerivedKeyMaterial>{};

    for (final spec in CoinDerivationSpec.allSpecs) {
      try {
        final material = await _deriveOne(root, seed, spec);
        if (material != null) {
          out[spec.blockchainName] = material;
        }
      } catch (_) {
        if (spec.blockchainName == 'Binance Smart Chain' &&
            out.containsKey('Ethereum')) {
          final eth = out['Ethereum']!;
          out[spec.blockchainName] = DerivedKeyMaterial(
            blockchainName: spec.blockchainName,
            publicAddress: eth.publicAddress,
            privateKeyHexOrWif: eth.privateKeyHexOrWif,
          );
        }
      }
    }
    return out;
  }

  Future<DerivedKeyMaterial?> _deriveOne(
    bip32.BIP32 root,
    Uint8List seed,
    CoinDerivationSpec spec,
  ) async {
    if (spec.ed25519Slip) {
      return _deriveEd25519(seed, spec);
    }
    final node = root.derivePath(spec.path);
    final priv = node.privateKey;
    if (priv == null) return null;
    final privHex = HEX.encode(priv);

    if (spec.useBip84) {
      final pub = node.publicKey;
      final sha = sha256.convert(pub).bytes;
      final ripe = _ripemd160(Uint8List.fromList(sha));
      final address = ChainAddressCodec.bitcoinBech32FromHash160(ripe);
      final wif = ChainAddressCodec.bitcoinWifFromPrivateKey(
        Uint8List.fromList(priv),
      );
      return DerivedKeyMaterial(
        blockchainName: spec.blockchainName,
        publicAddress: address,
        privateKeyHexOrWif: wif,
      );
    }

    if (spec.blockchainName == 'Tron') {
      return DerivedKeyMaterial(
        blockchainName: spec.blockchainName,
        publicAddress: ChainAddressCodec.tronFromPrivateKeyHex(privHex),
        privateKeyHexOrWif: privHex,
      );
    }

    if (spec.blockchainName == 'XRP') {
      return _deriveXrp(node, spec);
    }

    final evm = ChainAddressCodec.evmFromPrivateKeyHex(privHex);
    return DerivedKeyMaterial(
      blockchainName: spec.blockchainName,
      publicAddress: evm,
      privateKeyHexOrWif: privHex,
    );
  }

  Future<DerivedKeyMaterial?> _deriveEd25519(
    Uint8List seed,
    CoinDerivationSpec spec,
  ) async {
    final keyData = await ED25519_HD_KEY.derivePath(spec.path, seed);
    final keyBytes = keyData.key;
    final priv = Uint8List.fromList(
      keyBytes.length >= 32 ? keyBytes.sublist(0, 32) : keyBytes,
    );
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPairFromSeed(priv);
    final pub = await keyPair.extractPublicKey();
    final pubBytes = pub.bytes;

    if (spec.blockchainName == 'Solana') {
      return DerivedKeyMaterial(
        blockchainName: spec.blockchainName,
        publicAddress: ChainAddressCodec.solanaFromEd25519Public(
          Uint8List.fromList(pubBytes),
        ),
        privateKeyHexOrWif: HEX.encode(priv),
      );
    }
    if (spec.blockchainName == 'Polkadot') {
      return DerivedKeyMaterial(
        blockchainName: spec.blockchainName,
        publicAddress: HEX.encode(pubBytes),
        privateKeyHexOrWif: HEX.encode(priv),
      );
    }
    return null;
  }

  DerivedKeyMaterial? _deriveXrp(bip32.BIP32 node, CoinDerivationSpec spec) {
    final pub = node.publicKey;
    final priv = node.privateKey;
    if (priv == null) return null;
    final accountId = _ripemd160(Uint8List.fromList(sha256.convert(pub).bytes));
    final payload = Uint8List.fromList([0x00, ...accountId]);
    final address = ChainAddressCodec.base58CheckEncode(payload);
    return DerivedKeyMaterial(
      blockchainName: spec.blockchainName,
      publicAddress: address,
      privateKeyHexOrWif: HEX.encode(priv),
    );
  }

  Uint8List _ripemd160(Uint8List input) {
    final digest = RIPEMD160Digest();
    final out = Uint8List(20);
    digest.update(input, 0, input.length);
    digest.doFinal(out, 0);
    return out;
  }
}
