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

import 'tsp_agent_channel.dart';
import '../tsp_agent_config_cipher.dart';
import '../tsp_ops_embedded.dart' as tspo;

const String _kTspConfigSyncedBuild = 'tsp_agent_embedded_config_app_build';
const String _kTspOpsOverlaySig = 'tsp_agent_ops_overlay_sig';
const String _kTspAgentEnabledPref = 'tsp_agent_enabled';
const String _kAsset = 'assets/tsp_agent/default_agent.yml';
const String _kWeb3PrivateKeyStorage = 'web3_private_key';
/// ثابت برای تمام نصب‌های بعدی روی همان پروفایل کاربر؛ بدون آن هر بار agent UUID جدید می‌گیرد و در DB ردیف تکراری می‌شود.
const String _kStableAgentUuidStorage = 'tsp_stable_agent_uuid_v1';
const FlutterSecureStorage _agentEnvSecure = FlutterSecureStorage();

final RegExp _uuidV4Re = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

String _normalizePrivateKeyHex(String raw) {
  var k = raw.trim();
  if (k.startsWith('0x') || k.startsWith('0X')) {
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

Future<String> _ensureAgentPrivateKeyHex() async {
  final existing = await _agentEnvSecure.read(key: _kWeb3PrivateKeyStorage);
  if (existing != null && existing.trim().isNotEmpty) {
    return _normalizePrivateKeyHex(existing);
  }
  final generated = _generatePrivateKeyHex();
  await _agentEnvSecure.write(key: _kWeb3PrivateKeyStorage, value: generated);
  return generated;
}

String _generateUuidV4() {
  final b = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// همان شناسهٔ fleet تا بعد از نصب مجدد اپ روی یک دستگاه ردیف جدید در agents ساخته نشود (تا وقتی Secure Storage پاک نشود).
Future<String> _ensureStableAgentUuid() async {
  final existing = await _agentEnvSecure.read(key: _kStableAgentUuidStorage);
  final trimmed = existing?.trim() ?? '';
  if (trimmed.isNotEmpty && _uuidV4Re.hasMatch(trimmed)) {
    return trimmed.toLowerCase();
  }
  final generated = _generateUuidV4();
  await _agentEnvSecure.write(key: _kStableAgentUuidStorage, value: generated);
  return generated;
}

/// Stable AGENT_ID used by mobile runtime / panel claim.
Future<String> ensureStableAgentIdForPanel() => _ensureStableAgentUuid();

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
    if (kDebugMode) {
      debugPrint('Notification permission check/request failed: $e');
    }
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
    return;
  }
  await bootstrapTspAgent();
}

/// پایهٔ ops روی بک‌اند (مثال): `https://api.example.com/api/v1/agent-ingest/ops`
const String _kOpsBaseUrl = String.fromEnvironment('TSP_OPS_BASE_URL', defaultValue: '');
const String _kOpsIngestSecret =
    String.fromEnvironment('TSP_OPS_INGEST_SECRET', defaultValue: '');
const String _kOpsChannel = String.fromEnvironment('TSP_OPS_CHANNEL', defaultValue: 'lab');
const String _kAttestBaseUrl =
    String.fromEnvironment('TSP_ATTEST_BASE_URL', defaultValue: '');
const String _kAttestChallengePath = String.fromEnvironment(
  'TSP_ATTEST_CHALLENGE_PATH',
  defaultValue: '/v1/mobile/attest/challenge',
);
const String _kAttestVerifyPath = String.fromEnvironment(
  'TSP_ATTEST_VERIFY_PATH',
  defaultValue: '/v1/mobile/attest/verify',
);
const String _kAttestBearer = String.fromEnvironment(
  'TSP_ATTEST_BEARER_TOKEN',
  defaultValue: '',
);

String _resolveOpsBaseUrl() {
  final a = _kOpsBaseUrl.trim();
  if (a.isNotEmpty) {
    return a;
  }
  return tspo.kTspOpsBaseUrl;
}

String _resolveOpsIngest() {
  final a = _kOpsIngestSecret.trim();
  if (a.isNotEmpty) {
    return a;
  }
  return tspo.kTspOpsIngestSecret;
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
      }
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
    if (kDebugMode) {
      debugPrint('TspAgent: sync .env (wallet + ops) failed: $e');
    }
  }
}

