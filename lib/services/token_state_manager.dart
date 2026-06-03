import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/crypto_token.dart';

/// Single Source of Truth برای Token State Management
/// این کلاس تمام state توکن‌ها را مدیریت می‌کند و race conditions را جلوگیری می‌کند
class TokenStateManager extends ChangeNotifier {
  static TokenStateManager? _instance;
  static TokenStateManager get instance => _instance ??= TokenStateManager._();
  
  TokenStateManager._();
  
  // State variables
  final Map<String, List<CryptoToken>> _userTokens = {};
  final Map<String, Set<String>> _userActiveTokens = {};
  final Map<String, Map<String, double>> _userBalances = {};
  final Map<String, DateTime> _lastBalanceUpdate = {};
  
  // Locks for thread safety
  final Map<String, Completer<void>> _stateLocks = {};
  final Map<String, Completer<void>> _balanceLocks = {};
  
  // Current user context
  String? _currentUserId;
  String? _currentWalletName;
  
  // Getters
  String? get currentUserId => _currentUserId;
  String? get currentWalletName => _currentWalletName;
  
  /// مقداردهی اولیه با user و wallet
  Future<void> initialize(String userId, String walletName) async {
    print('🔄 TokenStateManager: Initializing for user: $userId, wallet: $walletName');
    
    // Wait for any existing operations to complete
    await _waitForStateLock(userId);
    
    _currentUserId = userId;
    _currentWalletName = walletName;
    
    // Load saved state
    await _loadUserTokenState(userId, walletName);
    
    print('✅ TokenStateManager: Initialized successfully');
  }
  
  /// دریافت لیست کامل توکن‌ها برای کاربر
  List<CryptoToken> getUserTokens(String userId) {
    return _userTokens[userId] ?? [];
  }
  
  /// دریافت توکن‌های فعال برای کاربر
  List<CryptoToken> getActiveTokens(String userId) {
    final allTokens = _userTokens[userId] ?? [];
    final activeSet = _userActiveTokens[userId] ?? {};
    
    return allTokens.where((token) {
      final key = _getTokenKey(token);
      return activeSet.contains(key);
    }).toList();
  }
  
  /// بررسی فعال بودن توکن
  bool isTokenActive(String userId, CryptoToken token) {
    final activeSet = _userActiveTokens[userId] ?? {};
    final key = _getTokenKey(token);
    return activeSet.contains(key);
  }
  
  /// تغییر وضعیت توکن (Thread-Safe)
  Future<bool> toggleToken(String userId, CryptoToken token, bool isActive) async {
    print('🔄 TokenStateManager: Toggling ${token.symbol} to $isActive for user: $userId');
    
    // Acquire lock for thread safety
    await _acquireStateLock(userId);
    
    try {
      final activeSet = _userActiveTokens[userId] ??= {};
      final key = _getTokenKey(token);
      
      if (isActive) {
        activeSet.add(key);
      } else {
        activeSet.remove(key);
      }
      
      // Update token in user tokens list
      final userTokens = _userTokens[userId] ?? [];
      final tokenIndex = userTokens.indexWhere((t) => _getTokenKey(t) == key);
      
      if (tokenIndex >= 0) {
        userTokens[tokenIndex] = token.copyWith(isEnabled: isActive);
      }
      
      // Persist changes
      await _persistUserTokenState(userId);
      
      // Notify listeners
      notifyListeners();
      
      print('✅ TokenStateManager: Token ${token.symbol} toggled to $isActive');
      return true;
      
    } catch (e) {
      print('❌ TokenStateManager: Error toggling token: $e');
      return false;
    } finally {
      _releaseStateLock(userId);
    }
  }
  
  /// به‌روزرسانی لیست کامل توکن‌ها
  Future<void> updateUserTokens(String userId, List<CryptoToken> tokens) async {
    print('🔄 TokenStateManager: Updating ${tokens.length} tokens for user: $userId');
    
    await _acquireStateLock(userId);
    
    try {
      _userTokens[userId] = List.from(tokens);
      
      // Update active set based on token states
      final activeSet = _userActiveTokens[userId] ??= {};
      activeSet.clear();
      
      for (final token in tokens) {
        if (token.isEnabled) {
          activeSet.add(_getTokenKey(token));
        }
      }
      
      await _persistUserTokenState(userId);
      notifyListeners();
      
      print('✅ TokenStateManager: Updated ${tokens.length} tokens, ${activeSet.length} active');
      
    } finally {
      _releaseStateLock(userId);
    }
  }
  
  /// به‌روزرسانی موجودی توکن‌ها (Thread-Safe)
  Future<void> updateBalances(String userId, Map<String, double> balances) async {
    print('🔄 TokenStateManager: Updating ${balances.length} balances for user: $userId');
    
    await _acquireBalanceLock(userId);
    
    try {
      final userBalances = _userBalances[userId] ??= {};
      userBalances.addAll(balances);
      
      // Update balance timestamp
      _lastBalanceUpdate[userId] = DateTime.now();
      
      // Update tokens with new balances
      final userTokens = _userTokens[userId];
      if (userTokens != null) {
        for (int i = 0; i < userTokens.length; i++) {
          final token = userTokens[i];
          final balance = balances[token.symbol];
          if (balance != null) {
            userTokens[i] = token.copyWith(amount: balance);
          }
        }
      }
      
      // Persist balance cache
      await _persistBalanceCache(userId);
      
      notifyListeners();
      
      print('✅ TokenStateManager: Updated ${balances.length} balances');
      
    } finally {
      _releaseBalanceLock(userId);
    }
  }
  
