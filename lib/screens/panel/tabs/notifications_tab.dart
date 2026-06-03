import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../providers/client_panel_provider.dart';
import '../../../models/client_panel_models.dart';
import '../../../utils/theme_helpers.dart';

class NotificationsTab extends StatelessWidget {
  const NotificationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientPanelProvider>(
      builder: (context, provider, _) {
        final primary = Theme.of(context).colorScheme.primary;
        final hasUnread =
            provider.notifications.any((n) => !n.isRead);
        return RefreshIndicator(
          color: primary,
          onRefresh: provider.loadNotifications,
          child: Column(
            children: [
              if (hasUnread)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: provider.markAllRead,
                        icon: Icon(Icons.done_all_rounded,
                            size: 16, color: primary),
                        label: Text(
                          'panel.mark_all_read'.tr(),
                          style: TextStyle(
                              color: primary,
                              fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: provider.notificationsLoading &&
                        provider.notifications.isEmpty
                    ? Center(
                        child: CircularProgressIndicator(color: primary))
                    : provider.notifications.isEmpty
                        ? _Empty()
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: provider.notifications.length,
                            itemBuilder: (ctx, i) => _NotifCard(
                                notif: provider.notifications[i]),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NotifCard extends StatelessWidget {
  final ClientNotification notif;
  const _NotifCard({required this.notif});

  IconData get _icon {
    switch (notif.type) {
      case 'earning':
        return Icons.trending_up_rounded;
      case 'withdrawal':
        return Icons.account_balance_wallet_rounded;
      case 'referral':
        return Icons.group_rounded;
      case 'system':
        return Icons.info_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _typeColor(BuildContext context) {
    switch (notif.type) {
      case 'earning':
        return Theme.of(context).colorScheme.primary;
      case 'withdrawal':
        return appPrimaryDark(context);
      case 'referral':
        return Theme.of(context).colorScheme.tertiary;
      case 'system':
        return appPrimary(context);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _typeColor(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            notif.isRead ? Colors.white : const Color(0xFFF0FAFA),
        borderRadius: BorderRadius.circular(14),
        border: notif.isRead
            ? null
            : Border.all(
                color:
                    Theme.of(context).colorScheme.primary.withOpacity(0.2)),
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(_icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notif.title,
                        style: TextStyle(
                          fontWeight: notif.isRead
                              ? FontWeight.w500
                              : FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (!notif.isRead)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ],
                ),
                if (notif.body != null && notif.body!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    notif.body!,
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 12),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  _timeAgo(notif.createdAt),
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.notifications_none_rounded,
              size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('panel.no_notifications'.tr(),
              style: const TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }
}
