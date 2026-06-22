/// Represents a network fee option with a specific priority level.
class NetworkFeeOption {
  final String priority;
  final int gasPriceGwei;
  final double feeEth;
  final double feeUsd;
  final String estimatedTime;

  const NetworkFeeOption({
    required this.priority,
    required this.gasPriceGwei,
    required this.feeEth,
    required this.feeUsd,
    required this.estimatedTime,
  });

  NetworkFeeOption copyWith({
    String? priority,
    int? gasPriceGwei,
    double? feeEth,
    double? feeUsd,
    String? estimatedTime,
  }) {
    return NetworkFeeOption(
      priority: priority ?? this.priority,
      gasPriceGwei: gasPriceGwei ?? this.gasPriceGwei,
      feeEth: feeEth ?? this.feeEth,
      feeUsd: feeUsd ?? this.feeUsd,
      estimatedTime: estimatedTime ?? this.estimatedTime,
    );
  }

  Map<String, dynamic> toJson() => {
        'priority': priority,
        'gasPriceGwei': gasPriceGwei,
        'feeEth': feeEth,
        'feeUsd': feeUsd,
        'estimatedTime': estimatedTime,
      };
}
