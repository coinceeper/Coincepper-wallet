import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

class LanguageManager {
  static const String _languageKey = 'selected_language';
  static const String _userSelectedLanguageKey = 'user_selected_language'; // کلید برای نشان دادن اینکه کاربر زبان دستی انتخاب کرده
  
  // Supported languages
  static const Map<String, Locale> supportedLanguages = {
    'en': Locale('en'),
    'fa': Locale('fa'),
    'tr': Locale('tr'),
    'ar': Locale('ar'),
    'zh': Locale('zh'),
    'es': Locale('es'),
  };

  /// Get current language code
  static String getCurrentLanguageCode(BuildContext context) {
    return context.locale.languageCode;
  }

  /// Get current language name
  static String getCurrentLanguageName(BuildContext context) {
    final code = getCurrentLanguageCode(context);
    switch (code) {
      case 'en':
        return 'English';
      case 'fa':
        return 'فارسی';
      case 'tr':
        return 'Türkçe';
      case 'ar':
        return 'العربية';
      case 'zh':
        return '中文';
      case 'es':
        return 'Español';
      default:
        return 'English';
    }
  }

  /// Get all available languages
  static Map<String, String> getAvailableLanguages() {
    return {
      'en': 'English',
      'fa': 'فارسی',
      'tr': 'Türkçe',
      'ar': 'العربية',
      'zh': '中文',
      'es': 'Español',
    };
  }

  /// Load saved language from SharedPreferences
  static Future<String?> getSavedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_languageKey);
    } catch (e) {
      print('❌ Error loading saved language: $e');
      return null;
    }
  }

  /// Check if user has manually selected a language
  static Future<bool> hasUserSelectedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_userSelectedLanguageKey) ?? false;
    } catch (e) {
      print('❌ Error checking user language selection: $e');
      return false;
    }
  }

  /// Save language to SharedPreferences
  static Future<void> saveLanguage(String languageCode, {bool isUserSelected = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageKey, languageCode);
      
      // اگر کاربر زبان را انتخاب کرده، این را ذخیره کنیم
      if (isUserSelected) {
        await prefs.setBool(_userSelectedLanguageKey, true);
      }
      
      print('✅ Language saved: $languageCode (userSelected: $isUserSelected)');
    } catch (e) {
      print('❌ Error saving language: $e');
    }
  }

  /// Detect device language
  static String detectDeviceLanguage() {
    try {
      // گرفتن زبان سیستم
      final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
      final deviceLanguageCode = systemLocale.languageCode;
      
      print('📱 Device language detected: $deviceLanguageCode');
      
      // بررسی اینکه آیا زبان سیستم در لیست زبان‌های پشتیبانی شده وجود دارد
      if (supportedLanguages.containsKey(deviceLanguageCode)) {
        print('✅ Device language is supported: $deviceLanguageCode');
        return deviceLanguageCode;
      } else {
        print('⚠️ Device language not supported, using default: en');
        return 'en'; // زبان پیش‌فرض
      }
    } catch (e) {
      print('❌ Error detecting device language: $e');
      return 'en'; // زبان پیش‌فرض در صورت خطا
    }
  }

  /// Change language (called by user)
  static Future<void> changeLanguage(BuildContext context, String languageCode) async {
    try {
      if (supportedLanguages.containsKey(languageCode)) {
        // Save to SharedPreferences with user selection flag
        await saveLanguage(languageCode, isUserSelected: true);
        
        // Change the app locale
        await context.setLocale(supportedLanguages[languageCode]!);
        
        // Force rebuild of all widgets that depend on localization
        // This ensures immediate visual update
        await Future.delayed(const Duration(milliseconds: 100));
        
        print('✅ Language changed by user to: $languageCode');
        print('🔄 Please restart the app for complete language change');
      } else {
        print('❌ Unsupported language code: $languageCode');
      }
    } catch (e) {
      print('❌ Error changing language: $e');
    }
  }

  /// Initialize language on app start
  static Future<void> initializeLanguage(BuildContext context) async {
    try {
      final savedLanguage = await getSavedLanguage();
      final userHasSelectedLanguage = await hasUserSelectedLanguage();
      
      String languageToSet = 'en'; // پیش‌فرض
      
      if (savedLanguage != null && supportedLanguages.containsKey(savedLanguage)) {
        if (userHasSelectedLanguage) {
          // کاربر زبان دستی انتخاب کرده - از آن استفاده کنیم
          languageToSet = savedLanguage;
          print('🎯 Using user-selected language: $savedLanguage');
        } else {
          // کاربر زبان دستی انتخاب نکرده - زبان سیستم را بررسی کنیم
          final deviceLanguage = detectDeviceLanguage();
          languageToSet = deviceLanguage;
          print('📱 Using device language: $deviceLanguage');
        }
      } else {
        // هیچ زبان ذخیره نشده - تشخیص زبان سیستم
        final deviceLanguage = detectDeviceLanguage();
        languageToSet = deviceLanguage;
        print('🆕 First time setup - using device language: $deviceLanguage');
      }
      
      // Set the determined language
      await context.setLocale(supportedLanguages[languageToSet]!);
      
      // Save the language if it's not already saved or if it's different
      if (savedLanguage != languageToSet) {
        await saveLanguage(languageToSet, isUserSelected: userHasSelectedLanguage);
      }
      
      print('✅ Language initialized: $languageToSet');
    } catch (e) {
      print('❌ Error initializing language: $e');
      // Fallback to English
      await context.setLocale(supportedLanguages['en']!);
      await saveLanguage('en', isUserSelected: false);
    }
  }

  /// Reset language to default (English)
  static Future<void> resetToDefault(BuildContext context) async {
    await changeLanguage(context, 'en');
  }
  
  /// Reset user language selection (used when app is reinstalled)
  static Future<void> resetUserLanguageSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userSelectedLanguageKey);
      await prefs.remove(_languageKey);
      print('✅ User language selection reset');
    } catch (e) {
      print('❌ Error resetting user language selection: $e');
    }
  }
} 