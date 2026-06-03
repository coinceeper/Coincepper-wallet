import 'package:flutter/material.dart';

import '../models/chart_models.dart';
import 'beautiful_crypto_chart.dart';
import 'interactive_crypto_chart.dart';
import 'simple_price_chart.dart';

enum CryptoChartMode {
  /// Full chart with API data ([BeautifulCryptoChart]).
  interactive,
  /// Touch + fl_chart ([InteractiveCryptoChart]).
  detailed,
  /// Generated trend from current price ([SimplePriceChart]).
  simple,
}

/// Unified chart entry point for the app.
class CryptoChart extends StatelessWidget {
  const CryptoChart({
    super.key,
    required this.symbol,
    this.mode = CryptoChartMode.interactive,
    this.height = 300,
    this.primaryColor,
    this.backgroundColor,
    this.showTimeframeSelector = true,
    this.initialTimeframe = '1d',
    this.fiatCurrency = 'USD',
    this.onPointSelected,
    this.onPointDeselected,
  });

  final String symbol;
  final CryptoChartMode mode;
  final double height;
  final Color? primaryColor;
  final Color? backgroundColor;
  final bool showTimeframeSelector;
  final String initialTimeframe;
  final String fiatCurrency;
  final void Function(ChartDataPoint? point, bool isPriceDown)? onPointSelected;
  final VoidCallback? onPointDeselected;

  @override
  Widget build(BuildContext context) {
    final primary =
        primaryColor ?? Theme.of(context).colorScheme.primary;
    final bg = backgroundColor ?? Theme.of(context).colorScheme.surface;

    switch (mode) {
      case CryptoChartMode.interactive:
        return BeautifulCryptoChart(
          symbol: symbol,
          height: height,
          primaryColor: primary,
          backgroundColor: bg,
          showTimeframeSelector: showTimeframeSelector,
          initialTimeframe: initialTimeframe,
          onPointSelected: onPointSelected,
          onPointDeselected: onPointDeselected,
        );
      case CryptoChartMode.detailed:
        return InteractiveCryptoChart(
          symbol: symbol,
          fiatCurrency: fiatCurrency,
          height: height,
          primaryColor: primary,
        );
      case CryptoChartMode.simple:
        return SimplePriceChart(
          symbol: symbol,
          height: height,
          primaryColor: primary,
        );
    }
  }
}
