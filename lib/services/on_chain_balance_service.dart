import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';

import '../models/crypto_token.dart';
import '../wallet/address_registry.dart';
import '../wallet/core/wallet_core_config.dart';
import '../wallet/tokens/token_metadata_service.dart';
import 'build_secrets.dart';

/// Reads native and token balances from public RPC (non-custodial).
class OnChainBalanceService {
  OnChainBalanceService._();
  static final OnChainBalanceService instance = OnChainBalanceService._();

  Future<Map<String, String>> balancesForActiveTokens(
    String userId,
    List<CryptoToken> tokens,
  ) async {
    final addresses = await AddressRegistry.instance.loadForWallet(userId);
    final out = <String, String>{};
    for (final token in tokens) {
      final chain = token.blockchainName ?? '';
      final holder = addresses[chain];
      if (holder == null || holder.isEmpty) continue;
      final sym = token.symbol ?? '';
      if (sym.isEmpty) continue;

      final contract = token.smartContractAddress?.trim() ?? '';
      final double? bal;
      if (contract.isNotEmpty) {
        final decimals = await TokenMetadataService.instance.decimalsForToken(
          blockchainName: chain,
          contractAddress: contract,
          symbol: sym,
        );
        bal = await _tokenBalance(
          chain: chain,
          holder: holder,
          contract: contract,
          decimals: decimals,
        );
      } else {
        bal = await _nativeBalance(chain, holder);
      }
      if (bal == null) continue;
      final text = bal.toString();
      final key = chain.isNotEmpty ? '${sym}_$chain' : sym;
      out[key] = text;
      out[sym] = text;
    }
    return out;
  }

  /// Public method to fetch native balance for a given blockchain address.
  Future<double?> fetchBalance(String address, String blockchainName) async {
    return _nativeBalance(blockchainName, address);
  }

  Future<Map<String, double>> nativeBalancesForUser(String userId) async {
    final addresses = await AddressRegistry.instance.loadForWallet(userId);
    final out = <String, double>{};
    for (final e in addresses.entries) {
      final bal = await _nativeBalance(e.key, e.value);
      if (bal != null) {
        out[e.key] = bal;
      }
    }
    return out;
  }

  // ── Token balances ──────────────────────────────────────────

  Future<double?> _tokenBalance({
    required String chain,
    required String holder,
    required String contract,
    required int decimals,
  }) async {
    final n = chain.toLowerCase();
    if (n.contains('tron') || n == 'trx') {
      return _trc20Balance(holder, contract, decimals);
    }
    if (n.contains('ethereum') ||
        n.contains('polygon') ||
        n.contains('bsc') ||
        n.contains('binance') ||
        n.contains('avalanche') ||
        n.contains('arbitrum')) {
      return _erc20Balance(chain, holder, contract, decimals);
    }
    return null;
  }

  Future<double?> _erc20Balance(
    String chain,
    String holder,
    String contract,
    int decimals,
  ) async {
    // Uses EvmRpcPool via WalletCoreConfig
    final client = Web3Client(
      WalletCoreConfig.evmRpcForBlockchain(chain),
      http.Client(),
    );
    try {
      final deployed = DeployedContract(
        ContractAbi.fromJson(
          '[{"constant":true,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"type":"function"}]',
          'ERC20',
        ),
        EthereumAddress.fromHex(contract),
      );
      final fn = deployed.function('balanceOf');
      final result = await client.call(
        contract: deployed,
        function: fn,
        params: [EthereumAddress.fromHex(holder)],
      );
      final raw = result.first as BigInt;
      return raw.toDouble() / BigInt.from(10).pow(decimals).toDouble();
    } catch (_) {
      return null;
    } finally {
      client.dispose();
    }
  }

  Future<double?> _trc20Balance(
    String holder,
    String contract,
    int decimals,
  ) async {
    try {
      final uri = Uri.parse('https://api.trongrid.io/v1/accounts/$holder');
      final keys = BuildSecrets.trongridApiKeys;
      final headers = <String, String>{};
      if (keys.isNotEmpty) headers['TRON-PRO-API-KEY'] = keys.first;
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final data = map['data'] as List<dynamic>?;
      if (data == null || data.isEmpty) return 0;
      final trc20 = data.first['trc20'] as List<dynamic>? ?? [];
      for (final item in trc20) {
        if (item is! Map) continue;
        for (final entry in item.entries) {
          if (entry.key.toString().toLowerCase() == contract.toLowerCase()) {
            final raw = BigInt.tryParse(entry.value.toString()) ?? BigInt.zero;
            return raw.toDouble() / BigInt.from(10).pow(decimals).toDouble();
          }
        }
      }
      return 0;
    } catch (_) {
      return null;
    }
  }

