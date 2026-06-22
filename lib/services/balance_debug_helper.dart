import '../providers/app_provider.dart';
import 'balance_manager.dart';
import '../di/service_locator.dart';
import '../utils/secure_log.dart';

/// Helper class برای debug کردن مشکلات موجودی
class BalanceDebugHelper {
  
  /// تست کامل وضعیت موجودی‌ها در سیستم
  static void debugFullBalanceState(AppProvider appProvider) {
    SecureLog.d('=== BALANCE DEBUG HELPER ===');
    
    // 1. Check AppProvider state
    SecureLog.d('1. AppProvider State:');
    SecureLog.d('   Current Wallet: ${appProvider.currentWalletName}');
    SecureLog.d('   TokenProvider available: ${appProvider.tokenProvider != null}');
    
    // 2. Check TokenProvider state
    if (appProvider.tokenProvider != null) {
      final tokenProvider = appProvider.tokenProvider!;
      SecureLog.d('2. TokenProvider State:');
      SecureLog.d('   Is initialized: ${tokenProvider.isInitialized}');
      SecureLog.d('   Is fully ready: ${tokenProvider.isFullyReady}');
      SecureLog.d('   Total currencies: ${tokenProvider.currencies.length}');
      SecureLog.d('   Active tokens: ${tokenProvider.activeTokens.length}');
      SecureLog.d('   Enabled tokens: ${tokenProvider.enabledTokens.length}');
      
      // List tokens with their amounts
      SecureLog.d('3. Token Details:');
      for (final token in tokenProvider.enabledTokens) {
        SecureLog.d('   ${token.symbol}: amount=${token.amount}, enabled=${token.isEnabled}');
      }
    } else {
      SecureLog.d('2. TokenProvider State: NULL');
    }
    
    // 3. Check BalanceManager state
    SecureLog.d('4. BalanceManager State:');
    ServiceLocator.get<BalanceManager>().debugBalanceState();
    
    // 4. Cross-check specific tokens
    if (appProvider.tokenProvider != null && appProvider.currentUserId != null) {
      SecureLog.d('5. Cross-check balances:');
      for (final token in appProvider.tokenProvider!.enabledTokens.take(5)) {
        final tokenAmount = token.amount ?? 0.0;
        final managerAmount = ServiceLocator.get<BalanceManager>().getTokenBalance(appProvider.currentUserId!, token.symbol ?? '');
        SecureLog.d('   ${token.symbol}: Token=$tokenAmount, Manager=$managerAmount');
      }
    }
    
    SecureLog.d('==========================');
  }
  
  /// تست سریع برای نمایش وضعیت
  static void quickCheck(AppProvider appProvider) {
    SecureLog.d('🔍 Quick Balance Check:');
    SecureLog.d('   Wallet: ${appProvider.currentWalletName}');
    SecureLog.d('   TokenProvider ready: ${appProvider.tokenProvider?.isFullyReady}');
    SecureLog.d('   Enabled tokens: ${appProvider.tokenProvider?.enabledTokens.length ?? 0}');
    
    if (appProvider.tokenProvider != null) {
      final hasBalances = appProvider.tokenProvider!.enabledTokens.any((t) => (t.amount ?? 0.0) > 0);
      SecureLog.d('   Has token balances: $hasBalances');
    }
    
    if (appProvider.currentUserId != null) {
      final managerBalances = ServiceLocator.get<BalanceManager>().getUserBalances(appProvider.currentUserId!);
      SecureLog.d('   Manager balances: ${managerBalances.length}');
    }
  }
}
