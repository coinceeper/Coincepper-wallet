import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../providers/client_panel_provider.dart';
import '../../../models/client_panel_models.dart';
import '../../../utils/theme_helpers.dart';

class EarningsTab extends StatelessWidget {
  const EarningsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientPanelProvider>(
      builder: (context, provider, _) {
        final primary = Theme.of(context).colorScheme.primary;
        return RefreshIndicator(
          color: primary,
          onRefresh: () => provider.loadEarnings(reset: true),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _BalanceSummary(provider: provider),
              const SizedBox(height: 16),
              Text('panel.earnings_history'.tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 12),
              if (provider.earningsLoading && provider.earnings.isEmpty)
                Center(
                    child: CircularProgressIndicator(color: primary))
              else if (provider.earnings.isEmpty)
                _Empty()
              else
                ...provider.earnings
                    .map((e) => _EarningRow(earning: e))
                    ,
              if (provider.earnings.isNotEmpty &&
                  provider.earnings.length < provider.earningsTotal)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: TextButton(
                      onPressed: provider.earningsLoading
                          ? null
                          : provider.loadMoreEarnings,
                      child: provider.earningsLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: primary))
                          : Text('panel.load_more'.tr()),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BalanceSummary extends StatelessWidget {
  final ClientPanelProvider provider;
  const _BalanceSummary({required this.provider});

  @override
  Widget build(BuildContext context) {
    final d = provider.dashboard;
    if (d == null) return const SizedBox.shrink();
    final p = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [p, p.withOpacity(0.72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryItem(
              label: 'panel.total_earned'.tr(),
              value:
                  '${d.balance.totalEarned.toStringAsFixed(8)} BTC',
            ),
          ),
          Container(width: 1, height: 50, color: Colors.white24),
          Expanded(
            child: _SummaryItem(
              label: 'panel.total_withdrawn'.tr(),
              value:
                  '${d.balance.totalWithdrawn.toStringAsFixed(8)} BTC',
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 6),
          Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12)),
        ],
      ),
    );
  }
}

class _EarningRow extends StatelessWidget {
  final ClientEarning earning;
  const _EarningRow({required this.earning});

  String get _sourceLabel {
    switch (earning.sourceType) {
      case 'own_agent':
        return 'Own Miner';
      case 'referral':
        return 'Referral';
      case 'daily_satoshi':
        return 'Daily';
      case 'signup_bonus':
        return 'Signup Bonus';
      default:
        return earning.sourceType;
    }
  }

  Color _sourceColor(BuildContext context) {
    switch (earning.sourceType) {
      case 'own_agent':
        return Theme.of(context).colorScheme.primary;
      case 'referral':
        return appPrimaryDark(context);
      case 'daily_satoshi':
        return Theme.of(context).colorScheme.tertiary;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final src = _sourceColor(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: src.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_sourceLabel,
                style: TextStyle(
                    color: src,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (earning.sourceAgentName != null)
                  Text(earning.sourceAgentName!,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis),
                Text(earning.periodDate,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${earning.earnedBtc.toStringAsFixed(8)} BTC',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
              ),
              if (earning.earnedUsd != null)
                Text(
                  '\$${earning.earnedUsd!.toStringAsFixed(4)}',
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.bar_chart_rounded,
                size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text('panel.no_earnings'.tr(),
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
