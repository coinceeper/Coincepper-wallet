import 'package:flutter/material.dart';

/// A standardized inline error state widget for screens.
///
/// Use this when a screen wants to show an error state inline (within the
/// screen body) instead of or in addition to the global error modal.
///
/// Unlike the centralized [GlobalErrorListener] which shows a modal overlay,
/// this widget is placed directly inside a screen's widget tree.
class ErrorStateWidget extends StatelessWidget {
  final String message;
  final String? title;
  final IconData icon;
  final Color? iconColor;
  final VoidCallback? onRetry;
  final String? retryLabel;

  const ErrorStateWidget({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.error_outline,
    this.iconColor,
    this.onRetry,
    this.retryLabel,
  });

  factory ErrorStateWidget.network({
    VoidCallback? onRetry,
  }) {
    return ErrorStateWidget(
      icon: Icons.wifi_off_rounded,
      title: 'Connection Error',
      message: 'Unable to connect to the server. Please check your internet connection.',
      onRetry: onRetry,
      retryLabel: 'Try Again',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? scheme.error;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: effectiveIconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: effectiveIconColor),
            ),
            const SizedBox(height: 24),
            if (title != null) ...[
              Text(
                title!,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
            Text(
              message,
              style: TextStyle(
                fontSize: 16,
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 20),
                  label: Text(retryLabel ?? 'Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF08C495),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
