import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../di/service_locator.dart';
import '../domain/interfaces/i_balance_manager.dart';
import '../models/crypto_token.dart';
import '../services/secure_storage.dart';
import '../services/api_service.dart';
import '../services/on_chain_balance_service.dart';
import '../utils/secure_log.dart';

/// مدیریت پایدار موجودی‌ها با کشینگ و refresh خودکار
/// این کلاس اطمینان می‌دهد که موجودی‌ها همیشه به‌روز و قابل نمایش باشند
class BalanceManager extends ChangeNotifier implements IBalanceManager {
  static BalanceManager get instance => ServiceLocator.get<BalanceManager>();
  
  BalanceManager._();
  /// DI constructor. Use [instance] for singleton access.
  BalanceManager() : super();
  
  // Core components
  late ApiService _apiService;
  
  // Balance state management
  final Map<String, Map<String, double>> _userBalances = {};
  final Map<String, DateTime> _lastBalanceUpdate = {};
  final Map<String, List<String>> _activeTokensPerUser = {};
  
  // Cache configuration
  static const Duration _balanceCacheValidity = Duration(minutes: 3);
  static const Duration _refreshInterval = Duration(seconds: 90);
  static const Duration _persistenceInterval = Duration(seconds: 30);
  
  // Timers and state
  Timer? _refreshTimer;
  Timer? _persistenceTimer;
  bool _isInitialized = false;
  String? _currentUserId;
  String? _currentWalletName;
  bool _isAppStartup = true; // Track if this is app startup
  
  // Thread safety
  final Map<String, Completer<void>> _refreshLocks = {};
  final Map<String, Completer<void>> _initializationLocks = {};
  
  /// مقداردهی اولیه
  Future<void> initialize(ApiService apiService) async {
    if (_isInitialized) return;
    
    _apiService = apiService;
    
    SecureLog.i('BalanceManager: Initializing...');
    
    try {
      // Load current wallet context
      await _loadCurrentWalletContext();
      
      // Restore cached balances for all users
      await _restoreAllUserBalances();
      
      // Start periodic operations
      _startPeriodicRefresh();
      _startPeriodicPersistence();
      
      _isInitialized = true;
      SecureLog.i('BalanceManager: Initialized successfully');
      
    } catch (e) {
      SecureLog.e('BalanceManager: Error during initialization', error: e);
      rethrow;
    }
  }
  
  /// تنظیم کاربر و کیف پول فعلی
  @override
  Future<void> setCurrentUserAndWallet(String userId, String walletName) async {
    // Prevent concurrent initialization
    final lockKey = '${userId}_$walletName';
    if (_initializationLocks.containsKey(lockKey)) {
      SecureLog.i('BalanceManager: Already initializing for current user/wallet, waiting...');
      await _initializationLocks[lockKey]!.future;
      return;
    }
    
    if (_currentUserId == userId && _currentWalletName == walletName && !_isAppStartup) {
      return; // No change needed unless this is app startup
    }
    
    SecureLog.i('BalanceManager: Setting current user/wallet (startup: $_isAppStartup)');
    
    final completer = Completer<void>();
    _initializationLocks[lockKey] = completer;
    
    try {
      // Save current user's state before switching (but not during app startup)
      if (_currentUserId != null && _currentWalletName != null && !_isAppStartup) {
        await _persistUserBalances(_currentUserId!);
      }
      
      _currentUserId = userId;
      _currentWalletName = walletName;
      
      // Load balances for new user/wallet
      await _loadUserBalances(userId, walletName);
      
      // During app startup, wait a bit for other systems to initialize
      if (_isAppStartup) {
        SecureLog.i('BalanceManager: App startup detected, waiting for stabilization...');
        await Future.delayed(const Duration(milliseconds: 500));
        _isAppStartup = false; // Mark startup complete
      }
      
      // Force immediate refresh only if we don't have recent cached data
      if (!areBalancesUpToDate(userId)) {
        SecureLog.i('BalanceManager: No recent balances, forcing refresh...');
        await refreshBalancesForUser(userId, force: true);
      } else {
        SecureLog.i('BalanceManager: Using cached balances (still valid)');
      }
      
      notifyListeners();
      
    } finally {
      _initializationLocks.remove(lockKey);
      completer.complete();
    }
  }
  
