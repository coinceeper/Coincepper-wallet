import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../utils/secure_log.dart';
import 'build_secrets.dart';

enum UpdateType { none, optional, force }

class VersionStatus {
  final UpdateType type;
  final String? url;
  final String? latestVersion;

  VersionStatus({required this.type, this.url, this.latestVersion});
}

class VersionCheckService {
  static String get _versionUrl => BuildSecrets.coinceeperVersionApiUrl;

  static Future<VersionStatus> checkVersion() async {
    try {
      final response = await http.get(Uri.parse(_versionUrl)).timeout(const Duration(seconds: 10));
      
      if (response.statusCode != 200) {
        return VersionStatus(type: UpdateType.none);
      }

      final data = json.decode(response.body);
      if (data['success'] != true) {
        return VersionStatus(type: UpdateType.none);
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      
      final platformKey = Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : null);
      if (platformKey == null || data[platformKey] == null) {
        return VersionStatus(type: UpdateType.none);
      }

      final platformData = data[platformKey];
      final minVersion = platformData['min_version'] as String;
      final latestVersion = platformData['latest_version'] as String;
      final url = (platformData['update_url'] as String?) ?? '';

      if (_isVersionLessThan(currentVersion, minVersion)) {
        return VersionStatus(type: UpdateType.force, url: url, latestVersion: latestVersion);
      } else if (_isVersionLessThan(currentVersion, latestVersion)) {
        return VersionStatus(type: UpdateType.optional, url: url, latestVersion: latestVersion);
      }

      return VersionStatus(type: UpdateType.none);
    } catch (e) {
      SecureLog.e('Version check failed', error: e);
      return VersionStatus(type: UpdateType.none);
    }
  }

  static bool _isVersionLessThan(String current, String target) {
    try {
      List<int> currentParts = current.split('.').map((e) => int.parse(e)).toList();
      List<int> targetParts = target.split('.').map((e) => int.parse(e)).toList();

      for (int i = 0; i < 3; i++) {
        int c = i < currentParts.length ? currentParts[i] : 0;
        int t = i < targetParts.length ? targetParts[i] : 0;
        if (c < t) return true;
        if (c > t) return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
