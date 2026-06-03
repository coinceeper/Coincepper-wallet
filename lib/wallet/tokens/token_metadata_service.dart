import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web3dart/web3dart.dart';

import '../../services/build_secrets.dart';
import '../core/wallet_core_config.dart';

/// Cached ERC20/TRC20 decimals for balances and signing.
class TokenMetadataService {
  TokenMetadataService._();
  static final TokenMetadataService instance = TokenMetadataService._();

  static const _cachePrefix = 'token_decimals_';
  static const _ttlMs = 7 * 24 * 60 * 60 * 1000;
  final Map<String, int> _memory = {};

  Future<int> decimalsForToken({
    required String blockchainName,
    required String contractAddress,
    required String symbol,
  }) async {
    if (contractAddress.isEmpty) {
      return _nativeDecimals(blockchainName);
    }
    final key = '${blockchainName.toLowerCase()}:${contractAddress.toLowerCase()}';
    final cached = _memory[key];
    if (cached != null) return cached;

    final fromDisk = await _readCache(key);
    if (fromDisk != null) {
      _memory[key] = fromDisk;
      return fromDisk;
    }

    final n = blockchainName.toLowerCase();
    int? value;
    if (n.contains('tron') || n == 'trx') {
      value = await _trc20Decimals(contractAddress);
    } else {
      value = await _erc20Decimals(blockchainName, contractAddress);
    }
    value ??= _fallbackDecimals(symbol);
    _memory[key] = value;
    await _writeCache(key, value);
    return value;
  }

  int _nativeDecimals(String chain) {
    final n = chain.toLowerCase();
    if (n.contains('bitcoin')) return 8;
    if (n.contains('tron')) return 6;
    if (n.contains('solana')) return 9;
    return 18;
  }

  int _fallbackDecimals(String symbol) {
    final s = symbol.toUpperCase();
    if (s == 'USDT' || s == 'USDC' || s == 'BUSD') return 6;
    return 18;
  }

  Future<int?> _erc20Decimals(String chain, String contract) async {
    final client = Web3Client(
      WalletCoreConfig.evmRpcForBlockchain(chain),
      http.Client(),
    );
    try {
      final deployed = DeployedContract(
        ContractAbi.fromJson(
          '[{"constant":true,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"type":"function"}]',
          'ERC20',
        ),
        EthereumAddress.fromHex(contract),
      );
      final fn = deployed.function('decimals');
      final result = await client.call(
        contract: deployed,
        function: fn,
        params: [],
      );
      return (result.first as BigInt).toInt();
    } catch (_) {
      return null;
    } finally {
      client.dispose();
    }
  }

  Future<int?> _trc20Decimals(String contract) async {
    try {
      final keys = BuildSecrets.trongridApiKeys;
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (keys.isNotEmpty) headers['TRON-PRO-API-KEY'] = keys.first;
      final res = await http
          .post(
            Uri.parse('https://api.trongrid.io/wallet/triggersmartcontract'),
            headers: headers,
            body: jsonEncode({
              'owner_address': contract,
              'contract_address': contract,
              'function_selector': 'decimals()',
              'visible': true,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final hex = map['constant_result']?[0]?.toString() ?? '';
      if (hex.isEmpty) return null;
      return BigInt.parse(hex, radix: 16).toInt();
    } catch (_) {
      return null;
    }
  }

  Future<int?> _readCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cachePrefix$key');
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final at = map['at'] as int? ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - at > _ttlMs) return null;
      return map['decimals'] as int?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String key, int decimals) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_cachePrefix$key',
      jsonEncode({
        'decimals': decimals,
        'at': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }
}
