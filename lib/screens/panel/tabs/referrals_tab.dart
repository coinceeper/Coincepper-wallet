import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:share_plus/share_plus.dart';

import '../../../providers/client_panel_provider.dart';
import '../../../models/client_panel_models.dart';
import '../../../utils/theme_helpers.dart';

class ReferralsTab extends StatelessWidget {
  const ReferralsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientPanelProvider>(
      builder: (context, provider, _) {
        final primary = Theme.of(context).colorScheme.primary;
        final refCode = provider.currentUser?.refCode ?? '';
        return RefreshIndicator(
          color: primary,
          onRefresh: provider.loadReferrals,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _RefCodeSection(refCode: refCode),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('panel.your_team'.tr(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(width: 8),
                  if (provider.referralCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${provider.referralCount}',
                        style: TextStyle(
                            color: primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'panel.existing_referrals_preserved'.tr(),
                style:
                    const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (provider.referralsLoading && provider.referrals.isEmpty)
                Center(child: CircularProgressIndicator(color: primary))
              else if (provider.referrals.isEmpty)
                _Empty()
              else
                ...provider.referrals
                    .map((r) => _ReferralRow(referral: r))
                    ,
            ],
          ),
        );
      },
    );
  }
}

extension on ClientPanelProvider {
  int get referralCount => dashboard?.referralCount ?? referrals.length;
}

class _RefCodeSection extends StatelessWidget {
  final String refCode;
  const _RefCodeSection({required this.refCode});

  @override
  Widget build(BuildContext context) {
    final p = appPrimary(context);
    final p2 = Color.lerp(p, Colors.white, 0.12) ?? p;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [p, p2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            'panel.invite_friends'.tr(),
            style: const TextStyle(
                color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              refCode.isEmpty ? '–' : refCode,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: 6,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ActionBtn(
                icon: Icons.copy_rounded,
                label: 'panel.copy'.tr(),
                onTap: () {
                  if (refCode.isEmpty) return;
                  Clipboard.setData(ClipboardData(text: refCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('panel.code_copied'.tr())),
                  );
                },
              ),
              const SizedBox(width: 16),
              _ActionBtn(
                icon: Icons.share_rounded,
                label: 'panel.share'.tr(),
                onTap: () {
                  if (refCode.isEmpty) return;
                  Share.share(
                      '${'panel.share_message'.tr()} $refCode');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.icon,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ReferralRow extends StatelessWidget {
  final ClientReferral referral;
  const _ReferralRow({required this.referral});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final accent = appPrimaryDark(context);
    final addr = referral.btcAddress;
    final shortAddr = addr.length > 12
        ? '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}'
        : addr;

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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_rounded,
                color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shortAddr,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _MiniStat(
                      icon: Icons.computer_rounded,
                      value: '${referral.agentCount}',
                      color: primary,
                    ),
                    const SizedBox(width: 12),
                    _MiniStat(
                      icon: Icons.circle,
                      value: '${referral.activeAgentCount}',
                      color: Colors.green,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${referral.totalEarned.toStringAsFixed(6)} BTC',
                style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
              ),
              Text(
                _formatJoined(referral.joinedAt),
                style: const TextStyle(
                    color: Colors.grey, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatJoined(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return 'today';
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  const _MiniStat(
      {required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(value,
            style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500)),
      ],
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
            const Icon(Icons.group_outlined,
                size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text('panel.no_referrals'.tr(),
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            Text('panel.share_to_invite'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
