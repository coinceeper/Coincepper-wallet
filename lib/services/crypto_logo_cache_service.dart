import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../services/service_provider.dart';

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
        print('✅ Logo cache loaded: ${_logoCache.length} logos');
      } else {
        print('⚠️ Logo cache empty — will be fed by TokenProvider');
      }
      
      _isInitialized = true;
    } catch (e) {
      print('❌ Error initializing logo cache: $e');
      _isInitialized = true;
    }
  }

  /// Populate the in-memory cache from a map of symbol→URL already
  /// fetched by [TokenProvider], avoiding a redundant API call.
  static void populateFromMap(Map<String, String> symbolToUrl,
      {bool persist = true}) {
    _logoCache = Map.from(symbolToUrl);
    _isInitialized = true;
    print('✅ Logo cache populated from external source: ${_logoCache.length} entries');
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

  /// Refresh cache from all-currencies API
  static Future<void> _refreshCacheFromAPI() async {
    try {
      print('🔄 Refreshing logo cache from API...');
      
      final apiService = ServiceProvider.instance.apiService;
      final response = await apiService.getAllCurrencies();
      
      if (response.success && response.currencies.isNotEmpty) {
        final newCache = <String, String>{};
        
        for (final currency in response.currencies) {
          if (currency.icon != null && currency.icon!.isNotEmpty && currency.symbol != null) {
            // Store with symbol only
            newCache[currency.symbol!.toUpperCase()] = currency.icon!;
            
            // Store with symbol_blockchain if blockchain is available
            if (currency.blockchainName != null && currency.blockchainName!.isNotEmpty) {
              final key = '${currency.symbol!.toUpperCase()}_${currency.blockchainName}';
              newCache[key] = currency.icon!;
            }
          }
        }
        
        _logoCache = newCache;
        await _saveCacheToPreferences();
        
        print('✅ Logo cache refreshed: ${_logoCache.length} logos cached');
        print('📋 Cached symbols: ${_logoCache.keys.take(10).join(', ')}...');
      } else {
        print('❌ Failed to refresh logo cache from API');
      }
    } catch (e) {
      print('❌ Error refreshing logo cache: $e');
    }
  }

  /// Save cache to SharedPreferences
  static Future<void> _saveCacheToPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, json.encode(_logoCache));
      await prefs.setInt(_cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
      print('💾 Logo cache saved to SharedPreferences');
    } catch (e) {
      print('❌ Error saving logo cache: $e');
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
      print('🗑️ Logo cache cleared');
    } catch (e) {
      print('❌ Error clearing logo cache: $e');
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
      print('❌ Error loading logo for ${widget.symbol}: $e');
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
        color: bgColor.withOpacity(widget.backgroundOpacity),
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
                    color: bgColor.withOpacity(0.5),
                  )
                : logoUrl != null && logoUrl!.startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: logoUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Icon(
                          Icons.monetization_on,
                          size: widget.size * 0.5,
                          color: bgColor.withOpacity(0.5),
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
                              print('❌ Error loading asset logo: $error');
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
