/// Web stub — no TSP sidecar.
bool get isTspDesktopHost => false;

Future<int> tspDesktopSetStrictMode(int v) async => 0;
Future<void> tspDesktopPrepareAttestation({
  String nonceHint = '',
  String baseUrl = '',
  String challengePath = '',
  String verifyPath = '',
  String bearerToken = '',
}) async {}
Future<String> tspDesktopVersion() async => '';
Future<String> tspDesktopHealthJson() async => '';
Future<String> tspDesktopFingerprint() async => '';
Future<int> tspDesktopStart({
  required String configPath,
  String? statePath,
  Map<String, String>? processEnv,
}) async {
  return -1;
}
Future<bool> tspDesktopSetDeviceKey() async => false;
Future<void> tspDesktopStop() async {}
Future<bool> tspDesktopIsRunning() async => false;
