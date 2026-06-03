import 'package:bip39/bip39.dart' as bip39;
import 'package:uuid/uuid.dart';

import '../services/secure_storage.dart';
import 'address_registry.dart';
import 'derivation/multi_chain_deriver.dart';
import 'wallet_models.dart';

class WalletRepository {
  WalletRepository._();
  static final WalletRepository instance = WalletRepository._();

  final _deriver = const MultiChainDeriver();
  final _uuid = const Uuid();

  Future<LocalWalletCreated> createWallet({
    required String walletName,
    List<String> activeTokens = const ['BTC', 'ETH', 'TRX'],
  }) async {
    final mnemonic = bip39.generateMnemonic(strength: 128);
    return _persistNewWallet(
      walletName: walletName,
      mnemonic: mnemonic,
      activeTokens: activeTokens,
    );
  }

  Future<LocalWalletImported> importWallet({
    required String walletName,
    required String mnemonic,
    List<String> activeTokens = const ['BTC', 'ETH', 'TRX'],
  }) async {
    final trimmed = mnemonic.trim().toLowerCase();
    if (!bip39.validateMnemonic(trimmed)) {
      throw ArgumentError('Invalid recovery phrase');
    }
    final walletId = _uuid.v4();
    final derived = await _deriver.deriveAll(trimmed);
    final addresses = {
      for (final e in derived.entries) e.key: e.value.publicAddress,
    };

    await _saveWalletRecord(
      walletName: walletName,
      walletId: walletId,
      mnemonic: trimmed,
      activeTokens: activeTokens,
      addresses: addresses,
    );

    return LocalWalletImported(
      walletId: walletId,
      walletName: walletName,
      mnemonic: trimmed,
      addressesByChain: addresses,
    );
  }

  Future<LocalWalletCreated> _persistNewWallet({
    required String walletName,
    required String mnemonic,
    required List<String> activeTokens,
  }) async {
    final walletId = _uuid.v4();
    final derived = await _deriver.deriveAll(mnemonic);
    final addresses = {
      for (final e in derived.entries) e.key: e.value.publicAddress,
    };

    await _saveWalletRecord(
      walletName: walletName,
      walletId: walletId,
      mnemonic: mnemonic,
      activeTokens: activeTokens,
      addresses: addresses,
    );

    return LocalWalletCreated(
      walletId: walletId,
      walletName: walletName,
      mnemonic: mnemonic,
      addressesByChain: addresses,
    );
  }

  Future<void> _saveWalletRecord({
    required String walletName,
    required String walletId,
    required String mnemonic,
    required List<String> activeTokens,
    required Map<String, String> addresses,
  }) async {
    await SecureStorage.instance.saveMnemonic(walletName, walletId, mnemonic);
    await SecureStorage.instance.saveUserId(walletName, walletId);
    await SecureStorage.instance.saveWalletIdForWallet(walletName, walletId);
    await SecureStorage.instance.saveActiveTokens(walletName, walletId, activeTokens);
    await AddressRegistry.instance.saveForWallet(walletId, addresses);

    final wallets = await SecureStorage.instance.getWalletsList();
    final exists = wallets.any(
      (w) =>
          (w['walletName'] ?? '') == walletName ||
          (w['userID'] ?? '') == walletId,
    );
    if (!exists) {
      wallets.add({'walletName': walletName, 'userID': walletId});
      await SecureStorage.instance.saveWalletsList(wallets);
    }
  }

  Future<String?> mnemonicForWallet(String walletName, String userId) async {
    return SecureStorage.instance.getMnemonic(walletName, userId);
  }

  Future<Map<String, String>> addressesForWallet(String userId) async {
    return AddressRegistry.instance.loadForWallet(userId);
  }
}
