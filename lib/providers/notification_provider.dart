import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import '../models/notification_models.dart';
import '../services/service_provider.dart';
import '../services/secure_storage.dart';
import '../services/firebase_messaging_service.dart';

/// Central state manager for all notification features (P1–P5).
///
/// Manages:
/// - Device registration state
/// - Security notification triggers (P2)
/// - Price alerts CRUD (P3)
/// - Notification preferences
/// - Admin notification panel state (P4, P5)
class NotificationProvider extends ChangeNotifier {
  // ─── Singleton ──────────────────────────────────────────────────────────
  NotificationProvider._();
  static final NotificationProvider instance = NotificationProvider._();

  // ─── Preferences ────────────────────────────────────────────────────────
  bool _pushEnabled = true;
  bool _transactionNotifications = true;
  bool _securityNotifications = true;
  bool _priceAlertNotifications = true;
  bool _networkNotifications = true;
  bool _engagementNotifications = true;

  bool get pushEnabled => _pushEnabled;
  bool get transactionNotifications => _transactionNotifications;
  bool get securityNotifications => _securityNotifications;
  bool get priceAlertNotifications => _priceAlertNotifications;
  bool get networkNotifications => _networkNotifications;
  bool get engagementNotifications => _engagementNotifications;

  // ─── Price Alerts State ─────────────────────────────────────────────────
  List<PriceAlertItem> _priceAlerts = [];
  bool _priceAlertsLoading = false;
  String? _priceAlertsError;

  /// Current prices keyed by symbol (e.g. "BTC" → 74500.0)
  /// Fetched alongside alerts so each card shows the live price.
  Map<String, double> _currentPrices = {};

  List<PriceAlertItem> get priceAlerts => _priceAlerts;
  bool get priceAlertsLoading => _priceAlertsLoading;
  String? get priceAlertsError => _priceAlertsError;
  Map<String, double> get currentPrices => _currentPrices;

  // ─── Notification History (local cache) ─────────────────────────────────
  List<LocalNotificationEntry> _notificationHistory = [];
  int _unreadCount = 0;

  List<LocalNotificationEntry> get notificationHistory => _notificationHistory;
  int get unreadCount => _unreadCount;

  // ─── Initialization ─────────────────────────────────────────────────────

