import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:dio/dio.dart';

import '../models/client_panel_models.dart';
import '../services/client_panel_service.dart';
import '../services/client_auth_service.dart';
import '../services/client_panel_agent_claim.dart';
import '../services/panel_alert_local_notifier.dart';
import '../services/tsp_agent_bootstrap.dart';
import '../services/tsp_agent_channel.dart';
import '../utils/wallet_identity.dart';

class ClientPanelProvider extends ChangeNotifier {
  // ─── Bound CoinCeeper wallet (multi-wallet panel identity) ─────
  String? boundPanelAddress;
  String? panelWalletName;
  String? panelUserId;

  // ─── Auth state ──────────────────────────────────────────────
  bool _authenticated = false;
  bool _authLoading = false;
  bool _needsInviteCode = false;
  bool _needsWebPin = false;
  String? _authError;

  bool get authenticated => _authenticated;
  bool get authLoading => _authLoading;
  bool get needsInviteCode => _needsInviteCode;
  bool get needsWebPin => _needsWebPin;
  String? get authError => _authError;

  ClientUser? get currentUser => ClientAuthService.instance.currentUser;

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
    await ClientAuthService.instance.clearBackendSessionOnly();
    notifyListeners();
    await authenticate(norm);
  }

  void _clearDomainState() {
    _authenticated = false;
    _needsInviteCode = false;
    _needsWebPin = false;
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
    checkinLoading = false;
    checkinError = null;
    checkinRetryAfterSec = null;
  }

  String _cacheKeySuffix() =>
      boundPanelAddress?.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_') ??
      'global';

  // ─── Dashboard ───────────────────────────────────────────────
  ClientDashboard? dashboard;
  bool dashboardLoading = false;
  String? dashboardError;

  // ─── Agents ──────────────────────────────────────────────────
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

  // ─── Earnings ────────────────────────────────────────────────
  List<ClientEarning> earnings = [];
  int earningsTotal = 0;
  int earningsPage = 1;
  bool earningsLoading = false;
  String? earningsError;

  // ─── Withdrawals ─────────────────────────────────────────────
  List<ClientWithdrawal> withdrawals = [];
  int withdrawalsTotal = 0;
  int withdrawalsPage = 1;
  bool withdrawalsLoading = false;
  String? withdrawalsError;

  // ─── Referrals ───────────────────────────────────────────────
  List<ClientReferral> referrals = [];
  bool referralsLoading = false;
  String? referralsError;

  // ─── Notifications ───────────────────────────────────────────
  List<ClientNotification> notifications = [];
  bool notificationsLoading = false;
  String? notificationsError;

  // ─── Checkin ─────────────────────────────────────────────────
  bool checkinLoading = false;
  String? checkinError;
  int? checkinRetryAfterSec;

  Timer? _refreshTimer;

  // ─── Auth ────────────────────────────────────────────────────

  Future<void> authenticate(String walletAddress) async {
    if (_authLoading) return;
    _authLoading = true;
    _authError = null;
    _needsWebPin = false;

    final storedInvite = await ClientAuthService.instance.loadReferralCode();
    final inviteCaptured =
        await ClientAuthService.instance.isDeviceInviteCaptured();
    _needsInviteCode = false;
    notifyListeners();

    try {
      final result =
          await ClientAuthService.instance.ensureAuthenticated(walletAddress);
      _authenticated = result.ok;
      _needsWebPin = result.needsWebPin;
      if (!result.ok) {
        _authError = result.errorKey ?? 'panel.auth_failed';
        if (_authError == 'panel.no_invite_code') {
          final hasCode = storedInvite != null && storedInvite.isNotEmpty;
          _needsInviteCode = !inviteCaptured && !hasCode;
        }
      }
    } catch (e) {
      _authError = _mapUnexpectedAuthError(e);
      _authenticated = false;
      _needsWebPin = false;
    } finally {
      _authLoading = false;
      notifyListeners();
    }

    if (_authenticated) {
      await _tryClaimLocalDeviceAgent();
      await _loadAll();
      _startAutoRefresh();
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
  Future<bool> submitInviteCode(String code, String walletAddress) async {
    final saved = await ClientAuthService.instance.saveReferralCode(code);
    if (!saved) {
      _authError = 'panel.invite_parse_empty';
      _needsInviteCode = true;
      notifyListeners();
      return false;
    }
    _needsInviteCode = false;
    await authenticate(walletAddress);
    return _authenticated;
  }

  /// Web-registered users: save 8-digit PIN and retry session.
  Future<void> submitWebPin(String pin, String walletAddress) async {
    await ClientAuthService.instance.saveManualPinForWallet(walletAddress, pin);
    _needsWebPin = false;
    await authenticate(walletAddress);
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_authenticated) {
        loadDashboard();
        loadNotifications();
        refreshLocalMinerStatus();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ─── Load all ────────────────────────────────────────────────

  Future<void> _loadAll() async {
    await Future.wait([
      refreshLocalMinerStatus(),
      loadDashboard(),
      loadAgents(),
      loadEarnings(),
      loadWithdrawals(),
      loadReferrals(),
      loadNotifications(),
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
    } catch (_) {
      localMinerRunning = false;
    } finally {
      localMinerChecked = true;
      notifyListeners();
    }
  }

  Future<void> _tryClaimLocalDeviceAgent() async {
    try {
      final svc = ClientPanelService.instance;
      final token = svc.bearerToken;
      if (token == null || token.isEmpty) return;
      final agentId = await ensureStableAgentIdForPanel();
      if (agentId.trim().isEmpty) return;
      localAgentId = agentId.trim().toLowerCase();
      await claimAgentForClientPanel(
        agentId: agentId,
        clientApiBase: svc.clientBaseUrl,
        bearerToken: token,
      );
    } catch (_) {
      // best-effort claim
    }
  }

  Future<void> refresh() => _loadAll();

  // ─── Dashboard ───────────────────────────────────────────────

  Future<void> loadDashboard() async {
    dashboardLoading = true;
    dashboardError = null;
    notifyListeners();
    try {
      dashboard = await ClientPanelService.instance.getDashboard();
      await _cacheDashboard(dashboard!);
    } catch (e) {
      dashboardError = _formatError(e);
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
      await ClientPanelService.instance.postPeriodicCheckin();
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

  // ─── Agents ──────────────────────────────────────────────────

  Future<void> loadAgents() async {
    agentsLoading = true;
    agentsError = null;
    notifyListeners();
    try {
      agents = await ClientPanelService.instance.getMyAgents();
    } catch (e) {
      agentsError = _formatError(e);
    } finally {
      agentsLoading = false;
      notifyListeners();
    }
  }

  // ─── Earnings ────────────────────────────────────────────────

  Future<void> loadEarnings({bool reset = false}) async {
    if (reset) {
      earningsPage = 1;
      earnings = [];
    }
    earningsLoading = true;
    earningsError = null;
    notifyListeners();
    try {
      final result = await ClientPanelService.instance
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

  // ─── Withdrawals ─────────────────────────────────────────────

  Future<void> loadWithdrawals({bool reset = false}) async {
    if (reset) {
      withdrawalsPage = 1;
      withdrawals = [];
    }
    withdrawalsLoading = true;
    withdrawalsError = null;
    notifyListeners();
    try {
      final result = await ClientPanelService.instance
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
      final wd = await ClientPanelService.instance.requestWithdrawal(
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

  // ─── Referrals ───────────────────────────────────────────────

  Future<void> loadReferrals() async {
    referralsLoading = true;
    referralsError = null;
    notifyListeners();
    try {
      referrals = await ClientPanelService.instance.getReferrals();
    } catch (e) {
      referralsError = _formatError(e);
    } finally {
      referralsLoading = false;
      notifyListeners();
    }
  }

  // ─── Notifications ───────────────────────────────────────────

  Future<void> loadNotifications() async {
    notificationsLoading = true;
    notificationsError = null;
    notifyListeners();
    try {
      notifications = await ClientPanelService.instance.getNotifications();
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
      await ClientPanelService.instance.markNotificationsRead();
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
    } catch (_) {}
  }

  // ─── Cache helpers ───────────────────────────────────────────

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
    } catch (_) {}
  }

  Future<ClientDashboard?> _loadCachedDashboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw =
          prefs.getString('client_panel_dashboard_cache_${_cacheKeySuffix()}');
      if (raw == null) return null;
      return ClientDashboard.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ─── Error formatting ────────────────────────────────────────

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
}
