import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

class SharedPreferencesUtils {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  /// ذخیره مقدار ساده
  static Future<void> saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  static Future<String?> getString(String key, {String? defaultValue}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key) ?? defaultValue;
  }

  static Future<void> saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  static Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? defaultValue;
  }

  /// ذخیره ارز انتخابی - مطابق با Kotlin
  static Future<void> saveSelectedCurrency(String currency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_currency', currency);
  }

  static Future<String> getSelectedCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_currency') ?? 'USD';
  }

  /// ذخیره و بارگذاری قیمت توکن‌ها (مطابق با Kotlin shared_preferences_utils.kt)
  static Future<void> saveTokenPrice(String symbol, String currency, String price) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('price_${symbol}_$currency', price);
  }

  static Future<String> getTokenPrice(String symbol, String currency) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('price_${symbol}_$currency') ?? '0.0';
  }

  /// ذخیره و بارگذاری کش قیمت‌ها با timestamp (مطابق با Kotlin fetchPricesWithCache)
  static Future<void> savePricesMapWithCache(Map<String, Map<String, double>> pricesMap) async {
    final prefs = await SharedPreferences.getInstance();
    
    // ذخیره نقشه قیمت‌ها
    final jsonMap = <String, Map<String, String>>{};
    pricesMap.forEach((symbol, currencyMap) {
      jsonMap[symbol] = currencyMap.map((currency, price) => MapEntry(currency, price.toString()));
    });
    
    await prefs.setString('cached_prices_map', json.encode(jsonMap));
    await prefs.setInt('prices_cache_timestamp', DateTime.now().millisecondsSinceEpoch);
    
    print('💾 Saved prices cache with ${pricesMap.length} symbols');
  }

  /// بارگذاری کش قیمت‌ها (مطابق با Kotlin fetchPricesWithCache)
  static Future<Map<String, Map<String, double>>?> loadPricesMapFromCache({int maxAgeMinutes = 5}) async {
    final prefs = await SharedPreferences.getInstance();
    
    final timestamp = prefs.getInt('prices_cache_timestamp') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final ageMinutes = (now - timestamp) / (1000 * 60);
    
    if (ageMinutes > maxAgeMinutes) {
      print('⚠️ Prices cache expired (${ageMinutes.toStringAsFixed(1)} minutes old)');
      return null;
    }
    
    final jsonString = prefs.getString('cached_prices_map');
    if (jsonString == null) {
      print('⚠️ No prices cache found');
      return null;
    }
    
    try {
      final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
      final pricesMap = <String, Map<String, double>>{};
      
      jsonMap.forEach((symbol, currencyMap) {
        if (currencyMap is Map<String, dynamic>) {
          pricesMap[symbol] = {};
          currencyMap.forEach((currency, priceString) {
            final price = double.tryParse(priceString.toString()) ?? 0.0;
            pricesMap[symbol]![currency] = price;
          });
        }
      });
      
      print('📥 Loaded prices cache with ${pricesMap.length} symbols (${ageMinutes.toStringAsFixed(1)} min old)');
      return pricesMap;
    } catch (e) {
      print('❌ Error loading prices cache: $e');
      return null;
    }
  }

  /// دریافت قیمت‌ها با کش (مطابق با Kotlin fetchPricesWithCache)
  static Future<Map<String, Map<String, double>>> fetchPricesWithCache({
    required List<String> symbols,
    required List<String> fiatCurrencies,
    int maxCacheAgeMinutes = 5,
  }) async {
    print('🔄 fetchPricesWithCache called with symbols: $symbols, currencies: $fiatCurrencies');
    
    // Try loading from cache first
    final cachedPrices = await loadPricesMapFromCache(maxAgeMinutes: maxCacheAgeMinutes);
    if (cachedPrices != null) {
      // Check if cache has all required data
      bool hasAllData = true;
      for (final symbol in symbols) {
        if (!cachedPrices.containsKey(symbol)) {
          hasAllData = false;
          break;
        }
        for (final currency in fiatCurrencies) {
          if (!cachedPrices[symbol]!.containsKey(currency)) {
            hasAllData = false;
            break;
          }
        }
        if (!hasAllData) break;
      }
      
      if (hasAllData) {
        print('✅ Using cached prices for all requested symbols');
        return cachedPrices;
      }
    }
    
    // Cache miss or incomplete, fetch from API and update cache
    print('🌐 Cache miss, fetching prices from API...');
    
    // This would normally call API service, but since we're in utils,
    // we'll return empty map and let the caller handle API calls
    print('⚠️ fetchPricesWithCache: API call should be handled by caller');
    return {};
  }

  /// ذخیره و بارگذاری mnemonic به صورت امن
  static Future<void> saveMnemonic(String userId, String walletName, String mnemonic) async {
    final key = 'mnemonic_${userId}_$walletName';
    await _secureStorage.write(key: key, value: mnemonic);
  }

  static Future<String?> getMnemonic(String userId, String walletName) async {
    final key = 'mnemonic_${userId}_$walletName';
    return await _secureStorage.read(key: key);
  }

  /// ذخیره و بارگذاری userId
  static Future<void> saveUserId(String walletName, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final walletsJson = prefs.getString('user_wallets') ?? '[]';
    List wallets = jsonDecode(walletsJson);
    final index = wallets.indexWhere((w) => w['walletName'] == walletName);
    if (index != -1) {
      wallets[index]['userId'] = userId;
    } else {
      wallets.add({'walletName': walletName, 'userId': userId});
    }
    await prefs.setString('user_wallets', jsonEncode(wallets));
  }

  static Future<String?> getUserId(String walletName) async {
    final prefs = await SharedPreferences.getInstance();
    final walletsJson = prefs.getString('user_wallets') ?? '[]';
    List wallets = jsonDecode(walletsJson);
    final wallet = wallets.cast<Map>().firstWhere(
      (w) => w['walletName'] == walletName,
      orElse: () => {},
    );
    return wallet['userId'] ?? prefs.getString('UserID');
  }

  /// فرمت نماد ارز - مطابق با Kotlin
  static String getCurrencySymbol(String currency) {
    switch (currency) {
      case 'USD': return '\$';       // دلار آمریکا
      case 'CAD': return 'CA\$';     // دلار کانادا
      case 'AUD': return 'AU\$';     // دلار استرالیا
      case 'GBP': return '£';       // پوند بریتانیا
      case 'EUR': return '€';       // یورو
      case 'KWD': return 'KD';      // دینار کویت
      case 'TRY': return '₺';       // لیر ترکیه
      case 'IRR': return '﷼';       // ریال ایران
      case 'SAR': return '﷼';       // ریال عربستان
      case 'CNY': return '¥';       // یوآن چین
      case 'KRW': return '₩';       // وون کره جنوبی
      case 'JPY': return '¥';       // ین ژاپن
      case 'INR': return '₹';       // روپیه هند
      case 'RUB': return '₽';       // روبل روسیه
      case 'IQD': return 'ع.د';     // دینار عراق
      case 'TND': return 'د.ت';     // دینار تونس
      case 'BHD': return 'ب.د';     // دینار بحرین
      case 'ZAR': return 'R';       // راند آفریقای جنوبی
      case 'CHF': return 'CHF';     // فرانک سوئیس
      case 'NZD': return 'NZ\$';     // دلار نیوزیلند
      case 'SGD': return 'S\$';      // دلار سنگاپور
      case 'HKD': return 'HK\$';     // دلار هنگ‌کنگ
      case 'MXN': return 'MX\$';     // پزو مکزیک
      case 'BRL': return 'R\$';      // رئال برزیل
      case 'SEK': return 'kr';      // کرون سوئد
      case 'NOK': return 'kr';      // کرون نروژ
      case 'DKK': return 'kr';      // کرون دانمارک
      case 'PLN': return 'zł';      // زلوتی لهستان
      case 'CZK': return 'Kč';      // کرون چک
      case 'HUF': return 'Ft';      // فورینت مجارستان
      case 'ILS': return '₪';       // شِکِل جدید اسرائیل
      case 'MYR': return 'RM';      // رینگیت مالزی
      case 'THB': return '฿';       // بات تایلند
      case 'PHP': return '₱';       // پزو فیلیپین
      case 'IDR': return 'Rp';      // روپیه اندونزی
      case 'EGP': return '£';       // پوند مصر
      case 'PKR': return '₨';       // روپیه پاکستان
      case 'NGN': return '₦';       // نایرا نیجریه
      case 'VND': return '₫';       // دونگ ویتنام
      case 'BDT': return '৳';       // تاکا بنگلادش
      case 'LKR': return 'Rs';      // روپیه سریلانکا
      case 'UAH': return '₴';       // گریونا اوکراین
      case 'KZT': return '₸';       // تنگه قزاقستان
      case 'XAF': return 'FCFA';    // فرانک آفریقای مرکزی
      case 'XOF': return 'CFA';     // فرانک آفریقای غربی
      default: return '';         // پیش‌فرض: رشته خالی
    }
  }

  /// فرمت قیمت - مطابق با Kotlin
  static String formatPrice(double? price, String symbol) {
    if (price == null || price.isNaN || price == 0.0) return '0';
    
    if (symbol == 'BTC' || symbol == 'ETH') {
      return price.toStringAsFixed(2);
    } else if (price < 0.01) {
      return price.toStringAsFixed(8);
    } else if (price < 1) {
      return price.toStringAsFixed(4);
    } else {
      return price.toStringAsFixed(2);
    }
  }

  /// فرمت مقدار - نسخه بهبود یافته برای خوانایی بهتر
  static String formatAmount(double amount, double price) {
    if (amount == 0.0) return '0';
    
    // برای مقادیر بسیار کوچک، از نمایش علمی استفاده کن
    if (amount < 0.000001) {
      return amount.toStringAsExponential(2);
    }
    // مقادیر خیلی کوچک با 8 رقم اعشار
    else if (amount < 0.001) {
      return _removeTrailingZeros(amount.toStringAsFixed(8));
    }
    // مقادیر کوچک با 6 رقم اعشار
    else if (amount < 0.1) {
      return _removeTrailingZeros(amount.toStringAsFixed(6));
    }
    // مقادیر کمتر از 1 با 4 رقم اعشار
    else if (amount < 1.0) {
      return _removeTrailingZeros(amount.toStringAsFixed(4));
    }
    // مقادیر متوسط با 3 رقم اعشار
    else if (amount < 100.0) {
      return _removeTrailingZeros(amount.toStringAsFixed(3));
    }
    // مقادیر بزرگ با کاما برای جداکننده هزارگان
    else if (amount < 1000000) {
      return _formatWithCommas(amount.toStringAsFixed(2));
    }
    // مقادیر خیلی بزرگ با نمایش مخفف
    else {
      return _formatLargeNumber(amount);
    }
  }

  /// حذف صفرهای اضافی انتهایی
  static String _removeTrailingZeros(String numberStr) {
    if (numberStr.contains('.')) {
      numberStr = numberStr.replaceAll(RegExp(r'0*$'), '');
      numberStr = numberStr.replaceAll(RegExp(r'\.$'), '');
    }
    return numberStr;
  }

  /// اضافه کردن کاما برای جداکننده هزارگان
  static String _formatWithCommas(String numberStr) {
    final parts = numberStr.split('.');
    final integerPart = parts[0];
    final decimalPart = parts.length > 1 ? parts[1] : '';
    
    // اضافه کردن کاما به قسمت صحیح
    String formattedInteger = '';
    for (int i = 0; i < integerPart.length; i++) {
      if (i > 0 && (integerPart.length - i) % 3 == 0) {
        formattedInteger += ',';
      }
      formattedInteger += integerPart[i];
    }
    
    return decimalPart.isNotEmpty ? '$formattedInteger.$decimalPart' : formattedInteger;
  }

  /// فرمت اعداد بزرگ با مخففات (K, M, B, T)
  static String _formatLargeNumber(double amount) {
    if (amount >= 1e12) {
      return '${_removeTrailingZeros((amount / 1e12).toStringAsFixed(2))}T';
    } else if (amount >= 1e9) {
      return '${_removeTrailingZeros((amount / 1e9).toStringAsFixed(2))}B';
    } else if (amount >= 1e6) {
      return '${_removeTrailingZeros((amount / 1e6).toStringAsFixed(2))}M';
    } else if (amount >= 1e3) {
      return '${_removeTrailingZeros((amount / 1e3).toStringAsFixed(2))}K';
    }
    return _formatWithCommas(amount.toStringAsFixed(2));
  }

  /// فرمت کردن ارزش کل پورتفولیو
  static String formatPortfolioValue(double value, String currencySymbol) {
    if (value == 0.0) return '${currencySymbol}0.00';
    
    // برای مقادیر بزرگ، از مخففات استفاده کن
    if (value >= 1e9) {
      return '$currencySymbol${_removeTrailingZeros((value / 1e9).toStringAsFixed(2))}B';
    } else if (value >= 1e6) {
      return '$currencySymbol${_removeTrailingZeros((value / 1e6).toStringAsFixed(2))}M';
    } else if (value >= 1e3) {
      return '$currencySymbol${_removeTrailingZeros((value / 1e3).toStringAsFixed(2))}K';
    } else if (value >= 100) {
      return '$currencySymbol${_formatWithCommas(value.toStringAsFixed(0))}';
    } else if (value >= 10) {
      return '$currencySymbol${value.toStringAsFixed(1)}';
    } else {
      return '$currencySymbol${value.toStringAsFixed(2)}';
    }
  }

  /// فرمت کردن ارزش توکن (قیمت × موجودی)
  static String formatTokenValue(double value, String currencySymbol) {
    if (value == 0.0) return '${currencySymbol}0.00';
    
    if (value >= 1e6) {
      return '$currencySymbol${_removeTrailingZeros((value / 1e6).toStringAsFixed(2))}M';
    } else if (value >= 1e3) {
      return '$currencySymbol${_removeTrailingZeros((value / 1e3).toStringAsFixed(2))}K';
    } else if (value >= 1) {
      return '$currencySymbol${_formatWithCommas(value.toStringAsFixed(2))}';
    } else if (value >= 0.01) {
      return '$currencySymbol${value.toStringAsFixed(2)}';
    } else {
      return '$currencySymbol${value.toStringAsFixed(4)}';
    }
  }

  /// پاک کردن همه داده‌ها (برای logout)
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _secureStorage.deleteAll();
  }
} 