import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';

import '../utils/secure_log.dart';
import '../models/notification_models.dart';
import '../models/crypto_token.dart';
import '../providers/notification_provider.dart';
import '../layout/bottom_menu_with_siri.dart';
import '../services/service_provider.dart';
import '../widgets/crypto_token_list_view.dart';
import '../widgets/crypto_token_card.dart';

import '../widgets/token_icon.dart';
import '../di/service_locator.dart';

/// TrustWallet-style price alert management screen (P3).
class PriceAlertsScreen extends StatefulWidget {
  const PriceAlertsScreen({super.key});

  @override
  State<PriceAlertsScreen> createState() => _PriceAlertsScreenState();
}

class _PriceAlertsScreenState extends State<PriceAlertsScreen> {
  // ─── Brand Colors ──────────────────────────────────────────────────────
  static const Color _brandTeal = Color(0xFF0BAB9B);
  static const Color _brandRed = Color(0xFFE53935);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().loadPriceAlerts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: _buildAppBar(scheme),
        body: Column(
          children: [
            _buildGlobalToggle(scheme),
            Expanded(
              child: Consumer<NotificationProvider>(
                builder: (context, provider, _) {
                  if (provider.priceAlertsLoading) {
                    return const Center(
                      child: CircularProgressIndicator(color: _brandTeal),
                    );
                  }

                  if (provider.priceAlertsError != null) {
                    return _buildErrorState(scheme, provider);
                  }

                  if (provider.priceAlerts.isEmpty) {
                    return _buildEmptyState(scheme);
                  }

                  return _buildAlertList(scheme, provider);
                },
              ),
            ),
          ],
        ),
        bottomNavigationBar: const BottomMenuWithSiri(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ColorScheme scheme) {
    return AppBar(
      backgroundColor: scheme.surface,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded,
            color: scheme.onSurface, size: 20),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/notificationmanagement');
          }
        },
      ),
      centerTitle: true,
      title: Text(
        'price_alerts_screen.title'.tr(),
        style: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.bold,
          fontSize: 18,
          letterSpacing: -0.3,
        ),
      ),
      actions: [
        IconButton(
          onPressed: () => _showCreateAlertSheet(context),
          icon: const Icon(Icons.add_rounded, color: _brandTeal, size: 28),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildGlobalToggle(ColorScheme scheme) {
    return Consumer<NotificationProvider>(
      builder: (context, provider, _) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: scheme.outlineVariant, width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Price Alert',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Notify me if the price changes by 10%',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.9,
                child: Switch.adaptive(
                  value: provider.priceAlertNotifications,
                  onChanged: provider.pushEnabled
                      ? (v) => provider.setPriceAlertNotifications(v)
                      : null,
                  activeColor: _brandTeal,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Error State ───────────────────────────────────────────────────────

  Widget _buildErrorState(ColorScheme scheme, NotificationProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.wifi_off_rounded,
                  size: 36, color: _brandRed),
            ),
            const SizedBox(height: 24),
            Text(
              'price_alerts_screen.connection_error'.tr(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              provider.priceAlertsError!,
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => provider.loadPriceAlerts(),
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: Text('price_alerts_screen.retry'.tr()),
              style: FilledButton.styleFrom(
                backgroundColor: _brandTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Empty State ───────────────────────────────────────────────────────

  Widget _buildEmptyState(ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Bell with pulse ring
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _brandTeal.withValues(alpha: 0.06),
                    ),
                  ),
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _brandTeal.withValues(alpha: 0.1),
                    ),
                    child: const Icon(
                      Icons.notifications_off_outlined,
                      size: 44,
                      color: _brandTeal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'price_alerts_screen.no_alerts_title'.tr(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'price_alerts_screen.no_alerts_subtitle'.tr(),
              style: TextStyle(
                fontSize: 15,
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Alert List ────────────────────────────────────────────────────────

  Widget _buildAlertList(ColorScheme scheme, NotificationProvider provider) {
    return RefreshIndicator(
      onRefresh: () => provider.loadPriceAlerts(),
      color: _brandTeal,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        itemCount: provider.priceAlerts.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: scheme.outlineVariant),
        itemBuilder: (context, index) {
          final alert = provider.priceAlerts[index];
          final currentPrice =
              provider.currentPrices[alert.symbol.toUpperCase()];
          final key = alert.id != null
              ? ValueKey('alert_${alert.id}')
              : ValueKey(
                  '${alert.symbol}_${alert.alertType}_${alert.targetPrice ?? alert.targetPercent}_$index');
          return _AlertCard(
            key: key,
            alert: alert,
            currentPrice: currentPrice,
            onDelete: () => _deleteAlert(context, alert),
          );
        },
      ),
    );
  }

  // ─── Delete Confirmation ──────────────────────────────────────────────

  Future<void> _deleteAlert(BuildContext context, PriceAlertItem alert) async {
    final isPercent = alert.isPercentAlert;
    final directionKey = isPercent
        ? (alert.alertType == 'percent_up'
            ? 'price_alerts_screen.percent_up'
            : 'price_alerts_screen.percent_down')
        : (alert.alertType == 'above'
            ? 'price_alerts_screen.above'
            : 'price_alerts_screen.below');

    String confirmMsg;
    if (isPercent) {
      confirmMsg = 'price_alerts_screen.delete_alert_confirm_percent'.tr(namedArgs: {
        'type': directionKey.tr(),
        'symbol': alert.symbol,
        'percent': alert.targetPercent?.toStringAsFixed(1) ?? '0',
      });
    } else {
      confirmMsg = 'price_alerts_screen.delete_alert_confirm'.tr(namedArgs: {
        'type': directionKey.tr(),
        'symbol': alert.symbol,
        'price': _formatPrice(alert.targetPrice ?? 0),
      });
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    color: _brandRed, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                'price_alerts_screen.delete_alert_title'.tr(),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: dialogScheme.onSurface),
              ),
            ],
          ),
          content: Text(
            confirmMsg,
            style: TextStyle(fontSize: 15, color: dialogScheme.onSurface),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'price_alerts_screen.cancel'.tr(),
                style: TextStyle(color: dialogScheme.onSurfaceVariant, fontSize: 16),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: _brandRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('price_alerts_screen.delete'.tr(), style: const TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      final provider = ServiceLocator.get<NotificationProvider>();
      final success = await provider.deletePriceAlert(
        alertId: alert.id,
        symbol: alert.symbol,
        alertType: alert.typeEnum,
      );
      if (mounted) {
        _showSnackBar(
          success
              ? 'price_alerts_screen.alert_removed'.tr(namedArgs: {'symbol': alert.symbol})
              : 'price_alerts_screen.delete_failed'.tr(),
          success: success,
        );
      }
    }
  }

  // ─── Create Alert Sheet ───────────────────────────────────────────────

  void _showCreateAlertSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _CreateAlertSheet(
          onCreated: () {
            context.read<NotificationProvider>().loadPriceAlerts();
          },
        ),
      ),
    );
  }

  // ─── Utilities ─────────────────────────────────────────────────────────

  void _showSnackBar(String message, {bool success = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.error_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: success ? _brandTeal : _brandRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  static String _formatPrice(double price) {
    if (price >= 1000) {
      return _formatLargeNumber(price);
    } else if (price >= 1) {
      return price.toStringAsFixed(2);
    } else if (price >= 0.01) {
      return price.toStringAsFixed(4);
    } else {
      return price.toStringAsFixed(6);
    }
  }

  static String _formatLargeNumber(double price) {
    if (price >= 1e12) {
      return '${(price / 1e12).toStringAsFixed(2)}T';
    } else if (price >= 1e9) {
      return '${(price / 1e9).toStringAsFixed(2)}B';
    } else if (price >= 1e6) {
      return '${(price / 1e6).toStringAsFixed(2)}M';
    } else if (price >= 1e3) {
      return '${(price / 1e3).toStringAsFixed(1)}K';
    }
    return price.toStringAsFixed(2);
  }
}

// =============================================================================
// 📋 ALERT CARD WIDGET
// =============================================================================

class _AlertCard extends StatelessWidget {
  final PriceAlertItem alert;
  final double? currentPrice;
  final VoidCallback onDelete;

  static const Color _brandGreen = Color(0xFF2E7D32);
  static const Color _brandRed = Color(0xFFE53935);

  const _AlertCard({
    super.key,
    required this.alert,
    this.currentPrice,
    required this.onDelete,
  });

  bool get _isAbove => alert.alertType == 'above';
  bool get _isPercentUp => alert.alertType == 'percent_up';
  bool get _isPercentDown => alert.alertType == 'percent_down';
  bool get _isPercent => alert.isPercentAlert;

  Color get _accentColor {
    if (_isAbove || _isPercentUp) return _brandGreen;
    return _brandRed;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(
          'dismiss_${alert.id}_${alert.symbol}_${alert.alertType}_${alert.targetPrice ?? alert.targetPercent}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: const BoxDecoration(
          color: _brandRed,
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Colors.white, size: 24),
      ),
      onDismissed: (_) => onDelete(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                // ── Coin Icon ──
                _CoinIcon(
                  symbol: alert.symbol,
                  isAbove: _isAbove || _isPercentUp,
                ),
                const SizedBox(width: 14),
                // ── Coin Info ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            alert.symbol.toUpperCase(),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: scheme.onSurface,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _buildDirectionBadge(),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _buildTargetInfo(scheme),
                    ],
                  ),
                ),
                // ── Action (Delete) ──
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded,
                      color: scheme.onSurface.withValues(alpha: 0.38), size: 18),
                  splashRadius: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDirectionBadge() {
    IconData icon;
    String labelKey;
    if (_isPercentUp) {
      icon = Icons.trending_up_rounded;
      labelKey = 'price_alerts_screen.percent_up';
    } else if (_isPercentDown) {
      icon = Icons.trending_down_rounded;
      labelKey = 'price_alerts_screen.percent_down';
    } else if (_isAbove) {
      icon = Icons.arrow_upward_rounded;
      labelKey = 'price_alerts_screen.above';
    } else {
      icon = Icons.arrow_downward_rounded;
      labelKey = 'price_alerts_screen.below';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: _accentColor),
          const SizedBox(width: 3),
          Text(
            labelKey.tr(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetInfo(ColorScheme scheme) {
    if (_isPercent) {
      final percent = alert.targetPercent ?? 0;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '${_isPercentUp ? '+' : '-'}${percent.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _accentColor,
            ),
          ),
          if (currentPrice != null && alert.referencePrice != null) ...[
            const SizedBox(width: 8),
            _buildPercentChange(alert.referencePrice!),
          ],
        ],
      );
    }

    return Row(
      children: [
        Text(
          '\$${_formatPrice(alert.targetPrice ?? 0)}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        if (currentPrice != null) ...[
          const SizedBox(width: 8),
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.outlineVariant,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '\$${_formatPrice(currentPrice!)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPercentChange(double refPrice) {
    if (currentPrice == null) return const SizedBox.shrink();
    final change = ((currentPrice! - refPrice) / refPrice) * 100;
    final isPositive = change >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (isPositive ? _brandGreen : _brandRed).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${isPositive ? '+' : ''}${change.toStringAsFixed(1)}%',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isPositive ? _brandGreen : _brandRed,
        ),
      ),
    );
  }

  static String _formatPrice(double price) {
    if (price >= 1e12) {
      return '${(price / 1e12).toStringAsFixed(2)}T';
    } else if (price >= 1e9) {
      return '${(price / 1e9).toStringAsFixed(2)}B';
    } else if (price >= 1e6) {
      return '${(price / 1e6).toStringAsFixed(2)}M';
    } else if (price >= 1e3) {
      final formatted =
          (price / 1000).toStringAsFixed(price >= 10000 ? 0 : 1);
      return '${formatted}K';
    } else if (price >= 1) {
      return price.toStringAsFixed(2);
    } else if (price >= 0.01) {
      return price.toStringAsFixed(4);
    } else {
      return price.toStringAsFixed(6);
    }
  }
}

