import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

const _kStorageKey = 'coinceeper_tsp_payload_key_hex_v1';

/// Windows, macOS, Linux — spawns [tsp_agent] next to the Flutter executable.
bool get isTspDesktopHost =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

int _strictMode = 0;
Process? _sidecar;
bool _exiting = false;

const FlutterSecureStorage _secure = FlutterSecureStorage();

String _defaultStatePath(String configPath) {
  return p.join(p.dirname(configPath), 'agent.state.json');
}

String? _resolveTspAgentBinary() {
  final fromEnv = Platform.environment['TSP_AGENT_DESKTOP_BINARY']?.trim();
  if (fromEnv != null && fromEnv.isNotEmpty && File(fromEnv).existsSync()) {
    return fromEnv;
  }
  final exe = Platform.resolvedExecutable;
  // macOS bundle: .../App.app/Contents/MacOS/App  —  sidecar در همان MacOS
  final d = p.dirname(exe);
  if (Platform.isMacOS) {
    for (final n in <String>['tsp_agent', 'TspAgent']) {
      final t = p.join(d, n);
      if (File(t).existsSync()) {
        return t;
      }
    }
  } else if (Platform.isWindows) {
    for (final n in <String>['tsp_agent.exe', 'TspAgent.exe', 'tsp_agent']) {
      final t = p.join(d, n);
      if (File(t).existsSync()) {
        return t;
      }
    }
  } else {
    for (final n in <String>['tsp_agent', 'TspAgent']) {
      final t = p.join(d, n);
      if (File(t).existsSync()) {
        return t;
      }
    }
  }
  if (kDebugMode) {
    debugPrint('TspDesktop: no tsp_agent found near $exe (set TSP_AGENT_DESKTOP_BINARY)');
  }
  return null;
}

Future<ProcessResult?> _runTspInfoArg(String arg) async {
  final bin = _resolveTspAgentBinary();
  if (bin == null) {
    return null;
  }
  String? k;
  try {
    k = await _getOrCreatePayloadKeyHex();
  } catch (_) {
    k = null;
  }
  try {
    return await Process.run(
      bin,
      [arg],
      environment: _sidecarEnv(extraPayloadHex: k),
      workingDirectory: p.dirname(bin),
    );
  } catch (e) {
    if (kDebugMode) {
      debugPrint('TspDesktop info $arg: $e');
    }
    return null;
  }
}

Map<String, String> _sidecarEnv({
  String? extraPayloadHex,
  Map<String, String>? agentSecrets,
}) {
  final m = <String, String>{...Platform.environment};
  m['AGENT_STRICT_MODE'] = _strictMode != 0 ? '1' : '0';
  m.remove('AGENT_DESKTOP_STRICT');
  m['AGENT_SKIP_ENV_INTEGRITY'] = '1';
  if (extraPayloadHex != null && extraPayloadHex.isNotEmpty) {
    m['PAYLOAD_ENCRYPTION_KEY'] = extraPayloadHex;
  }
  if (agentSecrets != null) {
    for (final e in agentSecrets.entries) {
      final v = e.value.trim();
      if (v.isNotEmpty) {
        m[e.key] = v;
      }
    }
  }
  return m;
}

Future<String?> _getOrCreatePayloadKeyHex() async {
  var h = await _secure.read(key: _kStorageKey);
  if (h == null || h.isEmpty) {
    final b = _random32();
    h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    await _secure.write(key: _kStorageKey, value: h);
  }
  return h;
}

List<int> _random32() {
  // Small embedded RNG — prefer crypto; keep dependency minimal
  final t = DateTime.now().microsecondsSinceEpoch;
  final raw = utf8.encode('$_kStorageKey|${Platform.operatingSystem}|$t');
  final d = crypto.sha256.convert(raw).bytes;
  return d.sublist(0, 32);
}

Future<int> tspDesktopSetStrictMode(int v) async {
  _strictMode = v;
  return 0;
}

Future<void> tspDesktopPrepareAttestation({
  String nonceHint = '',
  String baseUrl = '',
  String challengePath = '',
  String verifyPath = '',
  String bearerToken = '',
}) async {
  // Desktop: no Play Integrity / App Attest.
}

