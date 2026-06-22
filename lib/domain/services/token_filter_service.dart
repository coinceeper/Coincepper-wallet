import '../../models/crypto_token.dart';
import '../interfaces/price_query.dart';

/// Pure filtering and sorting logic for crypto tokens.
///
/// This service is stateless — all data is passed as parameters.
/// It depends on the [IPriceQuery] interface instead of directly
/// importing presentation-layer providers (Clean Architecture).
class TokenFilterService {
  const TokenFilterService();

  /// Filter and sort tokens based on the given criteria.
  List<CryptoToken> filterAndSort({
    required List<CryptoToken> tokens,
    required IPriceQuery priceQuery,
    String sortOption = 'balance',
    bool hideZeroBalances = false,
    bool showOnlyEnabled = false,
    List<String> selectedBlockchains = const [],
  }) {
    var result = List<CryptoToken>.from(tokens);

    if (showOnlyEnabled) {
      result = result.where((t) => t.isEnabled).toList();
    }

    if (hideZeroBalances) {
      result = result.where((t) => t.amount > 0).toList();
    }

    if (selectedBlockchains.isNotEmpty) {
      result = result.where((t) {
        return t.blockchainName != null &&
            selectedBlockchains.contains(t.blockchainName!);
      }).toList();
    }

    _applySorting(result, sortOption, priceQuery);
    return result;
  }

  void _applySorting(
    List<CryptoToken> tokens,
    String sortOption,
    IPriceQuery priceQuery,
  ) {
    switch (sortOption) {
      case 'name':
        tokens.sort((a, b) => (a.symbol ?? '').compareTo(b.symbol ?? ''));
        break;
      case 'price':
        tokens.sort((a, b) {
          final pa = priceQuery.getPrice(a.symbol ?? '') ?? 0.0;
          final pb = priceQuery.getPrice(b.symbol ?? '') ?? 0.0;
          return pb.compareTo(pa);
        });
        break;
      case 'balance':
      default:
        tokens.sort((a, b) => b.amount.compareTo(a.amount));
        break;
    }
  }

  /// Sort tokens by estimated dollar value (amount × price), descending.
  ///
  /// Tokens with non-zero balance appear first, then sorted by dollar value.
  /// Zero-balance tokens are sorted alphabetically at the end.
  List<CryptoToken> sortByDollarValue(
    List<CryptoToken> tokens,
    IPriceQuery priceQuery,
  ) {
    final result = tokens.toList();
    result.sort((a, b) {
      final aAmount = a.amount;
      final bAmount = b.amount;
      if (aAmount > 0 && bAmount == 0) return -1;
      if (aAmount == 0 && bAmount > 0) return 1;
      if (aAmount > 0 && bAmount > 0) {
        final aPrice = priceQuery.getPrice(a.symbol ?? '') ?? 0.0;
        final bPrice = priceQuery.getPrice(b.symbol ?? '') ?? 0.0;
        final comparison = (bAmount * bPrice).compareTo(aAmount * aPrice);
        if (comparison != 0) return comparison;
      }
      return (a.symbol ?? '').compareTo(b.symbol ?? '');
    });
    return result;
  }

  /// Search tokens by query (case-insensitive match on symbol or name).
  List<CryptoToken> search(List<CryptoToken> tokens, String query) {
    if (query.isEmpty) return tokens;
    final lowerQuery = query.toLowerCase();
    return tokens.where((t) {
      final symbolMatch = (t.symbol ?? '').toLowerCase().contains(lowerQuery);
      final nameMatch = (t.name ?? '').toLowerCase().contains(lowerQuery);
      return symbolMatch || nameMatch;
    }).toList();
  }
}
