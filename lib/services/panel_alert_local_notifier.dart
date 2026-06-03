import 'package:shared_preferences/shared_preferences.dart';

import '../models/client_panel_models.dart';
import 'notification_helper.dart';

/// Shows a **local** OS notification when the panel API returns a new unread alert
/// (FCM is optional; this works while the app is running / polling).
class PanelAlertLocalNotifier {
  static String _prefsKey(String? panelIdentity) {
    final safe = (panelIdentity ?? 'global')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_');
    return 'panel_local_notified_ids_v1_$safe';
  }

  static Future<void> processNewUnread(
    List<ClientNotification> items, {
    String? panelIdentity,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _prefsKey(panelIdentity);
    final bootKey = '${key}_bootstrapped';
    final known = Set<String>.from(prefs.getStringList(key) ?? []);
    final bootstrapped = prefs.getBool(bootKey) ?? false;

    if (!bootstrapped) {
      for (final n in items) {
        if (n.isRead) continue;
        final id = n.id.trim();
        if (id.isEmpty) continue;
        known.add(id);
      }
      await prefs.setStringList(key, known.toList());
      await prefs.setBool(bootKey, true);
      return;
    }

    for (final n in items) {
      if (n.isRead) continue;
      final id = n.id.trim();
      if (id.isEmpty) continue;
      if (known.contains(id)) continue;
      known.add(id);
      final body = (n.body ?? '').trim();
      await NotificationHelper.showPanelAlert(
        title: n.title.trim().isEmpty ? 'Panel' : n.title.trim(),
        body: body.isEmpty ? 'New alert' : body,
        payload: id,
      );
    }

    var list = known.toList();
    if (list.length > 500) {
      list = list.sublist(list.length - 500);
    }
    await prefs.setStringList(key, list);
  }
}
