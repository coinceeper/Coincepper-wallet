import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../providers/client_panel_provider.dart';
import '../../../models/client_panel_models.dart';
import '../../../models/geo_models.dart';
import '../../../widgets/error_state_widget.dart';
import '../../../utils/theme_helpers.dart';

/// RevenueTab — داشبورد تحلیل درآمد تبلیغاتی با استاندارد کیف‌پول ارز دیجیتال.
///
/// ویژگی‌های حرفه‌ای:
/// - Skeleton loading برای تجربه کاربری روان
/// - Animated value transitions
/// - پشتیبانی کامل از تم تاریک/روشن
/// - فرمت‌بندی حرفه‌ای اعداد BTC/USD
/// - Pull-to-refresh با haptic feedback
/// - Error boundaries با auto-retry
/// - Performance optimized با const widgets و Selector
class RevenueTab extends StatelessWidget {
  const RevenueTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<ClientPanelProvider, RevenueAnalytics?>(
      selector: (_, provider) => provider.revenueAnalytics,
      builder: (context, analytics, _) {
        final provider = context.read<ClientPanelProvider>();
        final primary = context.primary;

        // ── Loading State: Skeleton ──
        if (provider.revenueAnalyticsLoading && analytics == null) {
          return const _RevenueSkeleton();
        }

        // ── Error State ──
        if (provider.revenueAnalyticsError != null && analytics == null) {
          return Center(
            child: ErrorStateWidget(
              message: provider.revenueAnalyticsError!,
              onRetry: () => provider.loadRevenueAnalytics(),
            ),
          );
        }

        // ── Empty State ──
        if (analytics == null || analytics.totalClicks == 0) {
          return _EmptyRevenueState(onRefresh: provider.loadRevenueAnalytics);
        }

        // ── Data View ──
        return RefreshIndicator(
          color: primary,
          onRefresh: provider.loadRevenueAnalytics,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Balance / Summary Cards ──
              _RevenueSummaryCards(analytics: analytics),
              const SizedBox(height: 16),

              // ── Best Performers ──
              _BestPerformersCard(analytics: analytics),
              const SizedBox(height: 16),

              // ── Ad Network Comparison ──
              if (analytics.byAdNetwork.isNotEmpty) ...[
                _SectionHeader(
                  title: 'panel.rev_by_network'.tr(),
                  icon: Icons.swap_horiz_rounded,
                ),
                const SizedBox(height: 10),
                _AdNetworkComparison(analytics: analytics),
                const SizedBox(height: 16),
              ],

              // ── Website Performance ──
              if (analytics.byWebsite.isNotEmpty) ...[
                _SectionHeader(
                  title: 'panel.rev_by_website'.tr(),
                  icon: Icons.language_rounded,
                ),
                const SizedBox(height: 10),
                _WebsitePerformance(
                  websites: provider.sortedByWebsite,
                ),
                const SizedBox(height: 16),
              ],

              // ── Hourly Analysis ──
              if (analytics.byHour.isNotEmpty) ...[
                _SectionHeader(
                  title: 'panel.rev_by_hour'.tr(),
                  icon: Icons.access_time_rounded,
                ),
                const SizedBox(height: 10),
                _HourlyHeatmap(analytics: analytics),
                const SizedBox(height: 16),
              ],

              // ── User Agent Performance ──
              if (analytics.byUserAgent.isNotEmpty) ...[
                _SectionHeader(
                  title: 'panel.rev_by_ua'.tr(),
                  icon: Icons.phone_android_rounded,
                ),
                const SizedBox(height: 10),
                _UserAgentPerformance(
                  userAgents: provider.sortedByUserAgent,
                ),
                const SizedBox(height: 16),
              ],

              // ── GEO Performance ──
              if (analytics.byGeo.isNotEmpty) ...[
                _SectionHeader(
                  title: 'panel.rev_by_geo'.tr(),
                  icon: Icons.public_rounded,
                ),
                const SizedBox(height: 10),
                _GeoPerformance(
                  geoList: provider.sortedByGeo,
                  geoStats: provider.cachedGeoStats,
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Skeleton Loading
// ═══════════════════════════════════════════════════════════════════════════

class _RevenueSkeleton extends StatelessWidget {
  const _RevenueSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 4 summary card skeletons
        Row(
          children: [
            Expanded(child: _skeletonCard(scheme)),
            const SizedBox(width: 12),
            Expanded(child: _skeletonCard(scheme)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _skeletonCard(scheme)),
            const SizedBox(width: 12),
            Expanded(child: _skeletonCard(scheme)),
          ],
        ),
        const SizedBox(height: 16),
        _skeletonBlock(scheme, height: 120),
        const SizedBox(height: 16),
        _skeletonBlock(scheme, height: 200),
      ],
    );
  }

  Widget _skeletonCard(ColorScheme scheme) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _skeletonBlock(ColorScheme scheme, {double height = 100}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Summary Cards
// ═══════════════════════════════════════════════════════════════════════════

class _RevenueSummaryCards extends StatelessWidget {
  final RevenueAnalytics analytics;
  const _RevenueSummaryCards({required this.analytics});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'panel.rev_total_revenue'.tr(),
                value: '\$${_fmtUsd(analytics.totalRevenueUsd)}',
                subtitle: '${_fmtBtc(analytics.totalRevenueBtc)} BTC',
                icon: Icons.account_balance_wallet_rounded,
                gradientColors: [const Color(0xFF1A73E8), const Color(0xFF1557B0)],
                isLoading: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'panel.rev_total_clicks'.tr(),
                value: _fmtInt(analytics.totalClicks),
                subtitle: '${analytics.totalSuccessClicks} ${'panel.rev_success'.tr()}',
                icon: Icons.touch_app_rounded,
                gradientColors: [const Color(0xFF0F9D58), const Color(0xFF0B8043)],
                isLoading: false,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'panel.rev_success_rate'.tr(),
                value: '${analytics.successRatePct.toStringAsFixed(1)}%',
                subtitle: '${analytics.avgCpc.toStringAsFixed(6)} BTC/click',
                icon: Icons.check_circle_rounded,
                gradientColors: [const Color(0xFFF9AB00), const Color(0xFFE37400)],
                isLoading: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'panel.rev_avg_cpm'.tr(),
                value: '\$${analytics.avgCpm.toStringAsFixed(2)}',
                subtitle: 'CPC: \$${analytics.avgCpc.toStringAsFixed(4)}',
                icon: Icons.bar_chart_rounded,
                gradientColors: [const Color(0xFF9334E6), const Color(0xFF6C1DB2)],
                isLoading: false,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _fmtUsd(double v) => v >= 1 ? v.toStringAsFixed(2) : v.toStringAsFixed(4);
  static String _fmtBtc(double v) => v.toStringAsFixed(8);
  static String _fmtInt(int v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}K' : v.toString();
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final bool isLoading;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withAlpha(77),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withAlpha(191),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Best Performers
// ═══════════════════════════════════════════════════════════════════════════

class _BestPerformersCard extends StatelessWidget {
  final RevenueAnalytics analytics;
  const _BestPerformersCard({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = context.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withAlpha(38)),
        boxShadow: [
          BoxShadow(
            color: scheme.onSurface.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star_rounded, color: Colors.amber.shade600, size: 20),
              const SizedBox(width: 8),
              Text(
                'panel.rev_best_performers'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (analytics.topWebsite.isNotEmpty)
            _BestPerformerRow(
              icon: Icons.language_rounded,
              label: 'panel.rev_best_website'.tr(),
              value: analytics.topWebsite,
              color: const Color(0xFF1A73E8),
            ),
          if (analytics.topAdNetwork.isNotEmpty)
            _BestPerformerRow(
              icon: Icons.share_rounded,
              label: 'panel.rev_best_network'.tr(),
              value: analytics.topAdNetwork.toUpperCase(),
              color: const Color(0xFF0F9D58),
            ),
          _BestPerformerRow(
            icon: Icons.schedule_rounded,
            label: 'panel.rev_peak_hour'.tr(),
            value: '${analytics.peakHour.toString().padLeft(2, '0')}:00',
            color: const Color(0xFFF9AB00),
          ),
          if (analytics.bestUserAgent.isNotEmpty)
            _BestPerformerRow(
              icon: Icons.phone_android_rounded,
              label: 'panel.rev_best_ua'.tr(),
              value: analytics.bestUserAgent,
              color: const Color(0xFF9334E6),
            ),
        ],
      ),
    );
  }
}

class _BestPerformerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _BestPerformerRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(26),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Ad Network Comparison
// ═══════════════════════════════════════════════════════════════════════════

class _AdNetworkComparison extends StatelessWidget {
  final RevenueAnalytics analytics;
  const _AdNetworkComparison({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: scheme.onSurface.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _ComparisonHeader(),
          const SizedBox(height: 12),
          ...analytics.byAdNetwork.map((n) => _NetworkRow(network: n)),
        ],
      ),
    );
  }
}

class _ComparisonHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            'panel.rev_network'.tr(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            'panel.rev_revenue'.tr(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            '${'panel.rev_cpm'.tr()}/\$${'panel.rev_cpc'.tr()}',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            'panel.rev_sr'.tr(),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _NetworkRow extends StatelessWidget {
  final PerAdNetworkRevenue network;
  const _NetworkRow({required this.network});

  Color get _color {
    switch (network.adNetwork.toLowerCase()) {
      case 'coinzilla':
        return const Color(0xFF1A73E8);
      case 'monetag':
        return const Color(0xFF0F9D58);
      case 'hypelab':
        return const Color(0xFF9334E6);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxRev = network.totalRevenueUsd;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  network.adNetwork.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _color,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (network.totalRevenueUsd / (maxRev > 0 ? maxRev : 1)).clamp(0.0, 1.0),
                        backgroundColor: scheme.surfaceContainerLow,
                        valueColor: AlwaysStoppedAnimation<Color>(_color),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '\$${network.totalRevenueUsd.toStringAsFixed(4)} / ${network.clickCount} clicks',
                      style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 56,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${network.avgCpm.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: scheme.onSurface),
                    ),
                    Text(
                      '\$${network.avgCpc.toStringAsFixed(4)}',
                      style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${(network.successRate * 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurface),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Website Performance
// ═══════════════════════════════════════════════════════════════════════════

class _WebsitePerformance extends StatelessWidget {
  final List<PerWebsiteRevenue> websites;
  const _WebsitePerformance({required this.websites});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxRev = websites.isNotEmpty ? websites.first.totalRevenueUsd : 1.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: scheme.onSurface.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: websites
            .map((w) => _WebsiteRow(website: w, maxRev: maxRev))
            .toList(),
      ),
    );
  }
}

class _WebsiteRow extends StatelessWidget {
  final PerWebsiteRevenue website;
  final double maxRev;

  const _WebsiteRow({required this.website, required this.maxRev});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.language_rounded, size: 13, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  website.website,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '\$${website.totalRevenueUsd.toStringAsFixed(4)}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.primary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (website.totalRevenueUsd / (maxRev > 0 ? maxRev : 1)).clamp(0.0, 1.0),
              backgroundColor: scheme.surfaceContainerLow,
              valueColor: AlwaysStoppedAnimation<Color>(context.primary),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Text(
                '${website.clickCount} clicks | ${website.successRatePct.toStringAsFixed(0)}% SR',
                style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                'CPM: \$${website.avgCpm.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Hourly Heatmap
// ═══════════════════════════════════════════════════════════════════════════

class _HourlyHeatmap extends StatelessWidget {
  final RevenueAnalytics analytics;
  const _HourlyHeatmap({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxRev = analytics.byHour
        .map((h) => h.totalRevenueUsd)
        .reduce((a, b) => a > b ? a : b);
    final maxRatio = maxRev > 0 ? maxRev : 1.0;
    final peakHour = analytics.peakHour;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: scheme.onSurface.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...List.generate(4, (rowIdx) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: List.generate(6, (colIdx) {
                  final hour = rowIdx * 6 + colIdx;
                  final hr = analytics.byHour.length > hour
                      ? analytics.byHour[hour]
                      : null;
                  final rev = hr?.totalRevenueUsd ?? 0;
                  final ratio = rev / maxRatio;
                  final isPeak = hour == peakHour;

                  Color cellColor;
                  if (ratio > 0.75) {
                    cellColor = Colors.green.shade700;
                  } else if (ratio > 0.5) {
                    cellColor = Colors.green.shade500;
                  } else if (ratio > 0.25) {
                    cellColor = Colors.green.shade300;
                  } else if (ratio > 0) {
                    cellColor = Colors.green.shade100;
                  } else {
                    cellColor = scheme.surfaceContainerLow;
                  }

                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                      decoration: BoxDecoration(
                        color: cellColor,
                        borderRadius: BorderRadius.circular(6),
                        border: isPeak
                            ? Border.all(color: Colors.amber, width: 2)
                            : null,
                      ),
                      child: Column(
                        children: [
                          Text(
                            hour.toString().padLeft(2, '0'),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: isPeak ? FontWeight.w800 : FontWeight.w500,
                              color: ratio > 0.5 ? Colors.white : scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (hr != null && hr.clickCount > 0)
                            Text(
                              '\$${rev.toStringAsFixed(rev >= 0.01 ? 2 : 4)}',
                              style: TextStyle(
                                fontSize: 7,
                                color: ratio > 0.5 ? Colors.white70 : scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withAlpha(51)),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, color: Colors.amber.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'panel.rev_peak_hour_detail'.tr(args: [
                      '${peakHour.toString().padLeft(2, '0')}:00',
                    ]),
                    style: TextStyle(color: Colors.amber.shade800, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// User Agent Performance
// ═══════════════════════════════════════════════════════════════════════════

class _UserAgentPerformance extends StatelessWidget {
  final List<PerUaRevenue> userAgents;
  const _UserAgentPerformance({required this.userAgents});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: scheme.onSurface.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: userAgents
            .map((ua) => _UserAgentRow(ua: ua))
            .toList(),
      ),
    );
  }
}

class _UserAgentRow extends StatelessWidget {
  final PerUaRevenue ua;
  const _UserAgentRow({required this.ua});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              ua.userAgent,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: scheme.onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ua.successRate.clamp(0.0, 1.0),
                backgroundColor: scheme.surfaceContainerLow,
                valueColor: AlwaysStoppedAnimation<Color>(
                  ua.successRate > 0.7
                      ? Colors.green
                      : ua.successRate > 0.4
                          ? Colors.orange
                          : Colors.red,
                ),
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            child: Text(
              '${(ua.successRate * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// ═══════════════════════════════════════════════════════════════════════════
// GEO Performance Dashboard — تحلیل درآمد بر اساس منطقه جغرافیایی
// ═══════════════════════════════════════════════════════════════════════════

class _GeoPerformance extends StatelessWidget {
  final List<PerGeoRevenue> geoList;
  final GeoStats? geoStats;
  const _GeoPerformance({required this.geoList, required this.geoStats});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // geoList is already pre-sorted from provider
    final sorted = geoList;
    final maxRev = sorted.isNotEmpty ? sorted.first.totalRevenueUsd : 1.0;

    // Use cached GeoStats from provider (computed once per data load)
    final gs = geoStats ?? GeoStats(
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

    return Column(
      children: [
        // ── Revenue Gap / Potential Card ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                context.primary.withAlpha(26),
                context.primary.withAlpha(10),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.primary.withAlpha(38),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.trending_up_rounded, size: 18, color: context.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Revenue Potential (GEO)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _GeoMetric(
                      label: 'Current CPM',
                      value: '\$${gs.avgCpmOverall.toStringAsFixed(2)}',
                      color: scheme.onSurface,
                    ),
                  ),
                  Container(
                    height: 32,
                    width: 1,
                    color: scheme.outlineVariant,
                  ),
                  Expanded(
                    child: _GeoMetric(
                      label: 'Potential CPM',
                      value: gs.avgCpmOverall > 0
                          ? '\$${(gs.potentialRevenueAtTier1Cpm / (gs.totalRevenueUsd > 0 ? gs.totalRevenueUsd / gs.avgCpmOverall : 1)).toStringAsFixed(2)}'
                          : '\$0.00',
                      color: context.primary,
                    ),
                  ),
                  Container(
                    height: 32,
                    width: 1,
                    color: scheme.outlineVariant,
                  ),
                  Expanded(
                    child: _GeoMetric(
                      label: 'Diversity',
                      value: '${(gs.geoDiversityScore * 100).toStringAsFixed(0)}%',
                      color: gs.geoDiversityScore > 0.5
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                ],
              ),
              if (gs.revenueGap > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withAlpha(51)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_rounded,
                          size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'If all traffic were Tier 1 GEOs, revenue could be ${gs.totalRevenueUsd > 0 ? (gs.potentialRevenueAtTier1Cpm / gs.totalRevenueUsd).toStringAsFixed(1) : "0.0"}x higher',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Per-GEO Performance List ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: scheme.onSurface.withAlpha(10),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  const SizedBox(width: 28),
                  SizedBox(
                    width: 60,
                    child: Text(
                      'GEO',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Revenue / CPM',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      'Clicks',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      'SR',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...sorted.map((geo) => _GeoRow(
                geo: geo,
                maxRev: maxRev,
                isTop: geo == sorted.first,
              )),
            ],
          ),
        ),
      ],
    );
  }
}

class _GeoMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _GeoMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: color.withAlpha(153),
          ),
        ),
      ],
    );
  }
}

class _GeoRow extends StatelessWidget {
  final PerGeoRevenue geo;
  final double maxRev;
  final bool isTop;

  const _GeoRow({
    required this.geo,
    required this.maxRev,
    this.isTop = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final region = GeoRegion.fromCode(geo.geoCode);
    final regionFlag = region.flag;
    final ratio = maxRev > 0 ? (geo.totalRevenueUsd / maxRev).clamp(0.0, 1.0) : 0.0;

    // Color based on performance
    Color barColor;
    if (geo.cpmRatio >= 0.7) {
      barColor = Colors.green;
    } else if (geo.cpmRatio >= 0.4) {
      barColor = Colors.orange;
    } else {
      barColor = Colors.red.shade300;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(
            children: [
              // Flag
              SizedBox(
                width: 24,
                child: Text(
                  regionFlag,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(width: 4),
              // GEO Code
              SizedBox(
                width: 60,
                child: Row(
                  children: [
                    Text(
                      geo.geoCode,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isTop ? context.primary : scheme.onSurface,
                      ),
                    ),
                    if (region.tier == GeoRevenueTier.tier1)
                      Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: Icon(Icons.star_rounded,
                            size: 10, color: Colors.amber.shade600),
                      ),
                  ],
                ),
              ),
              // Revenue / CPM
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: ratio,
                        backgroundColor: scheme.surfaceContainerLow,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '\$${geo.totalRevenueUsd.toStringAsFixed(4)}',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'CPM \$${geo.avgCpm.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 8,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Clicks
              SizedBox(
                width: 56,
                child: Text(
                  geo.clickCount.toString(),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              // Success Rate
              SizedBox(
                width: 44,
                child: Text(
                  '${geo.successRatePct.toStringAsFixed(0)}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: geo.successRatePct > 70
                        ? Colors.green
                        : geo.successRatePct > 40
                            ? Colors.orange
                            : Colors.red,
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

// ═══════════════════════════════════════════════════════════════════════════
// Section Header
// ═══════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Empty State
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyRevenueState extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyRevenueState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.primary.withAlpha(26),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.analytics_rounded,
                size: 52,
                color: context.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'panel.no_revenue_data'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'panel.no_revenue_data_hint'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: Text(
                  'panel.refresh'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
