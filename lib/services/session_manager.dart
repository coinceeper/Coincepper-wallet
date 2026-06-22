import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../di/service_locator.dart';
import '../utils/secure_log.dart';
import 'secure_storage.dart';

// ──────────────────────────────────────────────────────────────────────────────
// SessionManager – Crypto Wallet Session Lifecycle
// ──────────────────────────────────────────────────────────────────────────────
//
// Crypto wallets MUST maintain sessions that:
//   - Survive app restarts (persistent JWT)
//   - Survive multi-tab browsing (SharedPreferences signal)
//   - Expire after a realistic duration (default 15 min inactivity)
//   - Re-authenticate transparently on expiry
//   - Never expose the raw mnemonic or private key
//
// Sessions are per-wallet (one app may have multiple wallets). Each wallet
// address gets its own stored session so switching wallets clears the old
// session and requires a fresh sign-in-with-wallet.
//
// ──────────────────────────────────────────────────────────────────────────────

/// Metadata stored alongside the JWT for session lifecycle management.
class SessionMetadata {
  final String walletAddress;
  final DateTime createdAt;
  final DateTime lastActivityAt;
  final DateTime expiresAt;
  final int tokenTtlMinutes;

  const SessionMetadata({
    required this.walletAddress,
    required this.createdAt,
    required this.lastActivityAt,
    required this.expiresAt,
    this.tokenTtlMinutes = 30,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get remaining => expiresAt.difference(DateTime.now());

  Duration get idleDuration => DateTime.now().difference(lastActivityAt);

  Map<String, dynamic> toJson() => {
        'walletAddress': walletAddress,
        'createdAt': createdAt.toIso8601String(),
        'lastActivityAt': lastActivityAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'tokenTtlMinutes': tokenTtlMinutes,
      };

  factory SessionMetadata.fromJson(Map<String, dynamic> json) =>
      SessionMetadata(
        walletAddress: json['walletAddress'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        lastActivityAt:
            DateTime.tryParse(json['lastActivityAt'] as String? ?? '') ??
                DateTime.now(),
        expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '') ??
            DateTime.now(),
        tokenTtlMinutes: json['tokenTtlMinutes'] as int? ?? 30,
      );

  SessionMetadata copyWith({DateTime? lastActivityAt, DateTime? expiresAt}) =>
      SessionMetadata(
        walletAddress: walletAddress,
        createdAt: createdAt,
        lastActivityAt: lastActivityAt ?? this.lastActivityAt,
        expiresAt: expiresAt ?? this.expiresAt,
        tokenTtlMinutes: tokenTtlMinutes,
      );
}

/// Events emitted by [SessionManager] so other layers can react.
enum SessionEvent {
  /// A new session was established (login / register).
  sessionEstablished,

  /// The session was refreshed (new token or activity reset).
  sessionRefreshed,

  /// The session expired (inactivity or TTL).
  sessionExpired,

  /// The session was explicitly terminated (logout / switch wallet).
  sessionTerminated,

  /// A tab-change signal was detected from another app instance.
  foreignTabSignal,
}

/// Callback type for session events.
typedef SessionEventCallback = void Function(SessionEvent event);

/// ═══════════════════════════════════════════════════════════════════════════
/// SessionManager — Thread-safe, persistent, multi-tab-aware session manager
/// ═══════════════════════════════════════════════════════════════════════════
///
/// ## Key features
///
/// 1. **Persistent JWT Storage** – Token + metadata stored in SecureStorage
///    (Keychain / EncryptedSharedPreferences). Survives app restart.
///
/// 2. **Session Duration** – Configurable TTL (default 15–30 min). Session
///    heartbeats reset the idle timer on every meaningful user interaction.
///
/// 3. **Multi-Tab Awareness** – Uses SharedPreferences as a lightweight
///    inter-process signalling channel. When session state changes in one
///    tab, other tabs detect it within 5 seconds and adapt.
///
/// 4. **Activity Heartbeat** – Tracks `lastActivityAt` so that the session
///    expires after N minutes of real inactivity, not wall-clock time.
///
/// 5. **Re-authentication Trigger** – [onSessionExpired] callback lets the
///    provider re-run the sign-in-with-wallet flow without losing the UI.
///
/// 6. **Clean Separation** – No direct dependency on Dio or UI widgets.
///    The [ClientPanelService] and [AuthInterceptor] layer on top.
///
/// ═══════════════════════════════════════════════════════════════════════════
class SessionManager {
  SessionManager._();
  SessionManager();

  static SessionManager get instance => ServiceLocator.get<SessionManager>();

  // ─── Constants ────────────────────────────────────────────────────────────
  static const String _sessionMetaKey = 'session_metadata';
  static const String _sessionJwtKey = 'session_jwt';
  static const String _sessionSignalKey = 'session_signal_timestamp';
  static const String _sessionSignalWalletKey = 'session_signal_wallet';
  static const String _sessionSignalEventKey = 'session_signal_event';
  static const String _sessionBearerPrefix = 'Bearer ';

  /// Default session TTL: 30 minutes of inactivity.
  static const Duration _defaultSessionTtl = Duration(minutes: 30);

  /// Maximum session lifetime: 24 hours (hard limit, even with activity).
  static const Duration _maxSessionLifetime = Duration(hours: 24);

  /// How often to check for foreign-tab signals.
  static const Duration _foreignTabPollInterval = Duration(seconds: 5);

  // ─── Internal State ───────────────────────────────────────────────────────

  SessionMetadata? _metadata;
  String? _jwtToken;
  bool _initialized = false;
  Timer? _foreignTabPoller;
  Timer? _sessionExpiryTimer;

  /// Fired when the session expires and the caller should re-authenticate.
  SessionEventCallback? onSessionEvent;

  /// Fired when a 401 is received and we cannot refresh – UI should lock.
  SessionEventCallback? onAuthRequired;

  /// Whether the session heartbeat should be running (true when app is
  /// foreground and authenticated).
  bool _heartbeatActive = false;

  /// The wallet address the current session is bound to.
  String? get sessionWalletAddress => _metadata?.walletAddress;

  /// Whether a valid (non-expired) session exists.
  bool get hasValidSession =>
      _metadata != null &&
      _jwtToken != null &&
      _jwtToken!.isNotEmpty &&
      !_metadata!.isExpired &&
      _metadata!.idleDuration < _defaultSessionTtl;

  /// The raw JWT token for API Bearer auth.
  String? get jwtToken => _jwtToken;

  /// Formatted "Bearer {token}" string.
  String? get bearerToken =>
      _jwtToken != null ? '$_sessionBearerPrefix$_jwtToken' : null;

  /// Remaining session duration before expiry.
  Duration? get remaining => _metadata?.remaining;

  /// Idle duration since last user activity.
  Duration get idleDuration => _metadata?.idleDuration ?? Duration.zero;

  /// Session metadata for debugging.
  SessionMetadata? get metadata => _metadata;

  /// Whether the session has been initialized from storage.
  bool get isInitialized => _initialized;

  // ─── Initialization ───────────────────────────────────────────────────────

  /// Load any persisted session from SecureStorage.
  /// Call once at app startup, after DI is initialized.
  Future<void> initialize() async {
    if (_initialized) return;
    SecureLog.i('SessionManager: initializing...');
    await _loadFromStorage();
    _startForeignTabPoller();
    _initialized = true;
    SecureLog.i(
        'SessionManager: initialized. hasValidSession=$hasValidSession');
  }

  Future<void> _loadFromStorage() async {
    try {
      final storage = ServiceLocator.get<SecureStorage>();
      final metaJson = await storage.getSecureJson(_sessionMetaKey);
      if (metaJson != null && metaJson.isNotEmpty) {
        _metadata = SessionMetadata.fromJson(
            metaJson.map((k, v) => MapEntry(k, v as dynamic)));
        _jwtToken = await storage.getSecureData(_sessionJwtKey);
        SecureLog.i(
            'SessionManager: loaded session for ${_metadata!.walletAddress}, '
            'expiresAt=${_metadata!.expiresAt.toIso8601String()}, '
            'remaining=${_metadata!.remaining.inSeconds}s');
      }
    } catch (e) {
      SecureLog.w('SessionManager: failed to load session from storage',
          error: e);
      _metadata = null;
      _jwtToken = null;
    }
  }

  // ─── Foreign-Tab Signal (SharedPreferences Channel) ───────────────────────

  void _startForeignTabPoller() {
    _foreignTabPoller?.cancel();
    _foreignTabPoller = Timer.periodic(_foreignTabPollInterval, (_) async {
      await _checkForeignTabSignal();
    });
  }

  /// Checks SharedPreferences for a session signal from another tab.
  /// If the signal is newer than our last known state, we react.
  Future<void> _checkForeignTabSignal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final signalTs = prefs.getInt(_sessionSignalKey);
      if (signalTs == null) return;

      final signalWallet = prefs.getString(_sessionSignalWalletKey) ?? '';
      final signalEvent = prefs.getString(_sessionSignalEventKey) ?? '';

      // Ignore signals for a different wallet.
      if (_metadata != null &&
          signalWallet.isNotEmpty &&
          signalWallet != _metadata!.walletAddress) {
        return;
      }

      final lastKnownSignal = _lastProcessedSignal;
      if (signalTs > lastKnownSignal) {
        _lastProcessedSignal = signalTs;
        SecureLog.d(
            'SessionManager: foreign tab signal detected: $signalEvent');

        try {
          switch (signalEvent) {
            case 'session_established':
              // Another tab logged in — reload our session state.
              await _loadFromStorage();
              onSessionEvent?.call(SessionEvent.foreignTabSignal);
              break;
            case 'session_terminated':
              // Another tab logged out — clear our session too.
              if (_metadata != null) {
                await _clearInternal();
                onSessionEvent?.call(SessionEvent.sessionTerminated);
              }
              break;
            case 'session_refreshed':
              // Another tab refreshed — reload token.
              await _loadFromStorage();
              onSessionEvent?.call(SessionEvent.foreignTabSignal);
              break;
          }
        } catch (e) {
          SecureLog.w('SessionManager: foreign tab signal handler failed', error: e);
        }
      }
    } catch (e) {
      SecureLog.w('SessionManager: foreign tab check failed', error: e);
    }
  }

