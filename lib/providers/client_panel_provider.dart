import 'dart:async';
import 'dart:convert';
import 'package:hex/hex.dart';
import 'package:eth_sig_util/eth_sig_util.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../utils/secure_log.dart';

import '../models/client_panel_models.dart';
import '../models/geo_models.dart';
import '../services/client_panel_service.dart';
import '../services/client_auth_service.dart';
import '../services/claim_coordinator.dart';
import '../services/panel_alert_local_notifier.dart';
import '../services/secure_storage.dart';
import '../services/session_manager.dart';
import '../services/tsp_agent_bootstrap.dart';
import '../services/tsp_agent_channel.dart';
import '../services/geo_proxy_service.dart';
import '../providers/session_provider.dart';
import '../utils/wallet_identity.dart';
import '../wallet/core/wallet_core_bridge_native.dart';
import '../di/service_locator.dart';

enum PanelConnectionStatus { connected, disconnected, reconnecting }

class ClientPanelProvider extends ChangeNotifier {
  // ─── Connection status ─────────────────────────────────────────
  PanelConnectionStatus _connectionStatus = PanelConnectionStatus.connected;
  PanelConnectionStatus get connectionStatus => _connectionStatus;

  // ─── Bound CoinCeeper wallet (multi-wallet panel identity) ─────
  String? boundPanelAddress;
  String? panelWalletName;
  String? panelUserId;
  String? walletAddressEth; // Ethereum address for signature verification

  // ─── Auth state ────────────────────────────────────────────────
  bool _authenticated = false;
  bool _authLoading = false;
  bool _needsInviteCode = false;
  String? _authError;

  bool get authenticated => _authenticated;
  bool get authLoading => _authLoading;
  bool get needsInviteCode => _needsInviteCode;
  String? get authError => _authError;

  ClientUser? get currentUser => ServiceLocator.get<ClientAuthService>().currentUser;

  /// Switch panel identity to another wallet: clears HTTP session and reloads data.
  Future<void> bindToResolvedWallet(
    String panelAddress,
    String walletName,
    String userId,
  ) async {
    var norm = ClientPanelService.normalizeBtcAddressForApi(panelAddress);
    if (norm == null) {
      final recovered =
          await getPanelAddressForWallet(walletName, userId);
      if (recovered != null) {
        norm = ClientPanelService.normalizeBtcAddressForApi(recovered);
      }
    }
    if (norm == null) {
      _authError = 'panel.wallet_address_incomplete';
      _authenticated = false;
      panelWalletName = walletName;
      panelUserId = userId;
      notifyListeners();
      return;
    }
    panelWalletName = walletName;
    panelUserId = userId;

    if (boundPanelAddress != null &&
        ClientPanelService.normalizeBtcAddressForApi(boundPanelAddress!) ==
            norm &&
        _authenticated) {
      notifyListeners();
      return;
    }

    _refreshTimer?.cancel();
    _clearDomainState();
    boundPanelAddress = norm;

    // 🏛️ Session-aware wallet switch.
    await ServiceLocator.get<SessionProvider>().onWalletSwitch();

    // Configure wallet signing callback for this wallet
    final wName = panelWalletName;
    final uId = panelUserId;
    if (wName != null && uId != null) {
      ServiceLocator.get<ClientAuthService>().setSigner((message) async {
        final mnemonic =
            await ServiceLocator.get<SecureStorage>().getMnemonic(wName, uId);
        if (mnemonic == null || mnemonic.isEmpty) {
          throw StateError('mnemonic not available for $wName');
        }
        final hexKey = await ServiceLocator.get<WalletCoreBridge>().withPrivateKeyHex(
          mnemonic: mnemonic,
          blockchainName: 'Ethereum',
          callback: (hex) async => hex,
        );
        final keyBytes = Uint8List.fromList(HEX.decode(hexKey));
        return EthSigUtil.signPersonalMessage(
          privateKeyInBytes: keyBytes,
          message: Uint8List.fromList(utf8.encode(message)),
        );
      });
    }

    await ServiceLocator.get<ClientAuthService>().clearBackendSessionOnly();
    notifyListeners();

    // Derive the ETH wallet address from the mnemonic (personal_sign recovers
    // to the ETH address, not the BTC address — the backend needs it for
    // signature verification).
    walletAddressEth = null;
    if (wName != null && uId != null) {
      final mnemonic = await ServiceLocator.get<SecureStorage>().getMnemonic(wName, uId);
      if (mnemonic != null && mnemonic.isNotEmpty) {
        walletAddressEth = await deriveEthStyleAddressFromMnemonic(mnemonic);
      }
    }

    await authenticate(norm, walletAddressEth: walletAddressEth);
  }

