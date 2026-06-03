
/// Token price data model
class PriceData {
  final String? change24h;
  final String price;

  PriceData({
    this.change24h,
    required this.price,
  });

  factory PriceData.fromJson(Map<String, dynamic> json) {
    return PriceData(
      change24h: json['change_24h'] as String?,
      price: json['price'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'change_24h': change24h,
      'price': price,
    };
  }

  /// Get price as double with safe parsing
  double? get priceAsDouble {
    try {
      // Clean the price string by removing commas, spaces, and other formatting
      final cleanPrice = price.replaceAll(',', '').replaceAll(' ', '').trim();
      final parsed = double.tryParse(cleanPrice);
      if (parsed == null) {
        print('⚠️ PriceData: Failed to parse price "$price" (cleaned: "$cleanPrice")');
      }
      return parsed;
    } catch (e) {
      print('❌ PriceData: Error parsing price "$price": $e');
      return null;
    }
  }

  /// Get 24h change as double with safe parsing
  double? get change24hAsDouble {
    try {
      if (change24h == null) return null;
      // Clean the change string by removing %, +, commas, and spaces
      final cleanChange = change24h!.replaceAll('%', '').replaceAll('+', '').replaceAll(',', '').replaceAll(' ', '').trim();
      final parsed = double.tryParse(cleanChange);
      if (parsed == null && change24h!.isNotEmpty) {
        print('⚠️ PriceData: Failed to parse change24h "$change24h" (cleaned: "$cleanChange")');
      }
      return parsed;
    } catch (e) {
      print('❌ PriceData: Error parsing change24h "$change24h": $e');
      return null;
    }
  }

  /// Market cap (placeholder - not available in this model)
  double? get marketCap => null;

  /// 24h volume (placeholder - not available in this model)
  String? get volume24h => null;

  /// 1h change (placeholder - not available in this model)
  String? get change1h => null;

  /// 7d change (placeholder - not available in this model)
  String? get change7d => null;

  @override
  String toString() {
    return 'PriceData(change24h: $change24h, price: $price)';
  }
} 