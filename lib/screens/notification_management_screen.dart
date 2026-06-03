import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';

import '../providers/notification_provider.dart';
import '../layout/bottom_menu_with_siri.dart';
import '../navigation/route_paths.dart';

/// Central notification management screen.
///
/// Shows 6 toggle categories (Master + P1–P5) and local notification history.
class NotificationManagementScreen extends StatefulWidget {
  const NotificationManagementScreen({super.key});

  @override
  State<NotificationManagementScreen> createState() =>
      _NotificationManagementScreenState();
}

class _NotificationManagementScreenState
    extends State<NotificationManagementScreen> {
  String _t(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          _t('notifications', 'Notifications'),
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, provider, _) {
              if (provider.unreadCount > 0) {
                return TextButton(
                  onPressed: () {
                    provider.markAllAsRead();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_t('marked_read', 'Marked all as read')),
                        backgroundColor: const Color(0xFF27B6AC),
                      ),
                    );
                  },
                  child: Text(
                    _t('mark_read', 'Mark Read'),
                    style: const TextStyle(color: Color(0xFF27B6AC)),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // ── Toggles Section ──
              const SizedBox(height: 8),
              _ToggleTile(
                title: _t('notif_push', 'Push Notifications'),
                value: provider.pushEnabled,
                onChanged: (v) => provider.setPushEnabled(v),
              ),
              const Divider(height: 1),
              _ToggleTile(
                title: _t('notif_tx', 'Transactions'),
                value: provider.transactionNotifications,
                onChanged: (v) => provider.setTransactionNotifications(v),
                enabled: provider.pushEnabled,
              ),
              const Divider(height: 1),
              _ToggleTile(
                title: _t('notif_security', 'Security Alerts'),
                value: provider.securityNotifications,
                onChanged: (v) => provider.setSecurityNotifications(v),
                enabled: provider.pushEnabled,
              ),
              const Divider(height: 1),
              InkWell(
                onTap: () => context.go(RoutePaths.priceAlerts),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _t('notif_price', 'Price Alerts'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          color: Colors.grey.shade400, size: 22),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              _ToggleTile(
                title: _t('notif_network', 'Network & Gas'),
                value: provider.networkNotifications,
                onChanged: (v) => provider.setNetworkNotifications(v),
                enabled: provider.pushEnabled,
              ),
              const Divider(height: 1),
              _ToggleTile(
                title: _t('notif_engagement', 'CoinCeeper News'),
                value: provider.engagementNotifications,
                onChanged: (v) => provider.setEngagementNotifications(v),
                enabled: provider.pushEnabled,
              ),

              // ── Notification History ──
              if (provider.notificationHistory.isNotEmpty) ...[
                const SizedBox(height: 24),
                _SectionHeader(
                  title: _t('recent_notifications', 'Recent Notifications'),
                  trailing: TextButton(
                    onPressed: () => provider.clearHistory(),
                    child: Text(
                      _t('clear', 'Clear'),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...provider.notificationHistory.take(20).map(
                  (entry) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      _iconForType(entry.type),
                      size: 20,
                      color: _colorForType(entry.type),
                    ),
                    title: Text(
                      entry.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            entry.isRead ? FontWeight.normal : FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      entry.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Text(
                      _formatTime(entry.timestamp),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: const BottomMenuWithSiri(),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'transaction_received':
      case 'receive':
        return Icons.arrow_downward;
      case 'send':
        return Icons.arrow_upward;
      case 'security_login':
      case 'security_change':
      case 'security_suspicious':
        return Icons.security;
      case 'price_alert':
        return Icons.trending_up;
      case 'gas_alert':
      case 'network_status':
        return Icons.wifi;
      default:
        return Icons.notifications;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'receive':
        return Colors.green;
      case 'send':
        return Colors.red;
      case 'security_login':
      case 'security_change':
      case 'security_suspicious':
        return Colors.orange;
      case 'price_alert':
        return Colors.green;
      case 'gas_alert':
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}

// ─── Shared Sub-widgets ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    if (trailing != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          trailing!,
        ],
      );
    }
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        color: Colors.grey,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  const _ToggleTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: Switch.adaptive(
                value: value,
                onChanged: enabled ? onChanged : null,
                activeColor: const Color(0xFF27B6AC),
                activeTrackColor:
                    const Color(0xFF27B6AC).withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
