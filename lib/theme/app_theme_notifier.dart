import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'app_theme_mode.dart';

class AppThemeNotifier extends ChangeNotifier {
  AppThemeMode _mode = AppThemeMode.system;

  AppThemeMode get mode => _mode;

  ThemeMode get materialThemeMode => _mode.materialThemeMode;

  Future<void> load() async {
    _mode = await AppTheme.loadThemeMode();
    notifyListeners();
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    await AppTheme.saveThemeMode(mode);
    notifyListeners();
  }
}
