import 'package:shared_preferences/shared_preferences.dart';

/// Utility class for SharedPreferences operations.
class SharedPreferencesUtils {
  static const String _selectedCurrencyKey = 'selected_currency';

  /// Get the selected currency from SharedPreferences.
  static Future<String> getSelectedCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedCurrencyKey) ?? 'USD';
  }

  /// Save the selected currency to SharedPreferences.
  static Future<void> saveSelectedCurrency(String currency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedCurrencyKey, currency);
  }

  /// Format an amount with proper currency display.
  static String formatAmount(double amount, double price) {
    final value = amount * price;
    if (value >= 1000) {
      return '\$${value.toStringAsFixed(2)}';
    } else if (value >= 1) {
      return '\$${value.toStringAsFixed(4)}';
    } else if (value >= 0.001) {
      return '\$${value.toStringAsFixed(6)}';
    } else {
      return '\$${value.toStringAsFixed(8)}';
    }
  }

  /// Format a token value with a currency symbol.
  /// @deprecated Portfolio value formatting moved to UI layer
  @Deprecated('Use UI formatting instead')
  static String formatPortfolioValue(double value) {
    if (value >= 1000) {
      return '\$${value.toStringAsFixed(2)}';
    } else if (value >= 1) {
      return '\$${value.toStringAsFixed(4)}';
    } else {
      return '\$${value.toStringAsFixed(6)}';
    }
  }

  static String formatTokenValue(double value, String currencySymbol) {
    if (value >= 1000000) {
      return '${currencySymbol}${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '${currencySymbol}${(value / 1000).toStringAsFixed(2)}K';
    } else if (value >= 1) {
      return '${currencySymbol}${value.toStringAsFixed(2)}';
    } else if (value >= 0.001) {
      return '${currencySymbol}${value.toStringAsFixed(4)}';
    } else if (value > 0) {
      return '${currencySymbol}${value.toStringAsFixed(6)}';
    } else {
      return '${currencySymbol}0.00';
    }
  }

  /// Get the currency symbol for a given currency code.
  static String getCurrencySymbol(String currency) {
    switch (currency.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'TRY':
        return '₺';
      case 'IRR':
        return '﷼';
      case 'SAR':
        return '﷼';
      case 'AED':
        return 'د.إ';
      case 'CNY':
        return '¥';
      case 'JPY':
        return '¥';
      case 'KRW':
        return '₩';
      case 'INR':
        return '₹';
      case 'CAD':
        return 'CA\$';
      case 'AUD':
        return 'AU\$';
      case 'KWD':
        return 'KD';
      case 'BHD':
        return 'ب.د';
      case 'TND':
        return 'د.ت';
      case 'IQD':
        return 'ع.د';
      case 'ZAR':
        return 'R';
      case 'CHF':
        return 'CHF';
      case 'NZD':
        return 'NZ\$';
      case 'SGD':
        return 'S\$';
      case 'HKD':
        return 'HK\$';
      case 'MXN':
        return 'MX\$';
      case 'BRL':
        return 'R\$';
      case 'SEK':
        return 'kr';
      case 'NOK':
        return 'kr';
      case 'DKK':
        return 'kr';
      case 'PLN':
        return 'zł';
      case 'CZK':
        return 'Kč';
      case 'HUF':
        return 'Ft';
      case 'ILS':
        return '₪';
      case 'MYR':
        return 'RM';
      case 'THB':
        return '฿';
      case 'PHP':
        return '₱';
      case 'IDR':
        return 'Rp';
      case 'EGP':
        return '£';
      case 'PKR':
        return '₨';
      case 'NGN':
        return '₦';
      case 'VND':
        return '₫';
      case 'BDT':
        return '৳';
      case 'LKR':
        return 'Rs';
      case 'UAH':
        return '₴';
      case 'KZT':
        return '₸';
      case 'XAF':
        return 'FCFA';
      case 'XOF':
        return 'CFA';
      default:
        return currency;
    }
  }
}
