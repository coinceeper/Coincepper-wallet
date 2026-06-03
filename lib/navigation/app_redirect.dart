import 'route_paths.dart';
import 'session_lock_coordinator.dart';

/// Testable GoRouter redirect decisions (bootstrap must be complete).
abstract final class AppRedirect {
  static Future<String?> resolve({
    required bool sessionLockRequired,
    required String location,
    required String matched,
    required bool shouldShowPasscodeNow,
  }) async {
    if (sessionLockRequired && matched != RoutePaths.enterPasscode) {
      await SessionLockCoordinator.saveReturnUri(location);
      return RoutePaths.enterPasscode;
    }

    if (shouldShowPasscodeNow &&
        matched != RoutePaths.enterPasscode &&
        !RoutePaths.publicRoutes.contains(matched)) {
      await SessionLockCoordinator.saveReturnUri(location);
      return RoutePaths.enterPasscode;
    }
    return null;
  }
}
