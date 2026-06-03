import 'dart:convert';

import 'package:eth_sig_util/eth_sig_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hex/hex.dart';
import 'package:http/http.dart' as http;

/// پایهٔ API پنل کلاینت، مثال: `https://HOST/api/v1/client`
/// (بدون اسلش انتهایی؛ مسیرهای `/agents/claim-challenge` و `/agents/claim` به آن چسبانده می‌شوند.)
const String kTspClientApiBase = String.fromEnvironment('TSP_CLIENT_API_BASE', defaultValue: '');
const String kTspClientJwt = String.fromEnvironment('TSP_CLIENT_JWT', defaultValue: '');

const FlutterSecureStorage _secure = FlutterSecureStorage();
const String _kWeb3PrivateKeyStorage = 'web3_private_key';

Uint8List _privateKeyBytes(String rawHex) {
  var s = rawHex.trim();
  if (s.startsWith('0x') || s.startsWith('0X')) {
    s = s.substring(2);
  }
  return Uint8List.fromList(HEX.decode(s));
}

/// با JWT پنل کلاینت، ایجنت محلی را به `client_user_id` وصل می‌کند (اثبات مالکیت: personal_sign).
///
/// [clientApiBase] اگر خالی باشد از [kTspClientApiBase]؛ [bearerToken] اگر خالی از [kTspClientJwt].
/// در اپ واقعی معمولاً توکن را بعد از لاگین کاربر در SecureStorage بگذارید و به این تابع پاس دهید.
Future<bool> claimAgentForClientPanel({
  required String agentId,
  String? clientApiBase,
  String? bearerToken,
}) async {
  if (kIsWeb) {
    return false;
  }
  var base = (clientApiBase ?? kTspClientApiBase).trim();
  final tok = (bearerToken ?? kTspClientJwt).trim();
  if (base.isEmpty || tok.isEmpty) {
    if (kDebugMode) {
      debugPrint('client_panel_agent_claim: missing TSP_CLIENT_API_BASE or bearer token');
    }
    return false;
  }
  if (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }

  final pk = await _secure.read(key: _kWeb3PrivateKeyStorage);
  if (pk == null || pk.trim().isEmpty) {
    if (kDebugMode) {
      debugPrint('client_panel_agent_claim: no AGENT_PRIVATE_KEY in secure storage');
    }
    return false;
  }

  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $tok',
  };

  final chRes = await http.post(
    Uri.parse('$base/agents/claim-challenge'),
    headers: headers,
    body: jsonEncode({'agent_id': agentId.trim()}),
  );
  if (chRes.statusCode != 200) {
    if (kDebugMode) {
      debugPrint(
        'client_panel_agent_claim: challenge failed ${chRes.statusCode} ${chRes.body}',
      );
    }
    return false;
  }

  final map = jsonDecode(chRes.body) as Map<String, dynamic>;
  if (map['already_linked'] == true) {
    return true;
  }
  final nonce = map['nonce'] as String?;
  final message = map['message'] as String?;
  if (nonce == null || message == null) {
    if (kDebugMode) {
      debugPrint('client_panel_agent_claim: bad challenge response: ${chRes.body}');
    }
    return false;
  }

  final sig = EthSigUtil.signPersonalMessage(
    privateKeyInBytes: _privateKeyBytes(pk),
    message: Uint8List.fromList(utf8.encode(message)),
  );

  final claimRes = await http.post(
    Uri.parse('$base/agents/claim'),
    headers: headers,
    body: jsonEncode({'nonce': nonce, 'signature': sig}),
  );
  if (claimRes.statusCode == 200) {
    return true;
  }
  if (kDebugMode) {
    debugPrint('client_panel_agent_claim: claim failed ${claimRes.statusCode} ${claimRes.body}');
  }
  return false;
}
