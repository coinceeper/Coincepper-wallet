/// Pure domain interface for price data caching.
///
/// Implemented by infrastructure layer.
/// Domain services depend on this interface instead of directly
/// importing concrete storage implementations.
abstract class IPriceDataStorage {
  Future<String> loadSelectedCurrency();
  Future<void> saveSelectedCurrency(String currency);
}
