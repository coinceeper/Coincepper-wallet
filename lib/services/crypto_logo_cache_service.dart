import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../utils/secure_log.dart';

class CryptoLogoCacheService {
  static const String _cacheKey = 'crypto_logos_cache';
  static const String _cacheTimestampKey = 'crypto_logos_cache_timestamp';
  static const Duration _cacheExpiry = Duration(hours: 24); // Cache for 24 hours
  
  static Map<String, String> _logoCache = {};
  static bool _isInitialized = false;

  /// Initialize the cache by loading from SharedPreferences only.
  /// Does NOT call the API — relies on [populateFromCache] or
  /// [TokenProvider] to keep data fresh.
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = prefs.getString(_cacheKey);
      final timestamp = prefs.getInt(_cacheTimestampKey) ?? 0;
      
      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();
      
      if (cacheData != null) {
        _logoCache = Map<String, String>.from(json.decode(cacheData));
        SecureLog.i('Logo cache loaded: ${_logoCache.length} logos');
      } else {
        SecureLog.w('Logo cache empty');
      }
      
      _isInitialized = true;
    } catch (e) {
        SecureLog.e('Error initializing logo cache', error: e);
      _isInitialized = true;
    }
  }

  /// Populate the in-memory cache from a map of symbol→URL already
  /// fetched by [TokenProvider], avoiding a redundant API call.
  static void populateFromMap(Map<String, String> symbolToUrl,
      {bool persist = true}) {
    _logoCache = Map.from(symbolToUrl);
    _isInitialized = true;
    SecureLog.i('Logo cache populated from external source: ${_logoCache.length} entries');
    if (persist) {
      unawaited(_saveCacheToPreferences());
    }
  }

  /// Get logo URL for a crypto symbol
  static Future<String?> getLogoUrl(String symbol, {String? blockchain}) async {
    await initialize();
    
    // Try exact match with blockchain first
    String cacheKey = blockchain != null ? '${symbol}_$blockchain' : symbol;
    if (_logoCache.containsKey(cacheKey)) {
      return _logoCache[cacheKey];
    }
    
    // Try symbol only
    if (_logoCache.containsKey(symbol)) {
      return _logoCache[symbol];
    }
    
    return null;
  }

  /// Refresh cache from CoinGecko
  static Future<void> _refreshCacheFromAPI() async {
    try {
      SecureLog.i('Refreshing logo cache from CoinGecko');
      
      // Use CoinGecko markets endpoint (free, no API key needed)
      final res = await http.get(
        Uri.parse('https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=250&page=1'),
      ).timeout(const Duration(seconds: 15));
      
      if (res.statusCode == 200) {
        final List<dynamic> coins = json.decode(res.body);
        final newCache = <String, String>{};
        
        for (final coin in coins) {
          final c = coin as Map<String, dynamic>;
          final symbol = (c['symbol']?.toString() ?? '').toUpperCase();
          final image = c['image']?.toString() ?? '';
          final name = c['name']?.toString() ?? '';
          
          if (symbol.isNotEmpty && image.isNotEmpty) {
            newCache[symbol] = image;
            newCache['${symbol}_$name'] = image;
          }
        }
        
        _logoCache = newCache;
        await _saveCacheToPreferences();
        
        SecureLog.i('Logo cache refreshed from CoinGecko: ${_logoCache.length} logos');
      } else {
        SecureLog.e('Failed to refresh logo cache from CoinGecko (status ${res.statusCode})');
      }
    } catch (e) {
      SecureLog.e('Error refreshing logo cache', error: e);
    }
  }

  /// Save cache to SharedPreferences
  static Future<void> _saveCacheToPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, json.encode(_logoCache));
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
      SecureLog.i('Logo cache saved to SharedPreferences');
    } catch (e) {
      SecureLog.e('Error saving logo cache', error: e);
    }
  }

  /// Force refresh cache from API
  static Future<void> forceRefresh() async {
    await _refreshCacheFromAPI();
  }

  /// Clear cache
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimestampKey);
      _logoCache.clear();
      SecureLog.i('Logo cache cleared');
    } catch (e) {
      SecureLog.e('Error clearing logo cache', error: e);
    }
  }

  /// Get cache info for debugging
  static Map<String, dynamic> getCacheInfo() {
    return {
      'isInitialized': _isInitialized,
      'cacheSize': _logoCache.length,
      'cachedSymbols': _logoCache.keys.toList(),
    };
  }
}

/// Widget for displaying cached crypto logos
class CachedCryptoLogo extends StatefulWidget {
  final String symbol;
  final String? blockchain;
  final String? fallbackUrl;
  final double size;
  final Color? backgroundColor;
  final double backgroundOpacity;

  const CachedCryptoLogo({
    super.key,
    required this.symbol,
    this.blockchain,
    this.fallbackUrl,
    this.size = 40,
    this.backgroundColor,
    this.backgroundOpacity = 0.15, // Much lighter background
  });

  @override
  State<CachedCryptoLogo> createState() => _CachedCryptoLogoState();
}

class _CachedCryptoLogoState extends State<CachedCryptoLogo> {
  String? logoUrl;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogo();
  }

  Future<void> _loadLogo() async {
    try {
      final url = await CryptoLogoCacheService.getLogoUrl(
        widget.symbol,
        blockchain: widget.blockchain,
      );
      
      setState(() {
        logoUrl = url ?? widget.fallbackUrl;
        isLoading = false;
      });
    } catch (e) {
      SecureLog.e('Error loading logo', error: e);
      setState(() {
        logoUrl = widget.fallbackUrl;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.backgroundColor ?? Theme.of(context).primaryColor;
    
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: widget.backgroundOpacity),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: ClipOval(
          child: SizedBox(
            width: widget.size * 0.7, // Logo is 70% of container size
            height: widget.size * 0.7,
            child: isLoading
                ? Icon(
                    Icons.monetization_on,
                    size: widget.size * 0.5,
                    color: bgColor.withValues(alpha: 0.5),
                  )
                : logoUrl != null && logoUrl!.startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: logoUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Icon(
                          Icons.monetization_on,
                          size: widget.size * 0.5,
                          color: bgColor.withValues(alpha: 0.5),
                        ),
                        errorWidget: (context, url, error) {
                          return Icon(
                            Icons.monetization_on,
                            size: widget.size * 0.5,
                            color: bgColor,
                          );
                        },
                      )
                    : logoUrl != null
                        ? Image.asset(
                            logoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              SecureLog.e('Error loading asset logo', error: error);
                              return Icon(
                                Icons.monetization_on,
                                size: widget.size * 0.5,
                                color: bgColor,
                              );
                            },
                          )
                        : Icon(
                            Icons.monetization_on,
                            size: widget.size * 0.5,
                            color: bgColor,
                          ),
          ),
        ),
      ),
    );
  }
}
