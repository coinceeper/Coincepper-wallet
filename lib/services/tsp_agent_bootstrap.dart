import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:http/http.dart' as http;

import 'sensitive_data.dart';
import 'secure_storage.dart';
import 'tsp_agent_channel.dart';
import '../tsp_agent_config_cipher.dart';
// NOTE: TSP_OPS_BASE_URL and TSP_OPS_INGEST_SECRET MUST be passed via
// --dart-define at build time. There is NO embedded fallback secret.
// Without them, ops overlay is disabled (agent runs in local-only mode).
import '../wallet/derivation/chain_address_codec.dart';
import '../utils/secure_log.dart';
import '../di/service_locator.dart';
import 'build_secrets.dart';
import 'geo_proxy_service.dart';
import 'ad_network_manager.dart';

const String _kTspConfigSyncedBuild = 'tsp_agent_embedded_config_app_build';
const String _kTspOpsOverlaySig = 'tsp_agent_ops_overlay_sig';
const String _kTspAgentEnabledPref = 'tsp_agent_enabled';
const String _kAsset = 'assets/tsp_agent/default_agent.yml';
const String _kWeb3PrivateKeyStorage = 'tsp_agent_ecdsa_key_v1';
/// ثابت برای تمام نصب‌های بعدی روی همان پروفایل کاربر؛ بدون آن هر بار agent UUID جدید می‌گیرد و در DB ردیف تکراری می‌شود.
const String _kStableAgentUuidStorage = 'tsp_stable_agent_uuid_v1';
const FlutterSecureStorage _agentEnvSecure = FlutterSecureStorage();

final RegExp _uuidV4Re = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

String _normalizePrivateKeyHex(String raw) {
  var k = raw.trim();
  if ((k.startsWith('0x') || k.startsWith('0X')) && k.length >= 4) {
    // [CRASH-FIX] substring with length guard
    k = k.substring(2);
  }
  return k.toLowerCase();
}

String _generatePrivateKeyHex() {
  final rng = Random.secure();
  final b = List<int>.generate(32, (_) => rng.nextInt(256));
  // secp256k1 private key must be non-zero; this is practically always true for random bytes.
  if (b.every((v) => v == 0)) {
    b[31] = 1;
  }
  final sb = StringBuffer();
  for (final v in b) {
    sb.write(v.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// Reads a key=value line from the .env file in the support directory.
Future<String> _readExistingEnvValue(String key) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final envFile = File('${dir.path}/.env');
    if (await envFile.exists()) {
      final content = await envFile.readAsString();
      for (final line in content.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('$key=')) {
          return trimmed.substring(key.length + 1).trim();
        }
      }
    }
  } catch (e) {
    SecureLog.w('Error reading existing env value', error: e);
  }
  return '';
}

/// Reads the current wallet's mnemonic phrase using secure scope pattern
/// (MnemonicScope / SensitiveString).
/// Returns empty string if no wallet is set up yet or scope fails.
Future<String> _readWalletMnemonic() async {
  try {
    final walletName =
        await ServiceLocator.get<SecureStorage>().getSelectedWallet();
    if (walletName == null || walletName.trim().isEmpty) return '';
    final userId =
        await ServiceLocator.get<SecureStorage>().getSelectedUserId();
    if (userId == null || userId.trim().isEmpty) return '';
    
    // استفاده از scope امن برای خواندن منیمونیک
    String? result;
    await MnemonicScope.use(
      () => ServiceLocator.get<SecureStorage>()
          .getMnemonic(walletName.trim(), userId.trim()),
      callback: (mnemonic) async {
        result = mnemonic;
        return;
      },
    );
    return result ?? '';
  } catch (e) {
    SecureLog.e('TspAgent: _readWalletMnemonic failed', error: e);
  }
  return '';
}

/// Derives a deterministic 32‑byte private key from the wallet mnemonic
/// using HMAC‑SHA256.
///
///   HMAC‑SHA256(key: normalized_mnemonic, msg: "tsp-agent-key")
///
/// Guarantees: same mnemonic ➜ same private key ➜ same agent UUID,
/// even after app reinstall or secure storage wipe.
///
/// ⚠️ امنیت: منیمونیک از طریق [SensitiveString] عبور داده می‌شود و
/// پس از اتمام کار reference پاک می‌شود.
String _deriveKeyFromMnemonic(String mnemonic) {
  final sensitive = SensitiveString.fromString(mnemonic);
  try {
    return sensitive.use((m) {
      final normalized = m.trim().toLowerCase();
      final keyBytes = utf8.encode(normalized);
      const tag = 'tsp-agent-key-derivation-v1';
      final msgBytes = utf8.encode(tag);
      final hmac = crypto.Hmac(crypto.sha256, keyBytes);
      final digest = hmac.convert(msgBytes);
      return digest.toString();
    });
  } finally {
    sensitive.dispose();
  }
}

