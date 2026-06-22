import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/current_price_data.dart';
import '../utils/secure_log.dart';

/// CoinMarketCap price lookup (V1 direct API).
/// This service is **deprecated** in favour of the V2 Cache Proxy on coinceeper.com.
/// The API key must be provided via `--dart-define=COINMARKETCAP_API_KEY=...`
/// at build/run time. Without it the service returns null.
///
/// NOTE: No mock/fake data is generated. If the API call fails or has no key,
/// null is returned.
class CoinMarketCapService {
  static const String _baseUrl = 'https://pro-api.coinmarketcap.com/v1';
  static const String _apiKey = String.fromEnvironment(
    'COINMARKETCAP_API_KEY',
    defaultValue: '',
  );

  static bool get _hasApiKey => _apiKey.isNotEmpty;

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'X-CMC_PRO_API_KEY': _apiKey,
  };

  /// Get current price data for a cryptocurrency
  static Future<CurrentPriceData?> getCurrentPrice(String symbol) async {
    if (!_hasApiKey) {
      SecureLog.w('CoinMarketCap: No API key configured — returning null');
      return null;
    }

    try {
      SecureLog.d('Fetching current price for $symbol from CoinMarketCap');

      final response = await http.get(
        Uri.parse('$_baseUrl/cryptocurrency/quotes/latest?symbol=${symbol.toUpperCase()}'),
        headers: _headers,
      );

      SecureLog.d('CoinMarketCap API Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status']['error_code'] == 0 && data['data'] != null) {
          final symbolData = data['data'][symbol.toUpperCase()];
          if (symbolData != null) {
            final quote = symbolData['quote']['USD'];
            
            return CurrentPriceData(
              price: (quote['price'] as num?)?.toDouble() ?? 0.0,
              change24h: (quote['percent_change_24h'] as num?)?.toDouble() ?? 0.0,
              marketCap: (quote['market_cap'] as num?)?.toDouble() ?? 0.0,
              volume24h: (quote['volume_24h'] as num?)?.toDouble() ?? 0.0,
              lastUpdated: DateTime.tryParse(quote['last_updated'] ?? '') ?? DateTime.now(),
            );
          }
        } else {
          SecureLog.e('CoinMarketCap API Error: ${data['status']['error_message']}');
        }
      } else {
        SecureLog.e('CoinMarketCap HTTP Error: ${response.statusCode}');
      }
      
      return null; // No mock fallback
    } catch (e) {
      SecureLog.e('Error fetching current price from CoinMarketCap', error: e);
      return null; // No mock fallback
    }
  }

  /// ⚡ BATCH: Get prices for multiple symbols in a single API call
  static Future<Map<String, CurrentPriceData>> getPricesBatch(List<String> symbols) async {
    final result = <String, CurrentPriceData>{};
    if (symbols.isEmpty) return result;
    
    if (!_hasApiKey) {
      SecureLog.w('CoinMarketCap: No API key configured — returning empty');
      return result;
    }
    
    try {
      final uniqueSymbols = symbols
          .map((s) => s.toUpperCase())
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList();
      
      if (uniqueSymbols.isEmpty) return result;
      
      SecureLog.d('Fetching batch prices for ${uniqueSymbols.length} symbols from CoinMarketCap');
      
      const int batchSize = 100;
      for (int i = 0; i < uniqueSymbols.length; i += batchSize) {
        final end = (i + batchSize).clamp(0, uniqueSymbols.length);
        final batch = uniqueSymbols.sublist(i, end);
        final symbolsParam = batch.join(',');
        
        final response = await http.get(
          Uri.parse('$_baseUrl/cryptocurrency/quotes/latest?symbol=$symbolsParam'),
          headers: _headers,
        );
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['status']['error_code'] == 0 && data['data'] != null) {
            for (final symbol in batch) {
              final symbolData = data['data'][symbol];
              if (symbolData != null) {
                final quote = symbolData['quote']['USD'];
                result[symbol] = CurrentPriceData(
                  price: (quote['price'] as num?)?.toDouble() ?? 0.0,
                  change24h: (quote['percent_change_24h'] as num?)?.toDouble() ?? 0.0,
                  marketCap: (quote['market_cap'] as num?)?.toDouble() ?? 0.0,
                  volume24h: (quote['volume_24h'] as num?)?.toDouble() ?? 0.0,
                  lastUpdated: DateTime.tryParse(quote['last_updated'] ?? '') ?? DateTime.now(),
                );
              }
            }
          }
        } else {
          SecureLog.w('CoinMarketCap batch HTTP Error: ${response.statusCode}');
        }
      }
      
      SecureLog.i('Batch prices fetched: ${result.length}/${uniqueSymbols.length} symbols');
      return result; // No mock fallback
    } catch (e) {
      SecureLog.e('Error fetching batch prices', error: e);
      return result; // No mock fallback
    }
  }
}
