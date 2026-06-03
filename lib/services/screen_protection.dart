import 'package:flutter/services.dart';
import 'package:screen_protector/screen_protector.dart';

/// Prevents screenshots / recents preview on sensitive screens.
class ScreenProtection {
  static const _channel = MethodChannel('com.coinceeper.app/screen_protection');

  static Future<void> enable() async {
    try {
      await ScreenProtector.protectDataLeakageOn();
    } catch (_) {}
    try {
      await _channel.invokeMethod<void>('enable');
    } catch (_) {}
  }

  static Future<void> disable() async {
    try {
      await ScreenProtector.protectDataLeakageOff();
    } catch (_) {}
    try {
      await _channel.invokeMethod<void>('disable');
    } catch (_) {}
  }
}
