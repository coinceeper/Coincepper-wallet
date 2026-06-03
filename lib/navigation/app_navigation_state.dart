import 'package:flutter/foundation.dart';

/// Notifies [GoRouter] when bootstrap or session lock state changes.
class AppNavigationState extends ChangeNotifier {
  AppNavigationState._();
  static final AppNavigationState instance = AppNavigationState._();

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
