import 'package:flutter/material.dart';

import '../di/service_locator.dart';
import '../services/screen_protection.dart';
import 'route_paths.dart';

class SensitiveRouteObserver extends NavigatorObserver {
  SensitiveRouteObserver._();
  SensitiveRouteObserver();
  static SensitiveRouteObserver get instance => ServiceLocator.get<SensitiveRouteObserver>();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _sync(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _sync(previousRoute);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _sync(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  void _sync(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name != null && RoutePaths.sensitiveRoutes.contains(name)) {
      ScreenProtection.enable();
    } else {
      ScreenProtection.disable();
    }
  }
}