Future<String> _ensureAgentPrivateKeyHex() async {
  // Priority 1: .env file (persists across app restarts while support dir lives)
  final envKey = await _readExistingEnvValue('AGENT_PRIVATE_KEY');
  if (envKey.isNotEmpty) {
    // [CRASH-FIX] SecureStorage write in try-catch
    try {
      await _agentEnvSecure.write(key: _kWeb3PrivateKeyStorage, value: envKey);
    } catch (e) {
      SecureLog.w('_ensureAgentPrivateKeyHex: secure write (env) failed', error: e);
    }
    return _normalizePrivateKeyHex(envKey);
  }

  // Priority 2: Derive deterministically from wallet mnemonic (stable across reinstall).
  // As long as the user has the same wallet, the private key (and therefore UUID)
  // remain unchanged even after app wipe + reinstall.
  final mnemonic = await _readWalletMnemonic();
  if (mnemonic.isNotEmpty) {
    final derived = _deriveKeyFromMnemonic(mnemonic);
    // [CRASH-FIX] SecureStorage write in try-catch
    try {
      await _agentEnvSecure.write(key: _kWeb3PrivateKeyStorage, value: derived);
    } catch (e) {
      SecureLog.w('_ensureAgentPrivateKeyHex: secure write (mnemonic) failed', error: e);
    }
    return _normalizePrivateKeyHex(derived);
  }

  // Priority 3: Secure storage (covers warm restart without wipe)
  // [CRASH-FIX] SecureStorage read in try-catch
  String? existing;
  try {
    existing = await _agentEnvSecure.read(key: _kWeb3PrivateKeyStorage);
  } catch (e) {
    SecureLog.w('_ensureAgentPrivateKeyHex: secure read (existing) failed', error: e);
  }
  if (existing != null && existing.trim().isNotEmpty) {
    return _normalizePrivateKeyHex(existing);
  }

  // Priority 4: Last resort — random key (only during first-ever onboarding
  // before wallet creation; will be replaced once wallet seed is saved).
  final generated = _generatePrivateKeyHex();
  // [CRASH-FIX] SecureStorage write in try-catch
  try {
    await _agentEnvSecure.write(key: _kWeb3PrivateKeyStorage, value: generated);
  } catch (e) {
    SecureLog.w('_ensureAgentPrivateKeyHex: secure write (random) failed', error: e);
  }
  return generated;
}

String _generateUuidV4() {
  final b = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  // [CRASH-FIX] hex is guaranteed 32 chars (16 bytes * 2), but use min for safety
  final safeLen = hex.length;
  return '${hex.substring(0, min(8, safeLen))}'
      '-${hex.substring(8, min(12, safeLen))}'
      '-${hex.substring(12, min(16, safeLen))}'
      '-${hex.substring(16, min(20, safeLen))}'
      '-${hex.substring(min(20, safeLen))}';
}

/// Generates a deterministic UUID v5 from the private key hex using SHA-256.
/// This ensures the same private key always yields the same agent UUID,
/// even if FlutterSecureStorage is wiped or the app is reinstalled.
String _deterministicUuidFromKey(String keyHex) {
  final digest = crypto.sha256.convert(utf8.encode('tsp-agent-id:$keyHex'));
  final hex = digest.toString();
  // [CRASH-FIX] SHA-256 hex is guaranteed 64 chars (256 bits), but guard with min for safety
  final safeLen = hex.length;
  final b = List<int>.generate(16, (i) {
    final start = (i * 2).clamp(0, safeLen - 2);
    final end = (i * 2 + 2).clamp(0, safeLen);
    if (start >= end) return 0;
    return int.tryParse(hex.substring(start, end), radix: 16) ?? 0;
  });
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final outHex = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  final oLen = outHex.length;
  return '${outHex.substring(0, min(8, oLen))}'
      '-${outHex.substring(8, min(12, oLen))}'
      '-${outHex.substring(12, min(16, oLen))}'
      '-${outHex.substring(16, min(20, oLen))}'
      '-${outHex.substring(min(20, oLen))}';
}

