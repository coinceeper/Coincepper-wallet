import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../navigation/app_navigation.dart';
import '../navigation/route_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import '../layout/bottom_menu_with_siri.dart';
import '../services/language_manager.dart';
import '../theme/app_theme_notifier.dart';
import '../ui/app_scaffold.dart';

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  String currentCurrency = 'USD';
  String currentLanguage = 'English';

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  // Convert language code to display name
  String _getLanguageDisplayName(String code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'fa':
        return 'فارسی';
      case 'ar':
        return 'العربية';
      case 'tr':
        return 'Türkçe';
      case 'zh':
        return '中文';
      case 'es':
        return 'Español';
      default:
        return 'English';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load currency
    final currency = prefs.getString('selected_currency') ?? 'USD';
    
    // Load current language from LanguageManager
    final languageCode = await LanguageManager.getSavedLanguage();
    final displayName = _getLanguageDisplayName(languageCode ?? 'en');
    
    setState(() {
      currentCurrency = currency;
      currentLanguage = displayName;
    });
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return _safeTranslate('theme_light', 'Light');
      case ThemeMode.dark:
        return _safeTranslate('theme_dark', 'Dark');
      case ThemeMode.system:
        return _safeTranslate('theme_system', 'System');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<AppThemeNotifier>();
    return AppScaffold(
      title: _safeTranslate('preferences', 'Preferences'),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _PreferenceItem(
              title: _safeTranslate('currency', 'Currency'),
              subtitle: currentCurrency,
              onTap: () async {
                final result = await AppNavigation.pushNamed(context, RoutePaths.fiatCurrencies);
                if (result != null) {
                  _loadPreferences(); // Reload preferences after returning
                }
              },
            ),
            _PreferenceItem(
              title: _safeTranslate('app_language', 'App Language'),
              subtitle: currentLanguage,
              onTap: () async {
                final result = await AppNavigation.pushNamed(context, RoutePaths.languages);
                if (result != null) {
                  _loadPreferences(); // Reload preferences after returning
                }
              },
            ),
            _PreferenceItem(
              title: _safeTranslate('appearance', 'Appearance'),
              subtitle: _themeModeLabel(themeNotifier.mode),
              onTap: () async {
                final picked = await showModalBottomSheet<ThemeMode>(
                  context: context,
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: Text(_safeTranslate('theme_system', 'System')),
                          onTap: () => Navigator.pop(ctx, ThemeMode.system),
                        ),
                        ListTile(
                          title: Text(_safeTranslate('theme_light', 'Light')),
                          onTap: () => Navigator.pop(ctx, ThemeMode.light),
                        ),
                        ListTile(
                          title: Text(_safeTranslate('theme_dark', 'Dark')),
                          onTap: () => Navigator.pop(ctx, ThemeMode.dark),
                        ),
                      ],
                    ),
                  ),
                );
                if (picked != null) {
                  await themeNotifier.setMode(picked);
                }
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomMenuWithSiri(),
    );
  }
}

class _PreferenceItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _PreferenceItem({required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20.0),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 16, color: Colors.black)),
            ),
            if (subtitle != null)
              Text(subtitle!, style: const TextStyle(fontSize: 14, color: Colors.grey)),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
} 