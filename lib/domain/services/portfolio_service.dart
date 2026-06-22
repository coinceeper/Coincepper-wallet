import '../../models/crypto_token.dart';
import '../interfaces/price_query.dart';

/// Pure portfolio calculation logic.
///
/// This service is stateless — all data is passed as parameters.
/// It depends on the [IPriceQuery] interface instead of directly
/// importing presentation-layer providers (Clean Architecture).
class PortfolioService {
  const PortfolioService();

  /// Calculate the total fiat value of all [tokens].
  ///
  /// Each token's value = `token.amount * price`.
  double calculateTotalValue({
    required List<CryptoToken> tokens,
    required IPriceQuery priceQuery,
  }) {
    double total = 0;
    for (final token in tokens) {
      final price = priceQuery.getPrice(token.symbol ?? '') ?? 0.0;
      total += token.amount * price;
    }
    return total;
  }

  /// Get the fiat price for a single token symbol.
  double getTokenPrice(IPriceQuery priceQuery, String symbol) {
    return priceQuery.getPrice(symbol) ?? 0.0;
  }

  /// Format a numeric value for display.
  String formatValue(double value) {
    if (value < 0.01) return value.toStringAsFixed(4);
    if (value < 1000) return value.toStringAsFixed(2);
    if (value < 1000000) return '${(value / 1000).toStringAsFixed(1)}K';
    return '${(value / 1000000).toStringAsFixed(2)}M';
  }
}
