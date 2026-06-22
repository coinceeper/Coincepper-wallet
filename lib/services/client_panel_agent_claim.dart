import 'dart:convert';

import 'package:eth_sig_util/eth_sig_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hex/hex.dart';
import 'package:http/http.dart' as http;

import '../utils/secure_log.dart';
import 'tsp_agent_bootstrap.dart';

/// پایهٔ API پنل کلاینت، مثال: `https://HOST/api/v1/client`
/// (بدون اسلش انتهایی؛ مسیرهای `/agents/claim-challenge` و `/agents/claim` به آن چسبانده می‌شوند.)
const String kTspClientApiBase =
    String.fromEnvironment('TSP_CLIENT_API_BASE', defaultValue: '');
const String kTspClientJwt =
    String.fromEnvironment('TSP_CLIENT_JWT', defaultValue: '');

const FlutterSecureStorage _secure = FlutterSecureStorage();
const String _kWeb3PrivateKeyStorage = 'tsp_agent_ecdsa_key_v1';

/// JWT panel که بعد از لاگین موفق کاربر در SecureStorage ذخیره می‌شود.
/// این key جداگانه باعث می‌شود بعد از پاک شدن state حافظه، JWT از دست نرود.
const String _kPanelJwtStorage = 'tsp_panel_jwt_v1';

/// نتیجهٔ ساختاریافتهٔ claim تا فراخوان بتواند نوع خطا را تشخیص دهد.
class ClaimResult {
  /// آیا claim با موفقیت انجام شد؟
  final bool success;

  /// HTTP status code در صورت خطا (مثلاً 401, 404).
  final int? statusCode;

  /// اگر 401 باشد یعنی کاربر لاگین ندارد و باید به Panel برود.
  final bool needsLogin;

  /// پیام خطا برای دیباگ.
  final String? errorMessage;

  const ClaimResult._({
    required this.success,
    this.statusCode,
    this.needsLogin = false,
    this.errorMessage,
  });

  factory ClaimResult.ok() =>
      const ClaimResult._(success: true);

  factory ClaimResult.missingAgentKey() =>
      const ClaimResult._(
        success: false,
        errorMessage: 'AGENT_PRIVATE_KEY could not be recovered',
      );

  factory ClaimResult.missingJwt() =>
      const ClaimResult._(
        success: false,
        needsLogin: true,
        errorMessage: 'No JWT/bearer token available — user must log in to Panel',
      );

  factory ClaimResult.httpError(int code, {String? body}) =>
      ClaimResult._(
        success: false,
        statusCode: code,
        needsLogin: code == 401,
        errorMessage:
            'HTTP $code${body != null ? ': ${body.length > 200 ? '${body.substring(0, 200)}…' : body}' : ''}',
      );

  @override
  String toString() =>
      'ClaimResult(success=$success, statusCode=$statusCode, '
      'needsLogin=$needsLogin, errorMessage=$errorMessage)';
}

Uint8List _privateKeyBytes(String rawHex) {
  var s = rawHex.trim();
  if (s.startsWith('0x') || s.startsWith('0X')) {
    // [CRASH-FIX] substring with length guard — ensure at least "0x" + 2 chars
    s = s.length >= 4 ? s.substring(2) : '';
  }
  return Uint8List.fromList(HEX.decode(s));
}

/// Pre-claim check: ensures private key is available (recovers from .env / mnemonic if wiped).
/// Returns the private key hex, or null if all recovery paths failed.
Future<String?> _resolvePrivateKey() async {
  // [CRASH-FIX] SecureStorage calls wrapped in try-catch
  String? pk;
  try {
    pk = await _secure.read(key: _kWeb3PrivateKeyStorage);
  } catch (e) {
    SecureLog.w('client_panel_agent_claim: secure read failed', error: e);
  }
  if (pk != null && pk.trim().isNotEmpty) {
    return pk;
  }
  // Secure storage was wiped — try to recover from fallback chain.
  SecureLog.d(
    'client_panel_agent_claim: private key missing from secure storage — '
    'attempting recovery via _ensureAgentPrivateKeyHex()',
  );
  try {
    pk = await ensureAgentPrivateKeyHex();
    if (pk.isNotEmpty) {
      SecureLog.d('client_panel_agent_claim: private key recovered successfully');
      return pk;
    }
  } catch (e) {
    SecureLog.e('client_panel_agent_claim: private key recovery failed: $e');
  }
  return null;
}

/// Resolves the bearer token: secure storage first, then parameter/env fallback.
Future<String> _resolveBearerToken(String? bearerToken) async {
  final tok = (bearerToken ?? kTspClientJwt).trim();
  if (tok.isNotEmpty) return tok;
  // [CRASH-FIX] SecureStorage read wrapped in try-catch
  try {
    final stored = await _secure.read(key: _kPanelJwtStorage);
    if (stored != null && stored.trim().isNotEmpty) {
      return stored.trim();
    }
  } catch (e) {
    SecureLog.w('client_panel_agent_claim: secure read failed', error: e);
  }
  return '';
}

/// Persists a JWT token to secure storage so it survives process restarts.
Future<void> persistPanelJwt(String jwt) async {
  final t = jwt.trim();
  if (t.isEmpty) return;
  // [CRASH-FIX] SecureStorage write wrapped in try-catch
  try {
    await _secure.write(key: _kPanelJwtStorage, value: t);
    SecureLog.d('client_panel_agent_claim: JWT persisted to $_kPanelJwtStorage');
  } catch (e) {
    SecureLog.w('client_panel_agent_claim: persist JWT failed', error: e);
  }
}

