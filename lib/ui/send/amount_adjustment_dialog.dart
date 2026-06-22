import 'package:flutter/material.dart';

/// Dialog shown when the backend auto-adjusts the transaction amount
/// due to insufficient balance to cover network fees.
class AmountAdjustmentDialog extends StatelessWidget {
  final String originalAmount;
  final String adjustedAmount;
  final String symbol;

  const AmountAdjustmentDialog({
    super.key,
    required this.originalAmount,
    required this.adjustedAmount,
    required this.symbol,
  });

  static Future<bool> show({
    required BuildContext context,
    required String originalAmount,
    required String adjustedAmount,
    required String symbol,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AmountAdjustmentDialog(
        originalAmount: originalAmount,
        adjustedAmount: adjustedAmount,
        symbol: symbol,
      ),
    ).then((result) => result ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_fix_high, color: Color(0xFF08C495)),
          SizedBox(width: 8),
          Text('Amount Adjusted'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your balance is insufficient for the requested amount plus network fees.'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF08C495), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info, color: Color(0xFF08C495), size: 16),
                    SizedBox(width: 4),
                    Text('Auto-Adjustment:',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF08C495))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Requested:'),
                    Text('$originalAmount $symbol',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Adjusted to:'),
                    Text('$adjustedAmount $symbol',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF08C495))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('This sends the maximum possible amount after reserving funds for network fees.'),
          const SizedBox(height: 8),
          const Text('Would you like to continue with the adjusted amount?'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF08C495),
            foregroundColor: Colors.white,
          ),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
