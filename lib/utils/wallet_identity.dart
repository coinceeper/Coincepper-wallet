import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/secure_storage.dart';
import '../wallet/address_registry.dart';
import '../wallet/derivation/multi_chain_deriver.dart';

/// BIP-44 Ethereum address (matches backend generator), not legacy seed-slice derivation.
Future<String?> deriveEthStyleAddressFromMnemonic(String mnemonic) async {
  try {
    final derived = await const MultiChainDeriver().deriveAll(mnemonic);
    return derived['Ethereum']?.publicAddress;
  } catch (_) {
    return null;
  }
}

/// CoinCeeper API + cache key — must match [ReceiveScreen] (`BlockchainName` for BTC).
const _kBtcBlockchainName = 'Bitcoin';

String? _pickBitcoinAddressFromCacheMap(Map<String, dynamic> map) {
  for (final e in map.entries) {
    if (e.key.toString().toLowerCase() == 'bitcoin') {
      final a = e.value?.toString().trim();
      if (a != null && a.isNotEmpty) return a;
    }
  }
  return null;
}

Future<String?> _readCachedBitcoinAddress(String userId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('wallet_addresses_cache_$userId');
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    return _pickBitcoinAddressFromCacheMap(map);
  } catch (_) {
    return null;
  }
}

Future<String?> _fetchBitcoinAddressFromCoinCeeper(String userId) async {
  final fromRegistry = await AddressRegistry.instance.addressForChain(
    userId,
    _kBtcBlockchainName,
  );
  if (fromRegistry != null && fromRegistry.isNotEmpty) {
    return fromRegistry;
  }
  final walletName = await SecureStorage.instance.getSelectedWallet();
  if (walletName != null) {
    await AddressRegistry.instance.refreshFromSecureStorage(
      walletName: walletName,
      userId: userId,
    );
    return AddressRegistry.instance.addressForChain(userId, _kBtcBlockchainName);
  }
  return null;
}

/// Bitcoin deposit address for this CoinCeeper wallet — **same source as Receive** (cache + `/api/Recive`).
///
/// [walletName] is reserved for future checks; resolution uses [userId] like the Receive flow.
Future<String?> getPanelAddressForWallet(String walletName, String userId) async {
  if (userId.isEmpty) return null;

  final cached = await _readCachedBitcoinAddress(userId);
  if (cached != null && cached.isNotEmpty) return cached;

  final fetched = await _fetchBitcoinAddressFromCoinCeeper(userId);
  if (fetched != null && fetched.isNotEmpty) return fetched;

  return null;
}

/// Resolved wallet row + Bitcoin address used for panel UI and auth.
class PanelWalletContext {
  final String walletName;
  final String userId;
  final String panelAddress;

  const PanelWalletContext({
    required this.walletName,
    required this.userId,
    required this.panelAddress,
  });
}

enum PanelResolveFailure {
  none,
  noWallets,
  /// Wallets exist but Bitcoin deposit address could not be loaded (network / open Receive once).
  btcAddressUnavailable,
}

class PanelResolveResult {
  final PanelWalletContext? context;
  final PanelResolveFailure failure;

  const PanelResolveResult({
    this.context,
    this.failure = PanelResolveFailure.none,
  });
}

/// Prefer selected wallet with a resolvable Bitcoin panel address; else first wallet in list.
Future<PanelResolveResult> resolvePanelWalletContextDetailed() async {
  final storage = SecureStorage.instance;

  Future<PanelWalletContext?> tryPair(String? name, String? uid) async {
    if (name == null ||
        uid == null ||
        name.isEmpty ||
        uid.isEmpty) {
      return null;
    }
    final addr = await getPanelAddressForWallet(name, uid);
    if (addr == null || addr.isEmpty) return null;
    return PanelWalletContext(
      walletName: name,
      userId: uid,
      panelAddress: addr,
    );
  }

  final selectedName = await storage.getSelectedWallet();
  final selectedUid =
      selectedName != null ? await storage.getUserIdForWallet(selectedName) : null;
  final fromSelected = await tryPair(selectedName, selectedUid);
  if (fromSelected != null) {
    return PanelResolveResult(context: fromSelected);
  }

  final wallets = await storage.getWalletsList();
  if (wallets.isEmpty) {
    return const PanelResolveResult(failure: PanelResolveFailure.noWallets);
  }

  for (final w in wallets) {
    final ctx = await tryPair(w['walletName'], w['userID']);
    if (ctx != null) return PanelResolveResult(context: ctx);
  }

  return const PanelResolveResult(
    failure: PanelResolveFailure.btcAddressUnavailable,
  );
}

Future<PanelWalletContext?> resolvePanelWalletContext() async {
  final r = await resolvePanelWalletContextDetailed();
  return r.context;
}

String shortPanelAddress(String hexAddr, {int head = 6, int tail = 4}) {
  final a = hexAddr.trim();
  if (a.length <= head + tail + 2) return a;
  return '${a.substring(0, head)}…${a.substring(a.length - tail)}';
}
