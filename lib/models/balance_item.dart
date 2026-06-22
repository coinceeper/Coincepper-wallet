class BalanceItem {
  final String symbol;
  final String? balance;
  final String? blockchain;

  BalanceItem({
    required this.symbol,
    this.balance,
    this.blockchain,
  });

  factory BalanceItem.fromJson(Map<String, dynamic> json) {
    return BalanceItem(
      symbol: json['symbol'] ?? '',
      balance: json['balance'],
      blockchain: json['blockchain'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'symbol': symbol,
      'balance': balance,
      'blockchain': blockchain,
    };
  }
} 