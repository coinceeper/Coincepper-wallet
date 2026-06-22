import '../di/service_locator.dart';
import '../services/secure_storage.dart';
import '../wallet/history/history_indexer.dart';
import '../providers/price_provider.dart';
import '../utils/secure_log.dart';

/// سرویس محاسبه سود و ضرر پرتفولیو
class PortfolioService {
  PortfolioService();

  PortfolioService._internal();

  static PortfolioService get instance => ServiceLocator.get<PortfolioService>();

  /// محاسبه قیمت متوسط خرید برای یک توکن
  /// از تراکنش‌های inbound (دریافتی) استفاده می‌کند
  Future<double?> calculateAveragePurchasePrice(String tokenSymbol) async {
    try {
      final userId = await SecureStorage.getUserId();
      if (userId == null) return null;

      SecureLog.d('PortfolioService: Calculating average purchase price for $tokenSymbol');

      final all = await ServiceLocator.get<HistoryIndexer>().fetchAndCache(userId);
      final sym = tokenSymbol.toLowerCase();
      final forToken = all
          .where((tx) => (tx.tokenSymbol ?? '').toLowerCase() == sym)
          .toList();

      if (forToken.isEmpty) {
        SecureLog.w('PortfolioService: No transactions found for $tokenSymbol');
        return null;
      }

      final purchaseTransactions = forToken.where((tx) {
        final isInbound = tx.direction.toLowerCase() == 'inbound';
        final hasPrice = tx.price != null && tx.price! > 0;
        final hasAmount = double.tryParse(tx.amount) != null;
        return isInbound && hasPrice && hasAmount;
      }).toList();

      if (purchaseTransactions.isEmpty) {
        SecureLog.w('PortfolioService: No valid purchase transactions found for $tokenSymbol');
        return null;
      }

      // محاسبه قیمت متوسط وزنی (Weighted Average)
      double totalCost = 0.0;
      double totalAmount = 0.0;

      for (final tx in purchaseTransactions) {
        final amount = double.parse(tx.amount);
        final price = tx.price!;
        final cost = amount * price;
        
        totalCost += cost;
        totalAmount += amount;
        
        SecureLog.d('Transaction: ${amount.toStringAsFixed(4)} $tokenSymbol @ \$${price.toStringAsFixed(4)} = \$${cost.toStringAsFixed(2)}');
      }

      if (totalAmount == 0) return null;

      final averagePrice = totalCost / totalAmount;
      SecureLog.i('PortfolioService: Average purchase price for $tokenSymbol: \$${averagePrice.toStringAsFixed(4)}');
      SecureLog.d('Total Cost: \$${totalCost.toStringAsFixed(2)}, Total Amount: ${totalAmount.toStringAsFixed(4)}');
      
      return averagePrice;
    } catch (e) {
      SecureLog.e('PortfolioService: Error calculating average purchase price', error: e);
      return null;
    }
  }

  /// محاسبه درصد سود/ضرر برای یک توکن
  Future<double?> calculateProfitLossPercentage(String tokenSymbol, PriceProvider priceProvider) async {
    try {
      // دریافت قیمت متوسط خرید
      final averagePurchasePrice = await calculateAveragePurchasePrice(tokenSymbol);
      if (averagePurchasePrice == null || averagePurchasePrice == 0) {
        SecureLog.w('PortfolioService: No average purchase price available for $tokenSymbol');
        return null;
      }

      // دریافت قیمت فعلی
      final currentPrice = priceProvider.getPrice(tokenSymbol);
      if (currentPrice == null || currentPrice == 0) {
        SecureLog.w('PortfolioService: No current price available for $tokenSymbol');
        return null;
      }

      // محاسبه درصد تغییرات
      // فرمول: ((قیمت فعلی - قیمت خرید) / قیمت خرید) * 100
      final profitLossPercentage = ((currentPrice - averagePurchasePrice) / averagePurchasePrice) * 100;
      
      SecureLog.d('PortfolioService: Profit/Loss calculation for $tokenSymbol:');
      SecureLog.d('Average Purchase Price: \$${averagePurchasePrice.toStringAsFixed(4)}');
      SecureLog.d('Current Price: \$${currentPrice.toStringAsFixed(4)}');
      SecureLog.d('Profit/Loss: ${profitLossPercentage >= 0 ? '+' : ''}${profitLossPercentage.toStringAsFixed(2)}%');
      
      return profitLossPercentage;
    } catch (e) {
      SecureLog.e('PortfolioService: Error calculating profit/loss percentage', error: e);
      return null;
    }
  }

