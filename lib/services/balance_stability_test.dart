import 'dart:async';
import 'balance_manager.dart';
import 'api_service.dart';
import '../di/service_locator.dart';
import '../utils/secure_log.dart';

/// تست ساده برای بررسی پایداری نمایش موجودی‌ها
class BalanceStabilityTest {
  static const String testUserId = 'test_user_123';
  static const Duration testDuration = Duration(minutes: 5);
  static const Duration checkInterval = Duration(seconds: 10);
  
  static Future<void> runStabilityTest() async {
    SecureLog.i('BalanceStabilityTest: Starting stability test...');
    
    try {
      // Initialize BalanceManager
      final apiService = ApiService();
      await ServiceLocator.get<BalanceManager>().initialize(apiService);
      
      // Set test context
      await ServiceLocator.get<BalanceManager>().setCurrentUserAndWallet(testUserId, 'test_wallet');
      
      // Set some test tokens
      ServiceLocator.get<BalanceManager>().setActiveTokensForUser(testUserId, ['BTC', 'ETH', 'TRX']);
      
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
      
      SecureLog.i('BalanceStabilityTest: Test started, will run for ${testDuration.inMinutes} minutes');
      
    } catch (e) {
      SecureLog.e('BalanceStabilityTest: Error during test', error: e);
    }
  }
  
  static void _checkBalanceStability() {
    final balances = ServiceLocator.get<BalanceManager>().getUserBalances(testUserId);
    final upToDate = ServiceLocator.get<BalanceManager>().areBalancesUpToDate(testUserId);
    final timestamp = DateTime.now().toIso8601String();
    
    SecureLog.d('$timestamp - Balances: ${balances.length}, Up to date: $upToDate');
    
    // Check for specific tokens
    for (final symbol in ['BTC', 'ETH', 'TRX']) {
      final balance = ServiceLocator.get<BalanceManager>().getTokenBalance(testUserId, symbol);
      SecureLog.d('$symbol: $balance');
    }
  }
  
  static void _printTestResults() {
    SecureLog.i('BalanceStabilityTest: Test completed');
    ServiceLocator.get<BalanceManager>().debugBalanceState();
  }
  
  /// تست سریع برای validation
  static Future<bool> quickValidationTest() async {
    try {
      SecureLog.i('BalanceStabilityTest: Running quick validation...');
      
      // Test BalanceManager initialization
      final apiService = ApiService();
      await ServiceLocator.get<BalanceManager>().initialize(apiService);
      
      // Test setting user context
      await ServiceLocator.get<BalanceManager>().setCurrentUserAndWallet('test_user', 'test_wallet');
      
      // Test setting active tokens
      ServiceLocator.get<BalanceManager>().setActiveTokensForUser('test_user', ['BTC', 'ETH']);
      
      // Test getting balances
      final balances = ServiceLocator.get<BalanceManager>().getUserBalances('test_user');
      final btcBalance = ServiceLocator.get<BalanceManager>().getTokenBalance('test_user', 'BTC');
      
      // Test up-to-date check
      final upToDate = ServiceLocator.get<BalanceManager>().areBalancesUpToDate('test_user');
      
      SecureLog.i('BalanceStabilityTest: Quick validation passed');
      SecureLog.d('Balances count: ${balances.length}');
      SecureLog.d('BTC balance: $btcBalance');
      SecureLog.d('Up to date: $upToDate');
      
      return true;
      
    } catch (e) {
      SecureLog.e('BalanceStabilityTest: Quick validation failed', error: e);
      return false;
    }
  }
}
