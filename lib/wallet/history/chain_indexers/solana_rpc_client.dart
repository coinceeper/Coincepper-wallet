import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../services/build_secrets.dart';

/// Thin JSON-RPC client for Solana.
class SolanaRpcClient {
  SolanaRpcClient({String? endpoint})
      : endpoint = endpoint ??
            (BuildSecrets.solanaRpcUrl.isNotEmpty
                ? BuildSecrets.solanaRpcUrl
                : 'https://api.mainnet-beta.solana.com');

  final String endpoint;

  Future<dynamic> call(String method, List<dynamic> params) async {
    final res = await http
        .post(
          Uri.parse(endpoint),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': method,
            'params': params,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) {
      throw StateError('Solana RPC HTTP ${res.statusCode}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    if (map['error'] != null) {
      throw StateError(map['error'].toString());
    }
    return map['result'];
  }
}
