import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../layout/bottom_menu_with_siri.dart';
import 'app_shell_scope.dart';

/// Tab shell: single bottom menu + branch content.
class AppShellScaffold extends StatelessWidget {
  const AppShellScaffold({
    super.key,
    required this.navigationShell,
  });

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return AppShellScope(
      shell: navigationShell,
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: const BottomMenuWithSiri(),
      ),
    );
  }
}
