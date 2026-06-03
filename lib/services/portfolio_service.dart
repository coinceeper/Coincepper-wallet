import '../services/secure_storage.dart';
import '../wallet/history/history_indexer.dart';
import '../providers/price_provider.dart';

/// سرویس محاسبه سود و ضرر پرتفولیو
class PortfolioService {
  static final PortfolioService _instance = PortfolioService._internal();
  factory PortfolioService() => _instance;
  PortfolioService._internal();

  /// محاسبه قیمت متوسط خرید برای یک توکن
  /// از تراکنش‌های inbound (دریافتی) استفاده می‌کند
  Future<double?> calculateAveragePurchasePrice(String tokenSymbol) async {
    try {
      final userId = await SecureStorage.getUserId();
      if (userId == null) return null;

      print('🔍 PortfolioService: Calculating average purchase price for $tokenSymbol');

      final all = await HistoryIndexer.instance.fetchAndCache(userId);
      final sym = tokenSymbol.toLowerCase();
      final forToken = all
          .where((tx) => (tx.tokenSymbol ?? '').toLowerCase() == sym)
          .toList();

      if (forToken.isEmpty) {
        print('❌ PortfolioService: No transactions found for $tokenSymbol');
        return null;
      }

      final purchaseTransactions = forToken.where((tx) {
        final isInbound = tx.direction.toLowerCase() == 'inbound';
        final hasPrice = tx.price != null && tx.price! > 0;
        final hasAmount = double.tryParse(tx.amount) != null;
        return isInbound && hasPrice && hasAmount;
      }).toList();

      if (purchaseTransactions.isEmpty) {
        print('❌ PortfolioService: No valid purchase transactions found for $tokenSymbol');
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
        
        print('📊 Transaction: ${amount.toStringAsFixed(4)} $tokenSymbol @ \$${price.toStringAsFixed(4)} = \$${cost.toStringAsFixed(2)}');
      }

      if (totalAmount == 0) return null;

      final averagePrice = totalCost / totalAmount;
      print('✅ PortfolioService: Average purchase price for $tokenSymbol: \$${averagePrice.toStringAsFixed(4)}');
      print('   Total Cost: \$${totalCost.toStringAsFixed(2)}, Total Amount: ${totalAmount.toStringAsFixed(4)}');
      
      return averagePrice;
    } catch (e) {
      print('❌ PortfolioService: Error calculating average purchase price: $e');
      return null;
    }
  }

  /// محاسبه درصد سود/ضرر برای یک توکن
  Future<double?> calculateProfitLossPercentage(String tokenSymbol, PriceProvider priceProvider) async {
    try {
      // دریافت قیمت متوسط خرید
      final averagePurchasePrice = await calculateAveragePurchasePrice(tokenSymbol);
      if (averagePurchasePrice == null || averagePurchasePrice == 0) {
        print('⚠️ PortfolioService: No average purchase price available for $tokenSymbol');
        return null;
      }

      // دریافت قیمت فعلی
      final currentPrice = priceProvider.getPrice(tokenSymbol);
      if (currentPrice == null || currentPrice == 0) {
        print('⚠️ PortfolioService: No current price available for $tokenSymbol');
        return null;
      }

      // محاسبه درصد تغییرات
      // فرمول: ((قیمت فعلی - قیمت خرید) / قیمت خرید) * 100
      final profitLossPercentage = ((currentPrice - averagePurchasePrice) / averagePurchasePrice) * 100;
      
      print('📈 PortfolioService: Profit/Loss calculation for $tokenSymbol:');
      print('   Average Purchase Price: \$${averagePurchasePrice.toStringAsFixed(4)}');
      print('   Current Price: \$${currentPrice.toStringAsFixed(4)}');
      print('   Profit/Loss: ${profitLossPercentage >= 0 ? '+' : ''}${profitLossPercentage.toStringAsFixed(2)}%');
      
      return profitLossPercentage;
    } catch (e) {
      print('❌ PortfolioService: Error calculating profit/loss percentage: $e');
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
      
      print('💰 PortfolioService: Profit/Loss amount for $tokenSymbol:');
      print('   Token Balance: ${tokenBalance.toStringAsFixed(4)}');
      print('   Purchase Value: \$${purchaseValue.toStringAsFixed(2)}');
      print('   Current Value: \$${currentValue.toStringAsFixed(2)}');
      print('   Profit/Loss Amount: ${profitLossAmount >= 0 ? '+' : ''}\$${profitLossAmount.toStringAsFixed(2)}');
      
      return profitLossAmount;
    } catch (e) {
      print('❌ PortfolioService: Error calculating profit/loss amount: $e');
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
      print('❌ PortfolioService: Error getting portfolio summary: $e');
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
