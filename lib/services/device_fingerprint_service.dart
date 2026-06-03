import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Generates a stable, persistent device fingerprint that survives app re-installs
/// on the same device (where possible).
///
/// Storage: SharedPreferences (plaintext — not sensitive, just a device identifier).
/// Generation: UUID v5 based on hardware identifiers (brand + model + OS-level ID).
class DeviceFingerprintService {
  static DeviceFingerprintService? _instance;
  static DeviceFingerprintService get instance =>
      _instance ??= DeviceFingerprintService._();
  DeviceFingerprintService._();

  static const _kPrefsKey = 'device_fingerprint_v2';
  static const _kLegacyKey = 'device_fingerprint';

  String? _cached;

  /// Returns the cached fingerprint (fast, no I/O) or loads from prefs.
  Future<String> get() async {
    if (_cached != null) return _cached!;
    final prefs = await SharedPreferences.getInstance();
    _cached = prefs.getString(_kPrefsKey) ?? prefs.getString(_kLegacyKey);
    if (_cached != null) return _cached!;
    _cached = await _generate();
    await prefs.setString(_kPrefsKey, _cached!);
    return _cached!;
  }

  Future<String> _generate() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String rawSeed;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final info = await deviceInfo.androidInfo;
        // Combine Android identifiers for a stable seed
        rawSeed = '${info.brand}|${info.model}|${info.device}|${info.id}';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final info = await deviceInfo.iosInfo;
        rawSeed =
            '${info.model}|${info.identifierForVendor ?? info.name}';
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        final info = await deviceInfo.windowsInfo;
        rawSeed =
            'windows|${info.computerName}|${info.productId}';
      } else if (defaultTargetPlatform == TargetPlatform.macOS) {
        final info = await deviceInfo.macOsInfo;
        rawSeed = 'macos|${info.model}|${info.computerName}';
      } else if (defaultTargetPlatform == TargetPlatform.linux) {
        final info = await deviceInfo.linuxInfo;
        rawSeed = 'linux|${info.machineId}';
      } else {
        // Fallback: random UUID if platform not recognized
        rawSeed = 'fallback|${const Uuid().v4()}';
      }

      // Use UUID v5 with DNS namespace for deterministic but non-reversible hash
      return const Uuid().v5(Namespace.url.value, rawSeed);
    } catch (e) {
      debugPrint('⚠️ DeviceFingerprintService: generation failed ($e), using random fallback');
      final fallback = const Uuid().v4();
      return const Uuid().v5(Namespace.url.value, 'fallback|$fallback');
    }
  }
}
