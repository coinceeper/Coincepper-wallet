import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/crypto_token.dart';
import '../providers/price_provider.dart';

/// مدیریت پایدار نمایش موجودی‌ها در همه صفحات
class BalanceDisplayManager extends ChangeNotifier {
  static final BalanceDisplayManager _instance = BalanceDisplayManager._internal();
  static BalanceDisplayManager get instance => _instance;
  
  BalanceDisplayManager._internal();

  // Cache برای موجودی‌های فرمت شده
  final Map<String, String> _formattedBalanceCache = {};
  final Map<String, String> _formattedValueCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  
  // تنظیمات cache
  static const Duration _cacheExpiry = Duration(seconds: 30);
  
  /// پاک کردن cache
  void clearCache() {
    _formattedBalanceCache.clear();
    _formattedValueCache.clear();
    _cacheTimestamps.clear();
    notifyListeners();
  }

  /// پاک کردن cache برای توکن خاص
  void clearTokenCache(String tokenSymbol) {
    final balanceKey = '${tokenSymbol}_balance';
    final valueKey = '${tokenSymbol}_value';
    
    _formattedBalanceCache.remove(balanceKey);
    _formattedValueCache.remove(valueKey);
    _cacheTimestamps.remove(balanceKey);
    _cacheTimestamps.remove(valueKey);
    
    notifyListeners();
  }

  /// بررسی اعتبار cache
  bool _isCacheValid(String key) {
    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return false;
    
    return DateTime.now().difference(timestamp) < _cacheExpiry;
  }

  /// دریافت موجودی فرمت شده با cache
  String getFormattedBalance(
    CryptoToken token,
    bool isHidden, {
    double? screenWidth,
    bool useCache = true,
  }) {
    final cacheKey = '${token.symbol}_balance_${screenWidth?.toInt() ?? 0}_$isHidden';
    
    // بررسی cache
    if (useCache && _isCacheValid(cacheKey)) {
      final cached = _formattedBalanceCache[cacheKey];
      if (cached != null) return cached;
    }

    // محاسبه جدید
    final formatted = _calculateFormattedBalance(token, isHidden, screenWidth);
    
    // ذخیره در cache
    if (useCache) {
      _formattedBalanceCache[cacheKey] = formatted;
      _cacheTimestamps[cacheKey] = DateTime.now();
    }
    
    return formatted;
  }

  /// دریافت ارزش فرمت شده با cache
  String getFormattedValue(
    CryptoToken token,
    PriceProvider priceProvider,
    bool isHidden, {
    double? screenWidth,
    bool useCache = true,
  }) {
    final cacheKey = '${token.symbol}_value_${screenWidth?.toInt() ?? 0}_$isHidden';
    
    // بررسی cache
    if (useCache && _isCacheValid(cacheKey)) {
      final cached = _formattedValueCache[cacheKey];
      if (cached != null) return cached;
    }

    // محاسبه جدید
    final formatted = _calculateFormattedValue(token, priceProvider, isHidden, screenWidth);
    
    // ذخیره در cache
    if (useCache) {
      _formattedValueCache[cacheKey] = formatted;
      _cacheTimestamps[cacheKey] = DateTime.now();
    }
    
    return formatted;
  }

  /// محاسبه موجودی فرمت شده
  String _calculateFormattedBalance(CryptoToken token, bool isHidden, double? screenWidth) {
    if (isHidden) return '****';
    
    final balance = _getSafeBalance(token);
    if (balance == 0.0) return '0.00';
    
    final isSmallScreen = (screenWidth ?? 400) < 360;
    final isMediumScreen = (screenWidth ?? 400) < 400;
    
    return _formatBalanceForScreen(balance, isSmallScreen, isMediumScreen);
  }

  /// محاسبه ارزش فرمت شده
  String _calculateFormattedValue(CryptoToken token, PriceProvider priceProvider, bool isHidden, double? screenWidth) {
    if (isHidden) return '****';
    
    final balance = _getSafeBalance(token);
    if (balance == 0.0) return '\$0.00';
    
    final price = priceProvider.getPrice(token.symbol ?? '') ?? 0.0;
    if (price <= 0) return '\$0.00';
    
    final value = balance * price;
    if (value.isNaN || value.isInfinite) return '\$0.00';
    
    final isSmallScreen = (screenWidth ?? 400) < 360;
    
    return _formatValueForScreen(value, isSmallScreen);
  }

  /// دریافت موجودی ایمن
  double _getSafeBalance(CryptoToken token) {
    final amount = token.amount;
    if (amount.isNaN || amount.isInfinite) {
      return 0.0;
    }
    return amount < 0 ? 0.0 : amount;
  }