  /// تنظیم توکن‌های فعال برای کاربر
  void setActiveTokensForUser(String userId, List<String> tokenSymbols) {
    final previousTokens = _activeTokensPerUser[userId] ?? [];
    _activeTokensPerUser[userId] = List.from(tokenSymbols);
    
    // ⚡ FIXED: Only refresh if tokens actually changed AND we don't have recent data
    if (!_listsEqual(previousTokens, tokenSymbols)) {
      SecureLog.i('BalanceManager: Active tokens changed for current user');
      
      // Only refresh if we don't have recent cached data
      if (!areBalancesUpToDate(userId)) {
        SecureLog.i('BalanceManager: No recent cached data, scheduling refresh');
        Timer(const Duration(milliseconds: 500), () {
          try {
            refreshBalancesForUser(userId, force: false); // ⚡ Changed to force: false
          } catch (e) {
            SecureLog.w('BalanceManager: scheduled refresh failed', error: e);
          }
        });
      } else {
        SecureLog.i('BalanceManager: Have recent cached data, skipping automatic refresh');
      }
    }
  }
  
  /// دریافت موجودی توکن خاص
  double getTokenBalance(String userId, String symbol) {
    final balance = _userBalances[userId]?[symbol] ?? 0.0;
    
    // Debug logging for troubleshooting
    if (balance == 0.0) {
      SecureLog.d('BalanceManager: No balance found for $symbol');
      SecureLog.d('BalanceManager: Available balance keys: ${_userBalances[userId]?.keys.toList() ?? "none"}');
    } else {
      SecureLog.d('BalanceManager: Found balance for $symbol: $balance');
    }
    
    return balance;
  }

  /// دریافت تمام کلیدهای موجودی برای debug
  void debugBalanceKeys(String userId) {
    final balances = _userBalances[userId] ?? {};
    SecureLog.d('BalanceManager DEBUG - All balance keys for current user:');
    balances.forEach((key, value) {
      SecureLog.d('   $key: $value');
    });
  }
  
  /// دریافت تمام موجودی‌های کاربر
  Map<String, double> getUserBalances(String userId) {
    return Map.from(_userBalances[userId] ?? {});
  }

  /// تنظیم موجودی‌های کاربر (برای cache restore)
  Future<void> setUserBalances(String userId, Map<String, double> balances) async {
    try {
      _userBalances[userId] = Map.from(balances);
      _lastBalanceUpdate[userId] = DateTime.now();
      
      // Persist to cache
      await _persistUserBalances(userId);
      
      notifyListeners();
      SecureLog.i('BalanceManager: Set ${balances.length} balances from cache');
    } catch (e) {
      SecureLog.e('BalanceManager: Error setting user balances', error: e);
    }
  }
  
  /// بررسی اینکه آیا موجودی‌ها به‌روز هستند
  bool areBalancesUpToDate(String userId) {
    final lastUpdate = _lastBalanceUpdate[userId];
    if (lastUpdate == null) return false;
    
    final age = DateTime.now().difference(lastUpdate);
    return age < _balanceCacheValidity;
  }
  
