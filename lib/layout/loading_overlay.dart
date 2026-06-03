import 'package:flutter/material.dart';


class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  const LoadingOverlay({super.key, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    if (!isLoading) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface.withValues(alpha: 0.85),
      child: Center(
        child: CircularProgressIndicator(color: scheme.primary),
      ),
    );
  }
} 