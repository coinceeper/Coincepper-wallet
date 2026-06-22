import 'package:bip39/bip39.dart' as bip39;
import 'package:uuid/uuid.dart';

import '../di/service_locator.dart';
import '../services/secure_storage.dart';
import '../services/sensitive_data.dart';
import 'address_registry.dart';
import 'derivation/multi_chain_deriver.dart';
import 'wallet_models.dart';

class WalletRepository {
  WalletRepository._();
  /// DI constructor. Use [instance] for singleton access.
  WalletRepository();
  static WalletRepository get instance => ServiceLocator.get<WalletRepository>();

  final _deriver = const MultiChainDeriver();
  final _uuid = const Uuid();

  Future<LocalWalletCreated> createWallet({
    required String walletName,
    List<String> activeTokens = const ['BTC', 'ETH', 'TRX'],
  }) async {
    final mnemonic = bip39.generateMnemonic(strength: 128);
    return _persistNewWallet(
      walletName: walletName,
      mnemonicSafe: mnemonic,
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
      mnemonicSafe: trimmed,
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
    required String mnemonicSafe,
    required List<String> activeTokens,
  }) async {
    final walletId = _uuid.v4();
    final derived = await _deriver.deriveAll(mnemonicSafe);
    final addresses = {
      for (final e in derived.entries) e.key: e.value.publicAddress,
    };

    await _saveWalletRecord(
      walletName: walletName,
      walletId: walletId,
      mnemonicSafe: mnemonicSafe,
      activeTokens: activeTokens,
      addresses: addresses,
    );

    return LocalWalletCreated(
      walletId: walletId,
      walletName: walletName,
      mnemonic: mnemonicSafe,
      addressesByChain: addresses,
    );
  }

  Future<void> _saveWalletRecord({
    required String walletName,
    required String walletId,
    required String mnemonicSafe,
    required List<String> activeTokens,
    required Map<String, String> addresses,
  }) async {
    await ServiceLocator.get<SecureStorage>().saveMnemonic(walletName, walletId, mnemonicSafe);
    await ServiceLocator.get<SecureStorage>().saveUserId(walletName, walletId);
    await ServiceLocator.get<SecureStorage>().saveWalletIdForWallet(walletName, walletId);
    // Token enable/disable state is managed by TokenPreferences (SharedPreferences)
    // — not by SecureStorage. The initial default tokens (BTC, ETH, TRX) are set
    // by TokenPreferences.initialize() when the TokenProvider is created.
    await ServiceLocator.get<AddressRegistry>().saveForWallet(walletId, addresses);

    final wallets = await ServiceLocator.get<SecureStorage>().getWalletsList();
    final exists = wallets.any(
      (w) =>
          (w['walletName'] ?? '') == walletName ||
          (w['userID'] ?? '') == walletId,
    );
    if (!exists) {
      wallets.add({'walletName': walletName, 'userID': walletId});
      await ServiceLocator.get<SecureStorage>().saveWalletsList(wallets);
    }
  }

  /// دریافت منیمونیک به صورت String ساده.
  ///
  /// 🚨 بحرانی: منیمونیک به صورت String برگردانده می‌شود که تا زمان GC
  /// در حافظه Heap می‌ماند و توسط attacker قابل خواندن است.
  ///
  /// ⚠️ حتماً پس از استفاده reference را null کنید:
  /// ```dart
  /// String? m = await repo.mnemonicForWallet(name, uid);
  /// try { await use(m); } finally { m = null; }
  /// ```
  ///
  /// ترجیحاً از [withMnemonic] استفاده کنید که reference را خودکار پاک می‌کند.
  @Deprecated('CRITICAL: Use withMnemonic() callback-based API for memory safety')
  Future<String?> mnemonicForWallet(String walletName, String userId) async {
    return ServiceLocator.get<SecureStorage>().getMnemonic(walletName, userId);
  }

  /// دسترسی امن به منیمونیک از طریق callback.
  ///
  /// منیمونیک از SecureStorage خوانده می‌شود، به [callback] داده می‌شود،
  /// و پس از بازگشت callback، reference آن پاک می‌شود.
  Future<T> withMnemonic<T>({
    required String walletName,
    required String userId,
    required Future<T> Function(String mnemonic) callback,
  }) async {
    return MnemonicScope.use(
      () => ServiceLocator.get<SecureStorage>().getMnemonic(walletName, userId),
      callback: callback,
    );
  }

  Future<Map<String, String>> addressesForWallet(String userId) async {
    return ServiceLocator.get<AddressRegistry>().loadForWallet(userId);
  }
}
