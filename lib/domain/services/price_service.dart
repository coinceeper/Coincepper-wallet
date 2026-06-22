import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/price_data.dart';
import '../../services/coingecko_service.dart';
import '../../utils/secure_log.dart';
import '../../di/service_locator.dart';

/// سرویس مدیریت قیمت توکن‌ها
///
/// این سرویس مسئول:
/// - دریافت قیمت‌ها از CoinGecko
/// - کشینگ قیمت‌ها در SharedPreferences
/// - مدیریت expired cache
///
/// طبق Clean Architecture:
/// - از ChangeNotifier استفاده نمی‌کند (pure Dart)
/// - تغییرات از طریق callback به لایه presentation منتقل می‌شود
class PriceService {
  // ==================== CALLBACK ====================
  ServiceChangeCallback? _onChange;

  /// تنظیم callback برای اطلاع‌رسانی تغییرات به لایه presentation
  void setOnChange(ServiceChangeCallback? callback) {
    _onChange = callback;
  }

  Map<String, Map<String, PriceData>> _tokenPrices = {};
  static const int PRICE_CACHE_EXPIRY_MINUTES = 5;

  // ==================== GETTERS / SETTERS ====================
  Map<String, Map<String, PriceData>> get tokenPrices => _tokenPrices;

  /// Setter for external delegation (used by PriceProvider fallback).
  set tokenPrices(Map<String, Map<String, PriceData>> prices) {
    _tokenPrices = prices;
    _notifyChange();
  }

  double getTokenPrice(String symbol, {String currency = 'USD'}) {
    final priceStr = _tokenPrices[symbol]?[currency]?.price;
    if (priceStr != null) return double.tryParse(priceStr.replaceAll(',', '')) ?? 0.0;
    return 0.0;
  }

  String? getAverageChange24h(List<String> activeSymbols) {
    if (activeSymbols.isEmpty) return null;
    double totalChange = 0.0;
    int validCount = 0;
    for (final symbol in activeSymbols) {
      final priceData = _tokenPrices[symbol]?['USD'];
      if (priceData?.change24h != null) {
        final change = double.tryParse((priceData!.change24h ?? '').replaceAll('%', '')) ?? 0.0;
        totalChange += change;
        validCount++;
      }
    }
    if (validCount > 0) {
      final avg = totalChange / validCount;
      return '${avg >= 0 ? '+' : ''}${avg.toStringAsFixed(2)}%';
    }
    return null;
  }

  // ==================== FETCH PRICES ====================
  Future<void> fetchPrices({List<String>? activeSymbols}) async {
    if (activeSymbols == null || activeSymbols.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    bool cacheLoaded = false;

    if (_isPriceCacheValid(prefs)) {
      await loadPricesFromCache(prefs);
      cacheLoaded = true;
    }

    try {
      final rawPrices = await ServiceLocator.get<CoinGeckoService>().fetchPrices(activeSymbols);

      if (rawPrices.isNotEmpty) {
        final convertedPrices = <String, Map<String, PriceData>>{};
        rawPrices.forEach((symbol, currencyMap) {
          final usdPrice = currencyMap['USD'];
          final change24h = currencyMap['change_24h'] ?? 0;
          final marketCap = currencyMap['market_cap'];
          final volume24h = currencyMap['volume_24h'];
          if (usdPrice != null) {
            convertedPrices[symbol] = {
              'USD': PriceData(
                change24h: change24h.toStringAsFixed(2),
                price: usdPrice.toStringAsFixed(6),
                marketCap: marketCap,
                volume24h: volume24h,
              ),
            };
          }
        });

        _tokenPrices = convertedPrices;
        await savePricesToCache(prefs, _tokenPrices);
        _notifyChange();
        return;
      }

      if (!cacheLoaded) _notifyChange();
    } catch (e) {
      if (!cacheLoaded) _notifyChange();
    }
  }

  /// Force-fetch prices without cache check
  Future<void> forceFetchPrices({required List<String> symbols}) async {
    await fetchPrices(activeSymbols: symbols);
  }

  // ==================== CACHE MANAGEMENT ====================
  bool _isPriceCacheValid(SharedPreferences prefs) {
    final lastCache = prefs.getInt('price_cache_timestamp') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return (now - lastCache) < const Duration(minutes: PRICE_CACHE_EXPIRY_MINUTES).inMilliseconds;
  }

  Future<void> loadPricesFromCache(SharedPreferences prefs) async {
    final jsonStr = prefs.getString('cached_prices');
    if (jsonStr == null) return;
    try {
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      _tokenPrices = map.map((k, v) => MapEntry(
        k,
        (v as Map<String, dynamic>).map((kk, vv) => MapEntry(kk, PriceData.fromJson(vv))),
      ));
      _notifyChange();
    } catch (e) {
      SecureLog.d('Error loading cached prices', error: e);
    }
  }

  Future<void> savePricesToCache(SharedPreferences prefs, Map<String, Map<String, PriceData>> prices) async {
    final map = prices.map((k, v) => MapEntry(k, v.map((kk, vv) => MapEntry(kk, vv.toJson()))));
    final jsonStr = json.encode(map);
    await prefs.setString('cached_prices', jsonStr);
    await prefs.setInt('price_cache_timestamp', DateTime.now().millisecondsSinceEpoch);
  }

  // ==================== CURRENCY PREFERENCES ====================
  Future<void> saveSelectedCurrency(String currency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_currency', currency);
  }

  Future<String> loadSelectedCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_currency') ?? 'USD';
  }

  // ==================== INTERNAL ====================
  void _notifyChange() {
    _onChange?.call();
  }
}

/// Type definition for no-parameter callback
typedef ServiceChangeCallback = void Function();