  /// refresh موجودی‌ها برای کاربر خاص
  Future<void> refreshBalancesForUser(String userId, {bool force = false}) async {
    // Check if already refreshing
    if (_refreshLocks.containsKey(userId)) {
      SecureLog.i('BalanceManager: Already refreshing for current user, waiting...');
      await _refreshLocks[userId]!.future;
      return;
    }
    
    // During app startup, be more conservative about API calls
    if (_isAppStartup && !force) {
      SecureLog.i('BalanceManager: Skipping API refresh during app startup (use cached data)');
      return;
    }
    
    // Check if refresh is needed
    if (!force && areBalancesUpToDate(userId)) {
      SecureLog.i('BalanceManager: Balances are up to date');
      return;
    }
    
    final completer = Completer<void>();
    _refreshLocks[userId] = completer;
    
    try {
      SecureLog.i('BalanceManager: Refreshing balances (force: $force)');
      
      // Get active tokens for this user
      final activeTokens = _activeTokensPerUser[userId] ?? [];
      if (activeTokens.isEmpty) {
        SecureLog.w('BalanceManager: No active tokens, skipping refresh');
        return;
      }
      
      final symbols = activeTokens.map((e) => e.toString()).toList();
      final tokens = symbols
          .map(
            (s) => CryptoToken(
              symbol: s,
              name: s,
              blockchainName: '',
              isEnabled: true,
              isToken: false,
            ),
          )
          .toList();
      final raw = await ServiceLocator.get<OnChainBalanceService>().balancesForActiveTokens(
        userId,
        tokens,
      );
      if (raw.isNotEmpty) {
        final newBalances = <String, double>{};
        for (final entry in raw.entries) {
          final amount = double.tryParse(entry.value) ?? 0.0;
          // Only store the blockchain-qualified key (e.g. "USDT_Tron").
          // Previously we also stored a flat key "USDT" which caused
          // multi-chain tokens (e.g. DOT on Polkadot vs DOT on BSC)
          // to overwrite each other — the last writer won non-deterministically.
          newBalances[entry.key] = amount;
        }
        
        // Update internal state with protection against empty responses
        if (newBalances.isNotEmpty && !_shouldPreventZeroBalances(userId, newBalances)) {
          // Backup current balances before updating
          final backup = _backupUserBalances(userId);
          
          _userBalances[userId] = newBalances;
          _lastBalanceUpdate[userId] = DateTime.now();
          
          // Persist immediately
          await _persistUserBalances(userId);
          
          SecureLog.i('BalanceManager: Updated ${newBalances.length} balances');
          
          // Notify listeners
          notifyListeners();
        } else {
          SecureLog.w('BalanceManager: API returned empty/suspicious balances, keeping cached data');
          // Still update timestamp to avoid too frequent API calls
          _lastBalanceUpdate[userId] = DateTime.now();
        }
        
      } else {
        SecureLog.e('BalanceManager: API failed to fetch balances');
      }
      
    } catch (e) {
      SecureLog.e('BalanceManager: Error refreshing balances', error: e);
    } finally {
      _refreshLocks.remove(userId);
      completer.complete();
    }
  }
  
  /// شروع periodic refresh
  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    
    _refreshTimer = Timer.periodic(_refreshInterval, (timer) {
      try {
        if (_currentUserId != null) {
          refreshBalancesForUser(_currentUserId!, force: false);
        }
      } catch (e) {
        SecureLog.w('BalanceManager: periodic refresh failed', error: e);
      }
    });
    
