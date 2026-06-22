/// Pure domain interface for home initialization dependencies.
///
/// Provides the minimal set of capabilities that [HomeInitService]
/// needs from the presentation layer, avoiding direct imports
/// of providers.
///
/// Implemented by [AppProvider] in the presentation layer.
abstract class IHomeInitDependencies {
  dynamic get tokenProvider;
  String? get currentUserId;
  String? get currentWalletName;
  Future<void> ensureBitcoinEthereumEnabled();
  List get enabledTokens;
  Future<void> loadSelectedCurrency();
  Future<void> fetchPrices(List<String> symbols);
}
