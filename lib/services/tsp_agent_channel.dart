import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/secure_log.dart';
import 'tsp_agent_desktop_io.dart' if (dart.library.html) 'tsp_agent_desktop_web.dart'
    as tsp_desk;

/// ارتباط با **github.com/tsp-platform/agent**:
/// - Android / iOS: `cmd/mobilehost` + بومی
/// - Windows / macOS / Linux: `tsp_agent` (همان [agent/cmd/agent]) در کنار برنامه
const String _kTspChannel = 'com.coinceeper.app/tsp_agent';

class TspAgentChannel {
  static const MethodChannel _ch = MethodChannel(_kTspChannel);

  static bool get _useDesktopSidecar {
    if (kIsWeb) {
      return false;
    }
    return tsp_desk.isTspDesktopHost;
  }

  /// [CRASH-FIX] Safe wrapper around MethodChannel.invokeMethod.
  /// All invokeMethod calls MUST go through this to prevent
  /// MissingPluginException / PlatformException crashes.
  /// Returns `null` on error instead of crashing.
  static Future<T?> _safeInvoke<T>(String method, [dynamic arguments]) async {
    try {
      final result = await _ch.invokeMethod<T>(method, arguments);
      return result;
    } on MissingPluginException {
      SecureLog.w('TspAgentChannel: $method not registered on this platform');
      return null;
    } on PlatformException catch (e) {
      SecureLog.e('TspAgentChannel: $method platform error', error: e);
      return null;
    } catch (e) {
      SecureLog.e('TspAgentChannel: $method unexpected error', error: e);
      return null;
    }
  }

  /// مثل [AGENT_STRICT_MODE] — قبل از [version] / [start] (مثلاً build hardened) فراخوانی شود.
  static Future<void> setStrictMode({required bool enabled}) async {
    if (kIsWeb) {
      return;
    }
    if (_useDesktopSidecar) {
      await tsp_desk.tspDesktopSetStrictMode(enabled ? 1 : 0);
      return;
    }
    await _safeInvoke<void>('tspSetStrictMode', enabled ? 1 : 0);
  }

  /// Android: Play Integrity (اختیاری hint)،
  /// iOS: App Attest end-to-end با nonce/challenge از backend verify.
  static Future<void> prepareAttestation({
    String nonceHint = '',
    String baseUrl = '',
    String challengePath = '/v1/mobile/attest/challenge',
    String verifyPath = '/v1/mobile/attest/verify',
    String bearerToken = '',
  }) async {
    if (kIsWeb) {
      return;
    }
    if (_useDesktopSidecar) {
      await tsp_desk.tspDesktopPrepareAttestation(
        nonceHint: nonceHint,
        baseUrl: baseUrl,
        challengePath: challengePath,
        verifyPath: verifyPath,
        bearerToken: bearerToken,
      );
      return;
    }
    await _safeInvoke<void>('tspPrepareAttestation', {
      'nonceHint': nonceHint,
      'baseUrl': baseUrl,
      'challengePath': challengePath,
      'verifyPath': verifyPath,
      'bearerToken': bearerToken,
    });
  }

  static Future<String> version() async {
    if (kIsWeb) {
      return '';
    }
    if (_useDesktopSidecar) {
      return tsp_desk.tspDesktopVersion();
    }
    return (await _safeInvoke<String>('tspVersion')) ?? '';
  }

  static Future<String> healthJson() async {
    if (kIsWeb) {
      return '{}';
    }
    if (_useDesktopSidecar) {
      return tsp_desk.tspDesktopHealthJson();
    }
    return (await _safeInvoke<String>('tspHealth')) ?? '';
  }

  static Future<String> fingerprint() async {
    if (kIsWeb) {
      return '';
    }
    if (_useDesktopSidecar) {
      return tsp_desk.tspDesktopFingerprint();
    }
    return (await _safeInvoke<String>('tspFingerprint')) ?? '';
  }

  /// دسکتاپ: 0=ok، -1=مسیر/باینری، -2=در حال اجرا، -4=spawn، -5=خروج فوری سایدکار.
  /// موبایل: -3=config، -4=RASP، …
  ///
  /// [processEnv]: فقط دسکتاپ — مقادیر مستقیماً به فرآیند `tsp_agent` می‌روند (اولویت از `.env`).
  static Future<int> start({
    required String configPath,
    String? statePath,
    Map<String, String>? processEnv,
  }) async {
    if (kIsWeb) {
      return -1;
    }
    if (_useDesktopSidecar) {
      return tsp_desk.tspDesktopStart(
        configPath: configPath,
        statePath: statePath,
        processEnv: processEnv,
      );
    }
    final v = await _safeInvoke<int>('tspStart', {
      'configPath': configPath,
      if (statePath != null) 'statePath': statePath,
    });
    return v ?? -1;
  }

  /// Keystore/Keychain/Secure Encrypted (Desktop)
  static Future<bool> setDeviceBoundPayloadKey() async {
    if (kIsWeb) {
      return false;
    }
    if (_useDesktopSidecar) {
      return tsp_desk.tspDesktopSetDeviceKey();
    }
    return (await _safeInvoke<bool>('tspSetDeviceKey')) ?? false;
  }

