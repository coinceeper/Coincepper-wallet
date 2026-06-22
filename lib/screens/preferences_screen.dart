import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import '../layout/bottom_menu_with_siri.dart';
import '../services/language_manager.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(_safeTranslate('preferences', 'Preferences'), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 24)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
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
                final result = await Navigator.pushNamed(context, '/fiat-currencies');
                if (result != null) {
                  _loadPreferences(); // Reload preferences after returning
                }
              },
            ),
            _PreferenceItem(
              title: _safeTranslate('app_language', 'App Language'),
              subtitle: currentLanguage,
              onTap: () async {
                final result = await Navigator.pushNamed(context, '/languages');
                if (result != null) {
                  _loadPreferences(); // Reload preferences after returning
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