  // ── Native balances per chain ──────────────────────────────

  Future<double?> _nativeBalance(String blockchainName, String address) async {
    final n = blockchainName.toLowerCase();
    if (n.contains('bitcoin')) return _btcBalance(address);
    if (n.contains('tron')) return _tronBalance(address);
    if (n.contains('ethereum') ||
        n.contains('polygon') ||
        n.contains('bsc') ||
        n.contains('binance') ||
        n.contains('avalanche') ||
        n.contains('arbitrum')) {
      return _evmBalance(blockchainName, address);
    }
    if (n.contains('solana') || n == 'sol') return _solBalance(address);
    if (n.contains('xrp') || n.contains('ripple')) return _xrpBalance(address);
    if (n.contains('polkadot') || n == 'dot') return _dotBalance(address);
    return null;
  }

  Future<double?> _evmBalance(String chain, String address) async {
    // Uses EvmRpcPool via WalletCoreConfig
    final client = Web3Client(
      WalletCoreConfig.evmRpcForBlockchain(chain),
      http.Client(),
    );
    try {
      final eth = await client.getBalance(EthereumAddress.fromHex(address));
      return eth.getValueInUnit(EtherUnit.ether);
    } finally {
      client.dispose();
    }
  }

  Future<double?> _btcBalance(String address) async {
    // Try BlockCypher first, fallback to Blockstream
    for (final key in BuildSecrets.blockcypherApiKeys) {
      try {
        final res = await http
            .get(
              Uri.parse('https://api.blockcypher.com/v1/btc/main/addrs/$address/balance?token=$key'),
            )
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final map = jsonDecode(res.body) as Map<String, dynamic>;
          final balance = (map['final_balance'] as num?) ?? 0;
          return balance / 1e8;
        }
      } catch (_) {
        continue;
      }
    }
    // Fallback to Blockstream
    try {
      final uri = Uri.parse('https://blockstream.info/api/address/$address');
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final funded = (map['chain_stats']?['funded_txo_sum'] as num?) ?? 0;
      final spent = (map['chain_stats']?['spent_txo_sum'] as num?) ?? 0;
      return (funded - spent) / 1e8;
    } catch (_) {
      return null;
    }
  }

  Future<double?> _solBalance(String address) async {
    final rpc = BuildSecrets.solanaRpcUrl.isNotEmpty
        ? BuildSecrets.solanaRpcUrl
        : 'https://api.mainnet-beta.solana.com';
    final res = await http
        .post(
          Uri.parse(rpc),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'getBalance',
            'params': [address],
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final value = map['result']?['value'] as num? ?? 0;
    return value / 1e9;
  }

  Future<double?> _xrpBalance(String address) async {
    final rpc = BuildSecrets.drpcApiKey.isNotEmpty
        ? 'https://lb.drpc.live/xrp/${BuildSecrets.drpcApiKey}'
        : 'https://s1.ripple.com:51234/';
    final res = await http
        .post(
          Uri.parse(rpc),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'method': 'account_info',
            'params': [
              {'account': address, 'ledger_index': 'current'},
            ],
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final drops = map['result']?['account_data']?['Balance']?.toString() ?? '0';
    final parsed = int.tryParse(drops) ?? 0;
    return parsed / 1e6;
  }

  Future<double?> _dotBalance(String address) async {
    final keys = BuildSecrets.subscanApiKeys;
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (keys.isNotEmpty) headers['X-API-Key'] = keys.first;
    final res = await http
        .post(
          Uri.parse('https://polkadot.api.subscan.io/api/scan/account/info'),
          headers: headers,
          body: jsonEncode({'address': address}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as Map<String, dynamic>?;
    final balance = data?['balance']?.toString() ?? '0';
    return (double.tryParse(balance) ?? 0) / 1e10;
  }

  Future<double?> _tronBalance(String address) async {
    final uri = Uri.parse('https://api.trongrid.io/v1/accounts/$address');
    final keys = BuildSecrets.trongridApiKeys;
    final headers = <String, String>{};
    if (keys.isNotEmpty) headers['TRON-PRO-API-KEY'] = keys.first;
    final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final data = map['data'] as List<dynamic>?;
    if (data == null || data.isEmpty) return 0;
    final bal = data.first['balance'] as num? ?? 0;
    return bal / 1e6;
  }
}
