/// Pure domain interface for price refresh dependencies.
///
/// Provides the minimal set of capabilities that [PriceRefreshService]
/// needs from the presentation layer, avoiding direct imports
/// of providers.
///
/// Implemented by [AppProvider] (via [IHomeInitDependencies]) in the
/// presentation layer.
abstract class IPriceRefreshDependencies {
  dynamic get tokenProvider;
  List get enabledTokens;
  Future<void> fetchPrices(List<String> symbols);
}