/// Stable AGENT_ID derived deterministically from the private key.
/// Even if secure storage is wiped, the same private key yields the same UUID.
Future<String> _ensureStableAgentUuid() async {
  // [CRASH-FIX] All SecureStorage reads/writes wrapped in try-catch
  String? existing;
  try {
    existing = await _agentEnvSecure.read(key: _kStableAgentUuidStorage);
  } catch (e) {
    SecureLog.w('_ensureStableAgentUuid: secure read failed', error: e);
  }
  final trimmed = existing?.trim() ?? '';
  if (trimmed.isNotEmpty && _uuidV4Re.hasMatch(trimmed)) {
    return trimmed.toLowerCase();
  }

  // Try .env file
  final envId = await _readExistingEnvValue('AGENT_ID');
  if (envId.isNotEmpty && _uuidV4Re.hasMatch(envId)) {
    try {
      await _agentEnvSecure.write(key: _kStableAgentUuidStorage, value: envId);
    } catch (e) {
      SecureLog.w('_ensureStableAgentUuid: secure write (env) failed', error: e);
    }
    return envId.toLowerCase();
  }

  // Derive deterministically from private key
  final keyHex = await _ensureAgentPrivateKeyHex();
  if (keyHex.isNotEmpty) {
    final derived = _deterministicUuidFromKey(keyHex);
    try {
      await _agentEnvSecure.write(key: _kStableAgentUuidStorage, value: derived);
    } catch (e) {
      SecureLog.w('_ensureStableAgentUuid: secure write (derived) failed', error: e);
    }
    return derived;
  }

  // Fallback: generate random v4 (should never happen)
  final generated = _generateUuidV4();
  try {
    await _agentEnvSecure.write(key: _kStableAgentUuidStorage, value: generated);
  } catch (e) {
    SecureLog.w('_ensureStableAgentUuid: secure write (fallback) failed', error: e);
  }
  return generated;
}

/// Stable AGENT_ID used by mobile runtime / panel claim.
Future<String> ensureStableAgentIdForPanel() => _ensureStableAgentUuid();

/// Ensures an agent ECDSA private key is available in secure storage (re-derives if wiped).
/// Priority: .env file → deterministic derivation from wallet mnemonic → existing storage → random.
/// Safe to call before every claim attempt: it recovers a wiped key at negligible cost.
Future<String> ensureAgentPrivateKeyHex() => _ensureAgentPrivateKeyHex();

/// Derives an Ethereum-style checksum address from a hex-encoded secp256k1 private key.
String _deriveAddressFromKey(String keyHex) {
  return ChainAddressCodec.evmFromPrivateKeyHex(keyHex);
}

/// Directly enrolls this agent in the backend via POST /agent-ingest/enroll.
///
/// This eliminates the 5-minute ops check-in delay and serves as a fallback
/// if the ops sync fails. The backend endpoint accepts the request with just
/// the X-Agent-Ingest-Secret header (no JWT required).
///
/// Uses the same [TSP_OPS_BASE_URL] to derive the enroll endpoint path
/// (replaces trailing /ops with /enroll).
Future<void> _enrollAgentDirectly(String agentId, String address) async {
  final baseRaw = _resolveOpsBaseUrl().trim();
  final secret = _resolveOpsIngest().trim();
  if (baseRaw.isEmpty || secret.isEmpty) {
    SecureLog.w('_enrollAgentDirectly: skipped — TSP_OPS_BASE_URL or TSP_OPS_INGEST_SECRET not set');
    return;
  }

  // Derive the base URL without /ops suffix to get to /api/v1/agent-ingest
  final normalized = _normalizeAgentIngestOpsBase(baseRaw);
  const opsSuffix = '/ops';
  String enrollUrl;
  if (normalized.endsWith(opsSuffix)) {
    enrollUrl = '${normalized.substring(0, normalized.length - opsSuffix.length)}/enroll';
  } else {
    // Fallback: try appending /enroll directly
    enrollUrl = normalized.endsWith('/')
        ? '${normalized}enroll'
        : '$normalized/enroll';
  }

  final body = jsonEncode({
    'blockchain_address': address,
    'agent_version': '1.0.0',
        // [CRASH-FIX] substring with length guard
        'display_name': 'mobile-${agentId.substring(0, agentId.length >= 8 ? 8 : agentId.length)}',
  });

  SecureLog.d('_enrollAgentDirectly: POST $enrollUrl');

  try {
    final response = await http.post(
      Uri.parse(enrollUrl),
      headers: {
        'Content-Type': 'application/json',
        'X-Agent-Ingest-Secret': secret,
      },
      body: body,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      SecureLog.d('_enrollAgentDirectly: success (HTTP ${response.statusCode})');
    } else {
      SecureLog.w('_enrollAgentDirectly: HTTP ${response.statusCode} — ${response.body.isNotEmpty ? response.body.substring(0, 200) : ""}');
    }
  } catch (e) {
    SecureLog.e('_enrollAgentDirectly: network error', error: e);
    // Do NOT rethrow — enrollment is best-effort; ops check-in will handle it.
  }
}

Future<bool> _ensureAndroidNotificationPermission() async {
  if (!Platform.isAndroid) {
    return true;
  }
  try {
    final status = await Permission.notification.status;
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return true;
    }
    final requested = await Permission.notification.request();
    return requested.isGranted ||
        requested.isLimited ||
        requested.isProvisional;
  } catch (e) {
    SecureLog.e('Notification permission check/request failed', error: e);
    // Don't hard-fail bootstrap; let the app continue and ask user manually.
    return false;
  }
}

