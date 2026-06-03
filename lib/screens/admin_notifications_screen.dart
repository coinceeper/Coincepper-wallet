import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../models/notification_models.dart';
import '../services/service_provider.dart';

/// Admin notification panel for P4 (Network & Gas) and P5 (Engagement).
///
/// This screen provides UI for administrators to send various
/// push notifications through the admin API endpoints.
class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  int _currentTab = 0;

  String _t(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (_) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            _t('admin_notifications', 'Admin Notifications'),
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.black),
          bottom: TabBar(
            labelColor: const Color(0xFF27B6AC),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF27B6AC),
            onTap: (i) => setState(() => _currentTab = i),
            tabs: [
              Tab(
                text: _t('network', 'Network'),
                icon: const Icon(Icons.wifi, size: 18),
              ),
              Tab(
                text: _t('engagement', 'Engagement'),
                icon: const Icon(Icons.campaign, size: 18),
              ),
              Tab(
                text: _t('broadcast', 'Broadcast'),
                icon: const Icon(Icons.send, size: 18),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _NetworkTab(),
            _EngagementTab(),
            _BroadcastTab(),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// P4: NETWORK TAB
// =============================================================================

class _NetworkTab extends StatefulWidget {
  @override
  State<_NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<_NetworkTab> {
  bool _sendingNetworkStatus = false;
  bool _sendingUpgrade = false;
  bool _sendingPortfolio = false;

  // Network Status fields
  final _blockchainCtrl = TextEditingController(text: 'Ethereum');
  String _status = 'maintenance';
  final _statusMsgCtrl = TextEditingController();

  // Network Upgrade fields
  final _upgradeBlockchainCtrl = TextEditingController(text: 'Ethereum');
  final _upgradeNameCtrl = TextEditingController(text: 'Pectra');
  final _upgradeDescCtrl = TextEditingController(
      text: 'Major protocol upgrade with EIP improvements');
  final _upgradeTimeCtrl = TextEditingController(text: 'June 2026');

  // Portfolio fields
  final _portfolioUserIdCtrl = TextEditingController();

  @override
  void dispose() {
    _blockchainCtrl.dispose();
    _statusMsgCtrl.dispose();
    _upgradeBlockchainCtrl.dispose();
    _upgradeNameCtrl.dispose();
    _upgradeDescCtrl.dispose();
    _upgradeTimeCtrl.dispose();
    _portfolioUserIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendNetworkStatus() async {
    setState(() => _sendingNetworkStatus = true);
    final request = NetworkStatusRequest(
      blockchain: _blockchainCtrl.text.trim(),
      status: _status,
      message: _statusMsgCtrl.text.trim(),
    );
    final response =
        await ServiceProvider.instance.apiService.adminNotifyNetworkStatus(request);
    setState(() => _sendingNetworkStatus = false);
    _showResult(response.success, response.message ?? '');
  }

  Future<void> _sendUpgrade() async {
    setState(() => _sendingUpgrade = true);
    final request = NetworkUpgradeRequest(
      blockchain: _upgradeBlockchainCtrl.text.trim(),
      upgradeName: _upgradeNameCtrl.text.trim(),
      description: _upgradeDescCtrl.text.trim(),
      estimatedTime: _upgradeTimeCtrl.text.trim(),
    );
    final response =
        await ServiceProvider.instance.apiService.adminNotifyNetworkUpgrade(request);
    setState(() => _sendingUpgrade = false);
    _showResult(response.success, response.message ?? '');
  }

  Future<void> _sendPortfolioSummary() async {
    setState(() => _sendingPortfolio = true);
    final response = await ServiceProvider.instance.apiService
        .adminSendPortfolioSummary(_portfolioUserIdCtrl.text.trim());
    setState(() => _sendingPortfolio = false);
    _showResult(response.success, response.message ?? '');
  }

  void _showResult(bool success, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? '✅ Sent successfully' : '❌ Failed: $message'),
        backgroundColor: success ? const Color(0xFF27B6AC) : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Network Status ──
          _AdminCard(
            title: 'Network Status Alert',
            subtitle: 'Send maintenance/outage/degraded/restored alerts',
            icon: Icons.warning_amber,
            iconColor: Colors.orange,
            children: [
              TextField(
                controller: _blockchainCtrl,
                decoration: const InputDecoration(
                  labelText: 'Blockchain',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'maintenance', child: Text('🔧 Maintenance')),
                  DropdownMenuItem(value: 'outage', child: Text('🚫 Outage')),
                  DropdownMenuItem(value: 'degraded', child: Text('⚠️ Degraded')),
                  DropdownMenuItem(value: 'restored', child: Text('✅ Restored')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'maintenance'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _statusMsgCtrl,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              _SendButton(
                loading: _sendingNetworkStatus,
                onPressed: _sendNetworkStatus,
                label: 'Send Network Status Alert',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Network Upgrade ──
          _AdminCard(
            title: 'Network Upgrade Notification',
            subtitle: 'Notify users about protocol upgrades',
            icon: Icons.system_update,
            iconColor: Colors.purple,
            children: [
              TextField(
                controller: _upgradeBlockchainCtrl,
                decoration: const InputDecoration(
                  labelText: 'Blockchain',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _upgradeNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Upgrade Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _upgradeDescCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _upgradeTimeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Estimated Time',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              _SendButton(
                loading: _sendingUpgrade,
                onPressed: _sendUpgrade,
                label: 'Send Upgrade Notification',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Portfolio Summary ──
          _AdminCard(
            title: 'Portfolio Summary (Manual)',
            subtitle: 'Trigger portfolio summary for a specific user',
            icon: Icons.account_balance_wallet,
            iconColor: Colors.blue,
            children: [
              TextField(
                controller: _portfolioUserIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'User ID',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              _SendButton(
                loading: _sendingPortfolio,
                onPressed: _sendPortfolioSummary,
                label: 'Send Portfolio Summary',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// P5: ENGAGEMENT TAB
// =============================================================================

class _EngagementTab extends StatefulWidget {
  @override
  State<_EngagementTab> createState() => _EngagementTabState();
}

class _EngagementTabState extends State<_EngagementTab> {
  bool _sendingListing = false;
  bool _sendingNews = false;
  bool _sendingUpdate = false;
  bool _sendingReward = false;

  // New Listing
  final _listingSymbolCtrl = TextEditingController(text: 'PEPE');
  final _listingNameCtrl = TextEditingController(text: 'Pepe Coin');
  final _listingBlockchainCtrl = TextEditingController(text: 'Ethereum');
  final _listingDescCtrl =
      TextEditingController(text: 'New memecoin now available');

  // Breaking News
  final _newsTitleCtrl =
      TextEditingController(text: 'Major Exchange Listing');
  final _newsBodyCtrl = TextEditingController(
      text: 'PEPE listed on major exchanges, +200% in 24h');
  final _newsUrlCtrl = TextEditingController(
      text: 'https://coinceeper.com/news/pepe-listing');

  // App Update
  final _updateVersionCtrl = TextEditingController(text: '2.4.0');
  final _updateChangesCtrl =
      TextEditingController(text: 'New staking feature,Bug fixes,Security improvements');
  bool _forceUpdate = false;

  // Reward
  final _rewardUserIdCtrl = TextEditingController();
  String _rewardType = 'staking';
  final _rewardAmountCtrl = TextEditingController(text: '0.5');
  final _rewardSymbolCtrl = TextEditingController(text: 'NCC');
  final _rewardDescCtrl =
      TextEditingController(text: 'Monthly staking rewards');

  @override
  void dispose() {
    _listingSymbolCtrl.dispose();
    _listingNameCtrl.dispose();
    _listingBlockchainCtrl.dispose();
    _listingDescCtrl.dispose();
    _newsTitleCtrl.dispose();
    _newsBodyCtrl.dispose();
    _newsUrlCtrl.dispose();
    _updateVersionCtrl.dispose();
    _updateChangesCtrl.dispose();
    _rewardUserIdCtrl.dispose();
    _rewardAmountCtrl.dispose();
    _rewardSymbolCtrl.dispose();
    _rewardDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendListing() async {
    setState(() => _sendingListing = true);
    final request = NewListingRequest(
      symbol: _listingSymbolCtrl.text.trim(),
      name: _listingNameCtrl.text.trim(),
      blockchain: _listingBlockchainCtrl.text.trim(),
      description: _listingDescCtrl.text.trim(),
    );
    final response =
        await ServiceProvider.instance.apiService.adminNotifyNewListing(request);
    setState(() => _sendingListing = false);
    _showResult(response.success, response.message ?? '');
  }

  Future<void> _sendNews() async {
    setState(() => _sendingNews = true);
    final request = BreakingNewsRequest(
      title: _newsTitleCtrl.text.trim(),
      body: _newsBodyCtrl.text.trim(),
      url: _newsUrlCtrl.text.trim().isEmpty ? null : _newsUrlCtrl.text.trim(),
    );
    final response =
        await ServiceProvider.instance.apiService.adminSendBreakingNews(request);
    setState(() => _sendingNews = false);
    _showResult(response.success, response.message ?? '');
  }

  Future<void> _sendUpdate() async {
    setState(() => _sendingUpdate = true);
    final changes = _updateChangesCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final request = AppUpdateRequest(
      version: _updateVersionCtrl.text.trim(),
      changes: changes,
      forceUpdate: _forceUpdate,
    );
    final response =
        await ServiceProvider.instance.apiService.adminNotifyAppUpdate(request);
    setState(() => _sendingUpdate = false);
    _showResult(response.success, response.message ?? '');
  }

  Future<void> _sendReward() async {
    setState(() => _sendingReward = true);
    final request = RewardRequest(
      userId: _rewardUserIdCtrl.text.trim(),
      rewardType: _rewardType,
      amount: _rewardAmountCtrl.text.trim(),
      symbol: _rewardSymbolCtrl.text.trim(),
      description: _rewardDescCtrl.text.trim(),
    );
    final response =
        await ServiceProvider.instance.apiService.adminSendReward(request);
    setState(() => _sendingReward = false);
    _showResult(response.success, response.message ?? '');
  }

  void _showResult(bool success, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? '✅ Sent successfully' : '❌ Failed: $message'),
        backgroundColor: success ? const Color(0xFF27B6AC) : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── New Listing ──
          _AdminCard(
            title: 'New Coin Listing',
            subtitle: 'Notify users about new available coins',
            icon: Icons.currency_bitcoin,
            iconColor: Colors.amber,
            children: [
              TextField(
                controller: _listingSymbolCtrl,
                decoration: const InputDecoration(
                  labelText: 'Symbol',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _listingNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _listingBlockchainCtrl,
                decoration: const InputDecoration(
                  labelText: 'Blockchain',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _listingDescCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              _SendButton(
                loading: _sendingListing,
                onPressed: _sendListing,
                label: 'Send New Listing',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Breaking News ──
          _AdminCard(
            title: 'Breaking News',
            subtitle: 'Send urgent news to all users',
            icon: Icons.new_releases,
            iconColor: Colors.red,
            children: [
              TextField(
                controller: _newsTitleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newsBodyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Body',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newsUrlCtrl,
                decoration: const InputDecoration(
                  labelText: 'URL (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              _SendButton(
                loading: _sendingNews,
                onPressed: _sendNews,
                label: 'Send Breaking News',
                color: Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── App Update ──
          _AdminCard(
            title: 'App Update Notification',
            subtitle: 'Notify users about new app versions',
            icon: Icons.system_update_alt,
            iconColor: Colors.blue,
            children: [
              TextField(
                controller: _updateVersionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Version',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _updateChangesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Changes (comma separated)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _forceUpdate,
                onChanged: (v) => setState(() => _forceUpdate = v ?? false),
                title: const Text('Force Update'),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
              const SizedBox(height: 8),
              _SendButton(
                loading: _sendingUpdate,
                onPressed: _sendUpdate,
                label: 'Send Update Notification',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Reward ──
          _AdminCard(
            title: 'Rewards & Airdrops',
            subtitle: 'Send rewards, airdrops, cashback to users',
            icon: Icons.card_giftcard,
            iconColor: Colors.green,
            children: [
              TextField(
                controller: _rewardUserIdCtrl,
                decoration: const InputDecoration(
                  labelText: 'User ID',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _rewardType,
                decoration: const InputDecoration(
                  labelText: 'Reward Type',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'staking', child: Text('🥩 Staking')),
                  DropdownMenuItem(value: 'airdrop', child: Text('🎁 Airdrop')),
                  DropdownMenuItem(value: 'cashback', child: Text('💵 Cashback')),
                  DropdownMenuItem(value: 'referral', child: Text('🎯 Referral')),
                ],
                onChanged: (v) => setState(() => _rewardType = v ?? 'staking'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _rewardAmountCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _rewardSymbolCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Symbol',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rewardDescCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              _SendButton(
                loading: _sendingReward,
                onPressed: _sendReward,
                label: 'Send Reward',
                color: Colors.green,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// BROADCAST TAB
// =============================================================================

class _BroadcastTab extends StatefulWidget {
  @override
  State<_BroadcastTab> createState() => _BroadcastTabState();
}

class _BroadcastTabState extends State<_BroadcastTab> {
  bool _sending = false;
  final _titleCtrl =
      TextEditingController(text: '🚀 CoinCeeper v2 is live!');
  final _bodyCtrl = TextEditingController(
      text: 'Experience the new non-custodial wallet');

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendBroadcast() async {
    setState(() => _sending = true);
    final request = BroadcastRequest(
      title: _titleCtrl.text.trim(),
      body: _bodyCtrl.text.trim(),
    );
    final response =
        await ServiceProvider.instance.apiService.adminSendBroadcast(request);
    setState(() => _sending = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(response.success
            ? '✅ Broadcast sent to all users'
            : '❌ Failed: ${response.message}'),
        backgroundColor: response.success
            ? const Color(0xFF27B6AC)
            : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Info Banner ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.campaign, color: Colors.teal),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Send a broadcast notification to ALL registered users. Use sparingly for important announcements.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _AdminCard(
            title: 'General Broadcast',
            subtitle: 'Send to all users',
            icon: Icons.send,
            iconColor: Colors.teal,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Body',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _sending ? null : _sendBroadcast,
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(_sending
                      ? 'Sending...'
                      : 'Send Broadcast to All Users'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
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

// =============================================================================
// SHARED WIDGETS
// =============================================================================

class _AdminCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;

  const _AdminCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  final String label;
  final Color? color;

  const _SendButton({
    required this.loading,
    required this.onPressed,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = color ?? const Color(0xFF27B6AC);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}