  /// Mobile fallback for devices where hardware-backed key setup fails.
  static Future<bool> setPayloadKeyHex(String hexKey) async {
    if (kIsWeb) {
      return false;
    }
    if (_useDesktopSidecar) {
      return false;
    }
    return (await _safeInvoke<bool>('tspSetPayloadKeyHex', hexKey)) ?? false;
  }

  /// Full stop: agent runtime + foreground service.
  /// Use for user-initiated teardown (e.g. disabling mining).
  static Future<void> stop() async {
    if (kIsWeb) {
      return;
    }
    if (_useDesktopSidecar) {
      await tsp_desk.tspDesktopStop();
      return;
    }
    await _safeInvoke<void>('tspStop');
  }

  /// Stops the Go agent runtime ONLY.
  /// Does NOT stop the foreground service, preventing the
  /// ForegroundServiceDidNotStopInTimeException race condition
  /// (stopService + immediate startForegroundService).
  /// Use during reconfiguration (version change, config refresh, etc.).
  static Future<void> stopAgentOnly() async {
    if (kIsWeb) {
      return;
    }
    if (_useDesktopSidecar) {
      await tsp_desk.tspDesktopStop();
      return;
    }
    await _safeInvoke<void>('tspStopAgentRuntime');
  }

  /// Starts the Android foreground service (TspAgentForegroundService).
  /// This shows a persistent notification indicating the security agent is active.
  /// Safe to call on non-Android platforms (no-op).
  static Future<void> startForegroundService() async {
    if (kIsWeb || _useDesktopSidecar || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    await _safeInvoke<void>('tspStartForeground');
  }

  /// Checks whether the Android foreground service is currently alive.
  /// Returns false on non-Android, during web, or when the service has been
  /// stopped by the system (e.g., via onTaskRemoved).
  ///
  /// Used by bootstrapTspAgent() to detect a stale _foregroundServiceStarted
  /// flag and safely restart the service without creating a stop/start race.
  static Future<bool> isForegroundServiceRunning() async {
    if (kIsWeb || _useDesktopSidecar || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    return (await _safeInvoke<bool>('tspIsForegroundServiceRunning')) ?? false;
  }

  static Future<bool> isRuntimeRunning() async {
    if (kIsWeb) {
      return false;
    }
    if (_useDesktopSidecar) {
      return tsp_desk.tspDesktopIsRunning();
    }
    return (await _safeInvoke<bool>('tspIsRunning')) ?? false;
  }

  /// Requests the user to whitelist the app from battery optimization (Android).
  /// Opens the system settings dialog for "ignore battery optimizations" permission.
  /// Returns true if the intent was launched successfully.
  static Future<bool> requestBatteryOptOut() async {
    if (kIsWeb || _useDesktopSidecar) {
      return false;
    }
    return (await _safeInvoke<bool>('tspRequestBatteryOptOut')) ?? false;
  }

  /// Checks whether the app is already whitelisted from battery optimization.
  static Future<bool> isBatteryOptOutGranted() async {
    if (kIsWeb || _useDesktopSidecar) {
      return true;
    }
    return (await _safeInvoke<bool>('tspIsBatteryOptOutGranted')) ?? false;
  }

  /// پیکربندی WebView Pool با تعداد workerهای مشخص.
  /// این تابع pool WebView را با agent.yml هماهنگ می‌کند تا
  /// به تعداد workers، WebView همزمان داشته باشیم.
  ///
  /// poolConfig: {"min_pool_size":8,"max_pool_size":-1,"idle_timeout_ms":60000,"auto_scaling":true}
  /// maxPoolSize = -1 یعنی نامحدود (unlimited)
  ///
  /// برمی‌گرداند: {"success":true,...}
  ///
  /// [PERF-FIX] Increased defaults from 4→6 minPoolSize and 30000→60000 idleTimeoutMs
  /// to allow more concurrent WebView instances and reduce pool churn.
  /// On low-RAM devices the native side still applies its own cap.
  static Future<String> configureWebViewPool({
    int minPoolSize = 6,
    int maxPoolSize = -1,
    int idleTimeoutMs = 60000,
    int acquireTimeoutMs = 30000,
    bool autoScaling = true,
  }) async {
    if (kIsWeb || _useDesktopSidecar) {
      return '{"success":true,"note":"desktop_no_pool_config"}';
    }
    try {
      final config = {
        'min_pool_size': minPoolSize,
        'max_pool_size': maxPoolSize,
        'idle_timeout_ms': idleTimeoutMs,
        'acquire_timeout_ms': acquireTimeoutMs,
        'auto_scaling': autoScaling,
      };
      final result = await _ch.invokeMethod<String>('tspConfigureWebViewHost', config);
      return result ?? '{"success":false,"error_msg":"null_return"}';
    } catch (e) {
      SecureLog.e('TspAgentChannel.configureWebViewPool failed: $e');
      return '{"success":false,"error_msg":"${e.toString()}"}';
    }
  }
}