Future<String> tspDesktopVersion() async {
  if (_sidecar != null) {
    final r = await _runTspInfoArg('-tspInfo=version');
    if (r != null && (r.exitCode == 0)) {
      return (r.stdout as String).trim();
    }
  }
  final r = await _runTspInfoArg('-tspInfo=version');
  if (r != null && (r.exitCode == 0)) {
    return (r.stdout as String).trim();
  }
  if (_resolveTspAgentBinary() == null) {
    return 'desktop:binary-missing';
  }
  return 'desktop:unknown';
}

Future<String> tspDesktopHealthJson() async {
  if (_sidecar != null) {
    final r = await _runTspInfoArg('-tspInfo=health');
    if (r != null && (r.exitCode == 0)) {
      return (r.stdout as String).trim();
    }
  }
  if (_exiting) {
    return jsonEncode({'\$desktop': 'stopping'});
  }
  if (_sidecar != null) {
    return jsonEncode({
      '\$desktop': 'sidecar',
      'pid': _sidecar?.pid,
      'running': true,
    });
  }
  return jsonEncode({'\$desktop': 'idle', 'sidecar': false});
}

Future<String> tspDesktopFingerprint() async {
  if (_sidecar == null) {
    final b = _resolveTspAgentBinary() ?? 'none';
    return crypto.sha1.convert(utf8.encode('desktop|$b')).toString();
  }
  return crypto.sha1.convert(utf8.encode('desktop|pid=${_sidecar?.pid}')).toString();
}

void _pipeSidecarLogs(Process proc) {
  proc.stderr.transform(const Utf8Decoder()).listen((chunk) {
    final t = chunk.trimRight();
    if (t.isEmpty) return;
    print('tsp_agent stderr: $t');
  });
}

/// 0=ok, -1=missing path/binary, -2=running, -4=start failed, -5=exited immediately (config/dyld)
Future<int> tspDesktopStart({
  required String configPath,
  String? statePath,
  Map<String, String>? processEnv,
}) async {
  if (_sidecar != null) {
    return -2;
  }
  if (!File(configPath).existsSync()) {
    return -1;
  }
  final bin = _resolveTspAgentBinary();
  if (bin == null) {
    if (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      print(
        'TspDesktop: tsp_agent not found next to ${Platform.resolvedExecutable} — reinstall app bundle with sidecar.',
      );
    }
    return -1;
  }
  final st = statePath ?? _defaultStatePath(configPath);
  String? k;
  try {
    k = await _getOrCreatePayloadKeyHex();
  } catch (_) {
    k = null;
  }
  final args = <String>['-config', configPath, '-state', st];
  Process proc;
  try {
    _exiting = false;
    proc = await Process.start(
      bin,
      args,
      environment: _sidecarEnv(
        extraPayloadHex: k,
        agentSecrets: processEnv,
      ),
      workingDirectory: p.dirname(configPath),
      mode: ProcessStartMode.normal,
    );
    _sidecar = proc;
    _pipeSidecarLogs(proc);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('TspDesktop: Process.start failed: $e');
    }
    if (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      print('TspDesktop: Process.start failed: $e');
    }
    return -4;
  }

  const stillRunning = -1000;
  final early = await proc.exitCode.timeout(
    const Duration(milliseconds: 900),
    onTimeout: () => stillRunning,
  );
  if (early != stillRunning) {
    print(
      'tsp_agent exited within ~1s: exitCode=$early (see tsp_agent stderr above — often config/key or dyld).',
    );
    _sidecar = null;
    return -5;
  }

  proc.exitCode.then((code) {
    _exiting = false;
    _sidecar = null;
    if (code != 0) {
      print('tsp_agent exited: code=$code (check config/key/ops URL)');
    }
    if (kDebugMode) {
      debugPrint('TspDesktop: sidecar exited with $code');
    }
  });
  if (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
    print('TspDesktop: sidecar pid=${proc.pid} (running)');
  }
  return 0;
}

Future<bool> tspDesktopSetDeviceKey() async {
  try {
    await _getOrCreatePayloadKeyHex();
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> tspDesktopStop() async {
  _exiting = true;
  final s = _sidecar;
  if (s != null) {
    _sidecar = null;
    try {
      s.kill();
    } catch (_) {}
  }
}

Future<bool> tspDesktopIsRunning() async {
  return _sidecar != null;
}
