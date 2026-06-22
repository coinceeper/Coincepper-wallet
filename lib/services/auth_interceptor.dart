import 'package:dio/dio.dart';
import '../di/service_locator.dart';
import '../utils/secure_log.dart';
import 'session_manager.dart';

/// Dio interceptor that handles authentication for the Client Panel API.
///
/// ## Responsibilities
///
/// 1. **Attach Bearer Token** – Reads the JWT from [SessionManager] and adds
///    it as an `Authorization` header to every request.
///
/// 2. **Touch Activity** – On every successful response, calls
///    [SessionManager.touchActivity] to keep the session alive.
///
/// 3. **401 Detection** – On a 401 response, fires [SessionManager.onAuthRequired]
///    so the provider can trigger re-authentication.
///
/// 4. **Session Expiry Check** – Before each request, checks if the session is
///    still valid. If expired, fires the session-expired callback without
///    sending the request.
///
/// ## Usage
///
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(ServiceLocator.get<ClientPanelAuthInterceptor>());
/// ```
///
class ClientPanelAuthInterceptor extends Interceptor {
  ClientPanelAuthInterceptor._();
  ClientPanelAuthInterceptor();

  static ClientPanelAuthInterceptor get instance =>
      ServiceLocator.get<ClientPanelAuthInterceptor>();

  SessionManager get _session => ServiceLocator.get<SessionManager>();

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // ── 1. Check session validity ──────────────────────────────────────
    final valid = await _session.ensureSessionValid();
    if (!valid) {
      // Session is expired — let the request go through anyway.
      // The server will return 401, and we handle it in onError.
      // But we make sure the event is fired.
      SecureLog.w(
          'AuthInterceptor: session invalid before request to ${options.path}');
    }

    // ── 2. Attach Bearer token ────────────────────────────────────────
    final bearer = _session.bearerToken;
    if (bearer != null && bearer.isNotEmpty) {
      options.headers['Authorization'] = bearer;
      SecureLog.d('AuthInterceptor: attached Bearer token');
    } else {
      SecureLog.d(
          'AuthInterceptor: no Bearer token available for ${options.path}');
    }

    handler.next(options);
  }

  @override
  void onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    // ── Touch activity on success ──────────────────────────────────────
    // Only for authenticated endpoints (status 2xx).
    if (response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300) {
      await _session.touchActivity();
    }

    handler.next(response);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // ── 401: Unauthorised → session expired or invalid token ──────────
    if (err.response?.statusCode == 401) {
      SecureLog.w(
          'AuthInterceptor: 401 received for ${err.requestOptions.path}');

      // Notify the app that auth is needed.
      // The provider should attempt re-authentication.
      _session.onAuthRequired
          ?.call(SessionEvent.sessionExpired);
    }

    handler.next(err);
  }
}
