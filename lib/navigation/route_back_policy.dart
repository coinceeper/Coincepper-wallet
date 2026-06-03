import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'route_paths.dart';

/// Central back-button behavior for [PopScope].
abstract final class RouteBackPolicy {
  static bool canPop(String matchedLocation) {
    switch (matchedLocation) {
      case RoutePaths.importCreate:
      case RoutePaths.createNewWallet:
      case RoutePaths.importWallet:
        return false;
      case RoutePaths.home:
        return false;
      default:
        return true;
    }
  }

  static void onPopInvoked(String matchedLocation, bool didPop) {
    if (didPop) return;
    if (matchedLocation == RoutePaths.home) {
      SystemNavigator.pop();
    }
  }
}

/// Wraps [child] with platform back policy for [matchedLocation].
class RouteBackScope extends StatelessWidget {
  const RouteBackScope({
    super.key,
    required this.matchedLocation,
    required this.child,
  });

  final String matchedLocation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: RouteBackPolicy.canPop(matchedLocation),
      onPopInvokedWithResult: (didPop, result) {
        RouteBackPolicy.onPopInvoked(matchedLocation, didPop);
      },
      child: child,
    );
  }
}
