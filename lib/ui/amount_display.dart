import 'package:flutter/material.dart';

import '../theme/app_typography.dart';

class AmountDisplay extends StatelessWidget {
  const AmountDisplay({
    super.key,
    required this.amount,
    this.currencySymbol,
    this.style,
    this.animate = true,
  });

  final String amount;
  final String? currencySymbol;
  final TextStyle? style;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = style ??
        AppTypography.balanceStyle(theme.textTheme, theme.colorScheme.onSurface);
    final text = currencySymbol != null ? '$currencySymbol$amount' : amount;
    final child = Text(
      text,
      style: textStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (!animate) return child;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      child: KeyedSubtree(
        key: ValueKey(text),
        child: child,
      ),
    );
  }
}
