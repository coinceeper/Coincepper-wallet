import 'package:flutter/material.dart';
import 'bottom_menu_with_siri.dart';
import '../navigation/app_shell_scope.dart';

class MainLayout extends StatelessWidget {
  final Widget child;
  const MainLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (AppShellScope.maybeOf(context) != null) {
      return child;
    }
    return Stack(
      children: [
        child,
        const Align(
          alignment: Alignment.bottomCenter,
          child: BottomMenuWithSiri(),
        ),
      ],
    );
  }
}
