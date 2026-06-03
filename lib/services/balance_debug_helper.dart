import '../providers/app_provider.dart';
import 'balance_manager.dart';

/// Helper class برای debug کردن مشکلات موجودی
class BalanceDebugHelper {
  
  /// تست کامل وضعیت موجودی‌ها در سیستم
  static void debugFullBalanceState(AppProvider appProvider) {
    print('=== BALANCE DEBUG HELPER ===');
    
    // 1. Check AppProvider state
    print('1. AppProvider State:');
    print('   Current User ID: ${appProvider.currentUserId}');
    print('   Current Wallet: ${appProvider.currentWalletName}');
    print('   TokenProvider available: ${appProvider.tokenProvider != null}');
    
    // 2. Check TokenProvider state
    if (appProvider.tokenProvider != null) {
      final tokenProvider = appProvider.tokenProvider!;
      print('2. TokenProvider State:');
      print('   Is initialized: ${tokenProvider.isInitialized}');
      print('   Is fully ready: ${tokenProvider.isFullyReady}');
      print('   Total currencies: ${tokenProvider.currencies.length}');
      print('   Active tokens: ${tokenProvider.activeTokens.length}');
      print('   Enabled tokens: ${tokenProvider.enabledTokens.length}');
      
      // List tokens with their amounts
      print('3. Token Details:');
      for (final token in tokenProvider.enabledTokens) {
        print('   ${token.symbol}: amount=${token.amount}, enabled=${token.isEnabled}');
      }
    } else {
      print('2. TokenProvider State: NULL');
    }
    
    // 3. Check BalanceManager state
    print('4. BalanceManager State:');
    BalanceManager.instance.debugBalanceState();
    
    // 4. Cross-check specific tokens
    if (appProvider.tokenProvider != null && appProvider.currentUserId != null) {
      print('5. Cross-check balances:');
      final userId = appProvider.currentUserId!;
      for (final token in appProvider.tokenProvider!.enabledTokens.take(5)) {
        final tokenAmount = token.amount ?? 0.0;
        final managerAmount = BalanceManager.instance.getTokenBalance(userId, token.symbol ?? '');
        print('   ${token.symbol}: Token=$tokenAmount, Manager=$managerAmount');
      }
    }
    
    print('==========================');
  }
  
  /// تست سریع برای نمایش وضعیت
  static void quickCheck(AppProvider appProvider) {
    print('🔍 Quick Balance Check:');
    print('   User: ${appProvider.currentUserId}');
    print('   Wallet: ${appProvider.currentWalletName}');
    print('   TokenProvider ready: ${appProvider.tokenProvider?.isFullyReady}');
    print('   Enabled tokens: ${appProvider.tokenProvider?.enabledTokens.length ?? 0}');
    
    if (appProvider.tokenProvider != null) {
      final hasBalances = appProvider.tokenProvider!.enabledTokens.any((t) => (t.amount ?? 0.0) > 0);
      print('   Has token balances: $hasBalances');
    }
    
    if (appProvider.currentUserId != null) {
      final managerBalances = BalanceManager.instance.getUserBalances(appProvider.currentUserId!);
      print('   Manager balances: ${managerBalances.length}');
    }
  }
}
