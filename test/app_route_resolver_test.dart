import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/navigation/route_paths.dart';

void main() {
  test('public routes include onboarding paths', () {
    expect(RoutePaths.publicRoutes, contains(RoutePaths.importCreate));
    expect(RoutePaths.publicRoutes, contains(RoutePaths.enterPasscode));
  });

  test('sensitive routes include import wallet', () {
    expect(RoutePaths.sensitiveRoutes, contains(RoutePaths.importWallet));
  });
}