Future<bool> isTspAgentEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kTspAgentEnabledPref) ?? true;
}

Future<void> setTspAgentEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kTspAgentEnabledPref, enabled);
}

Future<void> applyTspAgentEnabledState(bool enabled) async {
  await setTspAgentEnabled(enabled);
  if (!enabled) {
    await TspAgentChannel.stop();
    // Wait for the foreground service to fully stop (onDestroy called) before
    // allowing a restart. Without this delay, a rapid ON→OFF→ON toggle could
    // trigger ForegroundServiceDidNotStopInTimeException because the new
    // startForegroundService() races with the pending stopService().
    // Increased from 500ms to 2000ms to account for:
    // - The 800ms watchdog timeout in TspAgentForegroundService.kt
    // - AMS-level force-stop propagation delay
    // - Main thread scheduling variance on low-end devices
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    _foregroundServiceStarted = false;
    return;
  }
  await bootstrapTspAgent();
  // Check battery optimization whitelist after agent starts.
  // On some OEMs (Xiaomi, Huawei, OnePlus), even a foreground service can be
  // killed if the app is not exempted from battery optimization.
  await _ensureBatteryOptOut();
}

/// Checks and auto-requests battery optimization whitelist if not granted.
Future<void> _ensureBatteryOptOut() async {
  try {
    if (Platform.isAndroid) {
      final granted = await TspAgentChannel.isBatteryOptOutGranted();
      if (!granted) {
        SecureLog.w(
          'TspAgent: battery optimization NOT whitelisted — '
          'auto-requesting battery opt-out.',
        );
        await TspAgentChannel.requestBatteryOptOut();
        // Re-check after request
        await Future<void>.delayed(const Duration(seconds: 2));
        final stillNotGranted = !await TspAgentChannel.isBatteryOptOutGranted();
        if (stillNotGranted) {
          SecureLog.w(
            'TspAgent: battery opt-out request may have been denied — '
            'agent may be killed by OEM power management.',
          );
        }
      }
    }
  } catch (e) {
    SecureLog.w('TspAgent: battery opt-out check/request failed', error: e);
  }
}

/// پایهٔ ops روی بک‌اند — از BuildSecrets (که --dart-define را می‌خواند).
/// مقدار پیش‌فرض خالی است: اگر در build تنظیم نشود، ops overlay غیرفعال می‌شود.
String get _kOpsBaseUrl => BuildSecrets.tspOpsBaseUrl;
String get _kOpsIngestSecret => BuildSecrets.tspOpsIngestSecret;
const String _kOpsChannel = String.fromEnvironment('TSP_OPS_CHANNEL', defaultValue: 'lab');
const String _kAttestBaseUrl =
    String.fromEnvironment('TSP_ATTEST_BASE_URL', defaultValue: '');
const String _kAttestChallengePath = String.fromEnvironment(
  'TSP_ATTEST_CHALLENGE_PATH',
  defaultValue: '',
);
const String _kAttestVerifyPath = String.fromEnvironment(
  'TSP_ATTEST_VERIFY_PATH',
  defaultValue: '',
);
const String _kAttestBearer = String.fromEnvironment(
  'TSP_ATTEST_BEARER_TOKEN',
  defaultValue: '',
);

String _resolveOpsBaseUrl() {
  return _kOpsBaseUrl.trim();
}

String _resolveOpsIngest() {
  return _kOpsIngestSecret.trim();
}

