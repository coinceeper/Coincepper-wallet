import 'package:flutter/material.dart';

import 'app_theme.dart';

class AppThemeNotifier extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  Future<void> load() async {
    _mode = await AppTheme.loadThemeMode();
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    await AppTheme.saveThemeMode(mode);
    notifyListeners();
  }
}
