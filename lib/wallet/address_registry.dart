import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/secure_storage.dart';
import 'derivation/multi_chain_deriver.dart';

/// Cached derived public addresses per wallet user id.
class AddressRegistry {
  AddressRegistry._();
  static final AddressRegistry instance = AddressRegistry._();

  static String _cacheKey(String userId) => 'wallet_addresses_cache_$userId';

  Future<void> saveForWallet(
    String userId,
    Map<String, String> addressesByBlockchainName,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey(userId), jsonEncode(addressesByBlockchainName));
  }

  Future<Map<String, String>> loadForWallet(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey(userId));
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return {};
  }

  Future<String?> addressForChain(String userId, String blockchainName) async {
    final map = await loadForWallet(userId);
    if (map.containsKey(blockchainName)) {
      return map[blockchainName];
    }
    final lower = blockchainName.toLowerCase();
    for (final e in map.entries) {
      if (e.key.toLowerCase() == lower) return e.value;
    }
    return null;
  }

  Future<void> deriveAndCache({
    required String userId,
    required String mnemonic,
  }) async {
    final derived = await const MultiChainDeriver().deriveAll(mnemonic);
    final map = {
      for (final e in derived.entries) e.key: e.value.publicAddress,
    };
    await saveForWallet(userId, map);
  }

  Future<String?> resolveBitcoinAddress(String userId) async {
    return addressForChain(userId, 'Bitcoin');
  }

  Future<String?> resolveEthereumAddress(String userId) async {
    return addressForChain(userId, 'Ethereum');
  }

  /// Rebuild cache from mnemonic stored for a named wallet.
  Future<void> refreshFromSecureStorage({
    required String walletName,
    required String userId,
  }) async {
    final mnemonic =
        await SecureStorage.instance.getMnemonic(walletName, userId);
    if (mnemonic == null || mnemonic.isEmpty) return;
    await deriveAndCache(userId: userId, mnemonic: mnemonic);
  }
}