  Future<void> initialize() async {
    await _loadPreferences();
    notifyListeners();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _pushEnabled = prefs.getBool('notif_push_enabled') ?? true;
      _transactionNotifications = prefs.getBool('notif_transactions') ?? true;
      _securityNotifications = prefs.getBool('notif_security') ?? true;
      _priceAlertNotifications = prefs.getBool('notif_price_alerts') ?? true;
      _networkNotifications = prefs.getBool('notif_network') ?? true;
      _engagementNotifications = prefs.getBool('notif_engagement') ?? true;
    } catch (_) {}
  }

  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notif_push_enabled', _pushEnabled);
      await prefs.setBool('notif_transactions', _transactionNotifications);
      await prefs.setBool('notif_security', _securityNotifications);
      await prefs.setBool('notif_price_alerts', _priceAlertNotifications);
      await prefs.setBool('notif_network', _networkNotifications);
      await prefs.setBool('notif_engagement', _engagementNotifications);
    } catch (_) {}
  }

  // ─── Preference Setters ─────────────────────────────────────────────────

  Future<void> setPushEnabled(bool value) async {
    _pushEnabled = value;
    notifyListeners();
    await _savePreferences();
  }

  Future<void> setTransactionNotifications(bool value) async {
    _transactionNotifications = value;
    notifyListeners();
    await _savePreferences();
  }

  Future<void> setSecurityNotifications(bool value) async {
    _securityNotifications = value;
    notifyListeners();
    await _savePreferences();
  }

  Future<void> setPriceAlertNotifications(bool value) async {
    _priceAlertNotifications = value;
    notifyListeners();
    await _savePreferences();
  }

  Future<void> setNetworkNotifications(bool value) async {
    _networkNotifications = value;
    notifyListeners();
    await _savePreferences();
  }

  Future<void> setEngagementNotifications(bool value) async {
    _engagementNotifications = value;
    notifyListeners();
    await _savePreferences();
  }

  // =========================================================================
  // 🔐 P2: Security Notifications
  // =========================================================================

  /// Call when a new login is detected from a new device/location.
  Future<bool> reportSecurityLogin({
    required String deviceName,
    required String deviceType,
    required String ipAddress,
    String? location,
  }) async {
    final userId = await SecureStorage.instance.getUserIdForSelectedWallet();
    if (userId == null || userId.isEmpty) return false;

    final request = SecurityLoginRequest(
      userId: userId,
      deviceName: deviceName,
      deviceType: deviceType,
      ipAddress: ipAddress,
      location: location,
    );

    final response =
        await ServiceProvider.instance.apiService.notifySecurityLogin(request);
    return response.success;
  }

  /// Call when a security setting is changed.
  Future<bool> reportSecurityChange({
    required String changeType,
    required String deviceName,
  }) async {
    final userId = await SecureStorage.instance.getUserIdForSelectedWallet();
    if (userId == null || userId.isEmpty) return false;

    final request = SecurityChangeRequest(
      userId: userId,
      changeType: changeType,
      deviceName: deviceName,
    );

    final response =
        await ServiceProvider.instance.apiService.notifySecurityChange(request);
    return response.success;
  }

  /// Call when suspicious activity is detected.
  Future<bool> reportSuspiciousActivity({
    required String activityType,
    required String description,
    required String severity,
  }) async {
    final userId = await SecureStorage.instance.getUserIdForSelectedWallet();
    if (userId == null || userId.isEmpty) return false;

    final request = SecuritySuspiciousRequest(
      userId: userId,
      activityType: activityType,
      description: description,
      severity: severity,
    );

    final response =
        await ServiceProvider.instance.apiService.notifySecuritySuspicious(request);
    return response.success;
  }

  // =========================================================================
  // 💰 P3: Price Alerts Management
  // =========================================================================

  /// Load all price alerts for the current user and fetch current prices.
  /// Auto-retries once after 5s on transient failures.
  Future<void> loadPriceAlerts({int attempt = 1}) async {
    _priceAlertsLoading = true;
    _priceAlertsError = null;
    notifyListeners();

    try {
      final userId = await SecureStorage.instance.getUserIdForSelectedWallet();
      if (userId == null || userId.isEmpty) {
        _priceAlertsError = 'User not found';
        _priceAlertsLoading = false;
        notifyListeners();
        return;
      }

      final response = await ServiceProvider.instance.apiService.getPriceAlerts(userId);
      if (response.success) {
        _priceAlerts = response.alerts;

        // Fetch current prices for all alert symbols in parallel
        if (_priceAlerts.isNotEmpty) {
          final symbols = _priceAlerts.map((a) => a.symbol).toSet().toList();
          await _fetchPricesForSymbols(symbols);
        }
        _priceAlertsLoading = false;
        notifyListeners();
        return;
      }

      // Auto-retry once on first failure (server may be transiently busy)
      if (attempt == 1) {
        debugPrint('⏳ loadPriceAlerts failed, retrying in 5s...');
        await Future.delayed(const Duration(seconds: 5));
        await loadPriceAlerts(attempt: 2);
        return;
      }

      // Show network quality info in error (attempt 2+ also failed)
      final netStatus =
          ServiceProvider.instance.apiService.getNetworkStatus();
      final quality = netStatus['quality'] as String? ?? 'unknown';
      _priceAlertsError =
          'Server is busy ($quality). Please try again later.';
    } on DioException {
      _priceAlertsError = 'Connection timed out. The server is busy.';
    } catch (e) {
      _priceAlertsError = e.toString();
    } finally {
      _priceAlertsLoading = false;
      notifyListeners();
    }
  }

  /// Fetch current prices for a list of symbols (USD).
  /// Uses the bulk price endpoint first, then falls back to V2.
  Future<void> _fetchPricesForSymbols(List<String> symbols) async {
    if (symbols.isEmpty) return;
    try {
      final api = ServiceProvider.instance.apiService;
      final newPrices = <String, double>{};

      // Primary: bulk endpoint — یک درخواست برای همه سمبل‌ها
      final bulk = await api.getBulkPrices(symbols);
      if (bulk.success && bulk.prices.isNotEmpty) {
        newPrices.addAll(bulk.prices);
      }

      // Find symbols missing from bulk response
      final missing = symbols
          .map((s) => s.toUpperCase())
          .where((s) => !newPrices.containsKey(s))
          .toList();

      if (missing.isNotEmpty) {
        // Fallback 1: V2 bulk prices
        final v2Prices = await api.getPricesV2();
        for (final sym in missing) {
          final v2Entry = v2Prices[sym];
          if (v2Entry != null && v2Entry['USD'] != null) {
            newPrices[sym] = v2Entry['USD']!;
          }
        }

        // Fallback 2: still missing → single V2 price fetches in parallel
        final stillMissing = missing.where((s) => !newPrices.containsKey(s)).toList();
        if (stillMissing.isNotEmpty) {
          await Future.wait(stillMissing.map((sym) async {
            final single = await api.getPriceV2(sym);
            if (single != null) newPrices[sym] = single;
          }));
        }
      }

      if (newPrices.isNotEmpty) {
        _currentPrices = newPrices;
      }
    } catch (e) {
      debugPrint('⚠️ _fetchPricesForSymbols failed: $e');
    }
  }

  /// Manually register the device token for push notifications.
  /// Can be called on login or when the user wants to re-register.
  Future<bool> registerDevice() async {
    try {
      final userId = await SecureStorage.instance.getUserIdForSelectedWallet();
      final walletId = await SecureStorage.instance.getWalletIdForSelectedWallet();
      if (userId == null || userId.isEmpty || walletId == null || walletId.isEmpty) {
        return false;
      }

      // Use the existing FCM service to re-register
      await FirebaseMessagingService.instance.initialize();
      return true;
    } catch (e) {
      debugPrint('⚠️ registerDevice failed: $e');
      return false;
    }
  }

  /// Create a new price alert with optimistic update.
  /// Supports both exact-price (targetPrice) and percentage-based (targetPercent) alerts.
  Future<bool> createPriceAlert({
    required String symbol,
    double? targetPrice,
    required PriceAlertType alertType,
    double? targetPercent,
  }) async {
    final userId = await SecureStorage.instance.getUserIdForSelectedWallet();
    if (userId == null || userId.isEmpty) return false;

    final upperSymbol = symbol.toUpperCase();
    final typeStr = alertType.apiValue;

    // Validation: price type needs targetPrice, percent type needs targetPercent
    if (alertType == PriceAlertType.above || alertType == PriceAlertType.below) {
      if (targetPrice == null || targetPrice <= 0) return false;
    } else {
      if (targetPercent == null || targetPercent <= 0) return false;
    }

    final request = PriceAlertRequest(
      userId: userId,
      symbol: upperSymbol,
      targetPrice: targetPrice,
      alertType: typeStr,
      targetPercent: targetPercent,
    );

    // Optimistic: add to local list immediately
    final newAlert = PriceAlertItem(
      symbol: upperSymbol,
      targetPrice: targetPrice,
      alertType: typeStr,
      targetPercent: targetPercent,
    );
    _priceAlerts = [newAlert, ..._priceAlerts];
    notifyListeners();

    try {
      final response =
          await ServiceProvider.instance.apiService.createPriceAlert(request);
      if (response.success) {
        _fetchPricesForSymbols([upperSymbol]);
        return true;
      } else {
        // Rollback on failure
        _priceAlerts.removeWhere((a) =>
            a.symbol == upperSymbol &&
            a.targetPrice == targetPrice &&
            a.targetPercent == targetPercent &&
            a.alertType == typeStr);
        _priceAlertsError = response.message ?? 'Failed to create alert';
        notifyListeners();
        return false;
      }
    } catch (e) {
      // Rollback on exception
      _priceAlerts.removeWhere((a) =>
          a.symbol == upperSymbol &&
          a.targetPrice == targetPrice &&
          a.targetPercent == targetPercent &&
          a.alertType == typeStr);
      _priceAlertsError = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Delete a price alert with optimistic update.
  /// Supports deletion by [alertId] (preferred) or by [symbol] + [alertType].
  Future<bool> deletePriceAlert({
    int? alertId,
    String? symbol,
    PriceAlertType? alertType,
  }) async {
    final userId = await SecureStorage.instance.getUserIdForSelectedWallet();
    if (userId == null || userId.isEmpty) return false;

    final typeStr = alertType?.apiValue;

    // Optimistic: remove from local list immediately
    final before = _priceAlerts.length;
    if (alertId != null) {
      _priceAlerts.removeWhere((a) => a.id == alertId);
    } else if (symbol != null) {
      _priceAlerts.removeWhere(
          (a) => a.symbol == symbol.toUpperCase() && a.alertType == typeStr);
    }
    final removed = _priceAlerts.length < before;
    if (removed) notifyListeners();

    final request = DeletePriceAlertRequest(
      userId: userId,
      alertId: alertId,
      symbol: symbol?.toUpperCase(),
      alertType: typeStr,
    );

    try {
      final response =
          await ServiceProvider.instance.apiService.deletePriceAlert(request);
      if (response.success) {
        return true;
      }
      // Rollback on failure — hard to restore exact item, so just reload
      _priceAlertsError = response.message;
      notifyListeners();
      loadPriceAlerts();
      return false;
    } catch (e) {
      _priceAlertsError = e.toString();
      notifyListeners();
      loadPriceAlerts();
      return false;
    }
  }

  // =========================================================================
  // 📋 Local Notification History
  // =========================================================================

  /// Add an entry to local notification history.
  void addToHistory(LocalNotificationEntry entry) {
    _notificationHistory.insert(0, entry);
    _unreadCount++;
    // Keep max 100 entries
    if (_notificationHistory.length > 100) {
      _notificationHistory = _notificationHistory.sublist(0, 100);
    }
    notifyListeners();
  }

  /// Mark all notifications as read.
  void markAllAsRead() {
    _unreadCount = 0;
    notifyListeners();
  }

  /// Clear notification history.
  void clearHistory() {
    _notificationHistory.clear();
    _unreadCount = 0;
    notifyListeners();
  }
}

/// Local notification history entry.
class LocalNotificationEntry {
  final String id;
  final String title;
  final String body;
  final String type;
  final DateTime timestamp;
  final bool isRead;

  LocalNotificationEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    DateTime? timestamp,
    this.isRead = false,
  }) : timestamp = timestamp ?? DateTime.now();
}
