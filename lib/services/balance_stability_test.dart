import 'dart:async';
import 'balance_manager.dart';
import 'api_service.dart';

/// تست ساده برای بررسی پایداری نمایش موجودی‌ها
class BalanceStabilityTest {
  static const String testUserId = 'test_user_123';
  static const Duration testDuration = Duration(minutes: 5);
  static const Duration checkInterval = Duration(seconds: 10);
  
  static Future<void> runStabilityTest() async {
    print('🧪 BalanceStabilityTest: Starting stability test...');
    
    try {
      // Initialize BalanceManager
      final apiService = ApiService();
      await BalanceManager.instance.initialize(apiService);
      
      // Set test context
      await BalanceManager.instance.setCurrentUserAndWallet(testUserId, 'test_wallet');
      
      // Set some test tokens
      BalanceManager.instance.setActiveTokensForUser(testUserId, ['BTC', 'ETH', 'TRX']);
      
      // Start periodic checks
      final testEndTime = DateTime.now().add(testDuration);
      Timer.periodic(checkInterval, (timer) {
        if (DateTime.now().isAfter(testEndTime)) {
          timer.cancel();
          _printTestResults();
          return;
        }
        
        _checkBalanceStability();
      });
      
      print('✅ BalanceStabilityTest: Test started, will run for ${testDuration.inMinutes} minutes');
      
    } catch (e) {
      print('❌ BalanceStabilityTest: Error during test: $e');
    }
  }
  
  static void _checkBalanceStability() {
    final balances = BalanceManager.instance.getUserBalances(testUserId);
    final upToDate = BalanceManager.instance.areBalancesUpToDate(testUserId);
    final timestamp = DateTime.now().toIso8601String();
    
    print('🧪 $timestamp - Balances: ${balances.length}, Up to date: $upToDate');
    
    // Check for specific tokens
    for (final symbol in ['BTC', 'ETH', 'TRX']) {
      final balance = BalanceManager.instance.getTokenBalance(testUserId, symbol);
      print('   $symbol: $balance');
    }
  }
  
  static void _printTestResults() {
    print('🧪 BalanceStabilityTest: Test completed');
    BalanceManager.instance.debugBalanceState();
  }
  
  /// تست سریع برای validation
  static Future<bool> quickValidationTest() async {
    try {
      print('🧪 BalanceStabilityTest: Running quick validation...');
      
      // Test BalanceManager initialization
      final apiService = ApiService();
      await BalanceManager.instance.initialize(apiService);
      
      // Test setting user context
      await BalanceManager.instance.setCurrentUserAndWallet('test_user', 'test_wallet');
      
      // Test setting active tokens
      BalanceManager.instance.setActiveTokensForUser('test_user', ['BTC', 'ETH']);
      
      // Test getting balances
      final balances = BalanceManager.instance.getUserBalances('test_user');
      final btcBalance = BalanceManager.instance.getTokenBalance('test_user', 'BTC');
      
      // Test up-to-date check
      final upToDate = BalanceManager.instance.areBalancesUpToDate('test_user');
      
      print('✅ BalanceStabilityTest: Quick validation passed');
      print('   Balances count: ${balances.length}');
      print('   BTC balance: $btcBalance');
      print('   Up to date: $upToDate');
      
      return true;
      
    } catch (e) {
      print('❌ BalanceStabilityTest: Quick validation failed: $e');
      return false;
    }
  }
}
