import 'package:flutter/material.dart';
import '../../navigation/app_navigation.dart';
import '../../navigation/route_paths.dart';

/// Dialog shown when a Tatum API broadcast error occurs.
///
/// Gives the user options: OK, Retry broadcast, or Try a different network.
class TatumErrorDialog extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  const TatumErrorDialog({
    super.key,
    required this.errorMessage,
    required this.onRetry,
    required this.onDismiss,
  });

  static Future<void> show({
    required BuildContext context,
    required String errorMessage,
    required VoidCallback onRetry,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => TatumErrorDialog(
        errorMessage: errorMessage,
        onRetry: onRetry,
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.orange),
          SizedBox(width: 8),
          Text('Network Issue'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('The blockchain network is currently experiencing technical difficulties.'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.primary, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info, color: scheme.primary, size: 16),
                    const SizedBox(width: 4),
                    Text('Important:',
                        style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('• Your funds are completely safe', style: TextStyle(color: scheme.primary)),
                Text('• If already submitted, the tx will confirm automatically',
                    style: TextStyle(color: scheme.primary)),
                Text('• Retry only re-broadcasts — no re-signing required',
                    style: TextStyle(color: scheme.primary)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('You can:'),
          const SizedBox(height: 8),
          const Text('• Wait a few minutes and try again'),
          const Text('• Use a different blockchain (BSC, TRON)'),
          const Text('• Contact support if the problem persists'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onDismiss,
          child: const Text('OK'),
        ),
        TextButton(
          onPressed: () {
            onDismiss();
            Future.delayed(const Duration(seconds: 2), onRetry);
          },
          child: const Text('Retry'),
        ),
        TextButton(
          onPressed: () {
            onDismiss();
            AppNavigation.pushReplacementNamed(context, RoutePaths.home);
          },
          child: const Text('Try Different Network'),
        ),
      ],
    );
  }
}