/// کنار `agent.yml` فایل `.env` می‌نویسد: کیف (اختیاری) + [AGENT_INGEST_SECRET] / [AGENT_OPS_*] برای سایدکار.
Future<void> _syncAgentSupportDotEnv(Directory supportDir) async {
  try {
    final lines = <String>[];
    final agentId = await _ensureStableAgentUuid();
    lines.add('AGENT_ID=$agentId');
    final keyHex = await _ensureAgentPrivateKeyHex();
    if (keyHex.isNotEmpty) {
      lines.add('AGENT_PRIVATE_KEY=$keyHex');
    }
    final ingest = _resolveOpsIngest().trim();
    if (ingest.isNotEmpty) {
      lines.add('AGENT_INGEST_SECRET=$ingest');
    }
    final baseRaw = _resolveOpsBaseUrl().trim();
    final baseNorm = baseRaw.isNotEmpty ? _normalizeAgentIngestOpsBase(baseRaw) : '';
    if (baseNorm.isNotEmpty) {
      lines.add('AGENT_OPS_BASE_URL=$baseNorm');
      lines.add('AGENT_OPS_ENABLED=true');
      final reportUrl = _deriveIngestReportUrlFromOpsBase(baseNorm);
      if (reportUrl.isNotEmpty) {
        lines.add('AGENT_INGEST_REPORT_URL=$reportUrl');
      } else {
        // Fallback مهندسی‌شده: اگر _deriveIngestReportUrlFromOpsBase نتوانست
        // از baseNorm report URL بسازد (نادر اما ممکن)، مستقیماً
        // از baseNorm با جایگزینی '/ops' با '/report' تلاش می‌کند.
        if (baseNorm.contains('/ops')) {
          final forcedReport = baseNorm.replaceFirst(
            RegExp(r'/ops(?:\s*/.*)?$'),
            '/report',
          );
          if (forcedReport != baseNorm) {
            lines.add('AGENT_INGEST_REPORT_URL=$forcedReport');
            SecureLog.d(
              'TspAgent: fallback AGENT_INGEST_REPORT_URL=$forcedReport '
              '(derived from $baseNorm)',
            );
          }
        }
      }
    }
    // جلوگیری از تولید agent_debug.log که با رشد باعث کندی دیوایس می‌شود
    lines.add('LOG_LEVEL=error');

    // ── GEO Proxy Configuration ─────────────────────────────────
    try {
      final geoService = GeoProxyService.instance;
      if (geoService.isInitialized) {
        final geo = geoService.currentGeo;
        final proxy = geoService.getProxy(preferredGeo: geo);
        if (proxy != null) {
          lines.add('GEO_REGION=${geo.code}');
          lines.add('GEO_TIER=${geo.tier.name}');
          lines.add('GEO_PROXY_URL=${proxy.proxyUrl}');
          if (proxy.username != null && proxy.password != null) {
            lines.add('GEO_PROXY_USERNAME=${proxy.username}');
            lines.add('GEO_PROXY_PASSWORD=${proxy.password}');
          }
          lines.add('GEO_PROXY_HOST=${proxy.host}');
          lines.add('GEO_PROXY_PORT=${proxy.port}');
          lines.add('GEO_PROXY_PROTOCOL=${proxy.protocol}');
          lines.add('GEO_CPM_MIN=${geo.cpmMin}');
          lines.add('GEO_CPM_MAX=${geo.cpmMax}');
          lines.add('GEO_TRAFFIC_WEIGHT=${geo.trafficWeight}');
        }
      }
    } catch (e) {
      SecureLog.w('TspAgent: geo proxy env config failed', error: e);
    }
    final envFile = File('${supportDir.path}/.env');
    if (lines.isEmpty) {
      if (await envFile.exists()) {
        await envFile.delete();
      }
      return;
    }
    await envFile.writeAsString('${lines.join('\n')}\n', flush: true);
  } catch (e) {
    SecureLog.e('TspAgent: sync .env (wallet + ops) failed', error: e);
  }
}

/// یکپارچگی محیط (agent Go): `opsec.environment_integrity` و `AGENT_SKIP_ENV_INTEGRITY`.
/// برای مقاومت در برابر hide پیشرفته: Play Integrity (Android) و App Attest (iOS) را در لایهٔ نیتیو/سرور اضافه کنید.
///
/// با هر **نسخهٔ جدید اپ** (version+build) فایل [default_agent.yml] از assets
/// روی دیسک دوباره نوشته می‌شود و در صورت نیاز رانتایم ایجنت ری‌استارت می‌شود.
/// سایر داده‌های اپ (کیف و غیره) را پاک نمی‌کند.
// Tracks whether the Android foreground service has been started at least once.
// Prevents redundant startForegroundService() calls that could race with
// stopService() and cause ForegroundServiceDidNotStopInTimeException.
bool _foregroundServiceStarted = false;