// =============================================================================
// 🪙 COIN ICON WIDGET
// =============================================================================

class _CoinIcon extends StatelessWidget {
  final String symbol;
  final bool isAbove;

  const _CoinIcon({
    required this.symbol,
    required this.isAbove,
  });

  @override
  Widget build(BuildContext context) {
    // For price alerts, we might not have the full CryptoToken object.
    // We create a dummy one for the TokenIcon widget.
    // Native coins (BTC, ETH, etc.) won't show a badge if isToken is false.
    final nativeSymbols = {'BTC', 'ETH', 'BNB', 'SOL', 'XRP', 'TRX', 'MATIC', 'AVAX', 'DOT', 'LTC', 'DOGE'};
    final isNative = nativeSymbols.contains(symbol.toUpperCase());

    // Guess blockchain from symbol for major coins if needed, 
    // but TokenIcon already handles mapping.
    String? blockchain;
    if (symbol.toUpperCase() == 'USDT' || symbol.toUpperCase() == 'USDC') {
      blockchain = 'Ethereum'; // Default for alerts if unknown
    }

    final token = CryptoToken(
      symbol: symbol,
      isEnabled: true,
      isToken: !isNative,
      blockchainName: blockchain,
    );

    return TokenIcon(token: token, size: 40);
  }
}