  /// فرمت‌بندی موجودی بر اساس اندازه صفحه
  String _formatBalanceForScreen(double balance, bool isSmallScreen, bool isMediumScreen) {
    // برای صفحات کوچک - فرمت کوتاه‌تر
    if (isSmallScreen) {
      if (balance >= 1000000) {
        return '${(balance / 1000000).toStringAsFixed(1)}M';
      } else if (balance >= 1000) {
        return '${(balance / 1000).toStringAsFixed(1)}K';
      } else if (balance >= 1) {
        return balance.toStringAsFixed(2);
      } else if (balance >= 0.01) {
        return balance.toStringAsFixed(4);
      } else {
        return balance.toStringAsFixed(6);
      }
    }
    
    // برای صفحات متوسط - فرمت متعادل
    if (isMediumScreen) {
      if (balance >= 1000000) {
        return '${(balance / 1000000).toStringAsFixed(2)}M';
      } else if (balance >= 1000) {
        return '${(balance / 1000).toStringAsFixed(2)}K';
      } else if (balance >= 1) {
        return balance.toStringAsFixed(3);
      } else if (balance >= 0.001) {
        return balance.toStringAsFixed(5);
      } else {
        return balance.toStringAsFixed(8);
      }
    }
    
    // برای صفحات بزرگ - فرمت کامل
    if (balance >= 1000000) {
      return '${(balance / 1000000).toStringAsFixed(3)}M';
    } else if (balance >= 1000) {
      return '${(balance / 1000).toStringAsFixed(3)}K';
    } else if (balance >= 1) {
      return balance.toStringAsFixed(4);
    } else if (balance >= 0.0001) {
      return balance.toStringAsFixed(6);
    } else {
      return balance.toStringAsFixed(8);
    }
  }

  /// فرمت‌بندی ارزش بر اساس اندازه صفحه
  String _formatValueForScreen(double value, bool isSmallScreen) {
    if (isSmallScreen) {
      if (value >= 1000000) {
        return '\$${(value / 1000000).toStringAsFixed(1)}M';
      } else if (value >= 1000) {
        return '\$${(value / 1000).toStringAsFixed(1)}K';
      } else if (value >= 1) {
        return '\$${value.toStringAsFixed(1)}';
      } else {
        return '\$${value.toStringAsFixed(3)}';
      }
    }
    
    // صفحات بزرگ
    if (value >= 1000000) {
      return '\$${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '\$${(value / 1000).toStringAsFixed(2)}K';
    } else {
      return '\$${value.toStringAsFixed(2)}';
    }
  }

  /// محاسبه ارزش کل پورتفولیو
  double calculateTotalPortfolioValue(List<CryptoToken> tokens, PriceProvider priceProvider) {
    double total = 0.0;
    
    for (final token in tokens) {
      final balance = _getSafeBalance(token);
      if (balance <= 0) continue;
      
      final price = priceProvider.getPrice(token.symbol ?? '') ?? 0.0;
      if (price <= 0 || price.isNaN || price.isInfinite) continue;
      
      final value = balance * price;
      if (!value.isNaN && !value.isInfinite && value > 0) {
        total += value;
      }
    }
    
    return total.isNaN || total.isInfinite ? 0.0 : total;
  }

  /// فرمت‌بندی ارزش کل پورتفولیو
  String formatTotalPortfolioValue(double value, {bool isHidden = false}) {
    if (isHidden) return '****';
    if (value == 0.0) return '\$0.00';
    
    if (value >= 1000000) {
      return '\$${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '\$${(value / 1000).toStringAsFixed(2)}K';
    } else {
      return '\$${value.toStringAsFixed(2)}';
    }
  }

  /// به‌روزرسانی cache هنگام تغییر موجودی
  void onBalanceUpdated(String tokenSymbol) {
    // پاک کردن cache مربوط به این توکن
    clearTokenCache(tokenSymbol);
    
    // اطلاع‌رسانی به listeners
    notifyListeners();
  }

  /// به‌روزرسانی cache هنگام تغییر قیمت
  void onPriceUpdated(List<String> tokenSymbols) {
    // پاک کردن cache مربوط به value ها
    for (final symbol in tokenSymbols) {
      final valueKey = '${symbol}_value';
      _formattedValueCache.removeWhere((key, value) => key.startsWith(valueKey));
      _cacheTimestamps.removeWhere((key, value) => key.startsWith(valueKey));
    }
    
    // اطلاع‌رسانی به listeners
    notifyListeners();
  }
}
