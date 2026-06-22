import 'package:flutter/material.dart';
import '../domain/interfaces/price_query.dart';
import '../domain/services/price_service.dart';
import '../utils/secure_log.dart';

/// Provider قیمت توکن‌ها
///
/// ## معماری (Single Source of Truth)
///
/// این کلاس یک لایه UI-friendly روی [PriceService] است و تمام داده‌های
/// قیمتی (قیمت، تغییرات ۲۴ ساعته، Market Cap، حجم ۲۴ ساعته) را از
/// [PriceService] به عنوان Source of Truth می‌خواند.
///
/// **تمام داده‌ها**: از [PriceService] می‌آیند که خود از [CoinGeckoService]
/// استفاده می‌کند. تمام فیلدهای price, change_24h, market_cap, volume_24h
/// در یک درخواست واحد به CoinGecko API گرفته می‌شوند — فراخوانی مجدد API
/// وجود ندارد.
///
/// - `PriceService` مسئول کشینگ در SharedPreferences است.
/// - این Provider فقط داده را از `PriceService` می‌خواند و هرگز خودش
///   مستقیماً در SharedPreferences یا CoinGecko API نمی‌نویسد.
/// - هیچ داده جعلی یا mock تولید نمی‌شود.
/// - در صورت خطا در API، قیمت‌ها صفر/null باقی می‌مانند (نه داده جعلی).
/// - UI موظف است وضعیت "بدون قیمت" را به درستی نمایش دهد.
///
/// تغییرات ۱ ساعته و ۷ روزه از `/simple/price` در دسترس نیستند و از
/// طریق [CoinGeckoService.fetchMarketData] به صورت جداگانه گرفته می‌شوند.
class PriceProvider extends ChangeNotifier implements IPriceQuery {
  final PriceService _priceService;

  bool _isLoading = false;
  String? _error;
  String _selectedCurrency = 'USD';

  PriceProvider({PriceService? priceService})
      : _priceService = priceService ?? PriceService();

  /// قیمت‌ها از طریق [PriceService] به عنوان Source of Truth
  Map<String, Map<String, double>> get prices {
    final result = <String, Map<String, double>>{};
    for (final symbol in _priceService.tokenPrices.keys) {
      final currencyMap = _priceService.tokenPrices[symbol]!;
      result[symbol] = {};
      for (final currency in currencyMap.keys) {
        final priceData = currencyMap[currency]!;
        final price = double.tryParse(priceData.price.replaceAll(',', '')) ?? 0.0;
        result[symbol]![currency] = price;
      }
    }
    return result;
  }

  /// تغییرات ۲۴ ساعته از طریق [PriceService]
  Map<String, Map<String, double>> get priceChanges {
    final result = <String, Map<String, double>>{};
    for (final symbol in _priceService.tokenPrices.keys) {
      final currencyMap = _priceService.tokenPrices[symbol]!;
      result[symbol] = {};
      for (final currency in currencyMap.keys) {
        final priceData = currencyMap[currency]!;
        final change = double.tryParse((priceData.change24h ?? '').replaceAll('%', '')) ?? 0.0;
        result[symbol]![currency] = change;
      }
    }
    return result;
  }

  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedCurrency => _selectedCurrency;

  @override
  Future<void> fetchPrices(List<String> symbols, {List<String>? currencies}) async {
    if (symbols.isEmpty) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Single source of truth: PriceService fetches ALL market data
      // (price, 24h change, market cap, 24h volume) in a single
      // CoinGecko API call. No separate HTTP request is made here.
      await _priceService.fetchPrices(activeSymbols: symbols);
    } catch (e) {
      _error = e.toString();
      SecureLog.w('PriceProvider: Failed to fetch prices', error: e);
    }