  int _lastProcessedSignal = 0;

  /// Emit a signal to SharedPreferences so other tabs can detect it.
  Future<void> _emitForeignTabSignal(String event) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_sessionSignalKey, now);
      await prefs.setString(_sessionSignalWalletKey,
          _metadata?.walletAddress ?? '');
      await prefs.setString(_sessionSignalEventKey, event);
      _lastProcessedSignal = now;
    } catch (e) {
      SecureLog.w('SessionManager: failed to emit signal', error: e);
    }
  }

  // ─── Session Lifecycle ────────────────────────────────────────────────────

  /// Establish a new session after successful authentication.
  ///
  /// [jwtToken] – The JWT returned by the server.
  /// [walletAddress] – The wallet address this session is bound to.
  /// [ttlMinutes] – Session TTL in minutes (default 30).
  Future<void> establishSession({
    required String jwtToken,
    required String walletAddress,
    int ttlMinutes = 30,
  }) async {
    SecureLog.i(
        'SessionManager: establishing session for $walletAddress, TTL=${ttlMinutes}min');

    final now = DateTime.now();
    final expiresAt = now.add(Duration(minutes: ttlMinutes));

    // Hard cap at 24 hours.
    final maxExpiry = now.add(_maxSessionLifetime);
    final finalExpiry = expiresAt.isBefore(maxExpiry) ? expiresAt : maxExpiry;

    _metadata = SessionMetadata(
      walletAddress: walletAddress,
      createdAt: now,
      lastActivityAt: now,
      expiresAt: finalExpiry,
      tokenTtlMinutes: ttlMinutes,
    );
    _jwtToken = jwtToken;

    await _persistSession();
    _startExpiryTimer();

    // Signal other tabs.
    await _emitForeignTabSignal('session_established');
    onSessionEvent?.call(SessionEvent.sessionEstablished);
  }

  /// Record user activity. Resets the idle timer.
  Future<void> touchActivity() async {
    if (_metadata == null || _jwtToken == null) return;

    final now = DateTime.now();

    // Only persist if at least 10 seconds since last touch (throttle).
    if (now.difference(_metadata!.lastActivityAt).inSeconds < 10) return;

    // Extend expiry by TTL from now (rolling window, capped at 24h).
    final newExpiryCandidate =
        now.add(Duration(minutes: _metadata!.tokenTtlMinutes));
    final maxExpiry = _metadata!.createdAt.add(_maxSessionLifetime);
    final newExpiry =
        newExpiryCandidate.isBefore(maxExpiry) ? newExpiryCandidate : maxExpiry;

    _metadata = _metadata!.copyWith(
      lastActivityAt: now,
      expiresAt: newExpiry,
    );

    await _persistSession();
    _startExpiryTimer();
    onSessionEvent?.call(SessionEvent.sessionRefreshed);
  }

  /// Refresh the session (e.g. after a successful token refresh with the server).
  Future<void> refreshSession({
    String? newJwtToken,
    int? ttlMinutes,
  }) async {
    if (_metadata == null) return;

    final now = DateTime.now();
    final ttl = ttlMinutes ?? _metadata!.tokenTtlMinutes;
    final expiresAt = now.add(Duration(minutes: ttl));
    final maxExpiry = _metadata!.createdAt.add(_maxSessionLifetime);
    final finalExpiry = expiresAt.isBefore(maxExpiry) ? expiresAt : maxExpiry;

    _metadata = _metadata!.copyWith(
      lastActivityAt: now,
      expiresAt: finalExpiry,
    );
    if (newJwtToken != null) {
      _jwtToken = newJwtToken;
    }

    await _persistSession();
    _startExpiryTimer();
    await _emitForeignTabSignal('session_refreshed');
    onSessionEvent?.call(SessionEvent.sessionRefreshed);
  }

  /// Terminate the current session (logout / switch wallet).
  Future<void> terminateSession() async {
    SecureLog.i('SessionManager: terminating session');
    await _clearInternal();
    await _emitForeignTabSignal('session_terminated');
    onSessionEvent?.call(SessionEvent.sessionTerminated);
  }

  /// Check if the session is still valid. If expired, fires the expiry event.
  /// Returns `true` if the session is valid.
  Future<bool> ensureSessionValid() async {
    if (!hasValidSession) {
      if (_metadata != null && _metadata!.isExpired) {
        SecureLog.i('SessionManager: session expired, firing expiry event');
        onSessionEvent?.call(SessionEvent.sessionExpired);
      }
      return false;
    }
    return true;
  }

  // ─── Internal Persistence ─────────────────────────────────────────────────

  Future<void> _persistSession() async {
    try {
      final storage = ServiceLocator.get<SecureStorage>();
      if (_metadata != null) {
        await storage.saveSecureJson(
            _sessionMetaKey, _metadata!.toJson());
      }
      if (_jwtToken != null) {
        await storage.saveSecureData(_sessionJwtKey, _jwtToken!);
      }
    } catch (e) {
      SecureLog.e('SessionManager: failed to persist session', error: e);
    }
  }

  Future<void> _clearInternal() async {
    try {
      final storage = ServiceLocator.get<SecureStorage>();
      await storage.deleteSecureData(_sessionMetaKey);
      await storage.deleteSecureData(_sessionJwtKey);
    } catch (e) {
      SecureLog.w('SessionManager: error clearing storage', error: e);
    }
    _metadata = null;
    _jwtToken = null;
    _sessionExpiryTimer?.cancel();
    _sessionExpiryTimer = null;
  }

  void _startExpiryTimer() {
    _sessionExpiryTimer?.cancel();
    if (_metadata == null) return;

    final remaining = _metadata!.remaining;
    if (remaining.isNegative || remaining == Duration.zero) {
      // Already expired.
      try {
        onSessionEvent?.call(SessionEvent.sessionExpired);
      } catch (e) {
        SecureLog.w('SessionManager: expiry callback failed', error: e);
      }
      return;
    }

    _sessionExpiryTimer = Timer(remaining, () {
      SecureLog.i('SessionManager: expiry timer fired');
      try {
        onSessionEvent?.call(SessionEvent.sessionExpired);
      } catch (e) {
        SecureLog.w('SessionManager: expiry timer callback failed', error: e);
      }
    });
  }

  // ─── Heartbeat ────────────────────────────────────────────────────────────

  /// Start a periodic heartbeat that keeps the session alive.
  /// Call every time a user interaction happens.
  void startHeartbeat() {
    if (_heartbeatActive) return;
    _heartbeatActive = true;
  }

  /// Stop the heartbeat (e.g. app goes to background).
  void stopHeartbeat() {
    _heartbeatActive = false;
  }

  // ─── Cleanup ──────────────────────────────────────────────────────────────

  /// Dispose all timers. Call on app dispose.
  void dispose() {
    _foreignTabPoller?.cancel();
    _sessionExpiryTimer?.cancel();
    _foreignTabPoller = null;
    _sessionExpiryTimer = null;
    _heartbeatActive = false;
    onSessionEvent = null;
    onAuthRequired = null;
  }
}