    SecureLog.i('BalanceManager: Started periodic refresh every ${_refreshInterval.inSeconds} seconds');
  }
  
  /// شروع periodic persistence
  void _startPeriodicPersistence() {
    _persistenceTimer?.cancel();
    
    _persistenceTimer = Timer.periodic(_persistenceInterval, (timer) {
      try {
        _persistAllUserBalances();
      } catch (e) {
        SecureLog.w('BalanceManager: periodic persistence failed', error: e);
      }
    });
    
    SecureLog.i('BalanceManager: Started periodic persistence every ${_persistenceInterval.inSeconds} seconds');
  }
  
  /// بارگذاری context کیف پول فعلی
  Future<void> _loadCurrentWalletContext() async {
    try {
      final selectedWallet = await ServiceLocator.get<SecureStorage>().getSelectedWallet();
      final selectedUserId = await ServiceLocator.get<SecureStorage>().getSelectedUserId();
      
      if (selectedWallet != null && selectedUserId != null) {
        _currentWalletName = selectedWallet;
        _currentUserId = selectedUserId;
        SecureLog.i('BalanceManager: Loaded current context');
      }
    } catch (e) {
      SecureLog.e('BalanceManager: Error loading wallet context', error: e);
    }
  }
  
  /// بازیابی موجودی‌های cached برای همه کاربران
  Future<void> _restoreAllUserBalances() async {
    try {
      // Get all wallet users from secure storage
      final wallets = await ServiceLocator.get<SecureStorage>().getWalletsList();
      
      for (final wallet in wallets) {
        final userId = wallet['userID'];
        final walletName = wallet['walletName'];
        
        if (userId != null && walletName != null) {
          await _loadUserBalances(userId, walletName);
        }
      }
      
      SecureLog.i('BalanceManager: Restored balances for ${_userBalances.length} users');
      
    } catch (e) {
      SecureLog.e('BalanceManager: Error restoring user balances', error: e);
    }
  }
  
  /// بارگذاری موجودی‌ها برای کاربر خاص
  Future<void> _loadUserBalances(String userId, String walletName) async {
    try {
      // Load from SecureStorage (per-wallet cache)
      final cachedBalances = await ServiceLocator.get<SecureStorage>().getWalletBalanceCache(walletName, userId);
      
      if (cachedBalances.isNotEmpty) {
        _userBalances[userId] = cachedBalances;
        SecureLog.i('BalanceManager: Loaded ${cachedBalances.length} cached balances');
      }
      
      // Load from SharedPreferences (fallback cache)
      final prefs = await SharedPreferences.getInstance();
      final balanceJson = prefs.getString('balance_manager_$userId');
      
      if (balanceJson != null) {
        final balanceData = json.decode(balanceJson) as Map<String, dynamic>;
        
        if (balanceData['balances'] != null) {
          final balances = Map<String, double>.from(
            (balanceData['balances'] as Map).map(
              (key, value) => MapEntry(key, (value as num).toDouble()),
            ),
          );
          
          // Use cached balances if they're more recent or if SecureStorage was empty
          if (_userBalances[userId]?.isEmpty ?? true) {
            _userBalances[userId] = balances;
          }
        }
        
        if (balanceData['lastUpdate'] != null) {
          _lastBalanceUpdate[userId] = DateTime.fromMillisecondsSinceEpoch(
            balanceData['lastUpdate'] as int,
          );
        }
      }
      
      // Active tokens are managed by TokenPreferences (single source of truth).
      // Previous code also read from SecureStorage here, creating redundant storage
      // without atomicity — removed to maintain consistency.
      
    } catch (e) {
      SecureLog.e('BalanceManager: Error loading balances', error: e);
    }
  }
  
  /// ذخیره موجودی‌ها برای کاربر خاص
  Future<void> _persistUserBalances(String userId) async {
    try {
      final balances = _userBalances[userId] ?? {};
      final lastUpdate = _lastBalanceUpdate[userId] ?? DateTime.now();
      
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final balanceData = {
        'balances': balances,
        'lastUpdate': lastUpdate.millisecondsSinceEpoch,
      };
      
      await prefs.setString('balance_manager_$userId', json.encode(balanceData));
      
      // Save to SecureStorage (per-wallet)
      if (_currentWalletName != null && userId == _currentUserId) {
        await ServiceLocator.get<SecureStorage>().saveWalletBalanceCache(
          _currentWalletName!,
          userId,
          balances,
        );
      }
      
      SecureLog.i('BalanceManager: Persisted ${balances.length} balances');
      
    } catch (e) {
      SecureLog.e('BalanceManager: Error persisting balances', error: e);
    }
  }
  
  /// ذخیره موجودی‌های همه کاربران
  Future<void> _persistAllUserBalances() async {
    for (final userId in _userBalances.keys) {
      await _persistUserBalances(userId);
    }
  }
  
  /// متد کمکی برای مقایسه لیست‌ها
  bool _listsEqual<T>(List<T> list1, List<T> list2) {
    if (list1.length != list2.length) return false;
    return list1.every(list2.contains);
  }
  
  /// پاکسازی و تنظیم مجدد
  Future<void> clearAllBalances() async {
    _userBalances.clear();
    _lastBalanceUpdate.clear();
    _activeTokensPerUser.clear();
    
    // Clear from persistent storage
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys()
          .where((key) => key.startsWith('balance_manager_'))
          .toList();
      
      for (final key in keys) {
        await prefs.remove(key);
      }
      
      SecureLog.i('BalanceManager: Cleared all balance data');
      
    } catch (e) {
      SecureLog.e('BalanceManager: Error clearing balance data', error: e);
    }
    
    notifyListeners();
  }
  
  /// backup موجودی‌ها قبل از تغییرات مهم
  Map<String, double> _backupUserBalances(String userId) {
    return Map.from(_userBalances[userId] ?? {});
  }
  
  /// restore موجودی‌ها در صورت مشکل
  void _restoreUserBalances(String userId, Map<String, double> backup) {
    if (backup.isNotEmpty) {
      _userBalances[userId] = backup;
      notifyListeners();
      SecureLog.i('BalanceManager: Restored ${backup.length} balances from backup');
    }
  }
  
  /// بررسی و محافظت از صفر شدن موجودی‌ها
  bool _shouldPreventZeroBalances(String userId, Map<String, double> newBalances) {
    final currentBalances = _userBalances[userId] ?? {};
    
    // If current balances exist and new balances are empty, prevent the update
    if (currentBalances.isNotEmpty && newBalances.isEmpty) {
      SecureLog.w('BalanceManager: Preventing zero balance update (current: ${currentBalances.length}, new: 0)');
      return true;
    }
    
    // ⚡ ENHANCED PROTECTION: More conservative approach
    final currentNonZero = currentBalances.values.where((v) => v > 0).length;
    final newNonZero = newBalances.values.where((v) => v > 0).length;
    
    // If we have any current balances and new response has all zeros, be very cautious
    if (currentNonZero >= 1 && newNonZero == 0) {
      SecureLog.w('BalanceManager: Preventing suspicious zero balance update (current non-zero: $currentNonZero, new non-zero: 0)');
      return true;
    }
    
    // Also check if we're losing significant value
    final currentTotal = currentBalances.values.fold(0.0, (sum, balance) => sum + balance);
    final newTotal = newBalances.values.fold(0.0, (sum, balance) => sum + balance);
    
    if (currentTotal > 0.001 && newTotal == 0.0) {
      SecureLog.w('BalanceManager: Preventing total balance loss (current: $currentTotal, new: $newTotal)');
      return true;
    }
    
    return false;
  }
  
  /// اطلاعات debug
  void debugBalanceState() {
    SecureLog.i('=== BalanceManager Debug ===');
    SecureLog.i('Current Wallet: $_currentWalletName');
    SecureLog.i('Is App Startup: $_isAppStartup');
    SecureLog.i('Total Users: ${_userBalances.length}');
    
    for (final userId in _userBalances.keys) {
      final balances = _userBalances[userId] ?? {};
      final lastUpdate = _lastBalanceUpdate[userId];
      final activeTokens = _activeTokensPerUser[userId] ?? [];
      
      SecureLog.i('User balances: ${balances.length}');
      SecureLog.i('  Non-zero balances: ${balances.values.where((v) => v > 0).length}');
      SecureLog.i('  Active Tokens: ${activeTokens.length}');
      SecureLog.i('  Last Update: $lastUpdate');
      SecureLog.i('  Up to Date: ${areBalancesUpToDate(userId)}');
    }
    SecureLog.i('==========================');
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    _persistenceTimer?.cancel();
    
    // Final persistence
    try {
      _persistAllUserBalances();
    } catch (e) {
      SecureLog.w('BalanceManager: final persistence failed', error: e);
    }
    
    super.dispose();
  }
}
