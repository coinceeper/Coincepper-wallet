class CurrentPriceData {
  final double price;
  final double change24h;
  final double marketCap;
  final double volume24h;
  final DateTime lastUpdated;

  CurrentPriceData({
    required this.price,
    required this.change24h,
    required this.marketCap,
    required this.volume24h,
    required this.lastUpdated,
  });

  factory CurrentPriceData.fromJson(Map<String, dynamic> json) {
    return CurrentPriceData(
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      change24h: (json['change24h'] as num?)?.toDouble() ?? 0.0,
      marketCap: (json['market_cap'] as num?)?.toDouble() ?? 0.0,
      volume24h: (json['volume24h'] as num?)?.toDouble() ?? 0.0,
      lastUpdated: DateTime.tryParse(json['last_updated'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'price': price,
      'change24h': change24h,
      'market_cap': marketCap,
      'volume24h': volume24h,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }
}
