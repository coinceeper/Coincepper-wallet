import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Provides [StatefulNavigationShell] to [BottomMenuWithSiri].
class AppShellScope extends InheritedWidget {
  const AppShellScope({
    super.key,
    required this.shell,
    required super.child,
  });

  final StatefulNavigationShell shell;

  static AppShellScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppShellScope>();
  }

  @override
  bool updateShouldNotify(AppShellScope oldWidget) =>
      oldWidget.shell != shell;
}
