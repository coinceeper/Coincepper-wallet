import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/navigation/app_redirect.dart';
import 'package:my_flutter_app/navigation/route_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('session lock redirects to enter passcode and saves return uri', () async {
    final redirect = await AppRedirect.resolve(
      sessionLockRequired: true,
      location: '${RoutePaths.home}?tab=1',
      matched: RoutePaths.home,
      shouldShowPasscodeNow: false,
    );
    expect(redirect, RoutePaths.enterPasscode);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('session_lock_return_uri'), '${RoutePaths.home}?tab=1');
  });

  test('auto passcode lock skips public routes', () async {
    final redirect = await AppRedirect.resolve(
      sessionLockRequired: false,
      location: RoutePaths.importCreate,
      matched: RoutePaths.importCreate,
      shouldShowPasscodeNow: true,
    );
    expect(redirect, isNull);
  });

  test('auto passcode lock redirects protected routes', () async {
    final redirect = await AppRedirect.resolve(
      sessionLockRequired: false,
      location: RoutePaths.settings,
      matched: RoutePaths.settings,
      shouldShowPasscodeNow: true,
    );
    expect(redirect, RoutePaths.enterPasscode);
  });

  test('no redirect when unlocked and passcode not required', () async {
    final redirect = await AppRedirect.resolve(
      sessionLockRequired: false,
      location: RoutePaths.panel,
      matched: RoutePaths.panel,
      shouldShowPasscodeNow: false,
    );
    expect(redirect, isNull);
  });
}
