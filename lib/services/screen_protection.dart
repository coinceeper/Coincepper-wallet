import 'package:flutter/services.dart';
import 'package:screen_protector/screen_protector.dart';
import '../utils/secure_log.dart';

/// Prevents screenshots / recents preview on sensitive screens.
class ScreenProtection {
  static const _channel = MethodChannel('com.coinceeper.app/screen_protection');

  static Future<void> enable() async {
    try {
      await ScreenProtector.protectDataLeakageOn();
    } catch (e) {
      SecureLog.d('Screen protector enable via plugin failed', error: e);
    }
    try {
      await _channel.invokeMethod<void>('enable');
    } catch (e) {
      SecureLog.d('Screen protector enable via channel failed', error: e);
    }
  }

  static Future<void> disable() async {
    try {
      await ScreenProtector.protectDataLeakageOff();
    } catch (e) {
      SecureLog.d('Screen protector disable via plugin failed', error: e);
    }
    try {
      await _channel.invokeMethod<void>('disable');
    } catch (e) {
      SecureLog.d('Screen protector disable via channel failed', error: e);
    }
  }
}