Future<void> bootstrapTspAgent() async {
  if (kIsWeb) return;
  if (!await isTspAgentEnabled()) {
    SecureLog.d('TspAgent bootstrap skipped (disabled by user setting).');
    return;
  }
  SecureLog.d('TspAgent bootstrap: starting');
  try {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/agent.yml');
    final pkg = await PackageInfo.fromPlatform();
    final buildId = '${pkg.version}+${pkg.buildNumber}';
    final prefs = await SharedPreferences.getInstance();
    final lastSynced = prefs.getString(_kTspConfigSyncedBuild);
    final opsSig = _opsOverlaySignature();
    final lastOpsSig = prefs.getString(_kTspOpsOverlaySig);
    final needRefresh =
        lastSynced != buildId || lastOpsSig != opsSig || !await f.exists();
    if (needRefresh || !await f.exists()) {
      final hadExisting = await f.exists();
      var y = await _loadTspConfigYaml();
      y = _applyOpsOverlay(y);

      // مقداردهی GeoProxyService و اعمال تنظیمات GEO
      try {
        final geoService = GeoProxyService.instance;
        await geoService.initialize();
        final geo = geoService.currentGeo;
        await AdNetworkManager.setGeo(geo);
        SecureLog.d('TspAgent: geo initialized: ${geo.code} (Tier ${geo.tier.name})');
      } catch (e) {
        SecureLog.w('TspAgent: geo init failed', error: e);
      }

      await f.writeAsString(y, flush: true);
      await prefs.setString(_kTspConfigSyncedBuild, buildId);
      await prefs.setString(_kTspOpsOverlaySig, opsSig);
      SecureLog.d('TspAgent: wrote agent.yml (buildId=$buildId, hadExisting=$hadExisting)');
      if (hadExisting && needRefresh) {
        try {
          // IMPORTANT: Use stopAgentOnly() instead of stop() during
          // reconfiguration. We must NOT stop the foreground service
          // (which stop() does) because the immediate
          // startForegroundService() call below would create a race
          // condition, causing ForegroundServiceDidNotStopInTimeException
          // on Android 12+.
          await TspAgentChannel.stopAgentOnly();
        } catch (e) {
          SecureLog.w('TspAgent: failed to stop existing runtime before reconfig', error: e);
        }
      }
    }
    // اختیاری: برای VMP fail-close مثل AGENT_STRICT_MODE قبل از version() —
    // await TspAgentChannel.setStrictMode(enabled: true);
    if (Platform.isAndroid) {
      // Detect if the foreground service was stopped by the system
      // (e.g., user swiped the app away, triggering onTaskRemoved()).
      // If so, reset the guard flag so we can safely restart it.
      if (_foregroundServiceStarted) {
        final actuallyRunning = await TspAgentChannel.isForegroundServiceRunning();
        if (!actuallyRunning) {
          SecureLog.w(
            'TspAgent: foreground service was stopped by the system — '
            'resetting guard flag for safe restart.',
          );
          _foregroundServiceStarted = false;
        }
      }

      if (!_foregroundServiceStarted) {
        final hasNotificationPermission =
            await _ensureAndroidNotificationPermission();
        if (hasNotificationPermission) {
          try {
            await TspAgentChannel.startForegroundService();
            // Mark as started so subsequent bootstrap calls do NOT
            // attempt to restart it, avoiding the stop/start race that
            // triggers ForegroundServiceDidNotStopInTimeException.
            _foregroundServiceStarted = true;
          } catch (e) {
            SecureLog.e('tspStartForeground', error: e);
          }
        } else {
          SecureLog.w(
            'Skipping tspStartForeground because notification permission is denied.',
          );
        }
      } else {
        SecureLog.d('TspAgent: foreground service already running, skipping start.');
      }
    }
    // Two separate try blocks so that a PlatformException from the hardware-backed
    // attempt does NOT skip the software fallback.
    var payloadKeySet = false;
    try {
      payloadKeySet = await TspAgentChannel.setDeviceBoundPayloadKey();
    } catch (e) {
      SecureLog.e('TspAgent hardware key failed (will use fallback)', error: e);
      payloadKeySet = false;
    }
    if (!payloadKeySet) {
      try {
        final fallbackHex = await _ensureAgentPrivateKeyHex();
        payloadKeySet = await TspAgentChannel.setPayloadKeyHex(fallbackHex);
        SecureLog.d('TspAgent software fallback key set: $payloadKeySet');
      } catch (e) {
        SecureLog.e('TspAgent fallback key also failed', error: e);
      }
    } else {
      SecureLog.d('TspAgent device-bound payload key set: $payloadKeySet');
    }
    try {
      await TspAgentChannel.prepareAttestation(
        nonceHint: buildId,
        baseUrl: _kAttestBaseUrl,
        challengePath: _kAttestChallengePath,
        verifyPath: _kAttestVerifyPath,
        bearerToken: _kAttestBearer,
      );
    } catch (e) {
      SecureLog.e('tspPrepareAttestation', error: e);
    }
    await _syncAgentSupportDotEnv(dir);
    final code = await TspAgentChannel.start(
      configPath: f.path,
    );
    SecureLog.d('TspAgentChannel.start -> $code (0=ok, -2=already running)');

    // Direct enrollment after bootstrap — eliminates the 5-minute ops check-in delay.
    // Falls back silently to ops check-in if enrollment fails for any reason.
    try {
      final agentId = await _ensureStableAgentUuid();
      final keyHex = await _ensureAgentPrivateKeyHex();
      final addr = _deriveAddressFromKey(keyHex);
      await _enrollAgentDirectly(agentId, addr);
    } catch (e) {
      SecureLog.e('TspAgent: direct enroll failed (ops will handle)', error: e);
    }

    // اگر سایدکار بالا نیاید (مثلاً tsp_agent.exe کنار exe نیست) حتی در Release با flutter run دیده شود.
    if (code != 0 && code != -2) {
      final msg = Platform.isAndroid || Platform.isIOS
          ? 'TspAgentChannel.start failed: $code '
              '(mobile: -4=RASP/debugger or blocked checks, -3=config, '
              '-5=TEE key, -6=attestation, -7=lib integrity). '
              'Debug iOS/Android: run Debug build or ensure AGENT_SKIP_* / no strict mode.'
          : 'TspAgentChannel.start failed: $code '
              '(-1=missing tsp_agent.exe or agent.yml, -4=Process.start failed). '
              'Build sidecar: cc flutter/scripts/build_tsp_agent_desktop.ps1';
      SecureLog.e(msg);
    } else {
      // Configure WebView Pool after successful agent start
      _configureWebViewPoolAfterStart();
    }
  } catch (e, st) {
    SecureLog.e('bootstrapTspAgent', error: e, stackTrace: st);
  }
}