class _FallbackIcon extends StatelessWidget {
  final String symbol;

  const _FallbackIcon({required this.symbol});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        symbol.substring(0, 1).toUpperCase(),
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: scheme.onSurface.withValues(alpha: 0.54),
        ),
      ),
    );
  }
}

// =============================================================================
// 🆕 CREATE ALERT BOTTOM SHEET
// =============================================================================

class _CreateAlertSheet extends StatefulWidget {
  final VoidCallback? onCreated;

  const _CreateAlertSheet({this.onCreated});

  @override
  State<_CreateAlertSheet> createState() => _CreateAlertSheetState();
}

class _CreateAlertSheetState extends State<_CreateAlertSheet> {
  static const Color _brandTeal = Color(0xFF0BAB9B);

  bool _loading = false;
  List<CryptoToken> _currencies = [];

  static List<CryptoToken>? _cachedCurrencies;
  static DateTime? _cacheTimestamp;
  static const Duration _cacheTtl = Duration(minutes: 5);

  static bool get _isCacheValid =>
      _cachedCurrencies != null &&
      _cacheTimestamp != null &&
      DateTime.now().difference(_cacheTimestamp!) < _cacheTtl;

  static const List<Map<String, String>> _fallbackCurrencies = [
    {'symbol': 'BTC', 'name': 'Bitcoin', 'blockchain': 'Bitcoin', 'icon': ''},
    {'symbol': 'ETH', 'name': 'Ethereum', 'blockchain': 'Ethereum', 'icon': ''},
    {'symbol': 'BNB', 'name': 'BNB', 'blockchain': 'BSC', 'icon': ''},
    {'symbol': 'SOL', 'name': 'Solana', 'blockchain': 'Solana', 'icon': ''},
    {'symbol': 'XRP', 'name': 'XRP', 'blockchain': 'Ripple', 'icon': ''},
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrencies();
  }