  void _clearDomainState() {
    _authenticated = false;
    _needsInviteCode = false;
    _authError = null;
    dashboard = null;
    dashboardLoading = false;
    dashboardError = null;
    agents = [];
    agentsLoading = false;
    agentsError = null;
    localMinerRunning = false;
    localMinerChecked = false;
    localAgentId = null;
    localMinerLastStartCode = null;
    earnings = [];
    earningsTotal = 0;
    earningsPage = 1;
    earningsLoading = false;
    earningsError = null;
    withdrawals = [];
    withdrawalsTotal = 0;
    withdrawalsPage = 1;
    withdrawalsLoading = false;
    withdrawalsError = null;
    referrals = [];
    referralsLoading = false;
    referralsError = null;
    notifications = [];
    notificationsLoading = false;
    notificationsError = null;
    revenueAnalytics = null;
    revenueAnalyticsLoading = false;
    revenueAnalyticsError = null;
    _sortedByWebsite = [];
    _sortedByUserAgent = [];
    _sortedByGeo = [];
    _cachedGeoStats = null;
    geoAnalytics = null;
    geoAnalyticsLoading = false;
    geoAnalyticsError = null;
    checkinLoading = false;
    checkinError = null;
    checkinRetryAfterSec = null;
    _agentHealthFailureCount = 0;
  }

  String _cacheKeySuffix() =>
      boundPanelAddress?.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_') ??
      'global';

  // â”€â”€â”€ Dashboard â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  ClientDashboard? dashboard;
  bool dashboardLoading = false;
  String? dashboardError;

  // â”€â”€â”€ Agents â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<ClientAgent> agents = [];
  bool agentsLoading = false;
  String? agentsError;
  bool localMinerRunning = false;
  bool localMinerChecked = false;
  String? localAgentId;
  int? localMinerLastStartCode;

  /// Same rule as [BotsTab]: extra device miner tile when runtime is up but that agent is not in the API list yet.
  bool get showsExtraLocalMiner =>
      localMinerChecked &&
      localMinerRunning &&
      !(localAgentId != null &&
          agents.any((a) => a.id.toLowerCase() == localAgentId!.toLowerCase()));

  /// Dashboard "my miners" active count, including the on-device miner when the backend has not reflected it yet.
  int get effectiveDashboardMyActiveAgents {
    final d = dashboard;
    if (d == null) return 0;
    return showsExtraLocalMiner ? d.myActiveAgents + 1 : d.myActiveAgents;
  }

  /// Dashboard "my miners" total count, including the on-device miner when the backend has not reflected it yet.
  int get effectiveDashboardMyAgentCount {
    final d = dashboard;
    if (d == null) return 0;
    if (!showsExtraLocalMiner) return d.myAgentCount;
    final bumped = d.myAgentCount + 1;
    final active = effectiveDashboardMyActiveAgents;
    return bumped < active ? active : bumped;
  }

  // â”€â”€â”€ Earnings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<ClientEarning> earnings = [];
  int earningsTotal = 0;
  int earningsPage = 1;
  bool earningsLoading = false;
  String? earningsError;

