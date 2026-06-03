import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../navigation/app_navigation.dart';
import '../navigation/app_shell_scope.dart';
import '../navigation/route_paths.dart';
import '../theme/app_radius.dart';

class AppBottomBar extends StatefulWidget {
  const AppBottomBar({super.key});

  @override
  State<AppBottomBar> createState() => _AppBottomBarState();
}

class _AppBottomBarState extends State<AppBottomBar> {
  bool _isNavigating = false;
  Timer? _debounceTimer;

  // Mapping indices to routes for consistency
  final Map<int, String> _indexToRoute = {
    0: RoutePaths.home,
    1: RoutePaths.panel,
    3: RoutePaths.settings,
  };

  int _getCurrentIndex(BuildContext context, AppShellScope? shell) {
    if (shell != null) {
      final shellIndex = shell.shell.currentIndex;
      // Adjust shell index to bottom bar index (skip index 2 which is the scanner)
      return shellIndex >= 2 ? shellIndex + 1 : shellIndex;
    }
    
    final routeName = ModalRoute.of(context)?.settings.name;
    return _indexForRoute(routeName);
  }

  int _indexForRoute(String? routeName) {
    if (routeName == RoutePaths.home) return 0;
    if (routeName == RoutePaths.panel) return 1;
    if (routeName == RoutePaths.settings) return 3;
    return 0;
  }

  void _onDestinationSelected(int index) {
    if (_isNavigating) return;
    
    HapticFeedback.selectionClick();

    if (index == 2) {
      _openScanner();
      return;
    }

    final shell = AppShellScope.maybeOf(context);
    if (shell != null) {
      final branchIndex = index > 2 ? index - 1 : index;
      if (shell.shell.currentIndex != branchIndex) {
        shell.shell.goBranch(branchIndex);
      }
      return;
    }

    final route = _indexToRoute[index];
    if (route != null) {
      _navigateTo(route);
    }
  }

  void _navigateTo(String routeName) async {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    if (currentRoute == routeName) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () async {
      if (!mounted) return;
      setState(() => _isNavigating = true);
      try {
        await AppNavigation.pushReplacementNamed(context, routeName);
      } finally {
        if (mounted) setState(() => _isNavigating = false);
      }
    });
  }

  Future<void> _openScanner() async {
    setState(() => _isNavigating = true);
    try {
      final result = await AppNavigation.pushNamed(context, '/qr-scanner');
      if (result != null && result is String && result.isNotEmpty && mounted) {
        await Clipboard.setData(ClipboardData(text: result));
        // Note: Using tr() here as well if needed
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('menu.copied_to_clipboard'.tr()))
        );
      }
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shell = AppShellScope.maybeOf(context);
    final selectedIndex = _getCurrentIndex(context, shell);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.topLg,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 16,
            spreadRadius: 0,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
              _buildNavItem(
                index: 0,
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: 'menu.home'.tr(),
                isSelected: selectedIndex == 0,
                scheme: scheme,
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.hub_outlined,
                activeIcon: Icons.hub_rounded,
                label: 'menu.panel'.tr(),
                isSelected: selectedIndex == 1,
                scheme: scheme,
              ),
              _buildNavItem(
                index: 2,
                icon: Icons.qr_code_scanner_rounded,
                activeIcon: Icons.qr_code_scanner_rounded,
                label: 'menu.scan'.tr(),
                isSelected: selectedIndex == 2,
                scheme: scheme,
              ),
              _buildNavItem(
                index: 3,
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings_rounded,
                label: 'menu.settings'.tr(),
                isSelected: selectedIndex == 3,
                scheme: scheme,
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isSelected,
    required ColorScheme scheme,
  }) {
    return Expanded(
      child: InkResponse(
        onTap: () => _onDestinationSelected(index),
        highlightColor: Colors.transparent,
        splashColor: scheme.primary.withValues(alpha: 0.1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? scheme.primary.withValues(alpha: 0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Drop-in replacement for layout/bottom_menu_with_siri.dart
class BottomMenuWithSiri extends StatelessWidget {
  const BottomMenuWithSiri({super.key});

  @override
  Widget build(BuildContext context) => const AppBottomBar();
}
