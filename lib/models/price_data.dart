
import '../utils/secure_log.dart';

/// Token price data model — single source of truth for all market data.
///
/// Contains fields that CoinGecko's `/simple/price` endpoint provides:
/// - price, 24h change
/// - market cap, 24h volume
///
/// 1h and 7d changes are NOT available from `/simple/price` and require
/// the separate `/coins/{id}` endpoint. Those are fetched on demand by
/// [CoinGeckoService.fetchMarketData] and stored in [PriceService].
class PriceData {
  final String? change24h;
  final String price;
  final double? marketCap;
  final double? volume24h;

  PriceData({
    this.change24h,
    required this.price,
    this.marketCap,
    this.volume24h,
  });

  factory PriceData.fromJson(Map<String, dynamic> json) {
    return PriceData(
      change24h: json['change_24h'] as String?,
      price: json['price'] as String,
      marketCap: (json['market_cap'] as num?)?.toDouble(),
      volume24h: (json['volume_24h'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'change_24h': change24h,
      'price': price,
      if (marketCap != null) 'market_cap': marketCap,
      if (volume24h != null) 'volume_24h': volume24h,
    };
  }

  /// Get price as double with safe parsing
  double? get priceAsDouble {
    try {
      final cleanPrice = price.replaceAll(',', '').replaceAll(' ', '').trim();
      final parsed = double.tryParse(cleanPrice);
      if (parsed == null) {
        SecureLog.w('PriceData: Failed to parse price (cleaned length: ${cleanPrice.length})');
      }
      return parsed;
    } catch (e) {
      SecureLog.e('PriceData: Error parsing price', error: e);
      return null;
    }
  }

  /// Get 24h change as double with safe parsing
  double? get change24hAsDouble {
    try {
      if (change24h == null) return null;
      final cleanChange = change24h!.replaceAll('%', '').replaceAll('+', '').replaceAll(',', '').replaceAll(' ', '').trim();
      final parsed = double.tryParse(cleanChange);
      if (parsed == null && change24h!.isNotEmpty) {
        SecureLog.w('PriceData: Failed to parse change24h (cleaned length: ${cleanChange.length})');
      }
      return parsed;
    } catch (e) {
      SecureLog.e('PriceData: Error parsing change24h', error: e);
      return null;
    }
  }

  @override
  String toString() {
    return 'PriceData(price: $price, change24h: $change24h, marketCap: $marketCap, volume24h: $volume24h)';
  }
} 