import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Imperative navigation compatible with [GoRouter] route paths.
abstract final class AppNavigation {
  static Future<T?> pushNamed<T extends Object?>(
    BuildContext context,
    String name, {
    Object? arguments,
  }) {
    if (arguments != null) {
      return context.push<T>(name, extra: arguments);
    }
    return context.push<T>(name);
  }

  static Future<T?> pushReplacementNamed<T extends Object?>(
    BuildContext context,
    String name, {
    Object? arguments,
  }) async {
    if (arguments != null) {
      context.replace(name, extra: arguments);
    } else {
      context.replace(name);
    }
    return null;
  }

  static void pushNamedAndRemoveUntil(
    BuildContext context,
    String name,
    bool Function(Route<dynamic>) predicate, {
    Object? arguments,
  }) {
    if (arguments != null) {
      context.go(name, extra: arguments);
    } else {
      context.go(name);
    }
  }
}
