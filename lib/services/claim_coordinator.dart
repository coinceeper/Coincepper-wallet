import 'dart:async';

import '../di/service_locator.dart';
import '../utils/secure_log.dart';

import 'client_panel_agent_claim.dart';
import 'notification_helper.dart';

/// Coordinates intelligent retry of agent-claim requests with exponential
/// backoff, 401 detection, and local user notification when the session
/// repeatedly fails.
///
/// Backoff intervals (seconds): [30, 60, 120, 300]
/// After 2 consecutive 401 responses a local notification is fired so the
/// user knows they need to re-authenticate.
///
/// Thread-safe via a [_running] flag — only one retry cycle runs at a time.
class ClaimCoordinator {
  ClaimCoordinator();

  ClaimCoordinator._();

  static ClaimCoordinator get instance => ServiceLocator.get<ClaimCoordinator>();

  // ── Backoff configuration ───────────────────────────────────────────────
  static const List<int> _backoffIntervals = [30, 60, 120, 300];
  static const int _maxConsecutive401BeforeNotify = 2;

  // ── State ──────────────────────────────────────────────────────────────
  bool _running = false;
  int _consecutive401Count = 0;

  /// Whether a claim retry cycle is currently in progress.
  bool get isRunning => _running;

  /// Persists a JWT token to secure storage (delegates to [persistPanelJwt]).
  ///
  /// This method exists as a convenience on the coordinator so callers don't
  /// need to import the claim module directly for persistence.
  Future<void> persistJwt(String jwt) => persistPanelJwt(jwt);

  /// Clears the persisted JWT from secure storage (delegates to [clearPanelJwt]).
  Future<void> clearJwt() => clearPanelJwt();

  /// Resets internal state: clears the consecutive-401 counter and releases
  /// the running flag.
  ///
  /// Call this after a successful re-authentication so that the next claim
  /// attempt starts with a clean slate.
  void reset() {
    _consecutive401Count = 0;
    _running = false;
  }

  /// Attempts to claim [agentId] on [clientApiBase] with [bearerToken],
  /// retrying up to 4 times with increasing backoff ([30s, 60s, 120s, 300s]).
  ///
  /// Returns `true` if any attempt succeeded, `false` if all attempts failed.
  ///
  /// ## 401 escalation
  /// When two consecutive attempts both return a 401 status, a local
  /// notification is shown via [NotificationHelper.showPanelAlert] so the
  /// user is alerted that their panel session has expired.
  ///
  /// ## Thread safety
  /// While a retry cycle is running, concurrent calls return `false`
  /// immediately to avoid duplicate claim-waves.
  Future<bool> claimWithRetry({
    required String agentId,
    required String clientApiBase,
    required String bearerToken,
  }) async {
    if (_running) {
      SecureLog.d('ClaimCoordinator: already running — skipping duplicate call');
      return false;
    }

    _running = true;

    try {
      for (var attempt = 0; attempt < _backoffIntervals.length; attempt++) {
        SecureLog.d(
          'ClaimCoordinator: attempt ${attempt + 1}/${_backoffIntervals.length} '
          'for agent $agentId',
        );

        final result = await claimAgentForClientPanel(
          agentId: agentId,
          clientApiBase: clientApiBase,
          bearerToken: bearerToken,
        );

        if (result.success) {
          SecureLog.d('ClaimCoordinator: attempt ${attempt + 1} succeeded');
          _consecutive401Count = 0;
          return true;
        }

        // Track consecutive 401s and notify user when threshold is reached.
        if (result.needsLogin) {
          _consecutive401Count++;
          SecureLog.w(
            'ClaimCoordinator: consecutive 401 count = $_consecutive401Count',
          );

          if (_consecutive401Count >= _maxConsecutive401BeforeNotify) {
            _showSessionExpiredNotification();
            // Reset counter so we don't spam notifications on every retry.
            _consecutive401Count = 0;
          }
        } else {
          // Non-401 failure — reset counter since the issue is not auth.
          _consecutive401Count = 0;
        }

        if (attempt < _backoffIntervals.length - 1) {
          final delaySec = _backoffIntervals[attempt];
          SecureLog.w(
            'ClaimCoordinator: attempt ${attempt + 1} failed — '
            'retrying in ${delaySec}s',
          );
          await Future.delayed(Duration(seconds: delaySec));
        }
      }

      SecureLog.w(
        'ClaimCoordinator: all ${_backoffIntervals.length} attempts exhausted '
        'for agent $agentId',
      );
      return false;
    } catch (e) {
      SecureLog.e('ClaimCoordinator: unexpected error during claim cycle: $e');
      return false;
    } finally {
      _running = false;
    }
  }

  /// Fires a local notification telling the user their panel session has
  /// expired and they need to re-login.
  void _showSessionExpiredNotification() {
    try {
      NotificationHelper.showPanelAlert(
        title: 'Session Expired',
        body:
            'Your panel session has expired after multiple failed attempts. '
            'Please re-authenticate to continue mining.',
        payload: 'panel_reauth',
      );
    } catch (e) {
      SecureLog.e('ClaimCoordinator: failed to show notification: $e');
    }
  }
}