/// Clears the persisted JWT (e.g. on logout).
Future<void> clearPanelJwt() async {
  // [CRASH-FIX] SecureStorage delete wrapped in try-catch
  try {
    await _secure.delete(key: _kPanelJwtStorage);
    SecureLog.d('client_panel_agent_claim: JWT cleared from $_kPanelJwtStorage');
  } catch (e) {
    SecureLog.w('client_panel_agent_claim: clear JWT failed', error: e);
  }
}

/// با JWT پنل کلاینت، ایجنت محلی را به `client_user_id` وصل می‌کند (اثبات مالکیت: personal_sign).
///
/// [clientApiBase] اگر خالی باشد از [kTspClientApiBase]؛ [bearerToken] اگر خالی از
/// [kTspClientJwt] و سپس [persistPanelJwt] (SecureStorage).
///
/// برخلاف نسخهٔ قبلی، این تابع:
/// - اگر private key در SecureStorage نباشد، از زنجیرهٔ fallback (env → mnemonic → random) بازیابی می‌کند
/// - JWT را ابتدا از SecureStorage می‌خواند و سپس از parameter/env استفاده می‌کند
/// - خطاهای 401 را تشخیص می‌دهد و [ClaimResult.needsLogin] = true برمی‌گرداند
Future<ClaimResult> claimAgentForClientPanel({
  required String agentId,
  String? clientApiBase,
  String? bearerToken,
}) async {
  if (kIsWeb) {
    return const ClaimResult._(
      success: false,
      errorMessage: 'claim not supported on web',
    );
  }
  var base = (clientApiBase ?? kTspClientApiBase).trim();
  if (base.isEmpty) {
    return const ClaimResult._(
      success: false,
      errorMessage: 'missing TSP_CLIENT_API_BASE',
    );
  }
  if (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }

  // 1) Resolve bearer token (persistent storage → param → env)
  final tok = await _resolveBearerToken(bearerToken);
  if (tok.isEmpty) {
    SecureLog.w('client_panel_agent_claim: no JWT available');
    return ClaimResult.missingJwt();
  }

  // 2) Resolve private key (recover from fallback chain if wiped)
  final pk = await _resolvePrivateKey();
  if (pk == null) {
    SecureLog.e('client_panel_agent_claim: private key unrecoverable');
    return ClaimResult.missingAgentKey();
  }

  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $tok',
  };

  // [CRASH-FIX] HTTP calls with timeout to prevent permanent hang.
  // [CRASH-FIX] jsonDecode wrapped in try-catch for malformed server responses.
  http.Response chRes;
  try {
    chRes = await http
        .post(
          Uri.parse('$base/agents/claim-challenge'),
          headers: headers,
          body: jsonEncode({'agent_id': agentId.trim()}),
        )
        .timeout(const Duration(seconds: 30));
  } catch (e) {
    SecureLog.e('client_panel_agent_claim: challenge request failed', error: e);
    return ClaimResult.httpError(0, body: e.toString());
  }
  if (chRes.statusCode == 401 || chRes.statusCode == 404) {
    SecureLog.w(
      'client_panel_agent_claim: challenge failed with ${chRes.statusCode} '
      '(needsLogin=${chRes.statusCode == 401})',
    );
    return ClaimResult.httpError(chRes.statusCode, body: chRes.body);
  }
  if (chRes.statusCode != 200) {
    SecureLog.w(
      'client_panel_agent_claim: challenge failed ${chRes.statusCode} ${chRes.body}',
    );
    return ClaimResult.httpError(chRes.statusCode, body: chRes.body);
  }

  Map<String, dynamic> map;
  try {
    map = jsonDecode(chRes.body) as Map<String, dynamic>;
  } catch (e) {
    SecureLog.e('client_panel_agent_claim: challenge JSON parse failed', error: e);
    return const ClaimResult._(
      success: false,
      errorMessage: 'challenge response JSON parse failed',
    );
  }
  if (map['already_linked'] == true) {
    return ClaimResult.ok();
  }
  final nonce = map['nonce'] as String?;
  final message = map['message'] as String?;
  if (nonce == null || message == null) {
    SecureLog.e('client_panel_agent_claim: bad challenge response: ${chRes.body}');
    return const ClaimResult._(
      success: false,
      errorMessage: 'challenge response missing nonce/message',
    );
  }

  // 4) Sign + claim step
  final sig = EthSigUtil.signPersonalMessage(
    privateKeyInBytes: _privateKeyBytes(pk),
    message: Uint8List.fromList(utf8.encode(message)),
  );

  // [CRASH-FIX] HTTP with timeout
  http.Response claimRes;
  try {
    claimRes = await http
        .post(
          Uri.parse('$base/agents/claim'),
          headers: headers,
          body: jsonEncode({'nonce': nonce, 'signature': sig}),
        )
        .timeout(const Duration(seconds: 30));
  } catch (e) {
    SecureLog.e('client_panel_agent_claim: claim request failed', error: e);
    return ClaimResult.httpError(0, body: e.toString());
  }
  if (claimRes.statusCode == 200) {
    return ClaimResult.ok();
  }
  if (claimRes.statusCode == 401 || claimRes.statusCode == 404) {
    SecureLog.w(
      'client_panel_agent_claim: claim failed with ${claimRes.statusCode} '
      '(needsLogin=${claimRes.statusCode == 401})',
    );
    return ClaimResult.httpError(claimRes.statusCode, body: claimRes.body);
  }
  SecureLog.w(
    'client_panel_agent_claim: claim failed ${claimRes.statusCode} ${claimRes.body}',
  );
  return ClaimResult.httpError(claimRes.statusCode, body: claimRes.body);
}
