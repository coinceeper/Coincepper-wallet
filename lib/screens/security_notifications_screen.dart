import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import '../providers/notification_provider.dart';
import '../layout/bottom_menu_with_siri.dart';

/// Screen for security notification controls (P2).
///
/// Provides UI to trigger security notification API calls:
/// - Report new login
/// - Report security setting change
/// - Report suspicious activity
class SecurityNotificationsScreen extends StatefulWidget {
  const SecurityNotificationsScreen({super.key});

  @override
  State<SecurityNotificationsScreen> createState() =>
      _SecurityNotificationsScreenState();
}

class _SecurityNotificationsScreenState
    extends State<SecurityNotificationsScreen> {
  bool _loading = false;

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
        title: Text(
          _t('security_notifications', 'Security Notifications'),
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Info Banner ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _t('security_notif_info',
                          'Security notifications are triggered by frontend events. Report new logins, setting changes, and suspicious activity.'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── New Login Report ──
            _SectionHeader(
              icon: Icons.login,
              title: _t('report_login', 'Report New Login'),
              subtitle: _t('report_login_desc',
                  'Call this when user logs in from a new device'),
            ),
            const SizedBox(height: 12),
            _ReportLoginCard(
              onReport: (deviceName, deviceType, ipAddress, location) =>
                  _reportLogin(context, deviceName, deviceType, ipAddress, location),
            ),

            const SizedBox(height: 24),

            // ── Security Change Report ──
            _SectionHeader(
              icon: Icons.settings,
              title: _t('report_security_change', 'Report Security Change'),
              subtitle: _t('report_security_change_desc',
                  'Call this when security settings are changed'),
            ),
            const SizedBox(height: 12),
            _ReportSecurityChangeCard(
              onReport: (changeType, deviceName) =>
                  _reportSecurityChange(context, changeType, deviceName),
            ),

            const SizedBox(height: 24),

            // ── Suspicious Activity Report ──
            _SectionHeader(
              icon: Icons.warning_amber,
              title: _t('report_suspicious', 'Report Suspicious Activity'),
              subtitle: _t('report_suspicious_desc',
                  'Call this for unusual patterns'),
              iconColor: Colors.red,
            ),
            const SizedBox(height: 12),
            _ReportSuspiciousCard(
              onReport: (activityType, description, severity) =>
                  _reportSuspicious(context, activityType, description, severity),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomMenuWithSiri(),
    );
  }

  Future<void> _reportLogin(
    BuildContext context,
    String deviceName,
    String deviceType,
    String ipAddress,
    String? location,
  ) async {
    setState(() => _loading = true);
    final provider = context.read<NotificationProvider>();
    final success = await provider.reportSecurityLogin(
      deviceName: deviceName,
      deviceType: deviceType,
      ipAddress: ipAddress,
      location: location,
    );
    setState(() => _loading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? _t('login_reported', 'Login notification sent')
              : _t('report_failed', 'Failed to send notification')),
          backgroundColor: success ? const Color(0xFF27B6AC) : Colors.red,
        ),
      );
    }
  }

  Future<void> _reportSecurityChange(
    BuildContext context,
    String changeType,
    String deviceName,
  ) async {
    setState(() => _loading = true);
    final provider = context.read<NotificationProvider>();
    final success = await provider.reportSecurityChange(
      changeType: changeType,
      deviceName: deviceName,
    );
    setState(() => _loading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? _t('change_reported', 'Security change notification sent')
              : _t('report_failed', 'Failed to send notification')),
          backgroundColor: success ? const Color(0xFF27B6AC) : Colors.red,
        ),
      );
    }
  }

  Future<void> _reportSuspicious(
    BuildContext context,
    String activityType,
    String description,
    String severity,
  ) async {
    setState(() => _loading = true);
    final provider = context.read<NotificationProvider>();
    final success = await provider.reportSuspiciousActivity(
      activityType: activityType,
      description: description,
      severity: severity,
    );
    setState(() => _loading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? _t('suspicious_reported', 'Suspicious activity notification sent')
              : _t('report_failed', 'Failed to send notification')),
          backgroundColor: success ? const Color(0xFF27B6AC) : Colors.red,
        ),
      );
    }
  }

  bool get loading => _loading;
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? const Color(0xFF27B6AC);
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
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
    );
  }
}

class _ReportLoginCard extends StatefulWidget {
  final Future<void> Function(
      String deviceName, String deviceType, String ipAddress, String? location) onReport;

  const _ReportLoginCard({required this.onReport});

  @override
  State<_ReportLoginCard> createState() => _ReportLoginCardState();
}