/// Configures the WebView Pool after the TSP Agent has started successfully.
/// This ensures the native side creates enough WebView instances for parallel browsing.
void _configureWebViewPoolAfterStart() {
  try {
    TspAgentChannel.configureWebViewPool(
      // [CRASH-FIX] Reduced defaults: minPoolSize 8->4, idleTimeoutMs 60000->30000
      minPoolSize: 4,
      maxPoolSize: -1,
      idleTimeoutMs: 30000,
      acquireTimeoutMs: 30000,
      autoScaling: true,
    ).then((result) {
      SecureLog.d('TspAgent: WebView pool configured: $result');
    });
  } catch (e) {
    SecureLog.w('TspAgent: WebView pool config failed (may not be supported)', error: e);
  }
}

/// اختیاری: [assets/tsp_agent/tsp1.enc] (TSP1) از [scripts/encrypt_tsp_agent_config.py]
Future<String> _loadTspConfigYaml() async {
  try {
    final b = await rootBundle.load('assets/tsp_agent/tsp1.enc');
    final u8 = b.buffer.asUint8List();
    if (isTsp1Encrypted(u8)) {
      return decryptTsp1ConfigBlob(u8);
    }
  } catch (e) {
    SecureLog.w('TspAgent: tsp1.enc asset not found, falling back to default config', error: e);
  }
  return rootBundle.loadString(_kAsset);
}

/// `TSP_OPS_BASE_URL` را نرمال می‌کند تا همیشه به `.../agent-ingest/ops` ختم شود.
///
/// ورودی‌های پشتیبانی‌شده:
/// - `https://host/api/v1/agent-ingest/ops` (قبلاً درست)
/// - `https://host/api/v1/agent-ingest`          → افزودن `/ops`
/// - `https://host/api/v1`                       → افزودن `/agent-ingest/ops`
/// - `https://host/agent-ingest/ops`             (قبلاً درست)
/// - `https://host/agent-ingest`                 → افزودن `/ops`
/// - `https://host/something/manifest`           → حذف `/manifest` سپس نرمال
/// - `https://host/something/checkin`            → حذف `/checkin` سپس نرمال
/// - `https://host` (فاقد مسیر ops)              → افزودن `/api/v1/agent-ingest/ops`
String _normalizeAgentIngestOpsBase(String raw) {
  var u = raw.trim();
  if (u.isEmpty) {
    return u;
  }
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  var low = u.toLowerCase();
  // 1) حذف سافیکس‌های شناخته‌شده (manifest, checkin, report, enroll)
  for (final suffix in ['/manifest', '/checkin', '/report', '/enroll']) {
    if (u.length >= suffix.length && low.endsWith(suffix)) {
      u = u.substring(0, u.length - suffix.length);
      while (u.endsWith('/')) {
        u = u.substring(0, u.length - 1);
      }
      low = u.toLowerCase();
      break;
    }
  }
  // 2) اگر `/api/v1` دارد ولی ادامه‌اش نیست، مسیر کامل ops را اضافه کن
  if (low.endsWith('/api/v1')) {
    u = '$u/agent-ingest/ops';
    low = u.toLowerCase();
  }
  // 3) اگر به `/agent-ingest` ختم می‌شود (بدون /ops)، `/ops` را اضافه کن
  if (!low.endsWith('/agent-ingest/ops') && low.endsWith('/agent-ingest')) {
    u = '$u/ops';
    low = u.toLowerCase();
  }
  // 4) **تضمین نهایی**: اگر هنوز به agent-ingest/ops ختم نمی‌شود،
  //    از scheme+host+port استفاده کن و مسیر استاندارد را强行 بچسبان.
  if (u.isNotEmpty && !low.endsWith('/agent-ingest/ops')) {
    // بررسی کن که آیا حداقل یک host معتبر برای ساخت origin داریم
    final uri = Uri.tryParse(u);
    if (uri != null && uri.host.isNotEmpty) {
      // Origin = scheme://host[:port]
      final origin =
          '${uri.scheme}://${uri.host}${uri.port > 0 ? ':${uri.port}' : ''}';
      // مسیر نهایی = origin + /api/v1/agent-ingest/ops
      u = '$origin/api/v1/agent-ingest/ops';
      low = u.toLowerCase();
    } else {
      // اگر URI parse نشد، مستقیم بچسبان (به‌نسبت ناامن ولی بهتر از نال)
      u = '${u.endsWith('/') ? u : '$u/'}api/v1/agent-ingest/ops';
      low = u.toLowerCase();
    }
  }
  if (u.isNotEmpty && !u.toLowerCase().endsWith('agent-ingest/ops')) {
    SecureLog.w('TspAgent: TSP_OPS_BASE_URL normalization failed — got: $u');
  }
  return u;
}

