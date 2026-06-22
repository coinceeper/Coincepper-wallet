import 'package:flutter/foundation.dart';

/// Notifies [GoRouter] when bootstrap or session lock state changes.
import '../di/service_locator.dart';

class AppNavigationState extends ChangeNotifier {
  AppNavigationState._();
  /// DI constructor. Use [instance] for singleton access.
  AppNavigationState();
  static AppNavigationState get instance => ServiceLocator.get<AppNavigationState>();

  bool bootstrapComplete = false;
  bool sessionLockRequired = false;

  void completeBootstrap() {
    bootstrapComplete = true;
    notifyListeners();
  }

  void setSessionLockRequired(bool value) {
    if (sessionLockRequired == value) return;
    sessionLockRequired = value;
    notifyListeners();
  }
}
