import '../models/crypto_token.dart';
import 'on_chain_balance_service.dart';
import 'secure_storage.dart';
import '../utils/secure_log.dart';
import '../wallet/wallet_mode.dart';
import '../di/service_locator.dart';

/// Single-responsibility service for token balance operations.
///
/// Handles:
/// - Loading cached balances from secure storage
/// - Fetching on-chain balances
/// - Applying balance data to token lists
///
/// Does NOT own any token state — receives tokens as parameters and returns
/// updated copies. This makes it testable and reusable across providers.
class TokenBalanceService {
  final SecureStorage _secureStorage;
  final OnChainBalanceService _onChainBalanceService;

  TokenBalanceService({
    SecureStorage? secureStorage,
    OnChainBalanceService? onChainBalanceService,
  })  : _secureStorage = secureStorage ?? ServiceLocator.get<SecureStorage>(),
        _onChainBalanceService = onChainBalanceService ?? ServiceLocator.get<OnChainBalanceService>();

  /// Load cached balances from secure storage and apply them to the given
  /// [currencies] list. Returns an updated list with cached balances applied
  /// and additional cached tokens appended.
  Future<List<CryptoToken>> loadBalanceCache({
    required String userId,
    required String walletName,
    required List<CryptoToken> currencies,
  }) async {
    try {
      final balanceCache = await _secureStorage.getWalletBalanceCache(walletName, userId);
      if (balanceCache.isEmpty) return currencies;

      final updatedCurrencies = currencies.map((token) {
        final symbol = token.symbol ?? '';
        final chain = token.blockchainName ?? '';
        final qualifiedKey = chain.isNotEmpty ? '${symbol}_$chain' : symbol;
        final cachedBalance = balanceCache[qualifiedKey] ?? balanceCache[symbol] ?? 0.0;
        if (cachedBalance > 0.0) return token.copyWith(amount: cachedBalance);
        return token;
      }).toList();

      final additionalTokens = <CryptoToken>[];
      for (final cacheKey in balanceCache.keys) {
        final balance = balanceCache[cacheKey] ?? 0.0;
        if (balance <= 0.0) continue;

        final underscoreIdx = cacheKey.lastIndexOf('_');
        if (underscoreIdx <= 0 || underscoreIdx >= cacheKey.length - 1) continue;

        final sym = cacheKey.substring(0, underscoreIdx);
        final chain = cacheKey.substring(underscoreIdx + 1);

        final existsInCurrencies = updatedCurrencies.any(
          (t) => t.symbol == sym && t.blockchainName == chain,
        );
        if (!existsInCurrencies) {
          additionalTokens.add(CryptoToken(
            name: sym,
            symbol: sym,
            blockchainName: chain,
            iconUrl: 'https://assets.coingecko.com/coins/images/1/small/bitcoin.png',
            isEnabled: false,
            amount: balance,
            isToken: true,
          ));
        }
      }

      return [...updatedCurrencies, ...additionalTokens];
    } catch (e) {
      SecureLog.e('TokenBalanceService: Error loading balance cache', error: e);
      return currencies;
    }
  }

  /// Fetch on-chain balances for the given [activeTokens] belonging to [userId].
  /// Returns a map of "symbol_blockchain" -> "balance_string" for tokens that
  /// successfully resolved.
  Future<Map<String, String>> fetchBalancesForActiveTokens({
    required String userId,
    required List<CryptoToken> activeTokens,
  }) async {
    if (userId.isEmpty || activeTokens.isEmpty) return {};

    try {
      if (await WalletModePreferences.usesLocalBalanceOnly()) {
        return await _onChainBalanceService.balancesForActiveTokens(userId, activeTokens);
      }
    } catch (e) {
      SecureLog.e('TokenBalanceService: Error fetching balances', error: e);
    }
    return {};
  }

  /// Apply a [balances] map to the given [tokens] list.
  /// Each matching token is updated with its on-chain balance.
  List<CryptoToken> applyBalances({
    required Map<String, String> balances,
    required List<CryptoToken> tokens,
  }) {
    if (balances.isEmpty) return tokens;

    return tokens.map((token) {
      final sym = token.symbol ?? '';
      final chain = token.blockchainName ?? '';
      final blockchainKey = chain.isNotEmpty ? '${sym}_$chain' : sym;
      final balance = balances[blockchainKey] ?? balances[sym] ?? '0.0';
      return token.copyWith(amount: double.tryParse(balance) ?? 0.0);
    }).toList();
  }

  /// Fetch and update a single token's balance.
  /// Returns the updated token if successful, or null on failure.
  Future<CryptoToken?> updateSingleTokenBalance({
    required String userId,
    required CryptoToken token,
  }) async {
    if (userId.isEmpty) return null;
    try {
      if (await WalletModePreferences.usesLocalBalanceOnly()) {
        final map = await _onChainBalanceService.balancesForActiveTokens(userId, [token]);
        final sym = token.symbol ?? '';
        final chain = token.blockchainName ?? '';
        final key = chain.isNotEmpty ? '${sym}_$chain' : sym;
        final raw = map[key] ?? map[sym];
        if (raw != null) {
          return token.copyWith(amount: double.tryParse(raw) ?? 0.0);
        }
      }
    } catch (e) {
      SecureLog.e('TokenBalanceService: Error fetching single balance', error: e);
    }
    return null;
  }
}
