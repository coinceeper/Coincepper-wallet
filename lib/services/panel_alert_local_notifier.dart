import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/secure_log.dart';

import '../models/client_panel_models.dart';
import 'notification_helper.dart';

/// Processes newly-fetched panel notifications and fires local notifications
/// for any unread items that haven't been alerted yet.
///
/// Each panel identity (wallet address) has its own deduplication set so that
/// switching wallets correctly resets the "already shown" tracking.
class PanelAlertLocalNotifier {
  PanelAlertLocalNotifier._();

  /// SharedPreferences key prefix — scoped per panel identity.
  static const String _kPrefsPrefix = 'panel_alert_shown_';

  /// Processes [notifications] from the panel API and fires local alerts for
  /// any unread items that haven't been shown before on this device.
  ///
  /// [panelIdentity] scopes the deduplication set so that different wallets
  /// get independent tracking.
  ///
  /// After processing, newly-shown notification IDs are persisted via
  /// [SharedPreferences] so they won't re-fire on the next poll.
  static Future<void> processNewUnread(
    List<ClientNotification> notifications, {
    String? panelIdentity,
  }) async {
    if (notifications.isEmpty) return;

    // Filter to unread items only.
    final unread = notifications.where((n) => !n.isRead).toList();
    if (unread.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final key = _dedupKey(panelIdentity);
    final alreadyShown = _loadShownIds(prefs, key);

    final newlyShown = <String>{};

    for (final notification in unread) {
      if (alreadyShown.contains(notification.id)) continue;

      try {
        await NotificationHelper.showPanelAlert(
          title: notification.title,
          body: notification.body ?? notification.type,
          payload: 'panel_notification_${notification.id}',
        );
        newlyShown.add(notification.id);

        SecureLog.d('PanelAlertLocalNotifier: alerted notification ${notification.id}');
      } catch (e) {
        SecureLog.e('PanelAlertLocalNotifier: failed to show alert for ${notification.id}: $e');
      }
    }

    if (newlyShown.isNotEmpty) {
      alreadyShown.addAll(newlyShown);
      await _saveShownIds(prefs, key, alreadyShown);
    }
  }

  /// Returns the SharedPreferences key for the given [panelIdentity].
  /// Falls back to a global key when no identity is provided.
  static String _dedupKey(String? panelIdentity) {
    if (panelIdentity == null || panelIdentity.trim().isEmpty) {
      return '${_kPrefsPrefix}_global';
    }
    // Normalize to lower-case to avoid casing mismatches with ETH addresses.
    final norm = panelIdentity.trim().toLowerCase();
    return '$_kPrefsPrefix$norm';
  }

  /// Deserialises a JSON array of notification IDs from prefs.
  static Set<String> _loadShownIds(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toSet();
    } catch (e) {
      SecureLog.w('PanelAlertNotifier: failed to decode shown notification IDs, resetting', error: e);
      return <String>{};
    }
  }

  /// Serialises [shownIds] as a JSON array and writes to prefs.
  static Future<void> _saveShownIds(
    SharedPreferences prefs,
    String key,
    Set<String> shownIds,
  ) async {
    await prefs.setString(key, jsonEncode(shownIds.toList()));
  }
}
