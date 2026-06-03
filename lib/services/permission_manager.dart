import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

/// Permission management for all platforms
class PermissionManager {
  static PermissionManager? _instance;
  static PermissionManager get instance => _instance ??= PermissionManager._();
  
  PermissionManager._();
  
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  
  /// Check and request camera permission
  Future<bool> requestCameraPermission() async {
    try {
      final status = await Permission.camera.status;
      
      if (status.isGranted) {
        return true;
      }
      
      if (status.isDenied) {
        final result = await Permission.camera.request();
        return result.isGranted;
      }
      
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      
      return false;
    } catch (e) {
      print('Error requesting camera permission: $e');
      return false;
    }
  }
  
  /// Check and request notification permission
  Future<bool> requestNotificationPermission() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        if (androidInfo.version.sdkInt >= 33) {
          final status = await Permission.notification.status;
          
          if (status.isGranted) {
            return true;
          }
          
          if (status.isDenied) {
            final result = await Permission.notification.request();
            return result.isGranted;
          }
          
          if (status.isPermanentlyDenied) {
            await openAppSettings();
            return false;
          }
        }
      }
      
      return true; // For iOS and old Android
    } catch (e) {
      print('Error requesting notification permission: $e');
      return false;
    }
  }
  
  /// Check and request biometric permission
  Future<bool> requestBiometricPermission() async {
    try {
      final status = await Permission.sensors.status;
      
      if (status.isGranted) {
        return true;
      }
      
      if (status.isDenied) {
        final result = await Permission.sensors.request();
        return result.isGranted;
      }
      
      return false;
    } catch (e) {
      print('Error requesting biometric permission: $e');
      return false;
    }
  }
  
  /// Check and request storage permission
  Future<bool> requestStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        if (androidInfo.version.sdkInt >= 30) {
          // For Android 11+ no storage permission needed
          return true;
        }
        
        final status = await Permission.storage.status;
        
        if (status.isGranted) {
          return true;
        }
        
        if (status.isDenied) {
          final result = await Permission.storage.request();
          return result.isGranted;
        }
        
        if (status.isPermanentlyDenied) {
          await openAppSettings();
          return false;
        }
      }
      
      return true; // For iOS
    } catch (e) {
      print('Error requesting storage permission: $e');
      return false;
    }
  }
  
  /// Check and request microphone permission
  Future<bool> requestMicrophonePermission() async {
    try {
      final status = await Permission.microphone.status;
      
      if (status.isGranted) {
        return true;
      }
      
      if (status.isDenied) {
        final result = await Permission.microphone.request();
        return result.isGranted;
      }
      
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      
      return false;
    } catch (e) {
      print('Error requesting microphone permission: $e');
      return false;
    }
  }
  
  /// Check and request location permission
  Future<bool> requestLocationPermission() async {
    try {
      final status = await Permission.location.status;
      
      if (status.isGranted) {
        return true;
      }
      
      if (status.isDenied) {
        final result = await Permission.location.request();
        return result.isGranted;
      }
      
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      
      return false;
    } catch (e) {
      print('Error requesting location permission: $e');
      return false;
    }
  }
  
  /// Check and request bluetooth permission
  Future<bool> requestBluetoothPermission() async {
    try {
      final status = await Permission.bluetooth.status;
      
      if (status.isGranted) {
        return true;
      }
      
      if (status.isDenied) {
        final result = await Permission.bluetooth.request();
        return result.isGranted;
      }
      
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      
      return false;
    } catch (e) {
      print('Error requesting bluetooth permission: $e');
      return false;
    }
  }
  
  /// Check status of all required permissions
  Future<Map<String, bool>> checkAllPermissions() async {
    final permissions = <String, bool>{};
    
    permissions['camera'] = await Permission.camera.isGranted;
    permissions['notification'] = await Permission.notification.isGranted;
    permissions['biometric'] = await Permission.sensors.isGranted;
    permissions['storage'] = await Permission.storage.isGranted;
    permissions['microphone'] = await Permission.microphone.isGranted;
    permissions['location'] = await Permission.location.isGranted;
    permissions['bluetooth'] = await Permission.bluetooth.isGranted;
    
    return permissions;
  }
  
  /// Request all required permissions
  Future<Map<String, bool>> requestAllPermissions() async {
    final results = <String, bool>{};
    
    results['camera'] = await requestCameraPermission();
    results['notification'] = await requestNotificationPermission();
    results['biometric'] = await requestBiometricPermission();
    results['storage'] = await requestStoragePermission();
    results['microphone'] = await requestMicrophonePermission();
    results['location'] = await requestLocationPermission();
    results['bluetooth'] = await requestBluetoothPermission();
    
    return results;
  }
  
  /// Show permission explanation dialog
  Future<bool> showPermissionDialog(
    BuildContext context,
    String permission,
    String title,
    String message,
  ) async {
    // Remove dialog - permission dialog removed
    return false;
  }
  
  /// Open app settings
  Future<void> openAppSettings() async {
    try {
      await openAppSettings();
    } catch (e) {
      print('Error opening app settings: $e');
    }
  }
  
  /// Check if device supports biometric
  Future<bool> isBiometricSupported() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.version.sdkInt >= 23;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.systemName.isNotEmpty;
      }
      return false;
    } catch (e) {
      print('Error checking biometric support: $e');
      return false;
    }
  }
  
  /// Check if device supports Face ID
  Future<bool> isFaceIdSupported() async {
    try {
      if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.systemName.contains('iPhone X') ||
               iosInfo.systemName.contains('iPhone 11') ||
               iosInfo.systemName.contains('iPhone 12') ||
               iosInfo.systemName.contains('iPhone 13') ||
               iosInfo.systemName.contains('iPhone 14') ||
               iosInfo.systemName.contains('iPhone 15');
      }
      return false;
    } catch (e) {
      print('Error checking Face ID support: $e');
      return false;
    }
  }
  
  /// Get device information
  Future<Map<String, dynamic>> getDeviceInfo() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return {
          'platform': 'Android',
          'version': androidInfo.version.release,
          'sdkInt': androidInfo.version.sdkInt,
          'brand': androidInfo.brand,
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return {
          'platform': 'iOS',
          'version': iosInfo.systemVersion,
          'name': iosInfo.name,
          'model': iosInfo.model,
          'localizedModel': iosInfo.localizedModel,
          'identifierForVendor': iosInfo.identifierForVendor,
        };
      }
      return {};
    } catch (e) {
      print('Error getting device info: $e');
      return {};
    }
  }
} 