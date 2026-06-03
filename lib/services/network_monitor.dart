import 'dart:io';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Network monitor for checking connection status
class NetworkMonitor extends ChangeNotifier {
  static final NetworkMonitor _instance = NetworkMonitor._internal();
  
  factory NetworkMonitor() {
    return _instance;
  }
  
  static NetworkMonitor get instance => _instance;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription? _connectivitySubscription;
  
  bool _isConnected = true;
  bool _isInternetAvailable = true;
  String _connectionType = 'Unknown';
  String _connectionQuality = 'Unknown';

  bool get isConnected => _isConnected;
  bool get isInternetAvailable => _isInternetAvailable;
  String get connectionType => _connectionType;
  String get connectionQuality => _connectionQuality;

  NetworkMonitor._internal() {
    _initConnectivity();
    _startMonitoring();
  }

  void _initConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      final connectivityResult = _extractConnectivityResult(result);
      _updateConnectionStatus(connectivityResult);
    } catch (e) {
      print('Error checking connectivity: $e');
    }
  }

  void _startMonitoring() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((results) {
      final result = _extractConnectivityResult(results);
      _updateConnectionStatus(result);
    });
  }

  /// Extract ConnectivityResult from API result
  ConnectivityResult _extractConnectivityResult(dynamic result) {
    if (result is List<ConnectivityResult>) {
      return result.isNotEmpty ? result.first : ConnectivityResult.none;
    } else if (result is ConnectivityResult) {
      return result;
    } else {
      return ConnectivityResult.none;
    }
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    bool wasConnected = _isConnected;
    
    switch (result) {
      case ConnectivityResult.wifi:
        _isConnected = true;
        _connectionType = 'WiFi';
        break;
      case ConnectivityResult.mobile:
        _isConnected = true;
        _connectionType = 'Mobile';
        break;
      case ConnectivityResult.ethernet:
        _isConnected = true;
        _connectionType = 'Ethernet';
        break;
      case ConnectivityResult.vpn:
        _isConnected = true;
        _connectionType = 'VPN';
        break;
      case ConnectivityResult.bluetooth:
        _isConnected = true;
        _connectionType = 'Bluetooth';
        break;
      case ConnectivityResult.other:
        _isConnected = true;
        _connectionType = 'Other';
        break;
      case ConnectivityResult.none:
        _isConnected = false;
        _connectionType = 'None';
        break;
    }

    if (wasConnected != _isConnected) {
      notifyListeners();
    }

    // Check internet access
    _checkInternetAvailability();
  }

  Future<void> _checkInternetAvailability() async {
    bool wasInternetAvailable = _isInternetAvailable;
    
    try {
      final result = await InternetAddress.lookup('google.com');
      _isInternetAvailable = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      _isInternetAvailable = false;
    }

    if (wasInternetAvailable != _isInternetAvailable) {
      notifyListeners();
    }

    // Update connection quality
    _updateConnectionQuality();
  }

  void _updateConnectionQuality() {
    if (!_isConnected) {
      _connectionQuality = 'Disconnected';
    } else if (!_isInternetAvailable) {
      _connectionQuality = 'No Internet';
    } else {
      switch (_connectionType) {
        case 'WiFi':
          _connectionQuality = 'Excellent';
          break;
        case 'Mobile':
          _connectionQuality = 'Good';
          break;
        case 'Ethernet':
          _connectionQuality = 'Excellent';
          break;
        default:
          _connectionQuality = 'Fair';
      }
    }
    
    notifyListeners();
  }

  /// Check internet access
  Future<bool> checkInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Check connection to specific server
  Future<bool> checkServerConnection(String host) async {
    try {
      final result = await InternetAddress.lookup(host);
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Get full network status
  Map<String, dynamic> getNetworkStatus() {
    return {
      'isConnected': _isConnected,
      'isInternetAvailable': _isInternetAvailable,
      'connectionType': _connectionType,
      'connectionQuality': _connectionQuality,
    };
  }

  /// Check and show network status
  Future<void> showNetworkStatus() async {
    print('Network Status:');
    print('  Connected: $_isConnected');
    print('  Internet Available: $_isInternetAvailable');
    print('  Connection Type: $_connectionType');
    print('  Connection Quality: $_connectionQuality');
  }

  /// Get online status
  bool get isOnline => _isConnected && _isInternetAvailable;

  /// Get connection type
  Future<String> getConnectionType() async {
    return _connectionType;
  }

  /// Get network info
  Future<Map<String, dynamic>> getNetworkInfo() async {
    return {
      'isConnected': _isConnected,
      'isInternetAvailable': _isInternetAvailable,
      'connectionType': _connectionType,
      'connectionQuality': _connectionQuality,
      'isOnline': isOnline,
    };
  }

  /// Check real internet connection
  Future<bool> hasRealInternet() async {
    return await checkInternetConnection();
  }

  /// Stream for online status changes
  Stream<bool> get isOnlineStream {
    return Stream.periodic(const Duration(seconds: 5), (_) => isOnline);
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}

/// Class for handling network errors
class NetworkMonitorException implements Exception {
  final String message;
  final String? connectionType;
  final DateTime timestamp;
  
  NetworkMonitorException({
    required this.message,
    this.connectionType,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  
  @override
  String toString() {
    return 'NetworkMonitorException: $message (Type: $connectionType, Time: $timestamp)';
  }
} 