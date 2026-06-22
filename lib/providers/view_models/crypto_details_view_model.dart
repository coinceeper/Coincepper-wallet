import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/crypto_token.dart';
import '../../models/transaction.dart';
import '../../services/secure_storage.dart';
import '../../providers/price_provider.dart';
import '../../providers/token_provider.dart';
import '../../wallet/address_registry.dart';
import '../../wallet/history/history_indexer.dart';
import '../../services/error_service.dart';
import '../../di/service_locator.dart';
import '../../utils/secure_log.dart';

/// Price information for a crypto token.
class CurrentPriceData {
  final double price;
  final double change24h;
  final double marketCap;
  final double volume24h;
  final DateTime lastUpdated;

  CurrentPriceData({
    required this.price,
    required this.change24h,
    required this.marketCap,
    required this.volume24h,
    required this.lastUpdated,
  });
}

/// State and business logic for the crypto detail screen.
class CryptoDetailsViewModel extends ChangeNotifier {
  final String tokenName;
  final String tokenSymbol;
  final String iconUrl;
  final bool isToken;
  final String blockchainName;
  final double gasFee;

  CryptoDetailsViewModel({
    required this.tokenName,
    required this.tokenSymbol,
    required this.iconUrl,
    required this.isToken,
    required this.blockchainName,
    this.gasFee = 0.0,
  });

  // ==================== STATE ====================
  CurrentPriceData? _priceData;
  CurrentPriceData? get priceData => _priceData;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  bool _isRefreshing = false;
  bool get isRefreshing => _isRefreshing;

  String? _walletAddress;
  String? get walletAddress => _walletAddress;

  List<Transaction> _transactions = [];
  List<Transaction> get transactions => _transactions;

  CryptoToken? _token;
  CryptoToken? get token => _token;

  double _balance = 0.0;
  double get balance => _balance;

  // ==================== INITIALIZATION ====================

  Future<void> initialize(BuildContext context) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _loadWalletAddress();
      await _loadToken(context);
      await _loadTransactions();
      await _fetchPriceData(context);
    } catch (e, st) {
      SecureLog.w('Error initializing crypto details', error: e, stackTrace: st);
      _reportError(e, 'Failed to load token details.', st);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadWalletAddress() async {
    final userId = await ServiceLocator.get<SecureStorage>().getUserIdForSelectedWallet();
    if (userId != null) {
      final addresses = await ServiceLocator.get<AddressRegistry>().loadForWallet(userId);
      _walletAddress = addresses.values.firstOrNull;
    }
  }

  Future<void> _loadToken(BuildContext context) async {
    try {
      final tokenProvider = Provider.of<TokenProvider>(context, listen: false);
      _token = tokenProvider.activeTokens.where((t) => t.symbol == tokenSymbol).firstOrNull;
      if (_token != null) {
        _balance = _token!.amount;
      } else {
        // Create a basic token from the known info
        _token = CryptoToken(
          name: tokenName,
          symbol: tokenSymbol,
          blockchainName: blockchainName,
          isEnabled: true,
          isToken: isToken,
          iconUrl: iconUrl,
          amount: 0.0,
        );
      }
    } catch (e) {
      SecureLog.w('CryptoDetailsVM: failed to load token details, using fallback', error: e);
      _token = CryptoToken(
        name: tokenName,
        symbol: tokenSymbol,
        blockchainName: blockchainName,
        isEnabled: true,
        isToken: isToken,
        iconUrl: iconUrl,
        amount: 0.0,
      );
    }
  }

  Future<void> _loadTransactions() async {
    try {
      if (_walletAddress != null) {
        // Get userId for fetching
        final userId = await ServiceLocator.get<SecureStorage>().getUserIdForSelectedWallet();
        if (userId != null) {
          _transactions = await ServiceLocator.get<HistoryIndexer>().fetchAndCache(
            userId,
            tokenSymbol: tokenSymbol,
          );
        }
      }
    } catch (e, st) {
      SecureLog.w('Error loading transactions in crypto details', error: e, stackTrace: st);
      _reportError(e, 'Failed to load transaction history.', st);
    }
  }

  Future<void> _fetchPriceData(BuildContext context) async {
    try {
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      await priceProvider.fetchPrices([tokenSymbol]);
      final price = priceProvider.getPrice(tokenSymbol);
      if (price != null && price > 0) {
        _priceData = CurrentPriceData(
          price: price,
          change24h: priceProvider.getPriceChange(tokenSymbol) ?? 0.0,
          marketCap: double.tryParse(priceProvider.getMarketCap(tokenSymbol) ?? '') ?? 0.0,
          volume24h: double.tryParse(priceProvider.getVolume24h(tokenSymbol) ?? '') ?? 0.0,
          lastUpdated: DateTime.now(),
        );
      }
    } catch (e, st) {
      SecureLog.w('Error fetching price data in crypto details', error: e, stackTrace: st);
      _reportError(e, 'Failed to fetch price data.', st);
    }
  }

  // ==================== ACTIONS ====================

  Future<void> refresh(BuildContext context) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    notifyListeners();

    await _fetchPriceData(context);

    _isRefreshing = false;
    notifyListeners();
  }

  String getTokenJson() {
    if (_token == null) return '';
    return Uri.encodeComponent(jsonEncode(_token!.toJson()));
  }

  String formatAddress(String address) {
    if (address.length <= 12) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  void _reportError(Object error, String message, [StackTrace? stackTrace]) {
    try {
      ServiceLocator.get<ErrorService>().report(
        error,
        message: message,
        stackTrace: stackTrace,
      );
    } catch (e) {
      SecureLog.e('CryptoDetailsVM: ErrorService unavailable', error: e);
    }
  }
}