    _isLoading = false;
    notifyListeners();
  }

  @override
  double? getPrice(String symbol, {String? currency}) {
    final targetCurrency = currency ?? _selectedCurrency;
    return _priceService.getTokenPrice(symbol.toUpperCase(), currency: targetCurrency);
  }

  /// دریافت درصد تغییرات 24 ساعته برای ارز انتخابی
  double? getPriceChange(String symbol) {
    final priceData = _priceService.tokenPrices[symbol.toUpperCase()]?[_selectedCurrency];
    if (priceData?.change24h == null) return null;
    return double.tryParse((priceData!.change24h ?? '').replaceAll('%', '')) ?? 0.0;
  }

  /// دریافت قیمت برای ارز خاص
  double? getPriceForCurrency(String symbol, String currency) {
    return _priceService.getTokenPrice(symbol.toUpperCase(), currency: currency.toUpperCase());
  }

  /// دریافت درصد تغییرات 24 ساعته برای ارز خاص
  double? getPriceChangeForCurrency(String symbol, String currency) {
    final priceData = _priceService.tokenPrices[symbol.toUpperCase()]?[currency.toUpperCase()];
    if (priceData?.change24h == null) return null;
    return double.tryParse((priceData!.change24h ?? '').replaceAll('%', '')) ?? 0.0;
  }

  /// تغییر ارز انتخابی
  Future<void> setSelectedCurrency(String currency) async {
    _selectedCurrency = currency;
    await _priceService.saveSelectedCurrency(currency);
    notifyListeners();
    SecureLog.d('PriceProvider: Selected currency changed to: $currency');
  }

  /// بارگذاری ارز انتخابی
  Future<void> loadSelectedCurrency() async {
    _selectedCurrency = await _priceService.loadSelectedCurrency();
    notifyListeners();
    SecureLog.d('PriceProvider: Loaded selected currency: $_selectedCurrency');
  }

  /// دریافت نماد ارز انتخابی
  String getCurrencySymbol() {
    return _selectedCurrencySymbol(_selectedCurrency);
  }

  /// دریافت نماد ارز خاص
  String getCurrencySymbolForCurrency(String currency) {
    return _selectedCurrencySymbol(currency);
  }

  String _selectedCurrencySymbol(String currency) {
    switch (currency.toUpperCase()) {
      case 'USD': return '\$';
      case 'CAD': return 'CA\$';
      case 'AUD': return 'AU\$';
      case 'GBP': return '£';
      case 'EUR': return '€';
      case 'KWD': return 'KD';
      case 'TRY': return '₺';
      case 'IRR': return '﷼';
      case 'SAR': return '﷼';
      case 'CNY': return '¥';
      case 'KRW': return '₩';
      case 'JPY': return '¥';
      case 'INR': return '₹';
      case 'RUB': return '₽';
      case 'IQD': return 'ع.د';
      case 'TND': return 'د.ت';
      case 'BHD': return 'ب.د';
      case 'ZAR': return 'R';
      case 'CHF': return 'CHF';
      case 'NZD': return 'NZ\$';
      case 'SGD': return 'S\$';
      case 'HKD': return 'HK\$';
      case 'MXN': return 'MX\$';
      case 'BRL': return 'R\$';
      case 'SEK': return 'kr';
      case 'NOK': return 'kr';
      case 'DKK': return 'kr';
      case 'PLN': return 'zł';
      case 'CZK': return 'Kč';
      case 'HUF': return 'Ft';
      case 'ILS': return '₪';
      case 'MYR': return 'RM';
      case 'THB': return '฿';
      case 'PHP': return '₱';
      case 'IDR': return 'Rp';
      case 'EGP': return '£';
      case 'PKR': return '₨';
      case 'NGN': return '₦';
      case 'VND': return '₫';
      case 'BDT': return '৳';
      case 'LKR': return 'Rs';
      case 'UAH': return '₴';
      case 'KZT': return '₸';
      case 'XAF': return 'FCFA';
      case 'XOF': return 'CFA';
      default: return '';
    }
  }

  /// دریافت market cap از PriceService (Source of Truth)
  String? getMarketCap(String symbol, {String? currency}) {
    final curr = currency ?? _selectedCurrency;
    final priceData = _priceService.tokenPrices[symbol.toUpperCase()]?[curr.toUpperCase()];
    return priceData?.marketCap?.toString();
  }

  /// دریافت حجم 24 ساعته از PriceService (Source of Truth)
  String? getVolume24h(String symbol, {String? currency}) {
    final curr = currency ?? _selectedCurrency;
    final priceData = _priceService.tokenPrices[symbol.toUpperCase()]?[curr.toUpperCase()];
    return priceData?.volume24h?.toString();
  }

  /// دریافت تغییرات 1 ساعته
  /// توجه: این فیلد از `/simple/price` در دسترس نیست.
  /// در صورت نیاز از [CoinGeckoService.fetchMarketData] استفاده کنید.
  double? getChange1h(String symbol, {String? currency}) {
    return null;
  }

  /// دریافت تغییرات 7 روزه
  /// توجه: این فیلد از `/simple/price` در دسترس نیست.
  /// در صورت نیاز از [CoinGeckoService.fetchMarketData] استفاده کنید.
  double? getChange7d(String symbol, {String? currency}) {
    return null;
  }

  /// دریافت اطلاعات کامل توکن
  Map<String, dynamic> getTokenDetails(String symbol, {String? currency}) {
    final curr = currency ?? _selectedCurrency;
    final currencyUpper = curr.toUpperCase();
    final symbolUpper = symbol.toUpperCase();
    final priceData = _priceService.tokenPrices[symbolUpper]?[currencyUpper];

    return {
      'price': getPriceForCurrency(symbol, curr) ?? 0.0,
      'change_24h': getPriceChangeForCurrency(symbol, curr) ?? 0.0,
      'market_cap': priceData?.marketCap?.toString(),
      'volume_24h': priceData?.volume24h?.toString(),
      'currency': curr,
      'symbol': symbol,
    };
  }

  /// تست مستقیم CoinGecko API برای debug
  Future<void> testApiResponse() async {
    SecureLog.d('PriceProvider: Testing CoinGecko API response...');
    // Deprecated: use CoinGeckoService directly for testing
  }

  /// @deprecated Debug-only method preserved for old UI compatibility.
  @Deprecated('No longer supported in new architecture')
  void forceSetBitcoinEthereumPrices() {
    SecureLog.w('forceSetBitcoinEthereumPrices called but is a no-op');
  }
}
