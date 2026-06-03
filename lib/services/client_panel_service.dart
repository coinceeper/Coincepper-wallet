import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/client_panel_models.dart';
import 'tls_pinning.dart';

/// Thrown by [register]/[login] when the address is clearly incomplete ETH (`0x…` without 40 hex).
class MalformedPanelAddressException implements Exception {
  const MalformedPanelAddressException();
  @override
  String toString() => 'MalformedPanelAddressException';
}

/// Base URL for the backend server (same host as agent-ingest ops).
const _kBaseUrl = 'https://agentadmin.duckdns.org/api/v1/client';

class ClientPanelService {
  static ClientPanelService? _instance;
  static ClientPanelService get instance => _instance ??= ClientPanelService._();
  ClientPanelService._();

  Dio? _dio;
  PersistCookieJar? _cookieJar;
  bool _initialized = false;
  String? _bearerToken;
  String? get bearerToken => _bearerToken;
  String get clientBaseUrl => _kBaseUrl;

  Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    final cookiePath = '${dir.path}/.client_panel_cookies';
    _cookieJar = PersistCookieJar(storage: FileStorage(cookiePath));
    _dio = Dio(BaseOptions(
      baseUrl: _kBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio!.interceptors.add(CookieManager(_cookieJar!));
    _dio!.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final t = _bearerToken;
        if (t != null && t.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $t';
        }
        return handler.next(options);
      },
    ));
    TlsPinning.configure(_dio!);
    _initialized = true;
  }

  /// JWT from login/register JSON — survives clients where Set-Cookie is not applied to the jar.
  void setBearerFromAuthBody(Map<String, dynamic> data) {
    final t = data['token'];
    if (t is String && t.isNotEmpty) {
      _bearerToken = t;
    }
  }

  void clearBearerToken() {
    _bearerToken = null;
  }

  Dio get _client {
    assert(_initialized, 'ClientPanelService.init() must be called first');
    return _dio!;
  }

  /// Parses `0x` + exactly 40 hex digits (ignores spaces, dots, ellipsis, etc. in between).
  /// Returns `null` if the string looks ETH-like but does not contain 40 hex digits.
  static String? tryCanonicalEthAddress(String raw) {
    final a = raw.trim();
    if (a.length < 2 || !a.toLowerCase().startsWith('0x')) return null;
    final digits = StringBuffer();
    for (final r in a.substring(2).runes) {
      final c = String.fromCharCode(r);
      if (RegExp(r'[0-9a-fA-F]').hasMatch(c)) digits.write(c);
    }
    final d = digits.toString().toLowerCase();
    if (d.length != 40) return null;
    return '0x$d';
  }

  /// Same normalization as backend: canonical `0x` + 40 hex, or legacy BTC string as trimmed.
  /// Returns `null` if the input is empty or looks like ETH but cannot yield 40 hex digits
  /// (truncated display / ellipsis) — do not send that raw string to the API.
  static String? normalizeBtcAddressForApi(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final eth = tryCanonicalEthAddress(t);
    if (eth != null) return eth;
    if (t.length >= 2 && t.toLowerCase().startsWith('0x')) {
      return null;
    }
    return t;
  }

  /// True if [addr] is a full `0x` + 40 hex (after canonicalization).
  static bool isFullEthPanelAddress(String addr) =>
      tryCanonicalEthAddress(addr) != null;

  // ─── Auth ────────────────────────────────────────────────────

  /// Register a new client. Returns 201 on success, throws DioException otherwise.
  Future<Map<String, dynamic>> register({
    required String btcAddress,
    required String pin,
    required String inviteCode,
    String? deviceFingerprint,
  }) async {
    final addr = normalizeBtcAddressForApi(btcAddress);
    if (addr == null) throw const MalformedPanelAddressException();
    final data = <String, dynamic>{
      'btc_address': addr,
      'pin': pin,
      'invite_code': inviteCode,
    };
    if (deviceFingerprint != null && deviceFingerprint.isNotEmpty) {
      data['device_fingerprint'] = deviceFingerprint;
    }
    final resp = await _client.post('/auth/register', data: data);
    return resp.data as Map<String, dynamic>;
  }

  /// Login an existing client. Returns the user + token data.
  Future<Map<String, dynamic>> login({
    required String btcAddress,
    required String pin,
    String? deviceFingerprint,
  }) async {
    final addr = normalizeBtcAddressForApi(btcAddress);
    if (addr == null) throw const MalformedPanelAddressException();
    final data = <String, dynamic>{
      'btc_address': addr,
      'pin': pin,
    };
    if (deviceFingerprint != null && deviceFingerprint.isNotEmpty) {
      data['device_fingerprint'] = deviceFingerprint;
    }
    final resp = await _client.post('/auth/login', data: data);
    return resp.data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try {
      await _client.delete('/auth/logout');
    } catch (_) {}
    clearBearerToken();
    await _cookieJar?.deleteAll();
  }

  // ─── Dashboard ───────────────────────────────────────────────

  Future<ClientDashboard> getDashboard() async {
    final resp = await _client.get('/dashboard');
    return ClientDashboard.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<ClientUser> getProfile() async {
    final resp = await _client.get('/me');
    return ClientUser.fromJson(resp.data as Map<String, dynamic>);
  }

  /// POST /periodic-checkin — minimum 8h cooldown.
  /// Returns [CheckinResponse] on success, throws with [retryAfterSec] on 429.
  Future<CheckinResponse> postPeriodicCheckin() async {
    final resp = await _client.post('/periodic-checkin');
    return CheckinResponse.fromJson(resp.data as Map<String, dynamic>);
  }

  // ─── Balance ─────────────────────────────────────────────────

  Future<ClientBalance> getBalance() async {
    final resp = await _client.get('/balance');
    return ClientBalance.fromJson(resp.data as Map<String, dynamic>);
  }

  // ─── Agents ──────────────────────────────────────────────────

  Future<List<ClientAgent>> getMyAgents() async {
    final resp = await _client.get('/agents');
    final raw = resp.data;
    List<dynamic> data = const [];
    if (raw is List) {
      data = raw;
    } else if (raw is Map<String, dynamic>) {
      final byData = raw['data'];
      final byAgents = raw['agents'];
      if (byData is List) {
        data = byData;
      } else if (byAgents is List) {
        data = byAgents;
      }
    }
    return data
        .whereType<Map>()
        .map((e) => ClientAgent.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  // ─── Earnings ────────────────────────────────────────────────

  Future<({List<ClientEarning> items, int total})> getEarnings({
    int page = 1,
    int pageSize = 20,
  }) async {
    final resp = await _client.get('/earnings', queryParameters: {
      'page': page,
      'page_size': pageSize,
    });
    final body = resp.data as Map<String, dynamic>;
    final items = (body['data'] as List<dynamic>? ?? [])
        .map((e) => ClientEarning.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items: items, total: (body['total'] as num?)?.toInt() ?? 0);
  }

  // ─── Withdrawals ─────────────────────────────────────────────

  Future<ClientWithdrawal> requestWithdrawal({
    required double amountBtc,
    required String sourceType,
  }) async {
    final resp = await _client.post('/withdrawals', data: {
      'amount_btc': amountBtc,
      'source_type': sourceType,
    });
    return ClientWithdrawal.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<({List<ClientWithdrawal> items, int total})> getWithdrawals({
    int page = 1,
    int pageSize = 20,
  }) async {
    final resp = await _client.get('/withdrawals', queryParameters: {
      'page': page,
      'page_size': pageSize,
    });
    final body = resp.data as Map<String, dynamic>;
    final items = (body['data'] as List<dynamic>? ?? [])
        .map((e) => ClientWithdrawal.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items: items, total: (body['total'] as num?)?.toInt() ?? 0);
  }

  // ─── Referrals ───────────────────────────────────────────────

  Future<List<ClientReferral>> getReferrals() async {
    final resp = await _client.get('/referrals');
    final data = (resp.data as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
    return data.map((e) => ClientReferral.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ─── Notifications ───────────────────────────────────────────

  Future<List<ClientNotification>> getNotifications({bool onlyUnread = false}) async {
    final resp = await _client.get('/notifications',
        queryParameters: onlyUnread ? {'unread': 'true'} : null);
    final data = (resp.data as Map<String, dynamic>)['data'] as List<dynamic>? ?? [];
    return data.map((e) => ClientNotification.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> markNotificationsRead() async {
    await _client.put('/notifications/read-all');
  }

  // ─── Cookie helpers ──────────────────────────────────────────

  Future<bool> hasValidSession() async {
    if (_bearerToken != null && _bearerToken!.isNotEmpty) return true;
    if (_cookieJar == null) return false;
    final uri = Uri.parse(_kBaseUrl);
    final cookies = await _cookieJar!.loadForRequest(uri);
    return cookies.any((c) => c.name == 'client_token' && !_isCookieExpired(c));
  }

  bool _isCookieExpired(Cookie c) {
    final exp = c.expires;
    if (exp == null) return false;
    return exp.isBefore(DateTime.now());
  }

  Future<void> clearSession() async {
    clearBearerToken();
    await _cookieJar?.deleteAll();
  }
}