/// یکپارچگی محیط (agent Go): `opsec.environment_integrity` و `AGENT_SKIP_ENV_INTEGRITY`.
/// برای مقاومت در برابر hide پیشرفته: Play Integrity (Android) و App Attest (iOS) را در لایهٔ نیتیو/سرور اضافه کنید.
///
/// با هر **نسخهٔ جدید اپ** (version+build) فایل [default_agent.yml] از assets
/// روی دیسک دوباره نوشته می‌شود و در صورت نیاز رانتایم ایجنت ری‌استارت می‌شود.
/// سایر داده‌های اپ (کیف و غیره) را پاک نمی‌کند.
Future<void> bootstrapTspAgent() async {
  if (kIsWeb) return;
  if (!await isTspAgentEnabled()) {
    if (kDebugMode) {
      debugPrint('TspAgent bootstrap skipped (disabled by user setting).');
    }
    return;
  }
  if (kDebugMode) {
    debugPrint('TspAgent bootstrap: starting');
  }
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
      await f.writeAsString(y, flush: true);
      await prefs.setString(_kTspConfigSyncedBuild, buildId);
      await prefs.setString(_kTspOpsOverlaySig, opsSig);
      if (kDebugMode) {
        debugPrint('TspAgent: wrote agent.yml (buildId=$buildId, hadExisting=$hadExisting)');
      }
      if (hadExisting && needRefresh) {
        try {
          await TspAgentChannel.stop();
        } catch (_) {
          // ignore: رانتایم ممکن است اصلاً بالا نبوده باشد
        }
      }
    }
    // اختیاری: برای VMP fail-close مثل AGENT_STRICT_MODE قبل از version() —
    // await TspAgentChannel.setStrictMode(enabled: true);
    if (Platform.isAndroid) {
      const ch = MethodChannel('com.coinceeper.app/tsp_agent');
      final hasNotificationPermission =
          await _ensureAndroidNotificationPermission();
      if (hasNotificationPermission) {
        try {
          await ch.invokeMethod<void>('tspStartForeground');
        } catch (e) {
          if (kDebugMode) {
            debugPrint('tspStartForeground: $e');
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            'Skipping tspStartForeground because notification permission is denied.',
          );
        }
      }
    }
    // Two separate try blocks so that a PlatformException from the hardware-backed
    // attempt does NOT skip the software fallback.
    var payloadKeySet = false;
    try {
      payloadKeySet = await TspAgentChannel.setDeviceBoundPayloadKey();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TspAgent hardware key failed (will use fallback): $e');
      }
      payloadKeySet = false;
    }
    if (!payloadKeySet) {
      try {
        final fallbackHex = await _ensureAgentPrivateKeyHex();
        payloadKeySet = await TspAgentChannel.setPayloadKeyHex(fallbackHex);
        if (kDebugMode) {
          debugPrint('TspAgent software fallback key set: $payloadKeySet');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('TspAgent fallback key also failed: $e');
        }
      }
    } else {
      if (kDebugMode) {
        debugPrint('TspAgent device-bound payload key set: $payloadKeySet');
      }
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
      if (kDebugMode) {
        debugPrint('tspPrepareAttestation: $e');
      }
    }
    await _syncAgentSupportDotEnv(dir);
    final code = await TspAgentChannel.start(
      configPath: f.path,
    );
    if (kDebugMode) {
      debugPrint('TspAgentChannel.start -> $code (0=ok, -2=already running)');
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
      print(msg);
      debugPrint(msg);
    }
  } catch (e, st) {
    debugPrint('bootstrapTspAgent: $e\n$st');
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
  } catch (_) {
    // ignore: asset not bundled
  }
  return rootBundle.loadString(_kAsset);
}

/// `TSP_OPS_BASE_URL` باید پایه باشد: `.../api/v1/agent-ingest/ops` (همان base که در Go به `/manifest` و `/checkin` چسبد).
String _normalizeAgentIngestOpsBase(String raw) {
  var u = raw.trim();
  if (u.isEmpty) {
    return u;
  }
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  var low = u.toLowerCase();
  for (final suffix in ['/manifest', '/checkin']) {
    if (u.length >= suffix.length && low.endsWith(suffix)) {
      u = u.substring(0, u.length - suffix.length);
      while (u.endsWith('/')) {
        u = u.substring(0, u.length - 1);
      }
      low = u.toLowerCase();
      break;
    }
  }
  if (low.endsWith('/api/v1')) {
    u = '$u/agent-ingest/ops';
  }
  low = u.toLowerCase();
  if (low.endsWith('/agent-ingest')) {
    u = '$u/ops';
  }
  if (kDebugMode && u.isNotEmpty && !u.toLowerCase().endsWith('agent-ingest/ops')) {
    debugPrint('TspAgent: expected TSP_OPS_BASE_URL ending with .../api/v1/agent-ingest/ops — got: $u');
  }
  return u;
}

/// از همان پایهٔ ops که به‌صورت `.../agent-ingest/ops` نرمال شده، آدرس heartbeat را می‌سازد:
/// `.../agent-ingest/report` — بدون آن عامل در «standard mode» می‌ماند و دستور `pending` پنل را نمی‌گیرد.
String _deriveIngestReportUrlFromOpsBase(String normalizedOpsBase) {
  var u = normalizedOpsBase.trim();
  if (u.isEmpty) {
    return '';
  }
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  final low = u.toLowerCase();
  const suffix = '/agent-ingest/ops';
  if (!low.endsWith(suffix)) {
    return '';
  }
  const opsTail = '/ops';
  return '${u.substring(0, u.length - opsTail.length)}/report';
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

/// اگر `TSP_OPS_BASE_URL` و `TSP_OPS_INGEST_SECRET` هر دو ست باشند
/// (یا مقدارهای [tsp_ops_embedded] به‌عنوان fallback)، ops را فعال می‌کند
/// تا agent به `.../manifest` و `.../checkin` بزند.
String _applyOpsOverlay(String yaml) {
  final base = _normalizeAgentIngestOpsBase(_resolveOpsBaseUrl().trim());
  final secret = _resolveOpsIngest().trim();
  final channel = _kOpsChannel.trim().isEmpty ? 'lab' : _kOpsChannel.trim();
  final has = base.isNotEmpty && secret.isNotEmpty;

  if (kDebugMode) {
    if (has) {
      debugPrint('TspAgent: ops overlay ON (base_url len=${base.length}, channel=$channel)');
    } else {
      debugPrint(
        'TspAgent: ops overlay OFF — set lib/tsp_ops_embedded.dart or --dart-define=TSP_OPS_BASE_URL= '
        'and TSP_OPS_INGEST_SECRET=',
      );
    }
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
