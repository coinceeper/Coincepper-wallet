import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../utils/theme_helpers.dart';

class HowItWorksTab extends StatefulWidget {
  const HowItWorksTab({super.key});

  @override
  State<HowItWorksTab> createState() => _HowItWorksTabState();
}

class _HowItWorksTabState extends State<HowItWorksTab> {
  double _agentCount = 1;
  double _referralCount = 0;

  double get _dailyBtcEstimate {
    // 1 sat per active agent per day + referral cut
    const satoshi = 0.00000001;
    return (_agentCount * satoshi) +
        (_referralCount * _agentCount * satoshi * 0.1);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeroCard(),
        const SizedBox(height: 20),
        _StepsSection(),
        const SizedBox(height: 20),
        _Calculator(
          agentCount: _agentCount,
          referralCount: _referralCount,
          estimatedBtc: _dailyBtcEstimate,
          onAgentChanged: (v) => setState(() => _agentCount = v),
          onReferralChanged: (v) => setState(() => _referralCount = v),
        ),
        const SizedBox(height: 20),
        _FaqSection(),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [p, p.withOpacity(0.72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.lightbulb_rounded,
              color: Colors.white, size: 40),
          const SizedBox(height: 12),
          Text(
            'panel.how_title'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'panel.how_subtitle'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _StepsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final steps = [
      (
        icon: Icons.download_rounded,
        title: 'panel.step1_title'.tr(),
        desc: 'panel.step1_desc'.tr(),
        color: primary,
      ),
      (
        icon: Icons.computer_rounded,
        title: 'panel.step2_title'.tr(),
        desc: 'panel.step2_desc'.tr(),
        color: appPrimaryDark(context),
      ),
      (
        icon: Icons.trending_up_rounded,
        title: 'panel.step3_title'.tr(),
        desc: 'panel.step3_desc'.tr(),
        color: appPrimaryLight(context),
      ),
      (
        icon: Icons.group_rounded,
        title: 'panel.step4_title'.tr(),
        desc: 'panel.step4_desc'.tr(),
        color: appPrimaryDark(context),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('panel.how_it_works'.tr(),
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),
        ...steps.asMap().entries.map((e) => _StepCard(
              step: e.key + 1,
              icon: e.value.icon,
              title: e.value.title,
              desc: e.value.desc,
              color: e.value.color,
            )),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  final int step;
  final IconData icon;
  final String title;
  final String desc;
  final Color color;

  const _StepCard({
    required this.step,
    required this.icon,
    required this.title,
    required this.desc,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$step',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 16),
                    const SizedBox(width: 6),
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(desc,
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Calculator extends StatelessWidget {
  final double agentCount;
  final double referralCount;
  final double estimatedBtc;
  final ValueChanged<double> onAgentChanged;
  final ValueChanged<double> onReferralChanged;

  const _Calculator({
    required this.agentCount,
    required this.referralCount,
    required this.estimatedBtc,
    required this.onAgentChanged,
    required this.onReferralChanged,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
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
          Row(
            children: [
              Icon(Icons.calculate_rounded, color: primary, size: 20),
              const SizedBox(width: 8),
              Text('panel.calculator'.tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 16),
          Text('${'panel.active_bots'.tr()}: ${agentCount.toInt()}',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Slider(
            value: agentCount,
            min: 1,
            max: 100,
            divisions: 99,
            activeColor: primary,
            onChanged: onAgentChanged,
          ),
          const SizedBox(height: 8),
          Text('${'panel.referrals'.tr()}: ${referralCount.toInt()}',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Slider(
            value: referralCount,
            min: 0,
            max: 50,
            divisions: 50,
            activeColor: appPrimaryDark(context),
            onChanged: onReferralChanged,
          ),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('panel.est_daily'.tr(),
                  style: const TextStyle(color: Colors.grey)),
              Text(
                '${estimatedBtc.toStringAsFixed(8)} BTC',
                style: TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('panel.est_monthly'.tr(),
                  style: const TextStyle(color: Colors.grey)),
              Text(
                '${(estimatedBtc * 30).toStringAsFixed(8)} BTC',
                style: TextStyle(color: primary, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FaqSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final faqs = [
      ('panel.faq1_q'.tr(), 'panel.faq1_a'.tr()),
      ('panel.faq2_q'.tr(), 'panel.faq2_a'.tr()),
      ('panel.faq3_q'.tr(), 'panel.faq3_a'.tr()),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('panel.faq'.tr(),
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 12),
        ...faqs.map((faq) => _FaqItem(q: faq.$1, a: faq.$2)),
      ],
    );
  }
}

class _FaqItem extends StatefulWidget {
  final String q;
  final String a;
  const _FaqItem({required this.q, required this.a});

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
      child: ExpansionTile(
        title: Text(widget.q,
            style: const TextStyle(
                fontWeight: FontWeight.w500, fontSize: 13)),
        trailing: Icon(
            _expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            color: Theme.of(context).colorScheme.primary),
        onExpansionChanged: (v) => setState(() => _expanded = v),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(widget.a,
                style: const TextStyle(
                    color: Colors.grey, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