  /// محاسبه مقدار سود/ضرر به ارزش دلار
  Future<double?> calculateProfitLossAmount(String tokenSymbol, double tokenBalance, PriceProvider priceProvider) async {
    try {
      final averagePurchasePrice = await calculateAveragePurchasePrice(tokenSymbol);
      if (averagePurchasePrice == null || averagePurchasePrice == 0) return null;

      final currentPrice = priceProvider.getPrice(tokenSymbol);
      if (currentPrice == null || currentPrice == 0) return null;

      // محاسبه سود/ضرر کل
      final purchaseValue = tokenBalance * averagePurchasePrice;
      final currentValue = tokenBalance * currentPrice;
      final profitLossAmount = currentValue - purchaseValue;
      
      SecureLog.d('PortfolioService: Profit/Loss amount for $tokenSymbol:');
      SecureLog.d('Token Balance: ${tokenBalance.toStringAsFixed(4)}');
      SecureLog.d('Purchase Value: \$${purchaseValue.toStringAsFixed(2)}');
      SecureLog.d('Current Value: \$${currentValue.toStringAsFixed(2)}');
      SecureLog.d('Profit/Loss Amount: ${profitLossAmount >= 0 ? '+' : ''}\$${profitLossAmount.toStringAsFixed(2)}');
      
      return profitLossAmount;
    } catch (e) {
      SecureLog.e('PortfolioService: Error calculating profit/loss amount', error: e);
      return null;
    }
  }

  /// دریافت خلاصه پرتفولیو برای یک توکن
  Future<PortfolioSummary?> getTokenPortfolioSummary(String tokenSymbol, double tokenBalance, PriceProvider priceProvider) async {
    try {
      final averagePurchasePrice = await calculateAveragePurchasePrice(tokenSymbol);
      final currentPrice = priceProvider.getPrice(tokenSymbol);
      
      if (averagePurchasePrice == null || currentPrice == null) return null;

      final profitLossPercentage = await calculateProfitLossPercentage(tokenSymbol, priceProvider);
      final profitLossAmount = await calculateProfitLossAmount(tokenSymbol, tokenBalance, priceProvider);
      
      return PortfolioSummary(
        tokenSymbol: tokenSymbol,
        tokenBalance: tokenBalance,
        averagePurchasePrice: averagePurchasePrice,
        currentPrice: currentPrice,
        profitLossPercentage: profitLossPercentage ?? 0.0,
        profitLossAmount: profitLossAmount ?? 0.0,
      );
    } catch (e) {
      SecureLog.e('PortfolioService: Error getting portfolio summary', error: e);
      return null;
    }
  }
}

/// کلاس خلاصه پرتفولیو
class PortfolioSummary {
  final String tokenSymbol;
  final double tokenBalance;
  final double averagePurchasePrice;
  final double currentPrice;
  final double profitLossPercentage;
  final double profitLossAmount;

  PortfolioSummary({
    required this.tokenSymbol,
    required this.tokenBalance,
    required this.averagePurchasePrice,
    required this.currentPrice,
    required this.profitLossPercentage,
    required this.profitLossAmount,
  });

  bool get isProfit => profitLossPercentage >= 0;
  bool get isBreakEven => profitLossPercentage == 0;
  
  String get formattedPercentage => '${profitLossPercentage >= 0 ? '+' : ''}${profitLossPercentage.toStringAsFixed(2)}%';
  String get formattedAmount => '${profitLossAmount >= 0 ? '+' : ''}\$${profitLossAmount.abs().toStringAsFixed(2)}';
}
