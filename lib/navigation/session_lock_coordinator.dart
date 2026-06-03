import 'package:shared_preferences/shared_preferences.dart';

import 'route_paths.dart';

/// Persists route to restore after app passcode unlock.
class SessionLockCoordinator {
  SessionLockCoordinator._();

  static const _key = 'session_lock_return_uri';

  static Future<void> saveReturnUri(String uri) async {
    if (uri == RoutePaths.enterPasscode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, uri);
  }

  static Future<String?> consumeReturnUri() async {
    final prefs = await SharedPreferences.getInstance();
    final uri = prefs.getString(_key);
    if (uri != null) {
      await prefs.remove(_key);
    }
    return uri;
  }
}