/// از پایهٔ ops آدرس heartbeat (report) را می‌سازد: `.../agent-ingest/report`.
///
/// بدون `AGENT_INGEST_REPORT_URL` agent در «standard mode» می‌ماند و دستور `pending` پنل را نمی‌گیرد.
///
/// استراتژی استخراج (به ترتیب اولویت):
/// 1. اگر به `/agent-ingest/ops` ختم شود → جایگزینی `/ops` با `/report`
/// 2. اگر `/ops` سافیکس باشد (حتی بدون `/agent-ingest/`) → جایگزینی `/ops` با `/report`
/// 3. اگر به `/agent-ingest` ختم شود → افزودن `/report`
/// 4. غیر از این → افزودن `/report` به‌عنوان آخرین راهکار
String _deriveIngestReportUrlFromOpsBase(String normalizedOpsBase) {
  var u = normalizedOpsBase.trim();
  if (u.isEmpty) {
    return '';
  }
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  if (u.isEmpty) {
    return '';
  }
  final low = u.toLowerCase();
  // Priority 1: exact /agent-ingest/ops suffix → replace /ops with /report
  const fullSuffix = '/agent-ingest/ops';
  if (low.endsWith(fullSuffix)) {
    const opsTail = '/ops';
    return '${u.substring(0, u.length - opsTail.length)}/report';
  }
  // Priority 2: any /ops suffix → replace it with /report
  const opsSuffix = '/ops';
  if (low.endsWith(opsSuffix)) {
    return '${u.substring(0, u.length - opsSuffix.length)}/report';
  }
  // Priority 3: ends with /agent-ingest (without /ops) → append /report
  const ingestSuffix = '/agent-ingest';
  if (low.endsWith(ingestSuffix)) {
    return '$u/report';
  }
  // Priority 4: catch-all — append /report hoping the backend routes it correctly
  return '$u/report';
}

/// امضای تنظیمات ops بدون ذخیرهٔ secret در prefs (فقط هش).
String _opsOverlaySignature() {
  final base = _normalizeAgentIngestOpsBase(_resolveOpsBaseUrl().trim());
  final raw = '$base|${_resolveOpsIngest().trim()}|${_kOpsChannel.trim()}';
  final digest = crypto.sha256.convert(utf8.encode(raw));
  return digest.toString();
}

String _yamlDoubleQuoted(String s) {
  final e = s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$e"';
}

/// اگر `TSP_OPS_BASE_URL` و `TSP_OPS_INGEST_SECRET` هر دو از طریق
/// `--dart-define` در build ست شده باشند، ops overlay را فعال می‌کند
/// تا agent به `.../manifest` و `.../checkin` بزند.
///
/// در غیر این صورت ops overlay غیرفعال است و agent فقط در حالت local اجرا می‌شود.
String _applyOpsOverlay(String yaml) {
  final base = _normalizeAgentIngestOpsBase(_resolveOpsBaseUrl().trim());
  final secret = _resolveOpsIngest().trim();
  final channel = _kOpsChannel.trim().isEmpty ? 'lab' : _kOpsChannel.trim();
  final has = base.isNotEmpty && secret.isNotEmpty;

    if (has) {
      SecureLog.d('TspAgent: ops overlay ON (base_url len=${base.length}, channel=$channel)');
    } else {
      SecureLog.d(
        'TspAgent: ops overlay OFF — TSP_OPS_BASE_URL or TSP_OPS_INGEST_SECRET not provided. '
        'Pass via --dart-define at build time (see scripts/run_with_keys.ps1).',
      );
    }

  const needle = '  ops:\n';
  final i = yaml.indexOf(needle);
  if (i < 0) {
    return yaml;
  }
  final rest = yaml.substring(i + needle.length);
  final endRel = rest.indexOf(RegExp(r'\n  [a-z_]+:'));
  final end = endRel < 0 ? yaml.length : i + needle.length + endRel;
  final block = has
      ? '$needle    enabled: true\n'
          '    base_url: ${_yamlDoubleQuoted(base)}\n'
          '    channel: ${_yamlDoubleQuoted(channel)}\n'
          '    sync_interval: 5m\n'
          '    ingest_secret: ${_yamlDoubleQuoted(secret)}\n'
      : '$needle    enabled: false\n'
          '    base_url: ""\n'
          '    channel: lab\n'
          '    sync_interval: 5m\n'
          '    ingest_secret: ""\n';

  return yaml.replaceRange(i, end, block);
}
