import 'package:flutter/material.dart';
import '../layout/bottom_menu_with_siri.dart';
import '../services/language_manager.dart';
import 'package:easy_localization/easy_localization.dart';

class LanguagesScreen extends StatefulWidget {
  const LanguagesScreen({super.key});

  @override
  State<LanguagesScreen> createState() => _LanguagesScreenState();
}

class _LanguagesScreenState extends State<LanguagesScreen> {
  String selectedLanguage = 'en';

  final List<Map<String, String>> allLanguages = [
    {'code': 'en', 'name': 'English', 'nativeName': 'English'},
    {'code': 'fa', 'name': 'Persian', 'nativeName': 'فارسی'},
    {'code': 'ar', 'name': 'Arabic', 'nativeName': 'العربية'},
    {'code': 'tr', 'name': 'Turkish', 'nativeName': 'Türkçe'},
    {'code': 'zh', 'name': 'Chinese', 'nativeName': '中文'},
    {'code': 'es', 'name': 'Spanish', 'nativeName': 'Español'},
  ];

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      print('⚠️ Localization failed for key "$key": $e');
      return fallback;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final savedLanguage = await LanguageManager.getSavedLanguage();
    setState(() {
      selectedLanguage = savedLanguage ?? 'en';
    });
  }

  Future<void> _saveLanguage(String code) async {
    try {
      // Change language using LanguageManager (this marks it as user-selected)
      await LanguageManager.changeLanguage(context, code);
      
      setState(() {
        selectedLanguage = code;
      });
      
      Navigator.pop(context);
    } catch (e) {
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_safeTranslate('error_changing_language', 'Error changing language')}: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _safeTranslate('app_languages', 'App Languages'), 
          style: const TextStyle(
            color: Colors.black, 
            fontWeight: FontWeight.bold, 
            fontSize: 24
          )
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              _safeTranslate('select_language', 'Select Language'),
              style: const TextStyle(
                fontSize: 16, 
                color: Colors.grey, 
                fontWeight: FontWeight.bold
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: allLanguages.length,
                separatorBuilder: (context, index) => const Divider(
                  color: Color(0x32626262), 
                  thickness: 1, 
                  height: 1
                ),
                itemBuilder: (context, index) {
                  final language = allLanguages[index];
                  final isSelected = selectedLanguage == language['code'];
                  
                  return _LanguageItem(
                    name: language['name']!,
                    nativeName: language['nativeName']!,
                    isSelected: isSelected,
                    onTap: () => _saveLanguage(language['code']!),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomMenuWithSiri(),
    );
  }
}

class _LanguageItem extends StatelessWidget {
  final String name;
  final String nativeName;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageItem({
    required this.name,
    required this.nativeName,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 0.0),
        child: Row(
          children: [
            // Language icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF16B369) : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.language,
                color: isSelected ? Colors.white : Colors.grey,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            // Language names
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 16,
                      color: isSelected ? const Color(0xFF16B369) : Colors.black,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  if (name != nativeName)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        nativeName,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Selection indicator
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF16B369),
                size: 24,
              )
            else
              const Icon(
                Icons.chevron_right,
                color: Colors.grey,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
} 