import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../providers/client_panel_provider.dart';
import '../../../models/client_panel_models.dart';

class BotsTab extends StatefulWidget {
  const BotsTab({super.key});

  @override
  State<BotsTab> createState() => _BotsTabState();
}

class _BotsTabState extends State<BotsTab> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<ClientPanelProvider>();
      p.refreshLocalMinerStatus();
      p.loadAgents();
    });
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) {
      final p = context.read<ClientPanelProvider>();
      p.loadAgents();
      p.refreshLocalMinerStatus();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ClientPanelProvider>(
      builder: (context, provider, _) {
        final primary = Theme.of(context).colorScheme.primary;
        final agents = provider.agents;
        final localId = provider.localAgentId;
        final alreadyListed = localId != null &&
            agents.any((a) => a.id.toLowerCase() == localId);
        final showLocalTile = provider.localMinerChecked &&
            provider.localMinerRunning &&
            !alreadyListed;
        final showLocalOnly = showLocalTile && agents.isEmpty;
        final localTile = showLocalTile ? const _LocalMinerCard() : null;
        return RefreshIndicator(
          color: primary,
          onRefresh: () async {
            await provider.refreshLocalMinerStatus();
            await provider.loadAgents();
          },
          child: provider.agentsLoading && agents.isEmpty
              ? Center(
                  child: CircularProgressIndicator(color: primary))
              : (agents.isEmpty && !showLocalOnly)
                  ? _EmptyAgents(
                      startCode: provider.localMinerLastStartCode,
                      onRetry: () async {
                        await provider.refreshLocalMinerStatus();
                        await provider.loadAgents();
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: agents.length + (localTile == null ? 0 : 1),
                      itemBuilder: (context, i) {
                        if (localTile != null && i == 0) return localTile;
                        final idx = i - (localTile == null ? 0 : 1);
                        return _AgentCard(agent: agents[idx]);
                      },
                    ),
        );
      },
    );
  }
}

class _AgentCard extends StatelessWidget {
  final ClientAgent agent;
  const _AgentCard({required this.agent});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final successRate = agent.totalActions > 0
        ? agent.successActions / agent.totalActions
        : 0.0;
    final lastSeen = agent.lastSeenAt;
    String lastSeenStr = '–';
    if (lastSeen != null) {
      final diff = DateTime.now().difference(lastSeen);
      if (diff.inMinutes < 1) {
        lastSeenStr = 'panel.just_now'.tr();
      } else if (diff.inHours < 1) {
        lastSeenStr = '${diff.inMinutes}m ago';
      } else if (diff.inDays < 1) {
        lastSeenStr = '${diff.inHours}h ago';
      } else {
        lastSeenStr = '${diff.inDays}d ago';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 8, top: 1),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: agent.online ? Colors.green : Colors.grey,
                    boxShadow: agent.online
                        ? [
                            BoxShadow(
                                color: Colors.green.withOpacity(0.5),
                                blurRadius: 4)
                          ]
                        : null,
                  ),
                ),
                Expanded(
                  child: Text(
                    agent.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusBadge(status: agent.status, online: agent.online),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (agent.simulatedOs != null) ...[
                  Icon(
                    _osIcon(agent.simulatedOs!),
                    size: 14,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(agent.simulatedOs!,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 11)),
                  const SizedBox(width: 12),
                ],
                const Icon(Icons.access_time_rounded,
                    size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(lastSeenStr,
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: successRate,
                      backgroundColor: const Color(0xFFEEEEEE),
                      valueColor: AlwaysStoppedAnimation(
                          agent.online ? primary : Colors.grey),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${agent.successActions}/${agent.totalActions}',
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _osIcon(String os) {
    final lower = os.toLowerCase();
    if (lower.contains('android')) return Icons.android_rounded;
    if (lower.contains('ios') || lower.contains('iphone')) {
      return Icons.phone_iphone_rounded;
    }
    if (lower.contains('windows')) return Icons.laptop_windows_rounded;
    if (lower.contains('mac')) return Icons.laptop_mac_rounded;
    return Icons.devices_rounded;
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool online;
  const _StatusBadge({required this.status, required this.online});

  @override
  Widget build(BuildContext context) {
    final color = online
        ? Colors.green
        : status == 'active'
            ? Colors.orange
            : Colors.grey;
    final label = online
        ? 'panel.online'.tr()
        : status == 'active'
            ? 'panel.idle'.tr()
            : 'panel.offline'.tr();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyAgents extends StatelessWidget {
  final int? startCode;
  final Future<void> Function()? onRetry;
  const _EmptyAgents({this.startCode, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.computer_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text('panel.no_bots'.tr(),
              style: const TextStyle(color: Colors.grey, fontSize: 16)),
          const SizedBox(height: 8),
          Text('panel.no_bots_desc'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          if (startCode != null) ...[
            const SizedBox(height: 8),
            Text(
              'runtime code: $startCode',
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Retry Miner Detection'),
          ),
        ],
      ),
    );
  }
}

class _LocalMinerCard extends StatelessWidget {
  const _LocalMinerCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: const ListTile(
        leading: Icon(Icons.smartphone_rounded, color: Colors.green),
        title: Text(
          'This Device Miner',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('Miner is active on this device'),
        trailing: _StatusBadge(status: 'active', online: true),
      ),
    );
  }
}