  // â”€â”€â”€ Withdrawals â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<ClientWithdrawal> withdrawals = [];
  int withdrawalsTotal = 0;
  int withdrawalsPage = 1;
  bool withdrawalsLoading = false;
  String? withdrawalsError;

  // â”€â”€â”€ Referrals â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<ClientReferral> referrals = [];
  bool referralsLoading = false;
  String? referralsError;

  // â”€â”€â”€ Notifications â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<ClientNotification> notifications = [];
  bool notificationsLoading = false;
  String? notificationsError;

  // ─── Revenue Analytics ──────────────────────────────────────────

  RevenueAnalytics? revenueAnalytics;
  bool revenueAnalyticsLoading = false;
  String? revenueAnalyticsError;

  // Pre-sorted lists for performance optimization
  List<PerWebsiteRevenue> _sortedByWebsite = [];
  List<PerUaRevenue> _sortedByUserAgent = [];
  List<PerGeoRevenue> _sortedByGeo = [];
  GeoStats? _cachedGeoStats;

  List<PerWebsiteRevenue> get sortedByWebsite => _sortedByWebsite;
  List<PerUaRevenue> get sortedByUserAgent => _sortedByUserAgent;
  List<PerGeoRevenue> get sortedByGeo => _sortedByGeo;
  GeoStats? get cachedGeoStats => _cachedGeoStats;

  // ─── GEO Analytics ─────────────────────────────────────────────

  GeoStats? geoAnalytics;
  bool geoAnalyticsLoading = false;
  String? geoAnalyticsError;

  // ─── Checkin ─────────────────────────────────────────────────────
  bool checkinLoading = false;
  String? checkinError;
  int? checkinRetryAfterSec;

  Timer? _refreshTimer;
  int _refreshErrorBackoffCount = 0;
  int _agentHealthFailureCount = 0;

  // â”€â”€â”€ Auth â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> authenticate(String walletAddress, {String? walletAddressEth}) async {
    if (_authLoading) return;
    _authLoading = true;
    _authError = null;

    // 🏛️ Notify SessionProvider that auth is starting.
    ServiceLocator.get<SessionProvider>().onAuthStart();

    final storedInvite = await ServiceLocator.get<ClientAuthService>().loadReferralCode();
    final inviteCaptured =
        await ServiceLocator.get<ClientAuthService>().isDeviceInviteCaptured();
    SecureLog.d('ClientPanel: authenticate called, authLoading=$_authLoading needsInviteCode=$_needsInviteCode');
    // DON'T set _needsInviteCode = false here — doing so destroys the
    // _InviteCodeGate widget while _submit() is still awaiting us,
    // causing !mounted on return and swallowing error messages.
    notifyListeners();

    try {
      final result = await ServiceLocator.get<ClientAuthService>().ensureAuthenticated(
        walletAddress,
        walletAddressEth: walletAddressEth,
      );
      _authenticated = result.ok;
      if (!result.ok) {
        _authError = result.errorKey ?? 'panel.auth_failed';
        if (_authError == 'panel.no_invite_code') {
          final hasCode = storedInvite != null && storedInvite.isNotEmpty;
          _needsInviteCode = !inviteCaptured && !hasCode;
        } else if (_authError == 'panel.invite_invalid') {
          // کد دعوت قبلی منقضی یا یک‌بار مصرف بوده — پاکش کن و
          // دوباره از کاربر بخواه کد جدید وارد کند
          await ServiceLocator.get<ClientAuthService>().clearReferralCode();
          _needsInviteCode = true;
        }
      }
    } catch (e) {
      _authError = _mapUnexpectedAuthError(e);
      _authenticated = false;
    } finally {
      _authLoading = false;
      notifyListeners();
    }

