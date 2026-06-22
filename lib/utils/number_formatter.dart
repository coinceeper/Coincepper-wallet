

class NumberFormatter {
  /// Format amount for display in financial applications
  static String formatAmount(String amountStr, {int maxDecimals = 8}) {
    try {
      double amount = double.parse(amountStr);
      return formatDouble(amount, maxDecimals: maxDecimals);
    } catch (e) {
      return amountStr; // Return original if parsing fails
    }
  }
  
  /// Format double amount for display
  static String formatDouble(double amount, {int maxDecimals = 8}) {
    if (amount == 0) return '0';
    
    // Handle very small amounts (less than 0.000001)
    if (amount.abs() < 0.000001 && amount != 0) {
      // Use scientific notation for very small amounts
      return amount.toStringAsExponential(2);
    }
    
    // Handle normal amounts
    if (amount.abs() >= 1) {
      // For amounts >= 1, show at most 6 decimal places
      String formatted = amount.toStringAsFixed(6);
      // Remove trailing zeros
      formatted = formatted.replaceAll(RegExp(r'\.?0+$'), '');
      
      // Add thousand separators for large numbers
      if (amount.abs() >= 1000) {
        return _addThousandSeparators(formatted);
      }
      
      return formatted;
    } else {
      // For amounts < 1, show meaningful decimal places
      String formatted = amount.toStringAsFixed(maxDecimals);
      // Remove trailing zeros but keep at least one decimal place for small amounts
      formatted = formatted.replaceAll(RegExp(r'0+$'), '');
      if (formatted.endsWith('.')) {
        formatted = formatted.substring(0, formatted.length - 1);
      }
      
      // Ensure we don't show too many decimals for display
      if (formatted.contains('.')) {
        List<String> parts = formatted.split('.');
        if (parts[1].length > 6) {
          formatted = '${parts[0]}.${parts[1].substring(0, 6)}';
        }
      }
      
      return formatted;
    }
  }
  
  /// Add thousand separators to number string
  static String _addThousandSeparators(String numberStr) {
    List<String> parts = numberStr.split('.');
    String integerPart = parts[0];
    String decimalPart = parts.length > 1 ? parts[1] : '';
    
    // Add commas to integer part
    String formattedInteger = '';
    for (int i = 0; i < integerPart.length; i++) {
      if (i > 0 && (integerPart.length - i) % 3 == 0) {
        formattedInteger += ',';
      }
      formattedInteger += integerPart[i];
    }
    
    return decimalPart.isNotEmpty ? '$formattedInteger.$decimalPart' : formattedInteger;
  }
  
  /// Format currency value (fiat)
  static String formatCurrency(double value, String currencySymbol) {
    if (value.abs() < 0.01 && value != 0) {
      return '$currencySymbol${value.toStringAsExponential(2)}';
    }
    
    String formatted = value.toStringAsFixed(2);
    if (value.abs() >= 1000) {
      formatted = _addThousandSeparators(formatted);
    }
    
    return '$currencySymbol$formatted';
  }
  
  /// Format percentage
  static String formatPercentage(double percentage) {
    if (percentage.abs() < 0.01) {
      return '0.00%';
    }
    return '${percentage.toStringAsFixed(2)}%';
  }
  
  /// Format amount with sign prefix for transactions
  static String formatTransactionAmount(String amountStr, bool isInbound, {int maxDecimals = 8}) {
    String formatted = formatAmount(amountStr, maxDecimals: maxDecimals);
    String prefix = isInbound ? '+' : '-';
    return '$prefix$formatted';
  }
  
  /// Format number in compact form (K, M, B, T)
  static String formatCompact(double value) {
    if (value.isNaN || !value.isFinite) return '0';
    
    final absValue = value.abs();
    String sign = value < 0 ? '-' : '';
    
    if (absValue >= 1e12) {
      return '$sign${(absValue / 1e12).toStringAsFixed(1)}T';
    } else if (absValue >= 1e9) {
      return '$sign${(absValue / 1e9).toStringAsFixed(1)}B';
    } else if (absValue >= 1e6) {
      return '$sign${(absValue / 1e6).toStringAsFixed(1)}M';
    } else if (absValue >= 1e3) {
      return '$sign${(absValue / 1e3).toStringAsFixed(1)}K';
    } else if (absValue >= 1) {
      return '$sign${absValue.toStringAsFixed(1)}';
    } else if (absValue >= 0.01) {
      return '$sign${absValue.toStringAsFixed(2)}';
    } else if (absValue > 0) {
      return '$sign${absValue.toStringAsExponential(1)}';
    } else {
      return '0';
    }
  }
} 