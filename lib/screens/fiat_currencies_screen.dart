import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../utils/shared_preferences_utils.dart';
import '../providers/price_provider.dart';
import '../providers/token_provider.dart';
import '../layout/bottom_menu_with_siri.dart';

class FiatCurrenciesScreen extends StatelessWidget {
  const FiatCurrenciesScreen({super.key});

  // Safe translate method with fallback
  String _safeTranslate(BuildContext context, String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  Future<void> _saveSelectedCurrency(BuildContext context, String currency) async {
    await SharedPreferencesUtils.saveSelectedCurrency(currency);
    
    // Update PriceProvider with new selected currency
    final priceProvider = Provider.of<PriceProvider>(context, listen: false);
    await priceProvider.setSelectedCurrency(currency);
    
    // Refresh prices for the new currency
    final tokenProvider = Provider.of<TokenProvider>(context, listen: false);
    if (tokenProvider.enabledTokens.isNotEmpty) {
      final symbols = tokenProvider.enabledTokens.map((t) => t.symbol ?? '').where((s) => s.isNotEmpty).toList();
      await priceProvider.fetchPrices(symbols, currencies: [currency]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> currencies = [
      {
        'code': 'USD',
        'symbol': '\$',
        'flag': 'assets/images/us.png',
        'country': _safeTranslate(context, 'united_states', 'United States'),
        'fullName': _safeTranslate(context, 'us_dollar', 'US Dollar'),
      },
      {
        'code': 'CAD',
        'symbol': 'CA\$',
        'flag': 'assets/images/ca.png',
        'country': _safeTranslate(context, 'canada', 'Canada'),
        'fullName': _safeTranslate(context, 'canadian_dollar', 'Canadian Dollar'),
      },
      {
        'code': 'AUD',
        'symbol': 'AU\$',
        'flag': 'assets/images/au.png',
        'country': _safeTranslate(context, 'australia', 'Australia'),
        'fullName': _safeTranslate(context, 'australian_dollar', 'Australian Dollar'),
      },
      {
        'code': 'GBP',
        'symbol': '£',
        'flag': 'assets/images/gb.png',
        'country': _safeTranslate(context, 'united_kingdom', 'United Kingdom'),
        'fullName': _safeTranslate(context, 'pound_sterling', 'Pound Sterling'),
      },
      {
        'code': 'EUR',
        'symbol': '€',
        'flag': 'assets/images/eu.png',
        'country': _safeTranslate(context, 'european_union', 'European Union'),
        'fullName': _safeTranslate(context, 'euro', 'Euro'),
      },
      {
        'code': 'KWD',
        'symbol': 'KD',
        'flag': 'assets/images/kw.png',
        'country': _safeTranslate(context, 'kuwait', 'Kuwait'),
        'fullName': _safeTranslate(context, 'kuwaiti_dinar', 'Kuwaiti Dinar'),
      },
      {
        'code': 'TRY',
        'symbol': '₺',
        'flag': 'assets/images/tr.png',
        'country': _safeTranslate(context, 'turkey', 'Turkey'),
        'fullName': _safeTranslate(context, 'turkish_lira', 'Turkish Lira'),
      },
      {
        'code': 'SAR',
        'symbol': '﷼',
        'flag': 'assets/images/sa.png',
        'country': _safeTranslate(context, 'saudi_arabia', 'Saudi Arabia'),
        'fullName': _safeTranslate(context, 'saudi_riyal', 'Saudi Riyal'),
      },
      {
        'code': 'CNY',
        'symbol': '¥',
        'flag': 'assets/images/cn.png',
        'country': _safeTranslate(context, 'china', 'China'),
        'fullName': _safeTranslate(context, 'chinese_yuan', 'Chinese Yuan'),
      },
      {
        'code': 'KRW',
        'symbol': '₩',
        'flag': 'assets/images/kr.png',
        'country': _safeTranslate(context, 'south_korea', 'South Korea'),
        'fullName': _safeTranslate(context, 'south_korean_won', 'South Korean Won'),
      },
      {
        'code': 'JPY',
        'symbol': '¥',
        'flag': 'assets/images/jp.png',
        'country': _safeTranslate(context, 'japan', 'Japan'),
        'fullName': _safeTranslate(context, 'japanese_yen', 'Japanese Yen'),
      },
      {
        'code': 'INR',
        'symbol': '₹',
        'flag': 'assets/images/in.png',
        'country': _safeTranslate(context, 'india', 'India'),
        'fullName': _safeTranslate(context, 'indian_rupee', 'Indian Rupee'),
      },
      {
        'code': 'RUB',
        'symbol': '₽',
        'flag': 'assets/images/ru.png',
        'country': _safeTranslate(context, 'russia', 'Russia'),
        'fullName': _safeTranslate(context, 'russian_ruble', 'Russian Ruble'),
      },
      {
        'code': 'IQD',
        'symbol': 'ع.د',
        'flag': 'assets/images/iq.png',
        'country': _safeTranslate(context, 'iraq', 'Iraq'),
        'fullName': _safeTranslate(context, 'iraqi_dinar', 'Iraqi Dinar'),
      },
      {
        'code': 'TND',
        'symbol': 'د.ت',
        'flag': 'assets/images/tn.png',
        'country': _safeTranslate(context, 'tunisia', 'Tunisia'),
        'fullName': _safeTranslate(context, 'tunisian_dinar', 'Tunisian Dinar'),
      },
      {
        'code': 'BHD',
        'symbol': 'ب.د',
        'flag': 'assets/images/bh.png',
        'country': _safeTranslate(context, 'bahrain', 'Bahrain'),
        'fullName': _safeTranslate(context, 'bahraini_dinar', 'Bahraini Dinar'),
      },
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _safeTranslate(context, 'fiat_currencies', 'Fiat Currencies'),
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text(
              _safeTranslate(context, 'all_currency', 'All currency:'),
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xCB838383),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: currencies.length,
                itemBuilder: (context, index) {
                  final currency = currencies[index];
                  return InkWell(
                    onTap: () {
                      final selectedCurrency = currency['code'];
                      
                      // Navigate back immediately
                      Navigator.pop(context);
                      
                      // Save currency in background
                      _saveSelectedCurrency(context, selectedCurrency).catchError((e) {
                        print('Error saving currency: $e');
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Image.asset(
                            currency['flag'],
                            width: 28,
                            height: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '${currency['code']} (${currency['symbol']})',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        color: Colors.black,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      currency['fullName'],
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: Colors.black,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  currency['country'],
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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