    if (_authenticated) {
      // 🏛️ Session heartbeat is active.
      ServiceLocator.get<SessionManager>().startHeartbeat();
      await _tryClaimLocalDeviceAgent();
      await _loadAll();
      _startAutoRefresh();
    } else {
      // 🏛️ Notify SessionProvider that auth failed.
      ServiceLocator.get<SessionProvider>().onAuthFailed();
    }
  }

  String _mapUnexpectedAuthError(Object e) {
    if (e is DioException) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError ||
          (e.response == null && e.type != DioExceptionType.cancel)) {
        return 'panel.network_error';
      }
    }
    return e.toString();
  }

  /// Returns `false` if the pasted text did not contain a usable code (nothing saved).
  Future<bool> submitInviteCode(
    String code,
    String walletAddress, {
    String? walletAddressEth,
  }) async {
    final saved = await ServiceLocator.get<ClientAuthService>().saveReferralCode(code);
    if (!saved) {
      _authError = 'panel.invite_parse_empty';
      _needsInviteCode = true;
      notifyListeners();
      return false;
    }
    SecureLog.d('ClientPanel: submitInviteCode starts, saved=$saved, calling authenticate');
    await authenticate(walletAddress, walletAddressEth: walletAddressEth);
    return _authenticated;
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    var backoff = const Duration(seconds: 60);
    _refreshTimer = Timer.periodic(backoff, (_) async {
      // [CRASH-FIX] Entire Timer callback wrapped in try-catch.
      // Unhandled exceptions in Timer.periodic escape the error zone and crash the isolate.
      try {
        if (!_authenticated) return;

        // Exponential backoff on repeated errors — resets on success
        if (_connectionStatus == PanelConnectionStatus.disconnected) {
          _refreshErrorBackoffCount++;
          final factor = (_refreshErrorBackoffCount).clamp(1, 5);
          backoff = Duration(seconds: 60 * factor);
        } else {
          _refreshErrorBackoffCount = 0;
          backoff = const Duration(seconds: 60);
        }

        await loadDashboard();
        await loadNotifications();
        await refreshLocalMinerStatus();
        // Refresh revenue and geo analytics on every cycle for up-to-date data
        await loadRevenueAnalytics();
        await loadGeoAnalytics();

        // Agent health check with auto-restart
        await _performAgentHealthCheck();
      } catch (e) {
        SecureLog.w('Auto-refresh cycle failed', error: e);
      }
    });
  }

  /// Periodic agent health check: if the TSP Agent is not running, try to restart it.
  /// Tracks consecutive failures to prevent infinite restart loops.
  Future<void> _performAgentHealthCheck() async {
    try {
      final running = await TspAgentChannel.isRuntimeRunning();
      if (!running) {
        _agentHealthFailureCount++;
        SecureLog.w(
          'Agent health check: NOT running '
          '(failure #$_agentHealthFailureCount)',
        );
        if (_agentHealthFailureCount <= 3) {
          // Try to restart the agent
          SecureLog.d('Agent health check: attempting restart');
          await bootstrapTspAgent();
        } else {
          SecureLog.w(
            'Agent health check: too many consecutive failures ($_agentHealthFailureCount) — '
            'will re-check on next cycle.',
          );
        }
      } else {
        // Reset failure counter on success
        if (_agentHealthFailureCount > 0) {
          SecureLog.d('Agent health check: running again (recovered after $_agentHealthFailureCount failures)');
          _agentHealthFailureCount = 0;
        }
      }
    } catch (e) {
      SecureLog.w('Agent health check failed', error: e);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    ServiceLocator.get<SessionManager>().stopHeartbeat();
    super.dispose();
  }

  // â”€â”€â”€ Load all â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _loadAll() async {
    await Future.wait([
      refreshLocalMinerStatus(),
      loadDashboard(),
      loadAgents(),
      loadEarnings(),
      loadWithdrawals(),
      loadReferrals(),
      loadNotifications(),
      loadRevenueAnalytics(),
      loadGeoAnalytics(),
    ]);
  }

  Future<void> refreshLocalMinerStatus() async {
    try {
      final enabled = await isTspAgentEnabled();
      if (enabled) {
        // Ensure agent runtime is (re)started even if app cold-start timing missed it.
        await bootstrapTspAgent();
      }
      var running = await TspAgentChannel.isRuntimeRunning();
      if (!running && enabled) {
        final dir = await getApplicationSupportDirectory();
        final cfg = '${dir.path}/agent.yml';
        final startCode = await TspAgentChannel.start(configPath: cfg);
        localMinerLastStartCode = startCode;
        if (startCode == 0 || startCode == -2) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
          running = await TspAgentChannel.isRuntimeRunning();
          if (!running) {
            await Future<void>.delayed(const Duration(milliseconds: 1200));
            running = await TspAgentChannel.isRuntimeRunning();
          }
          if (!running && startCode == -2) {
            running = true;
          }
        }
      }
      localMinerRunning = running;
      // If agent is running and localAgentId is set but not yet visible in
      // the backend agent list, retry the claim (enrollment may have just completed).
      if (running && localAgentId != null && showsExtraLocalMiner) {
        await _tryClaimLocalDeviceAgent();
      }
    } catch (e) {
      SecureLog.w('ClientPanel: refreshLocalMinerStatus failed', error: e);
      localMinerRunning = false;
    } finally {
      localMinerChecked = true;
      notifyListeners();
    }
  }

  /// Retry claim with exponential backoff (30s â†’ 60s â†’ 120s â†’ 300s).
  /// Uses [ClaimCoordinator] for intelligent retry + 401 detection + user notification.
  /// Agent enrollment may not have completed when auth finishes, so we retry.
  Future<void> _tryClaimLocalDeviceAgent() async {
    final svc = ServiceLocator.get<ClientPanelService>();
    final token = svc.bearerToken;
    if (token == null || token.isEmpty) return;
    final agentId = await ensureStableAgentIdForPanel();
    if (agentId.trim().isEmpty) return;
    localAgentId = agentId.trim().toLowerCase();

    final ok = await ServiceLocator.get<ClaimCoordinator>().claimWithRetry(
      agentId: agentId,
      clientApiBase: svc.clientBaseUrl,
      bearerToken: token,
    );
    if (!ok) {
      SecureLog.w('ClaimAgent: coordinator returned false');
    }
  }

  Future<void> refresh() => _loadAll();

  // â”€â”€â”€ Dashboard â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> loadDashboard() async {
    dashboardLoading = true;
    dashboardError = null;
    notifyListeners();
    try {
      _connectionStatus = PanelConnectionStatus.reconnecting;
      dashboard = await ServiceLocator.get<ClientPanelService>().getDashboard();
      _connectionStatus = PanelConnectionStatus.connected;
      await _cacheDashboard(dashboard!);
    } catch (e) {
      dashboardError = _formatError(e);
      _connectionStatus = PanelConnectionStatus.disconnected;
      dashboard ??= await _loadCachedDashboard();
    } finally {
      dashboardLoading = false;
      notifyListeners();
    }
  }

  Future<void> doCheckin() async {
    checkinLoading = true;
    checkinError = null;
    checkinRetryAfterSec = null;
    notifyListeners();
    try {
      await ServiceLocator.get<ClientPanelService>().postPeriodicCheckin();
      await loadDashboard();
    } catch (e) {
      final retryAfter = _extractRetryAfter(e);
      if (retryAfter != null) {
        checkinRetryAfterSec = retryAfter;
      } else {
        checkinError = _formatError(e);
      }
    } finally {
      checkinLoading = false;
      notifyListeners();
    }
  }

  // â”€â”€â”€ Agents â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> loadAgents() async {
    agentsLoading = true;
    agentsError = null;
    notifyListeners();
    try {
      agents = await ServiceLocator.get<ClientPanelService>().getMyAgents();
    } catch (e) {
      agentsError = _formatError(e);
    } finally {
      agentsLoading = false;
      notifyListeners();
    }
  }

  // â”€â”€â”€ Earnings â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> loadEarnings({bool reset = false}) async {
    if (reset) {
      earningsPage = 1;
      earnings = [];
    }
    earningsLoading = true;
    earningsError = null;
    notifyListeners();
    try {
      final result = await ServiceLocator.get<ClientPanelService>()
          .getEarnings(page: earningsPage);
      earnings = reset ? result.items : [...earnings, ...result.items];
      earningsTotal = result.total;
    } catch (e) {
      earningsError = _formatError(e);
    } finally {
      earningsLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreEarnings() async {
    if (earningsLoading) return;
    if (earnings.length >= earningsTotal) return;
    earningsPage++;
    await loadEarnings();
  }

  // â”€â”€â”€ Withdrawals â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> loadWithdrawals({bool reset = false}) async {
    if (reset) {
      withdrawalsPage = 1;
      withdrawals = [];
    }
    withdrawalsLoading = true;
    withdrawalsError = null;
    notifyListeners();
    try {
      final result = await ServiceLocator.get<ClientPanelService>()
          .getWithdrawals(page: withdrawalsPage);
      withdrawals = reset ? result.items : [...withdrawals, ...result.items];
      withdrawalsTotal = result.total;
    } catch (e) {
      withdrawalsError = _formatError(e);
    } finally {
      withdrawalsLoading = false;
      notifyListeners();
    }
  }

  Future<bool> requestWithdrawal({
    required double amountBtc,
    required String sourceType,
  }) async {
    withdrawalsLoading = true;
    withdrawalsError = null;
    notifyListeners();
    try {
      final wd = await ServiceLocator.get<ClientPanelService>().requestWithdrawal(
        amountBtc: amountBtc,
        sourceType: sourceType,
      );
      withdrawals = [wd, ...withdrawals];
      withdrawalsTotal++;
      await loadDashboard();
      return true;
    } catch (e) {
      withdrawalsError = _formatError(e);
      return false;
    } finally {
      withdrawalsLoading = false;
      notifyListeners();
    }
  }

  // â”€â”€â”€ Referrals â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> loadReferrals() async {
    referralsLoading = true;
    referralsError = null;
    notifyListeners();
    try {
      referrals = await ServiceLocator.get<ClientPanelService>().getReferrals();
    } catch (e) {
      referralsError = _formatError(e);
    } finally {
      referralsLoading = false;
      notifyListeners();
    }
  }

  // â”€â”€â”€ Notifications â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> loadNotifications() async {
    notificationsLoading = true;
    notificationsError = null;
    notifyListeners();
    try {
      notifications = await ServiceLocator.get<ClientPanelService>().getNotifications();
      await PanelAlertLocalNotifier.processNewUnread(
        notifications,
        panelIdentity: boundPanelAddress,
      );
    } catch (e) {
      notificationsError = _formatError(e);
    } finally {
      notificationsLoading = false;
      notifyListeners();
    }
  }

  Future<void> markAllRead() async {
    try {
      await ServiceLocator.get<ClientPanelService>().markNotificationsRead();
      notifications = notifications.map((n) {
        return ClientNotification(
          id: n.id,
          type: n.type,
          title: n.title,
          body: n.body,
          isRead: true,
          createdAt: n.createdAt,
        );
      }).toList();
      if (dashboard != null) {
        dashboard = ClientDashboard(
          balance: dashboard!.balance,
          myAgentCount: dashboard!.myAgentCount,
          myActiveAgents: dashboard!.myActiveAgents,
          referralCount: dashboard!.referralCount,
          downlineAgentCount: dashboard!.downlineAgentCount,
          downlineActiveAgents: dashboard!.downlineActiveAgents,
          btcPriceUsd: dashboard!.btcPriceUsd,
          earningTodayBtc: dashboard!.earningTodayBtc,
          earningThisMonthBtc: dashboard!.earningThisMonthBtc,
          unreadNotifications: 0,
          lastPeriodicCheckinAt: dashboard!.lastPeriodicCheckinAt,
        );
      }
      notifyListeners();
    } catch (e) {
      SecureLog.w('Error refreshing client panel dashboard', error: e);
    }
  }

  // ─── Revenue Analytics ──────────────────────────────────────────

  Future<void> loadRevenueAnalytics() async {
    revenueAnalyticsLoading = true;
    revenueAnalyticsError = null;
    notifyListeners();
    try {
      final fetched = await _fetchWithRetry();
      revenueAnalytics = fetched;
      if (fetched != null) {
        await _cacheRevenueAnalytics(fetched);
        // Pre-sort lists for UI performance
        _sortedByWebsite = List<PerWebsiteRevenue>.from(fetched.byWebsite)
          ..sort((a, b) => b.totalRevenueUsd.compareTo(a.totalRevenueUsd));
        _sortedByUserAgent = List<PerUaRevenue>.from(fetched.byUserAgent)
          ..sort((a, b) => b.successRate.compareTo(a.successRate));
        _sortedByGeo = List<PerGeoRevenue>.from(fetched.byGeo)
          ..sort((a, b) => b.totalRevenueUsd.compareTo(a.totalRevenueUsd));
        // Compute and cache GeoStats
        if (fetched.byGeo.isNotEmpty) {
          _cachedGeoStats = ServiceLocator.get<GeoProxyService>().computeGeoStats(fetched.byGeo);
        } else {
          _cachedGeoStats = null;
        }
      }
    } catch (e) {
      revenueAnalyticsError = _formatError(e);
      // Fallback to cached data on error
      if (revenueAnalytics == null) {
        revenueAnalytics = await _loadCachedRevenueAnalytics();
      }
    } finally {
      revenueAnalyticsLoading = false;
      notifyListeners();
    }
  }

  /// Fetch with exponential backoff retry (1 retry after 5s, 2nd after 15s)
  Future<RevenueAnalytics> _fetchWithRetry({int attempt = 0}) async {
    const maxAttempts = 3;
    try {
      return await ServiceLocator.get<ClientPanelService>().getRevenueAnalytics();
    } catch (e) {
      if (attempt < maxAttempts - 1) {
        final delay = attempt == 0 ? const Duration(seconds: 5) : const Duration(seconds: 15);
        SecureLog.w('RevenueAnalytics fetch failed, retrying in ${delay.inSeconds}s (attempt ${attempt + 1}/$maxAttempts)');
        await Future<void>.delayed(delay);
        return _fetchWithRetry(attempt: attempt + 1);
      }
      rethrow;
    }
  }

  // ─── GEO Analytics ──────────────────────────────────────────────

  Future<void> loadGeoAnalytics() async {
    geoAnalyticsLoading = true;
    geoAnalyticsError = null;
    notifyListeners();
    try {
      geoAnalytics = await ServiceLocator.get<ClientPanelService>().getGeoAnalytics();
    } catch (e) {
      geoAnalyticsError = _formatError(e);
    } finally {
      geoAnalyticsLoading = false;
      notifyListeners();
    }
  }

  /// دریافت GeoStats محاسبه شده از RevenueAnalytics جاری (در صورت عدم دسترسی به API)
  GeoStats computeGeoStatsFromLocal() {
    if (revenueAnalytics == null || revenueAnalytics!.byGeo.isEmpty) {
      return GeoStats(
        byGeo: [],
        totalRevenueUsd: 0,
        avgCpmOverall: 0,
        potentialRevenueAtTier1Cpm: 0,
        revenueGap: 0,
        topGeoCode: '',
        geoDiversityScore: 0,
        activeProxyCount: 0,
        proxyDistribution: {},
      );
    }
    return ServiceLocator.get<GeoProxyService>().computeGeoStats(revenueAnalytics!.byGeo);
  }

  // â”€â”€â”€ Cache helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _cacheDashboard(ClientDashboard d) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        'balance': {
          'own_btc': d.balance.ownBtc,
          'referral_btc': d.balance.referralBtc,
          'total_earned': d.balance.totalEarned,
          'total_withdrawn': d.balance.totalWithdrawn,
        },
        'my_agent_count': d.myAgentCount,
        'my_active_agents': d.myActiveAgents,
        'referral_count': d.referralCount,
        'downline_agent_count': d.downlineAgentCount,
        'downline_active_agents': d.downlineActiveAgents,
        'btc_price_usd': d.btcPriceUsd,
        'earning_today_btc': d.earningTodayBtc,
        'earning_this_month_btc': d.earningThisMonthBtc,
        'unread_notifications': d.unreadNotifications,
        'last_periodic_checkin_at': d.lastPeriodicCheckinAt,
        '_cached_at': DateTime.now().toIso8601String(),
      });
      await prefs.setString(
          'client_panel_dashboard_cache_${_cacheKeySuffix()}', encoded);
    } catch (e) {
      SecureLog.d('Error caching client panel dashboard', error: e);
    }
  }

  Future<ClientDashboard?> _loadCachedDashboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          prefs.getString('client_panel_dashboard_cache_${_cacheKeySuffix()}');
      if (raw == null) return null;
      return ClientDashboard.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      SecureLog.w('ClientPanel: failed to decode cached dashboard, returning null', error: e);
      return null;
    }
  }

  // ─── Revenue Analytics Cache ────────────────────────────────────

  Future<void> _cacheRevenueAnalytics(RevenueAnalytics d) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        'total_revenue_usd': d.totalRevenueUsd,
        'total_revenue_btc': d.totalRevenueBtc,
        'total_clicks': d.totalClicks,
        'total_success_clicks': d.totalSuccessClicks,
        'success_rate_pct': d.successRatePct,
        'avg_cpm': d.avgCpm,
        'avg_cpc': d.avgCpc,
        'peak_hour': d.peakHour,
        'top_website': d.topWebsite,
        'top_ad_network': d.topAdNetwork,
        'best_user_agent': d.bestUserAgent,
        'by_website': d.byWebsite.map((w) => w.toJson()).toList(),
        'by_ad_network': d.byAdNetwork.map((n) => n.toJson()).toList(),
        'by_hour': d.byHour.map((h) => h.toJson()).toList(),
        'by_user_agent': d.byUserAgent.map((ua) => ua.toJson()).toList(),
        'by_geo': d.byGeo.map((g) => g.toJson()).toList(),
        '_cached_at': DateTime.now().toIso8601String(),
      });
      await prefs.setString(
          'client_panel_revenue_cache_${_cacheKeySuffix()}', encoded);
    } catch (e) {
      SecureLog.d('Error caching revenue analytics', error: e);
    }
  }

  Future<RevenueAnalytics?> _loadCachedRevenueAnalytics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          prefs.getString('client_panel_revenue_cache_${_cacheKeySuffix()}');
      if (raw == null) return null;
      return RevenueAnalytics.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      SecureLog.w('ClientPanel: failed to decode cached revenue analytics, returning null', error: e);
      return null;
    }
  }

  // â”€â”€â”€ Error formatting â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String _formatError(Object e) {
    if (e is Exception) return e.toString().replaceFirst('Exception: ', '');
    return e.toString();
  }

  int? _extractRetryAfter(Object e) {
    final str = e.toString();
    final match = RegExp(r'retry_after_sec.*?(\d+)').firstMatch(str);
    if (match != null) return int.tryParse(match.group(1) ?? '');
    return null;
  }

  /// @deprecated Preserved for old panel screen compatibility
  bool get needsWebPin => false;

  /// @deprecated Preserved for old panel screen compatibility
  Future<bool> submitWebPin(String pin, VoidCallback? onSuccess) async {
    SecureLog.w('submitWebPin called but is a no-op');
    return false;
  }
}
