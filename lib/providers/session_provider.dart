import 'dart:async';
import 'package:flutter/foundation.dart';
import '../di/service_locator.dart';
import '../utils/secure_log.dart';
import '../services/session_manager.dart';

/// State exposed by [SessionProvider] to the UI layer.
enum SessionState {
  /// No session exists (fresh app start, or logged out).
  none,

  /// A session is being established (authentication in progress).
  establishing,

  /// A valid session exists and is active.
  active,

  /// The session expired and re-authentication is needed.
  expired,

  /// A 401 was received and the app should re-authenticate.
  authRequired,

  /// The user switched to a different wallet — session is being re-established.
  switchingWallet,
}

/// ChangeNotifier that bridges [SessionManager] to the Flutter widget tree.
///
/// ## Crypto Wallet Session Lifecycle
///
/// ```
/// NONE → establishing → ACTIVE → expired → authRequired → establishing → ACTIVE
///                                                                   
///                                 → terminated → NONE
/// ```
///
/// ## Multi-Tab Support
///
/// When another tab logs out, [SessionManager] detects the foreign-tab signal
/// and fires [SessionEvent.sessionTerminated], which causes this provider to
/// emit `SessionState.none` and triggers a UI redirect to the login screen.
///
class SessionProvider extends ChangeNotifier {
  SessionProvider._();
  SessionProvider();

  static SessionProvider get instance =>
      ServiceLocator.get<SessionProvider>();

  SessionManager get _manager => ServiceLocator.get<SessionManager>();

  // ─── State ─────────────────────────────────────────────────────────────────
  SessionState _state = SessionState.none;
  SessionState get state => _state;

  bool get hasActiveSession => _state == SessionState.active;
  bool get isEstablishing => _state == SessionState.establishing;
  bool get sessionExpired => _state == SessionState.expired;
  bool get authRequired => _state == SessionState.authRequired;

  /// The wallet address the current session is bound to, if any.
  String? get sessionWalletAddress =>
      _state == SessionState.active ? _manager.sessionWalletAddress : null;

  /// Remaining session duration for UI display.
  Duration? get remaining => _manager.remaining;

  /// Idle time for UI display.
  Duration get idleDuration => _manager.idleDuration;

  /// Whether the session survived past the minimum realistic duration (5 min).
  bool get hasMinimumSessionDuration {
    if (_manager.metadata == null) return false;
    return DateTime.now()
            .difference(_manager.metadata!.createdAt)
            .inMinutes >=
        5;
  }

  // ─── Initialization ───────────────────────────────────────────────────────

  /// Must be called once after DI init.
  Future<void> initialize() async {
    SecureLog.i('SessionProvider: initializing...');
    _manager.onSessionEvent = _onSessionEvent;
    _manager.onAuthRequired = _onAuthRequired;

    if (_manager.hasValidSession) {
      _state = SessionState.active;
      SecureLog.i('SessionProvider: valid session found on init');
    } else {
      _state = SessionState.none;
      SecureLog.i('SessionProvider: no valid session on init');
    }

    notifyListeners();
  }

  void _onSessionEvent(SessionEvent event) {
    SecureLog.d('SessionProvider: event=$event');
    switch (event) {
      case SessionEvent.sessionEstablished:
        _state = SessionState.active;
        notifyListeners();
        break;
      case SessionEvent.sessionRefreshed:
        if (_state == SessionState.active) {
          // Stay active.
          notifyListeners();
        }
        break;
      case SessionEvent.sessionExpired:
        _state = SessionState.expired;
        notifyListeners();
        break;
      case SessionEvent.sessionTerminated:
        _state = SessionState.none;
        notifyListeners();
        break;
      case SessionEvent.foreignTabSignal:
        // Re-evaluate session state from storage.
        if (_manager.hasValidSession) {
          _state = SessionState.active;
        } else {
          _state = SessionState.none;
        }
        notifyListeners();
        break;
    }
  }

  void _onAuthRequired(SessionEvent event) {
    _state = SessionState.authRequired;
    notifyListeners();
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  /// Mark the session as expired (e.g. user manually locks the app).
  void markExpired() {
    _state = SessionState.expired;
    notifyListeners();
  }

  /// Called when the user switches to a different wallet.
  Future<void> onWalletSwitch() async {
    _state = SessionState.switchingWallet;
    notifyListeners();
    await _manager.terminateSession();
  }

  /// Called when authentication starts.
  void onAuthStart() {
    _state = SessionState.establishing;
    notifyListeners();
  }

  /// Called when authentication fails permanently.
  void onAuthFailed() {
    _state = SessionState.none;
    notifyListeners();
  }

  /// Clear the session and set state to none.
  Future<void> clearSession() async {
    await _manager.terminateSession();
    _state = SessionState.none;
    notifyListeners();
  }

  @override
  void dispose() {
    _manager.onSessionEvent = null;
    _manager.onAuthRequired = null;
    super.dispose();
  }
}
