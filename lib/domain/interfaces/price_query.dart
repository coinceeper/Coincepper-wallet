/// Pure domain interface for querying token prices.
///
/// Implemented by [PriceProvider] in the presentation layer.
/// Domain services depend on this interface instead of directly
/// importing presentation-layer providers.
abstract class IPriceQuery {
  double? getPrice(String symbol, {String? currency});

  Future<void> fetchPrices(List<String> symbols, {List<String>? currencies});
}
