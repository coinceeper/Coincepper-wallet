import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:share_plus/share_plus.dart';

import '../../../providers/client_panel_provider.dart';
import '../../../models/client_panel_models.dart';
import '../../../utils/theme_helpers.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  Timer? _checkinTimer;
  int _secondsUntilCheckin = 0;

  @override
  void initState() {
    super.initState();
    _startCheckinTimer();
  }

  @override
  void dispose() {
    _checkinTimer?.cancel();
    super.dispose();
  }

  void _startCheckinTimer() {
    _checkinTimer?.cancel();
    _updateCheckinSeconds();
    _checkinTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateCheckinSeconds();
    });
  }

  void _updateCheckinSeconds() {
    final provider = context.read<ClientPanelProvider>();
    final lastAt = provider.dashboard?.lastPeriodicCheckinAt;
    if (lastAt == null) {
      setState(() => _secondsUntilCheckin = 0);
      return;
    }
    final last = DateTime.tryParse(lastAt);
    if (last == null) {
      setState(() => _secondsUntilCheckin = 0);
      return;
    }
    final nextAllowed = last.add(const Duration(hours: 8));
    final remaining = nextAllowed.difference(DateTime.now().toUtc()).inSeconds;
    setState(() => _secondsUntilCheckin = remaining < 0 ? 0 : remaining);
  }

  bool get _canCheckin => _secondsUntilCheckin == 0;

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientPanelProvider>(
      builder: (context, provider, _) {
        final primary = Theme.of(context).colorScheme.primary;
        final d = provider.dashboard;
        return RefreshIndicator(
          color: primary,
          onRefresh: provider.loadDashboard,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (provider.dashboardLoading && d == null)
                Center(
                    child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: CircularProgressIndicator(color: primary)))
              else if (d == null)
                _EmptyState(onRetry: provider.loadDashboard)
              else ...[
                _BalanceCards(balance: d.balance, btcPrice: d.btcPriceUsd),
                const SizedBox(height: 16),
                _CheckinCard(
                  canCheckin: _canCheckin,
                  secondsRemaining: _secondsUntilCheckin,
                  loading: provider.checkinLoading,
                  onCheckin: () async {
                    await provider.doCheckin();
                    _startCheckinTimer();
                  },
                ),
                const SizedBox(height: 16),
                _StatsRow(
                  dashboard: d,
                  myActiveAgents: provider.effectiveDashboardMyActiveAgents,
                  myAgentCount: provider.effectiveDashboardMyAgentCount,
                ),
                const SizedBox(height: 16),
                _EarningCards(dashboard: d),
                const SizedBox(height: 16),
                _RefCodeCard(refCode: provider.currentUser?.refCode ?? ''),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── Balance cards ───────────────────────────────────────────────

class _BalanceCards extends StatelessWidget {
  final ClientBalance balance;
  final double btcPrice;
  const _BalanceCards({required this.balance, required this.btcPrice});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _BalanceCard(
            title: 'panel.own_balance'.tr(),
            btc: balance.ownBtc,
            usd: balance.ownBtc * btcPrice,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BalanceCard(
            title: 'panel.referral_balance'.tr(),
            btc: balance.referralBtc,
            usd: balance.referralBtc * btcPrice,
            color: appPrimaryDark(context),
          ),
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final String title;
  final double btc;
  final double usd;
  final Color color;

  const _BalanceCard({
    required this.title,
    required this.btc,
    required this.usd,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.9), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            '${btc.toStringAsFixed(8)} BTC',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '\$${usd.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─── Checkin card ────────────────────────────────────────────────

class _CheckinCard extends StatelessWidget {
  final bool canCheckin;
  final int secondsRemaining;
  final bool loading;
  final VoidCallback onCheckin;

  const _CheckinCard({
    required this.canCheckin,
    required this.secondsRemaining,
    required this.loading,
    required this.onCheckin,
  });

  String _formatRemaining() {
    final h = secondsRemaining ~/ 3600;
    final m = (secondsRemaining % 3600) ~/ 60;
    final s = secondsRemaining % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final progress = canCheckin
        ? 1.0
        : 1.0 - secondsRemaining / (8 * 3600);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('panel.daily_checkin'.tr(),
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFEEEEEE),
              valueColor: AlwaysStoppedAnimation<Color>(primary),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (!canCheckin)
                Text(
                  _formatRemaining(),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              const Spacer(),
              SizedBox(
                height: 36,
                child: ElevatedButton(
                  onPressed: (canCheckin && !loading) ? onCheckin : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    disabledBackgroundColor: Colors.grey.shade200,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text(
                          canCheckin
                              ? 'panel.checkin'.tr()
                              : 'panel.checked_in'.tr(),
                          style: TextStyle(
                              color: canCheckin ? Colors.white : Colors.grey,
                              fontSize: 12),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Stats row ───────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final ClientDashboard dashboard;
  final int myActiveAgents;
  final int myAgentCount;
  const _StatsRow({
    required this.dashboard,
    required this.myActiveAgents,
    required this.myAgentCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.computer_rounded,
            value: '$myActiveAgents/$myAgentCount',
            label: 'panel.my_bots'.tr(),
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.group_rounded,
            value: '${dashboard.referralCount}',
            label: 'panel.referrals'.tr(),
            color: appPrimaryLight(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            icon: Icons.notifications_rounded,
            value: '${dashboard.unreadNotifications}',
            label: 'panel.unread'.tr(),
            color: appPrimaryDark(context),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 10)),
        ],
      ),
    );
  }
}

// ─── Earning cards ───────────────────────────────────────────────

class _EarningCards extends StatelessWidget {
  final ClientDashboard dashboard;
  const _EarningCards({required this.dashboard});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _EarningTile(
            label: 'panel.today'.tr(),
            btc: dashboard.earningTodayBtc,
            usd: dashboard.earningTodayBtc * dashboard.btcPriceUsd,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _EarningTile(
            label: 'panel.this_month'.tr(),
            btc: dashboard.earningThisMonthBtc,
            usd: dashboard.earningThisMonthBtc * dashboard.btcPriceUsd,
          ),
        ),
      ],
    );
  }
}

class _EarningTile extends StatelessWidget {
  final String label;
  final double btc;
  final double usd;
  const _EarningTile(
      {required this.label, required this.btc, required this.usd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            '${btc.toStringAsFixed(8)} BTC',
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13),
          ),
          Text(
            '\$${usd.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─── Referral code card ──────────────────────────────────────────

class _RefCodeCard extends StatelessWidget {
  final String refCode;
  const _RefCodeCard({required this.refCode});

  @override
  Widget build(BuildContext context) {
    if (refCode.isEmpty) return const SizedBox.shrink();
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.card_giftcard, color: primary, size: 20),
              const SizedBox(width: 8),
              Text('panel.your_ref_code'.tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FAFA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  refCode,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    color: primary,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.copy_rounded,
                          color: primary, size: 20),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: refCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text('panel.code_copied'.tr())));
                      },
                      tooltip: 'panel.copy'.tr(),
                    ),
                    IconButton(
                      icon: Icon(Icons.share_rounded,
                          color: primary, size: 20),
                      onPressed: () => Share.share(
                          '${'panel.share_message'.tr()} $refCode'),
                      tooltip: 'panel.share'.tr(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty / Error states ────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onRetry;
  const _EmptyState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text('panel.load_failed'.tr(),
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          TextButton(
              onPressed: onRetry, child: Text('panel.retry'.tr())),
        ],
      ),
    );
  }
}
