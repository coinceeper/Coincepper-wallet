import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';

import '../di/service_locator.dart';
import '../models/client_panel_models.dart';
import '../models/geo_models.dart';
import 'build_secrets.dart';
import 'tls_pinning.dart';
import '../utils/secure_log.dart';
import 'session_manager.dart';
import 'auth_interceptor.dart';

/// Thrown by [register]/[login] when the address is clearly incomplete ETH (`0x…` without 40 hex).
class MalformedPanelAddressException implements Exception {
  const MalformedPanelAddressException();
  @override
  String toString() => 'MalformedPanelAddressException';
}

/// Base URL for the backend server (same host as agent-ingest ops).
/// از طریق --dart-define=CLIENT_PANEL_BASE_URL=... تأمین شود.
String get _kBaseUrl => BuildSecrets.clientPanelBaseUrl;

class ClientPanelService {
  static ClientPanelService get instance => ServiceLocator.get<ClientPanelService>();
  ClientPanelService._();
  /// DI constructor. Use [instance] for singleton access.
  ClientPanelService();

  Dio? _dio;
  PersistCookieJar? _cookieJar;
  bool _initialized = false;
  String? _bearerToken;
  String? get bearerToken => _bearerToken;
  String get clientBaseUrl => _kBaseUrl;

  Future<void> init() async {
    if (_initialized) return;
    if (_kBaseUrl.isEmpty) {
      _initialized = true;
      return;
    }
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

    // 🏛️ Session-aware interceptor — attaches Bearer from SessionManager,
    //     touches activity on success, detects 401.
    _dio!.interceptors.add(ServiceLocator.get<ClientPanelAuthInterceptor>());

    // Legacy fallback: if _bearerToken is set (old code path),
    // still attach it. The AuthInterceptor takes precedence.
    _dio!.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.headers['Authorization'] == null ||
            (options.headers['Authorization'] as String).isEmpty) {
          final t = _bearerToken;
          if (t != null && t.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $t';
          }
        }
        return handler.next(options);
      },
    ));
    TlsPinning.configure(_dio!);
    _initialized = true;
  }

  /// JWT from login/register JSON — also persists to [SessionManager].
  ///
  /// Legacy: keeps `_bearerToken` for code paths that read it directly.
  /// Modern: establishes the session in [SessionManager] so the
  /// [AuthInterceptor] can pick it up and activity-tracking works.
  void setBearerFromAuthBody(Map<String, dynamic> data) {
    final t = data['token'];
    if (t is String && t.isNotEmpty) {
      _bearerToken = t;
      // Also push into SessionManager so the interceptor, activity tracker,
      // and multi-tab signal channel all see it.
      final walletAddr = data['btc_address'] as String? ??
          data['wallet_address'] as String? ??
          data['address'] as String?;
      if (walletAddr != null && walletAddr.isNotEmpty) {
        // [CRASH-FIX] unawaited with catchError ensures exceptions don't escape
        unawaited(
          ServiceLocator.get<SessionManager>()
              .establishSession(jwtToken: t, walletAddress: walletAddr)
              .catchError((e, st) {
            SecureLog.w('SessionManager.establishSession failed', error: e, stackTrace: st);
          }),
        );
      }
    }
  }

  void clearBearerToken() {
    _bearerToken = null;
  }

  Dio get _client {
    assert(_initialized, 'ClientPanelService.init() must be called first');
    if (_dio == null) {
      SecureLog.e('ClientPanelService: _dio is null but _initialized is true — lazy-init race?');
      throw StateError('ClientPanelService Dio client not initialized');
    }
    return _dio!;
  }

  /// Parses `0x` + exactly 40 hex digits (ignores spaces, dots, ellipsis, etc. in between).
  /// Returns `null` if the string looks ETH-like but does not contain 40 hex digits.
  static String? tryCanonicalEthAddress(String raw) {
    final a = raw.trim();
    if (a.length < 2 || !a.toLowerCase().startsWith('0x')) return null;
    final digits = StringBuffer();
    // [CRASH-FIX] substring with length guard — already checked a.length >= 2
    final body = a.length > 2 ? a.substring(2) : '';
    for (final r in body.runes) {
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

  // ─── Auth Challenge (Sign-in with Wallet) ───────────────────

  /// Request a nonce + message to sign with the wallet's private key.
  Future<Map<String, dynamic>> getChallenge(String btcAddress) async {
    final addr = normalizeBtcAddressForApi(btcAddress);
    if (addr == null) throw const MalformedPanelAddressException();
    final resp = await _client.post('/auth/challenge', data: {
      'btc_address': addr,
    });
    return resp.data as Map<String, dynamic>;
  }

  // ─── Auth ────────────────────────────────────────────────────

  /// Register a new client using wallet signature.
  /// [signature] is the EIP-191 personal_sign of the challenge message.
  Future<Map<String, dynamic>> register({
    required String btcAddress,
    required String nonce,
    required String signature,
    required String inviteCode,
    String? deviceFingerprint,
    String? walletAddress,
  }) async {
    final addr = normalizeBtcAddressForApi(btcAddress);
    if (addr == null) throw const MalformedPanelAddressException();
    final data = <String, dynamic>{
      'btc_address': addr,
      'nonce': nonce,
      'signature': signature,
      'invite_code': inviteCode,
    };
    if (walletAddress != null && walletAddress.isNotEmpty) {
      data['wallet_address'] = walletAddress;
    }
    if (deviceFingerprint != null && deviceFingerprint.isNotEmpty) {
      data['device_fingerprint'] = deviceFingerprint;
    }
    final resp = await _client.post('/auth/register', data: data);
    return resp.data as Map<String, dynamic>;
  }

  /// Login using wallet signature.
  /// [signature] is the EIP-191 personal_sign of the challenge message.
  Future<Map<String, dynamic>> login({
    required String btcAddress,
    required String nonce,
    required String signature,
    String? deviceFingerprint,
    String? walletAddress,
  }) async {
    final addr = normalizeBtcAddressForApi(btcAddress);
    if (addr == null) throw const MalformedPanelAddressException();
    final data = <String, dynamic>{
      'btc_address': addr,
      'nonce': nonce,
      'signature': signature,
    };
    if (walletAddress != null && walletAddress.isNotEmpty) {
      data['wallet_address'] = walletAddress;
    }
    if (deviceFingerprint != null && deviceFingerprint.isNotEmpty) {
      data['device_fingerprint'] = deviceFingerprint;
    }
    final resp = await _client.post('/auth/login', data: data);
    return resp.data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try {
      await _client.delete('/auth/logout');
    } catch (e) {
      SecureLog.w('Error during server-side logout', error: e);
    }
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

  // ─── Revenue Analytics ──────────────────────────────────────────

  /// دریافت تحلیل کامل درآمد تبلیغاتی با تفکیک:
  /// - per-website: کدام وب‌سایت بیشترین درآمد
  /// - per-ad-network: کدام شبکه بهتر pay می‌کند
  /// - per-hour: چه ساعتی CPC بالاتر است  
  /// - per-user-agent: کدام User Agent بهتر است
  /// - per-geo: کدام منطقه GEO بالاترین CPM را دارد
  Future<RevenueAnalytics> getRevenueAnalytics() async {
    final resp = await _client.get('/revenue-analytics');
    return RevenueAnalytics.fromJson(resp.data as Map<String, dynamic>);
  }

  // ─── GEO Analytics ──────────────────────────────────────────────

  /// دریافت تحلیل GEO: درآمد به تفکیک منطقه جغرافیایی
  ///
  /// این endpoint اطلاعات زیر را برمی‌گرداند:
  /// - CPM به تفکیک GEO
  /// - توزیع ترافیک
  /// - نرخ موفقیت کلیک به تفکیک منطقه
  Future<GeoStats> getGeoAnalytics() async {
    final resp = await _client.get('/geo-analytics');
    return GeoStats.fromJson(resp.data as Map<String, dynamic>);
  }

  /// ارسال گزارش GEO به سرور
  Future<void> reportGeoData(Map<String, dynamic> geoReport) async {
    try {
      await _client.post('/geo-analytics/report', data: geoReport);
    } catch (e) {
      SecureLog.w('ClientPanel: reportGeoData failed', error: e);
    }
  }

  // ─── Cookie helpers ──────────────────────────────────────────

  /// Checks session validity via [SessionManager] first (persistent JWT),
  /// then falls back to cookie jar for backward compatibility.
  Future<bool> hasValidSession() async {
    // Modern path: SessionManager (persistent JWT, activity-aware).
    if (ServiceLocator.get<SessionManager>().hasValidSession) return true;

    // Legacy path: in-memory bearer + cookie jar.
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
    // Also terminate the SessionManager session (multi-tab signal emitted).
    await ServiceLocator.get<SessionManager>().terminateSession();
  }
}
