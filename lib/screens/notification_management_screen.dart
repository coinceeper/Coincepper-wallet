import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import '../layout/bottom_menu_with_siri.dart';

class NotificationManagementScreen extends StatefulWidget {
  const NotificationManagementScreen({super.key});

  @override
  State<NotificationManagementScreen> createState() => _NotificationManagementScreenState();
}

class _NotificationManagementScreenState extends State<NotificationManagementScreen> {
  bool pushNotifications = true;
  bool sendAndReceive = false;
  bool isLoading = true;

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      pushNotifications = prefs.getBool('push_notifications') ?? true;
      sendAndReceive = prefs.getBool('send_and_receive') ?? false;
      isLoading = false;
    });
  }

  Future<void> _setPushNotifications(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      pushNotifications = value;
      if (!value) sendAndReceive = false;
    });
    await prefs.setBool('push_notifications', value);
    if (!value) {
      await prefs.setBool('send_and_receive', false);
    }
  }

  Future<void> _setSendAndReceive(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      sendAndReceive = value;
    });
    await prefs.setBool('send_and_receive', value);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(_safeTranslate('notifications', 'Notifications'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _NotificationItem(
              title: _safeTranslate('allow_push_notifications', 'Allow push notifications'),
              description: _safeTranslate('activate_deactivate_push_notifications', 'Activate or deactivate push notifications'),
              state: pushNotifications,
              onToggle: (val) => _setPushNotifications(val),
              switchColor: const Color(0xFF27B6AC),
            ),
            const SizedBox(height: 32),
            _NotificationItem(
              title: _safeTranslate('send_and_receive', 'Send and receive'),
              description: _safeTranslate('get_notified_sending_receiving', 'Get notified when sending or receiving'),
              state: sendAndReceive,
              onToggle: (val) => _setSendAndReceive(val),
              enabled: pushNotifications,
              switchColor: const Color(0xFF27B6AC),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomMenuWithSiri(),
    );
  }
}

class _NotificationItem extends StatelessWidget {
  final String title;
  final String? description;
  final bool state;
  final ValueChanged<bool> onToggle;
  final bool enabled;
  final Color switchColor;
  const _NotificationItem({required this.title, this.description, required this.state, required this.onToggle, this.enabled = true, required this.switchColor});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, color: Colors.black)),
                if (description != null)
                  Text(description!, style: const TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ),
          ),
          _CustomSwitch(
            checked: state,
            onCheckedChange: enabled ? onToggle : null,
            switchColor: switchColor,
          ),
        ],
      ),
    );
  }
}

class _CustomSwitch extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool>? onCheckedChange;
  final Color switchColor;
  const _CustomSwitch({required this.checked, required this.onCheckedChange, required this.switchColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onCheckedChange != null ? () => onCheckedChange!(!checked) : null,
      child: Container(
        width: 50,
        height: 28,
        decoration: BoxDecoration(
          color: checked ? switchColor : Colors.grey,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: checked ? Alignment.centerRight : Alignment.centerLeft,
        padding: const EdgeInsets.all(2),
        child: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
} 