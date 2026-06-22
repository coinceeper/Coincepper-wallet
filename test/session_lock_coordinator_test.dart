import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/navigation/route_paths.dart';
import 'package:my_flutter_app/navigation/session_lock_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('does not persist enter passcode as return uri', () async {
    await SessionLockCoordinator.saveReturnUri(RoutePaths.enterPasscode);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('session_lock_return_uri'), isNull);
  });

  test('consumeReturnUri returns saved location once', () async {
    await SessionLockCoordinator.saveReturnUri(RoutePaths.dex);
    expect(await SessionLockCoordinator.consumeReturnUri(), RoutePaths.dex);
    expect(await SessionLockCoordinator.consumeReturnUri(), isNull);
  });
}