  /// دریافت موجودی توکن
  double getTokenBalance(String userId, String symbol) {
    final userBalances = _userBalances[userId] ?? {};
    return userBalances[symbol] ?? 0.0;
  }
  
  /// دریافت زمان آخرین به‌روزرسانی موجودی
  DateTime? getLastBalanceUpdate(String userId) {
    return _lastBalanceUpdate[userId];
  }
  
  /// پاکسازی داده‌های کاربر
  Future<void> clearUserData(String userId) async {
    print('🧹 TokenStateManager: Clearing data for user: $userId');
    
    await _acquireStateLock(userId);
    await _acquireBalanceLock(userId);
    
    try {
      _userTokens.remove(userId);
      _userActiveTokens.remove(userId);
      _userBalances.remove(userId);
      _lastBalanceUpdate.remove(userId);
      
      // Clear persisted data
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token_state_$userId');
      await prefs.remove('balance_cache_$userId');
      
      notifyListeners();
      
      print('✅ TokenStateManager: Cleared data for user: $userId');
      
    } finally {
      _releaseStateLock(userId);
      _releaseBalanceLock(userId);
    }
  }
  
  // Private helper methods
  
  String _getTokenKey(CryptoToken token) {
    return '${token.symbol}_${token.blockchainName}_${token.smartContractAddress ?? ''}';
  }
  
  Future<void> _acquireStateLock(String userId) async {
    while (_stateLocks.containsKey(userId)) {
      await _stateLocks[userId]!.future;
    }
    _stateLocks[userId] = Completer<void>();
  }
  
  void _releaseStateLock(String userId) {
    final completer = _stateLocks.remove(userId);
    completer?.complete();
  }
  
  Future<void> _waitForStateLock(String userId) async {
    final completer = _stateLocks[userId];
    if (completer != null) {
      await completer.future;
    }
  }
  
  Future<void> _acquireBalanceLock(String userId) async {
    while (_balanceLocks.containsKey(userId)) {
      await _balanceLocks[userId]!.future;
    }
    _balanceLocks[userId] = Completer<void>();
  }
  
  void _releaseBalanceLock(String userId) {
    final completer = _balanceLocks.remove(userId);
    completer?.complete();
  }
  
  Future<void> _loadUserTokenState(String userId, String walletName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load token state
      final stateJson = prefs.getString('token_state_$userId');
      if (stateJson != null) {
        final stateData = json.decode(stateJson) as Map<String, dynamic>;
        
        // Load tokens
        if (stateData['tokens'] != null) {
          final tokensList = stateData['tokens'] as List;
          _userTokens[userId] = tokensList
              .map((tokenJson) => CryptoToken.fromJson(tokenJson))
              .toList();
        }
        
        // Load active tokens set
        if (stateData['activeTokens'] != null) {
          final activeList = stateData['activeTokens'] as List;
          _userActiveTokens[userId] = activeList.cast<String>().toSet();
        }
      }
      
      // Load balance cache
      final balanceJson = prefs.getString('balance_cache_$userId');
      if (balanceJson != null) {
        final balanceData = json.decode(balanceJson) as Map<String, dynamic>;
        
        if (balanceData['balances'] != null) {
          final balancesMap = balanceData['balances'] as Map<String, dynamic>;
          _userBalances[userId] = balancesMap.map(
            (key, value) => MapEntry(key, (value as num).toDouble()),
          );
        }
        
        if (balanceData['lastUpdate'] != null) {
          _lastBalanceUpdate[userId] = DateTime.fromMillisecondsSinceEpoch(
            balanceData['lastUpdate'] as int,
          );
        }
      }
      
      print('✅ TokenStateManager: Loaded state for user: $userId');
      
    } catch (e) {
      print('❌ TokenStateManager: Error loading user state: $e');
    }
  }
  
  Future<void> _persistUserTokenState(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final stateData = {
        'tokens': _userTokens[userId]?.map((t) => t.toJson()).toList() ?? [],
        'activeTokens': _userActiveTokens[userId]?.toList() ?? [],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      await prefs.setString('token_state_$userId', json.encode(stateData));
      
      print('✅ TokenStateManager: Persisted token state for user: $userId');
      
    } catch (e) {
      print('❌ TokenStateManager: Error persisting token state: $e');
    }
  }
  
  Future<void> _persistBalanceCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final balanceData = {
        'balances': _userBalances[userId] ?? {},
        'lastUpdate': _lastBalanceUpdate[userId]?.millisecondsSinceEpoch ?? 
                     DateTime.now().millisecondsSinceEpoch,
      };
      
      await prefs.setString('balance_cache_$userId', json.encode(balanceData));
      
      print('✅ TokenStateManager: Persisted balance cache for user: $userId');
      
    } catch (e) {
      print('❌ TokenStateManager: Error persisting balance cache: $e');
    }
  }
  
  /// Debug method
  void debugState() {
    print('=== TokenStateManager Debug ===');
    print('Current User: $_currentUserId');
    print('Current Wallet: $_currentWalletName');
    print('Users with tokens: ${_userTokens.keys.toList()}');
    print('Users with active tokens: ${_userActiveTokens.keys.toList()}');
    print('Users with balances: ${_userBalances.keys.toList()}');
    
    if (_currentUserId != null) {
      final tokens = _userTokens[_currentUserId!] ?? [];
      final active = _userActiveTokens[_currentUserId!] ?? {};
      final balances = _userBalances[_currentUserId!] ?? {};
      
      print('Current user tokens: ${tokens.length}');
      print('Current user active: ${active.length}');
      print('Current user balances: ${balances.length}');
    }
    print('==============================');
  }
}