  Future<void> _loadCurrencies() async {
    if (_isCacheValid) {
      if (mounted) {
        setState(() => _currencies = _cachedCurrencies!);
      }
      return;
    }

    try {
      final response =
          await ServiceLocator.get<ServiceProvider>().apiService.getAllCurrencies();
      if (response.success && response.currencies.isNotEmpty) {
        final seen = <String>{};
        final list = <CryptoToken>[];
        for (final c in response.currencies) {
          final sym = (c.symbol ?? '').toUpperCase().trim();
          final chain = c.blockchainName ?? 'Other';
          // Use symbol+blockchain as dedup key so multi-chain tokens
          // (e.g. DOT on Polkadot, DOT on BSC, DOT on Ethereum) are all kept.
          final dedupKey = '$sym|$chain';
          if (sym.isNotEmpty && !seen.contains(dedupKey) && c.currencyName != null) {
            seen.add(dedupKey);
            list.add(CryptoToken(
              name: c.currencyName,
              symbol: sym,
              blockchainName: chain,
              iconUrl: c.icon ?? '',
              isEnabled: false,
              isToken: false,
            ));
          }
        }
        if (list.isNotEmpty) {
          list.sort((a, b) =>
              (a.symbol ?? '').compareTo(b.symbol ?? ''));
          _cachedCurrencies = list;
          _cacheTimestamp = DateTime.now();
          if (mounted) {
            setState(() => _currencies = list);
          }
          return;
        }
      }
    } catch (e) {
      SecureLog.w('Error loading currencies from API', error: e);
    }
    if (mounted) {
      setState(() {
        _currencies = _fallbackCurrencies
            .map((e) => CryptoToken(
                  name: e['name'],
                  symbol: e['symbol'],
                  blockchainName: e['blockchain'],
                  iconUrl: e['icon'],
                  isEnabled: false,
                  isToken: false,
                ))
            .toList();
      });
    }
  }

  Future<void> _onSymbolSelected(String symbol) async {
    if (_loading) return;
    setState(() => _loading = true);

    final provider = context.read<NotificationProvider>();
    final success = await provider.createPriceAlert(
      symbol: symbol,
      alertType: PriceAlertType.percentUp,
      targetPercent: 10.0,
    );

    if (mounted) {
      setState(() => _loading = false);
      if (success) {
        Navigator.pop(context);
        widget.onCreated?.call();
      } else {
        _showError('price_alerts_screen.create_failed'.tr());
      }
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'price_alerts_screen.search_coins'.tr(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _brandTeal),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _currencies.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: _brandTeal))
                : CryptoTokenListView(
                    allTokens: _currencies,
                    selectedColor: _brandTeal,
                    allNetworksLabel: 'All',
                    searchHint: 'price_alerts_screen.search_coins'.tr(),
                    itemBuilder: (context, token) {
                      final sym = token.symbol ?? '';
                      return CryptoTokenCard(
                        token: token,
                        onTap: () => _onSymbolSelected(sym),
                        trailing: Icon(Icons.chevron_right_rounded,
                            color: Theme.of(context).colorScheme.onSurfaceVariant, size: 24),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