class _ReportLoginCardState extends State<_ReportLoginCard> {
  final _deviceNameCtrl = TextEditingController(text: 'Samsung Galaxy S24');
  final _ipCtrl = TextEditingController(text: '192.168.1.1');
  final _locationCtrl = TextEditingController();
  String _deviceType = 'android';
  bool _loading = false;

  @override
  void dispose() {
    _deviceNameCtrl.dispose();
    _ipCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

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
            TextField(
              controller: _deviceNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Device Name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _deviceType,
              decoration: const InputDecoration(
                labelText: 'Device Type',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'android', child: Text('Android')),
                DropdownMenuItem(value: 'ios', child: Text('iOS')),
                DropdownMenuItem(value: 'web', child: Text('Web')),
              ],
              onChanged: (v) => setState(() => _deviceType = v ?? 'android'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ipCtrl,
              decoration: const InputDecoration(
                labelText: 'IP Address',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading
                    ? null
                    : () async {
                        setState(() => _loading = true);
                        await widget.onReport(
                          _deviceNameCtrl.text.trim(),
                          _deviceType,
                          _ipCtrl.text.trim(),
                          _locationCtrl.text.trim().isEmpty
                              ? null
                              : _locationCtrl.text.trim(),
                        );
                        setState(() => _loading = false);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27B6AC),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Send Login Notification'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportSecurityChangeCard extends StatefulWidget {
  final Future<void> Function(String changeType, String deviceName) onReport;

  const _ReportSecurityChangeCard({required this.onReport});

  @override
  State<_ReportSecurityChangeCard> createState() =>
      _ReportSecurityChangeCardState();
}

class _ReportSecurityChangeCardState extends State<_ReportSecurityChangeCard> {
  String _changeType = 'password_changed';
  final _deviceNameCtrl = TextEditingController(text: 'Samsung Galaxy S24');
  bool _loading = false;

  @override
  void dispose() {
    _deviceNameCtrl.dispose();
    super.dispose();
  }

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
            DropdownButtonFormField<String>(
              value: _changeType,
              decoration: const InputDecoration(
                labelText: 'Change Type',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                    value: 'password_changed', child: Text('Password Changed')),
                DropdownMenuItem(
                    value: 'pin_changed', child: Text('PIN Changed')),
                DropdownMenuItem(
                    value: '2fa_enabled', child: Text('2FA Enabled')),
                DropdownMenuItem(
                    value: '2fa_disabled', child: Text('2FA Disabled')),
              ],
              onChanged: (v) => setState(() => _changeType = v ?? 'password_changed'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _deviceNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Device Name',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading
                    ? null
                    : () async {
                        setState(() => _loading = true);
                        await widget.onReport(
                          _changeType,
                          _deviceNameCtrl.text.trim(),
                        );
                        setState(() => _loading = false);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27B6AC),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Send Security Change Notification'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportSuspiciousCard extends StatefulWidget {
  final Future<void> Function(
      String activityType, String description, String severity) onReport;

  const _ReportSuspiciousCard({required this.onReport});

  @override
  State<_ReportSuspiciousCard> createState() => _ReportSuspiciousCardState();
}

class _ReportSuspiciousCardState extends State<_ReportSuspiciousCard> {
  String _activityType = 'failed_login';
  String _severity = 'warning';
  final _descCtrl =
      TextEditingController(text: '5 failed login attempts in 2 minutes');
  bool _loading = false;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

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
            DropdownButtonFormField<String>(
              value: _activityType,
              decoration: const InputDecoration(
                labelText: 'Activity Type',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                    value: 'failed_login', child: Text('Failed Login')),
                DropdownMenuItem(
                    value: 'unusual_transaction',
                    child: Text('Unusual Transaction')),
                DropdownMenuItem(value: 'new_ip', child: Text('New IP')),
              ],
              onChanged: (v) =>
                  setState(() => _activityType = v ?? 'failed_login'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _severity,
              decoration: const InputDecoration(
                labelText: 'Severity',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'info', child: Text('Info')),
                DropdownMenuItem(value: 'warning', child: Text('Warning')),
                DropdownMenuItem(value: 'critical', child: Text('Critical')),
              ],
              onChanged: (v) => setState(() => _severity = v ?? 'warning'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading
                    ? null
                    : () async {
                        setState(() => _loading = true);
                        await widget.onReport(
                          _activityType,
                          _descCtrl.text.trim(),
                          _severity,
                        );
                        setState(() => _loading = false);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Send Suspicious Activity Alert'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
