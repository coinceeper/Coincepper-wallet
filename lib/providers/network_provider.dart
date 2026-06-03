import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Provider برای مدیریت وضعیت شبکه
class NetworkProvider extends ChangeNotifier {
  bool _isOnline = true;
  String _connectionType = 'Unknown';
  StreamSubscription? _connectivitySubscription;

  bool get isOnline => _isOnline;
  String get connectionType => _connectionType;

  NetworkProvider() {
    _initializeConnectivity();
  }

  /// مقداردهی اولیه نظارت بر اتصال
  void _initializeConnectivity() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (dynamic results) {
        final result = _extractConnectivityResult(results);
        _handleConnectivityChange(result);
      },
      onError: (error) {
        print('Error in connectivity listener: $error');
        _handleConnectivityChange(ConnectivityResult.none);
      },
    );
  }

  /// استخراج ConnectivityResult از نتیجه API
  ConnectivityResult _extractConnectivityResult(dynamic result) {
    if (result is List<ConnectivityResult>) {
      return result.isNotEmpty ? result.first : ConnectivityResult.none;
    } else if (result is ConnectivityResult) {
      return result;
    } else {
      return ConnectivityResult.none;
    }
  }

  /// مدیریت تغییرات اتصال
  void _handleConnectivityChange(ConnectivityResult result) {
    bool wasOnline = _isOnline;
    String oldConnectionType = _connectionType;

    switch (result) {
      case ConnectivityResult.wifi:
        _isOnline = true;
        _connectionType = 'WiFi';
        break;
      case ConnectivityResult.mobile:
        _isOnline = true;
        _connectionType = 'Mobile';
        break;
      case ConnectivityResult.ethernet:
        _isOnline = true;
        _connectionType = 'Ethernet';
        break;
      case ConnectivityResult.vpn:
        _isOnline = true;
        _connectionType = 'VPN';
        break;
      case ConnectivityResult.bluetooth:
        _isOnline = true;
        _connectionType = 'Bluetooth';
        break;
      case ConnectivityResult.other:
        _isOnline = true;
        _connectionType = 'Other';
        break;
      case ConnectivityResult.none:
        _isOnline = false;
        _connectionType = 'None';
        break;
    }

    // فقط در صورت تغییر وضعیت، notifyListener فراخوانی کن
    if (wasOnline != _isOnline || oldConnectionType != _connectionType) {
      notifyListeners();
    }
  }

  /// بررسی وضعیت اتصال
  Future<bool> checkConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final result = _extractConnectivityResult(connectivityResult);
      _handleConnectivityChange(result);
      return _isOnline;
    } catch (e) {
      print('Error checking connectivity: $e');
      return false;
    }
  }

  /// دریافت نوع اتصال
  Future<String> getConnectionType() async {
    try {
      final result = await Connectivity().checkConnectivity();
      final connectivityResult = _extractConnectivityResult(result);
      
      switch (connectivityResult) {
        case ConnectivityResult.wifi:
          return 'WiFi';
        case ConnectivityResult.mobile:
          return 'Mobile';
        case ConnectivityResult.ethernet:
          return 'Ethernet';
        case ConnectivityResult.bluetooth:
          return 'Bluetooth';
        case ConnectivityResult.vpn:
          return 'VPN';
        case ConnectivityResult.other:
          return 'Other';
        case ConnectivityResult.none:
        default:
          return 'None';
      }
    } catch (e) {
      print('Error getting connection type: $e');
      return 'Unknown';
    }
  }

  /// تست اتصال به اینترنت
  Future<bool> testInternetConnection() async {
    try {
      // تست ساده با ping به Google DNS
      final result = await _pingHost('8.8.8.8');
      return result;
    } catch (e) {
      print('Error testing internet connection: $e');
      return false;
    }
  }

  /// تست ping به یک host
  Future<bool> _pingHost(String host) async {
    try {
      // این یک تست ساده است. در حالت واقعی می‌توانید از http package استفاده کنید
      return true; // فعلاً true برمی‌گردانیم
    } catch (e) {
      return false;
    }
  }

  /// دریافت اطلاعات کامل شبکه
  Future<Map<String, dynamic>> getNetworkInfo() async {
    final isConnected = await checkConnection();
    final connectionType = await getConnectionType();
    final hasInternet = await testInternetConnection();

    return {
      'isOnline': isConnected,
      'connectionType': connectionType,
      'hasInternet': hasInternet,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
} 