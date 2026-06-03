import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  /// مثل [AGENT_STRICT_MODE] — قبل از [version] / [start] (مثلاً build hardened) فراخوانی شود.
  static Future<void> setStrictMode({required bool enabled}) async {
    if (kIsWeb) {
      return;
    }
    if (_useDesktopSidecar) {
      await tsp_desk.tspDesktopSetStrictMode(enabled ? 1 : 0);
      return;
    }
    await _ch.invokeMethod<void>('tspSetStrictMode', enabled ? 1 : 0);
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
    await _ch.invokeMethod<void>('tspPrepareAttestation', {
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
    return (await _ch.invokeMethod<String>('tspVersion')) ?? '';
  }

  static Future<String> healthJson() async {
    if (kIsWeb) {
      return '{}';
    }
    if (_useDesktopSidecar) {
      return tsp_desk.tspDesktopHealthJson();
    }
    return (await _ch.invokeMethod<String>('tspHealth')) ?? '';
  }

  static Future<String> fingerprint() async {
    if (kIsWeb) {
      return '';
    }
    if (_useDesktopSidecar) {
      return tsp_desk.tspDesktopFingerprint();
    }
    return (await _ch.invokeMethod<String>('tspFingerprint')) ?? '';
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
    final v = await _ch.invokeMethod<int>('tspStart', {
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
    return (await _ch.invokeMethod<bool>('tspSetDeviceKey')) ?? false;
  }

  /// Mobile fallback for devices where hardware-backed key setup fails.
  static Future<bool> setPayloadKeyHex(String hexKey) async {
    if (kIsWeb) {
      return false;
    }
    if (_useDesktopSidecar) {
      return false;
    }
    return (await _ch.invokeMethod<bool>('tspSetPayloadKeyHex', hexKey)) ?? false;
  }

  static Future<void> stop() async {
    if (kIsWeb) {
      return;
    }
    if (_useDesktopSidecar) {
      await tsp_desk.tspDesktopStop();
      return;
    }
    await _ch.invokeMethod<void>('tspStop');
  }

  static Future<bool> isRuntimeRunning() async {
    if (kIsWeb) {
      return false;
    }
    if (_useDesktopSidecar) {
      return tsp_desk.tspDesktopIsRunning();
    }
    return (await _ch.invokeMethod<bool>('tspIsRunning')) ?? false;
  }
}
