import 'package:flutter/material.dart';
import '../navigation/app_navigation.dart';
import '../navigation/route_paths.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';

import 'package:my_flutter_app/screens/receive_wallet_screen.dart';
import '../models/transaction.dart';
import '../models/crypto_token.dart';
import '../services/api_models.dart' as api;
import '../services/secure_storage.dart';
import '../services/service_provider.dart';
import '../services/chart_api_service.dart';
import '../services/crypto_logo_cache_service.dart';
import '../providers/price_provider.dart';
import '../utils/number_formatter.dart';
import '../providers/app_provider.dart';
import '../providers/token_provider.dart';
import '../wallet/history/history_indexer.dart';
import '../wallet/address_registry.dart';
import '../wallet/wallet_mode.dart';
import '../widgets/crypto_chart.dart';
import '../ui/token_avatar.dart';
import '../models/chart_models.dart' as chart_models;
import '../services/portfolio_service.dart';
import '../services/chart_data_manager.dart' as chart_manager;
import '../services/chart_api_service_v2.dart';
import '../services/screen_cache_manager.dart';

/// Simple data class for price information
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

/// Live price data class for display
class LivePriceData {
  final String symbol;
  final double price;
  final double change24h;
  final double volume24h;
  final DateTime lastUpdated;

  LivePriceData({
    required this.symbol,
    required this.price,
    required this.change24h,
    required this.volume24h,
    required this.lastUpdated,
  });
}



/// Simple service for price data
class CoinMarketCapService {
  static Future<CurrentPriceData?> getCurrentPrice(String symbol) async {
    try {
      // Check if symbol has real price data by trying actual API call first
      // For now, return null to indicate no price data is available
      // This prevents showing fake prices for tokens without real data
      print('⚠️ No real price data available for symbol: $symbol');
      return null;
    } catch (e) {
      print('❌ Error fetching crypto price: $e');
      return null;
    }
  }
}

class CryptoDetailsScreen extends StatefulWidget {
  final String tokenName;
  final String tokenSymbol;
  final String iconUrl;
  final bool isToken;
  final String blockchainName;
  final double gasFee;
  // سایر پارامترهای مورد نیاز مانند قیمت، مقدار و ...

  const CryptoDetailsScreen({
    super.key,
    required this.tokenName,
    required this.tokenSymbol,
    required this.iconUrl,
    required this.isToken,
    required this.blockchainName,
    required this.gasFee,
  });

  @override
  State<CryptoDetailsScreen> createState() => _CryptoDetailsScreenState();
}

class _CryptoDetailsScreenState extends State<CryptoDetailsScreen> with SingleTickerProviderStateMixin {
  Color? dominantColor;

  List<Transaction> transactions = [];
  bool isLoading = true;
  String? errorMessage;
  double tokenBalance = 0.0;
  bool isLoadingBalance = true;
  TokenProvider? _tokenProvider;
  
  // New state variables for the redesigned UI
  late TabController _tabController;
  int _selectedTabIndex = 0;
  CurrentPriceData? currentPriceData;
  LivePriceData? livePrice; // Live price from new API
  bool isLoadingPrice = true;
  String? apiIconUrl; // Store the icon URL from API
  String _selectedTimeframe = '1D'; // Default timeframe
  
  // Chart interaction state
  bool _isChartInteracting = false;
  double? _selectedPointPrice;
  double? _selectedPointChange;
  
  // Portfolio data
  PortfolioSummary? portfolioSummary;
  bool isLoadingPortfolio = true;
  
  // Tooltip state
  bool _showTooltip = false;
  

  void _onTokenProviderChanged() {
    if (_tokenProvider == null) return;
    _syncBalanceFromProvider(_tokenProvider!);
  }

  void _syncBalanceFromProvider(TokenProvider tokenProvider) {
    try {
      final symbol = widget.tokenSymbol;
      final blockchain = widget.blockchainName;
      // Prefer enabled tokens, fallback to full list
      CryptoToken? token = tokenProvider.enabledTokens.firstWhere(
        (t) => (t.symbol ?? '').toUpperCase() == symbol.toUpperCase() &&
               (t.blockchainName ?? '') == blockchain,
        orElse: () => tokenProvider.currencies.firstWhere(
          (t) => (t.symbol ?? '').toUpperCase() == symbol.toUpperCase() &&
                 (t.blockchainName ?? '') == blockchain,
          orElse: () => CryptoToken(
            name: symbol,
            symbol: symbol,
            blockchainName: blockchain,
            iconUrl: widget.iconUrl,
            isEnabled: true,
            amount: 0.0,
            isToken: widget.isToken,
            smartContractAddress: null,
          ),
        ),
      );

      if (token.amount != tokenBalance && mounted) {
        setState(() {
          tokenBalance = token.amount ?? 0.0;
        });
      }
    } catch (_) {
      // Silent
    }
  }

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  // Get specific description for each cryptocurrency
  String _getCryptoDescription(String symbol) {
    switch (symbol.toUpperCase()) {
      case 'BTC':
        return 'Bitcoin is the first and most valuable cryptocurrency, often called digital gold.';
      case 'ETH':
        return 'Ethereum is a blockchain platform that enables smart contracts and decentralized applications.';
      case 'BNB':
        return 'Binance Coin is the native token of Binance exchange, used for trading fee discounts.';
      case 'TRX':
        return 'TRON is a blockchain platform focused on entertainment and content sharing applications.';
      case 'USDT':
        return 'Tether is a stablecoin pegged to the US Dollar, maintaining a 1:1 value ratio.';
      case 'USDC':
        return 'USD Coin is a regulated stablecoin backed by US Dollar reserves.';
      case 'ADA':
        return 'Cardano is a blockchain platform focused on sustainability and peer-reviewed research.';
      case 'DOT':
        return 'Polkadot enables different blockchains to transfer messages and value in a trust-free fashion.';
      case 'SOL':
        return 'Solana is a high-performance blockchain supporting fast and low-cost transactions.';
      case 'AVAX':
        return 'Avalanche is a platform for decentralized applications and custom blockchain networks.';
      case 'MATIC':
      case 'POL':
        return 'Polygon is a scaling solution for Ethereum, providing faster and cheaper transactions.';
      case 'XRP':
        return 'XRP is designed for fast and low-cost international payments and remittances.';
      case 'LINK':
        return 'Chainlink connects blockchain smart contracts with real-world data and services.';
      case 'UNI':
        return 'Uniswap is a decentralized exchange protocol for trading cryptocurrencies.';
      case 'SHIB':
        return 'Shiba Inu is a meme cryptocurrency inspired by the Shiba Inu dog breed.';
      case 'LTC':
        return 'Litecoin is a peer-to-peer cryptocurrency designed for fast and low-cost payments.';
      case 'DOGE':
        return 'Dogecoin started as a meme but became a popular cryptocurrency for tips and donations.';
      case 'NCC':
        return 'NCC is the native token of the Coinceeper ecosystem, providing utility and rewards.';
      case 'NCCOLD':
        return 'NCCOLD represents staked NCC tokens with enhanced rewards and governance rights.';
      case 'ARB':
        return 'Arbitrum is a Layer 2 scaling solution for Ethereum with faster and cheaper transactions.';
      default:
        return 'This cryptocurrency offers unique features and opportunities in the digital asset space.';
    }
  }



  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeCryptoLogoCache(); // Initialize logo cache first
    _updatePalette(widget.iconUrl);
    
    // ⚡ PRELOAD: Start preloading chart data
    _preloadChartData();
    
    _loadTransactions();
    _loadTokenBalance(); // اضافه کردن بارگذاری موجودی توکن
    _loadCurrentPrice(); // Load current price from CoinMarketCap
    _loadCryptoIcon(); // Load crypto icon from API
    _loadPortfolioData(); // Load portfolio profit/loss data
    
    // Immediately show balance from TokenProvider if available, and listen for updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final appProvider = Provider.of<AppProvider>(context, listen: false);
        _tokenProvider = appProvider.tokenProvider;
        if (_tokenProvider != null) {
          _syncBalanceFromProvider(_tokenProvider!);
          _tokenProvider!.addListener(_onTokenProviderChanged);
        }
      } catch (_) {}
    });
    
    // Load selected currency and fetch price for this token (مطابق با Kotlin crypto_details.kt)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      await priceProvider.loadSelectedCurrency();
      
      print('🔍 CryptoDetails: Loading price for ${widget.tokenSymbol} from PriceProvider');
      
      // دریافت قیمت این توکن خاص (مطابق با Kotlin crypto_details.kt)
      await priceProvider.fetchPrices([widget.tokenSymbol], currencies: [priceProvider.selectedCurrency]);
      
      // Check if price was loaded successfully
      final price = priceProvider.getPrice(widget.tokenSymbol);
      final priceChange = priceProvider.getPriceChange(widget.tokenSymbol);
      print('🔍 CryptoDetails: Price from PriceProvider: ${price ?? 'null'}');
      print('🔍 CryptoDetails: Price Change from PriceProvider: ${priceChange?.toStringAsFixed(2) ?? 'null'}%');
      
      // Reload portfolio data when prices are updated
      _loadPortfolioData();
    });
  }

  @override
  void dispose() {
    _tokenProvider?.removeListener(_onTokenProviderChanged);
    _tabController.dispose();
    // Dispose ChartDataManager resources
    chart_manager.ChartDataManager.instance.dispose();
    super.dispose();
  }

  /// ⚡ Preload chart data in background
  Future<void> _preloadChartData() async {
    try {
      print('🚀 CryptoDetails: Preloading chart data for ${widget.tokenSymbol}');
      
      // Preload multiple timeframes in parallel
      final chartDataManager = chart_manager.ChartDataManager.instance;
      final preloadTasks = ['1d', '1w', '1m'].map((timeframe) => 
        chartDataManager.getChartData(widget.tokenSymbol, timeframe, 'USD')
      );
      
      await Future.wait(preloadTasks);
      print('✅ CryptoDetails: Chart data preloaded for ${widget.tokenSymbol}');
    } catch (e) {
      print('⚠️ CryptoDetails: Error preloading chart data: $e');
    }
  }

  /// Load portfolio profit/loss data
  Future<void> _loadPortfolioData() async {
    setState(() {
      isLoadingPortfolio = true;
    });

    try {
      print('📊 Loading portfolio data for ${widget.tokenSymbol}...');
      
      // Wait for PriceProvider to have current prices
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      await priceProvider.fetchPrices([widget.tokenSymbol], currencies: [priceProvider.selectedCurrency]);
      
      // Get portfolio summary
      final portfolioService = PortfolioService();
      final summary = await portfolioService.getTokenPortfolioSummary(
        widget.tokenSymbol,
        tokenBalance,
        priceProvider,
      );
      
      setState(() {
        portfolioSummary = summary;
        isLoadingPortfolio = false;
      });
      
      if (summary != null) {
        print('✅ Portfolio data loaded for ${widget.tokenSymbol}:');
        print('   Profit/Loss: ${summary.formattedPercentage}');
        print('   Amount: ${summary.formattedAmount}');
      } else {
        print('⚠️ No portfolio data available for ${widget.tokenSymbol}');
      }
    } catch (e) {
      print('❌ Error loading portfolio data: $e');
      setState(() {
        isLoadingPortfolio = false;
      });
    }
  }

  /// Load current price data from PriceProvider
  Future<void> _loadCurrentPrice() async {
    setState(() {
      isLoadingPrice = true;
    });

    try {
      print('🔍 Loading price for ${widget.tokenSymbol}...');
      
      // Use PriceProvider directly
      print('📡 Using PriceProvider for price data...');
      final priceProvider = Provider.of<PriceProvider>(context, listen: false);
      
      // Make sure we have the latest prices
      await priceProvider.fetchPrices([widget.tokenSymbol], currencies: ['USD']);
      
      final price = priceProvider.getPrice(widget.tokenSymbol);
      final priceChange = priceProvider.getPriceChange(widget.tokenSymbol);
      
      if (price != null && price > 0) {
        // Create LivePriceData from PriceProvider data with actual change data
        setState(() {
          livePrice = LivePriceData(
            symbol: widget.tokenSymbol,
            price: price,
            change24h: priceChange ?? 0.0, // Use actual price change from PriceProvider
            volume24h: 0.0, // PriceProvider doesn't provide volume data
            lastUpdated: DateTime.now(),
          );
          isLoadingPrice = false;
        });
        print('✅ Price loaded from PriceProvider: \$${price.toStringAsFixed(4)}, Change: ${priceChange?.toStringAsFixed(2) ?? 'N/A'}%');
      } else {
        print('❌ No price found in PriceProvider for ${widget.tokenSymbol}');
        setState(() {
          isLoadingPrice = false;
        });
      }
    } catch (e) {
      print('❌ Error loading current price: $e');
      setState(() {
        isLoadingPrice = false;
      });
    }
  }

  /// Initialize crypto logo cache
  Future<void> _initializeCryptoLogoCache() async {
    try {
      await CryptoLogoCacheService.initialize();
      print('✅ Crypto logo cache initialized');
    } catch (e) {
      print('❌ Error initializing crypto logo cache: $e');
    }
  }

  /// Load crypto icon from cache
  Future<void> _loadCryptoIcon() async {
    try {
      print('🔍 Loading crypto icon for ${widget.tokenSymbol} from cache');
      
      final cachedUrl = await CryptoLogoCacheService.getLogoUrl(
        widget.tokenSymbol,
        blockchain: widget.blockchainName,
      );
      
      if (cachedUrl != null && cachedUrl.isNotEmpty) {
        print('✅ Found cached icon for ${widget.tokenSymbol}: $cachedUrl');
        setState(() {
          apiIconUrl = cachedUrl;
        });
        // Update palette with new icon
        _updatePalette(widget.iconUrl);
      } else {
        print('❌ No cached icon found for ${widget.tokenSymbol}');
      }
    } catch (e) {
      print('❌ Error loading crypto icon from cache: $e');
    }
  }

  /// ایجاد CryptoToken object برای ارسال به صفحه Send
  CryptoToken _createCryptoTokenForSend() {
    return CryptoToken(
      name: widget.tokenName,
      symbol: widget.tokenSymbol,
      blockchainName: widget.blockchainName,
      iconUrl: widget.iconUrl,
      isEnabled: true,
      amount: tokenBalance,
      isToken: widget.isToken,
      smartContractAddress: null, // می‌تواند null باشد یا از API دریافت شود
    );
  }

  /// هدایت به صفحه Send
  void _navigateToSendScreen() async {
    try {
      // ایجاد CryptoToken object
      final cryptoToken = _createCryptoTokenForSend();
      
      // تبدیل به JSON و encode کردن
      final tokenJson = jsonEncode(cryptoToken.toJson());
      final encodedTokenJson = Uri.encodeComponent(tokenJson);
      
      print('🚀 Navigating to Send screen with token data:');
      print('   Token: ${widget.tokenSymbol}');
      print('   Balance: $tokenBalance');
      print('   Blockchain: ${widget.blockchainName}');
      print('   Encoded JSON length: ${encodedTokenJson.length}');
      
      // هدایت به صفحه Send با format مطابق onGenerateRoute
      AppNavigation.pushNamed(
        context,
        '/send_detail/$encodedTokenJson',
      );
    } catch (e) {
      print('❌ Error navigating to send screen: $e');
      // Remove error message - silent failure
    }
  }

  /// دریافت آدرس کیف پول از API
  Future<String?> _getWalletAddress() async {
    try {
      final userId = await SecureStorage.getUserId();
      if (userId == null) {
        print('❌ CryptoDetails - No userId found for getting wallet address');
        return null;
      }

      print('🔍 CryptoDetails - Getting wallet address for blockchain: ${widget.blockchainName}');
      
      final addresses = await AddressRegistry.instance.loadForWallet(userId);
      final chain = widget.blockchainName ?? '';
      final addr = addresses[chain] ?? addresses[chain.toLowerCase()] ?? '';
      if (addr.isNotEmpty) {
        print('✅ CryptoDetails - Wallet address: $addr');
        return addr;
      }
      print('❌ CryptoDetails - No local address for $chain');
      return null;
    } catch (e) {
      print('❌ CryptoDetails - Error getting wallet address: $e');
      return null;
    }
  }

  /// دریافت موجودی توکن خاص فقط با API update-balance
  Future<void> _loadTokenBalance() async {
    setState(() {
      isLoadingBalance = true;
    });

    try {
      final userId = await SecureStorage.getUserId();
      if (userId != null) {
        print('🔍 CryptoDetails - Loading balance for token: ${widget.tokenSymbol}');
        print('🔍 CryptoDetails - UserID: $userId');
        
        if (await WalletModePreferences.usesLocalBalanceOnly()) {
          final appProvider = Provider.of<AppProvider>(context, listen: false);
          final tp = appProvider.tokenProvider;
          if (tp != null) {
            final match = tp.activeTokens.where(
              (t) =>
                  (t.symbol ?? '').toUpperCase() ==
                  widget.tokenSymbol.toUpperCase(),
            );
            if (match.isNotEmpty) {
              await tp.updateSingleTokenBalance(match.first);
              _syncBalanceFromProvider(tp);
              setState(() => isLoadingBalance = false);
              return;
            }
          }
        }

        try {
          final appProvider = Provider.of<AppProvider>(context, listen: false);
          final tp = appProvider.tokenProvider;
          if (tp != null) {
            _syncBalanceFromProvider(tp);
          }
        } catch (_) {}
        setState(() {
          isLoadingBalance = false;
        });
      } else {
        print('❌ CryptoDetails - No userId found');
        setState(() {
          tokenBalance = 0.0;
          isLoadingBalance = false;
        });
      }
    } catch (e) {
      print('❌ CryptoDetails - Error loading token balance: $e');
      // Fallback to provider state on error as well (بدون استفاده از API balance)
      try {
        final appProvider = Provider.of<AppProvider>(context, listen: false);
        final tp = appProvider.tokenProvider;
        if (tp != null) {
          _syncBalanceFromProvider(tp);
        }
      } catch (_) {}
      setState(() {
        isLoadingBalance = false;
      });
    }
  }

  Future<void> _updatePalette(String iconUrl) async {
    try {
      // Use API icon if available, otherwise use provided iconUrl
      final effectiveIconUrl = apiIconUrl ?? iconUrl;
      final ImageProvider provider = effectiveIconUrl.startsWith('http')
          ? NetworkImage(effectiveIconUrl)
          : AssetImage(effectiveIconUrl) as ImageProvider;
      // Palette generation removed for now
      print('Palette generation removed for $effectiveIconUrl');
              setState(() {
          dominantColor = const Color(0x80D7FBE7);
        });
    } catch (_) {
      setState(() {
        dominantColor = const Color(0x80D7FBE7);
      });
    }
  }

  Future<void> _loadTransactions() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    try {
      final userId = await SecureStorage.getUserId();
      if (userId != null && userId.isNotEmpty) {
        final all = await HistoryIndexer.instance.fetchAndCache(userId);
        final sym = (widget.tokenSymbol ?? '').toLowerCase();
        final filtered = all
            .where(
              (tx) => (tx.tokenSymbol ?? '').toLowerCase() == sym ||
                  (tx.blockchainName ?? '').toLowerCase().contains(sym),
            )
            .toList();
        setState(() {
          transactions = filtered;
          isLoading = false;
        });
        return;
      } else {
        print('❌ CryptoDetails: No userId found');
        setState(() {
          errorMessage = 'User ID not found';
          isLoading = false;
        });
      }
    } catch (e) {
      print('❌ CryptoDetails: Error loading transactions: $e');
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  // Build timeframe button - exactly like image
  Widget _buildTimeframeButton(String label, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTimeframe = label;
        });
        // Update chart with new timeframe
        _updateChartTimeframe(label);
        print('Selected timeframe: $label');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  // Update chart timeframe
  void _updateChartTimeframe(String timeframe) {
    // Convert display timeframe to API format
    String apiTimeframe;
    switch (timeframe) {
      case '1H':
        apiTimeframe = '1h';
        break;
      case '1D':
        apiTimeframe = '1d';
        break;
      case '1W':
        apiTimeframe = '1w';
        break;
      case '1M':
        apiTimeframe = '1m';
        break;
      case '1Y':
        apiTimeframe = '1y';
        break;
      case 'All':
        apiTimeframe = 'all';
        break;
      default:
        apiTimeframe = '1d';
    }
    
    print('🔄 Updating chart timeframe to: $apiTimeframe');
    // The chart will automatically update since we're using the same widget
  }

  // Convert display timeframe to API format
  String _convertTimeframeToAPI(String timeframe) {
    switch (timeframe) {
      case '1H':
        return '1h';
      case '1D':
        return '1d';
      case '1W':
        return '1w';
      case '1M':
        return '1m';
      case '1Y':
        return '1y';
      case 'All':
        return 'all';
      default:
        return '1d';
    }
  }

  // Handle chart point selection
  void _onChartPointSelected(double price, double change) {
    setState(() {
      _isChartInteracting = true;
      _selectedPointPrice = price;
      _selectedPointChange = change;
    });
    print('📊 Chart point selected: Price=\$${price.toStringAsFixed(2)}, Change=${change.toStringAsFixed(2)}%');
  }

  // Handle chart interaction end
  void _onChartInteractionEnd() {
    setState(() {
      _isChartInteracting = false;
      _selectedPointPrice = null;
      _selectedPointChange = null;
    });
    print('📊 Chart interaction ended - back to live price');
  }

  // Build tab button - exactly like image
  Widget _buildTabButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border: isSelected 
              ? const Border(
                  bottom: BorderSide(
                    color: Colors.black,
                    width: 2,
                  ),
                )
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? Colors.black : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  Widget _buildTokenIcon(String iconUrl, {double size = 40}) {
    // لیست لوگوهای asset محلی (مشابه home_screen.dart)
    final assetIcons = {
      'BTC': 'assets/images/btc.png',
      'ETH': 'assets/images/ethereum_logo.png',
      'BNB': 'assets/images/binance_logo.png',
      'TRX': 'assets/images/tron.png',
      'USDT': 'assets/images/usdt.png',
      'USDC': 'assets/images/usdc.png',
      'ADA': 'assets/images/cardano.png',
      'DOT': 'assets/images/dot.png',
      'SOL': 'assets/images/sol.png',
      'AVAX': 'assets/images/avax.png',
      'MATIC': 'assets/images/pol.png',
      'XRP': 'assets/images/xrp.png',
      'LINK': 'assets/images/chainlink.png',
      'UNI': 'assets/images/uniswap.png',
      'SHIB': 'assets/images/shiba.png',
      'LTC': 'assets/images/litecoin_logo.png',
      'DOGE': 'assets/images/dogecoin.png',
      'NCC': 'assets/images/ncc.png',
      'NCCOLD': 'assets/images/hold.png', // اضافه کردن NCCOLD با لوگوی جداگانه
    };
    
    final symbol = widget.tokenSymbol.toUpperCase();
    final assetIcon = assetIcons[symbol];
    
    print('🖼️ Building token icon for ${widget.tokenSymbol}:');
    print('   - Symbol: $symbol');
    print('   - Asset icon: $assetIcon');
    print('   - Original iconUrl: $iconUrl');
    print('   - API iconUrl: $apiIconUrl');
    
    // اولویت: Asset محلی > API icon > iconUrl اصلی
    if (assetIcon != null) {
      // استفاده از asset محلی
      print('✅ Using local asset icon: $assetIcon');
      return Image.asset(
        assetIcon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          print('❌ Error loading local asset icon: $error');
          return Icon(Icons.monetization_on, size: size, color: Colors.grey);
        },
      );
    }
    
    // اگر asset محلی وجود نداشت، از API یا iconUrl استفاده کن
    final effectiveIconUrl = apiIconUrl ?? iconUrl;
    print('⚠️ No local asset for $symbol, using URL: $effectiveIconUrl');
    
    if (effectiveIconUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: effectiveIconUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) => SizedBox(
          width: size,
          height: size,
          child: const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
              strokeWidth: 2,
            ),
          ),
        ),
        errorWidget: (context, url, error) {
          print('❌ Error loading network icon from $url: $error');
          return Icon(Icons.monetization_on, size: size, color: Colors.grey);
        },
      );
    } else {
      return Image.asset(
        effectiveIconUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          print('❌ Error loading asset icon: $error');
          return Icon(Icons.monetization_on, size: size, color: Colors.grey);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Hide tooltip when tapping elsewhere
        if (_showTooltip) {
          setState(() {
            _showTooltip = false;
          });
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
            // Header with back button and notification icon - exactly like image
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        widget.tokenSymbol,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        widget.tokenName,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showTooltip = !_showTooltip;
                      });
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _showTooltip ? const Color(0xFF0BAB9B).withOpacity(0.1) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: _showTooltip ? Border.all(color: const Color(0xFF0BAB9B), width: 1) : null,
                      ),
                      child: Icon(
                        Icons.notifications_outlined,
                        color: _showTooltip ? const Color(0xFF0BAB9B) : Colors.grey,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Tooltip widget
            if (_showTooltip)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Stack(
                  children: [
                    // Main tooltip container
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[700],
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _getCryptoDescription(widget.tokenSymbol),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Arrow pointing up to the notification bell
                    Positioned(
                      top: -8,
                      right: 24,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.grey[700],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                          ),
                        ),
                        transform: Matrix4.rotationZ(0.785398), // 45 degrees in radians
                      ),
                    ),
                  ],
                ),
              ),
            
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Balance and Price section - exactly like image
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                      child: Column(
                        children: [
                          // Small balance display
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF0BAB9B),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Consumer<PriceProvider>(
                                builder: (context, priceProvider, child) {
                                  final price = priceProvider.getPrice(widget.tokenSymbol) ?? 0.0;
                                  final balanceInUSD = tokenBalance * price;
                                  return Text(
                                    '\$${balanceInUSD.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.black,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          
                          // Main price display - dynamic based on chart interaction
                          Consumer<PriceProvider>(
                            builder: (context, priceProvider, child) {
                              // Use selected point price if interacting, otherwise live price
                              final displayPrice = _isChartInteracting && _selectedPointPrice != null
                                  ? _selectedPointPrice!
                                  : (priceProvider.getPrice(widget.tokenSymbol) ?? 4322.67);
                              
                              final displayChange = _isChartInteracting && _selectedPointChange != null
                                  ? _selectedPointChange!
                                  : (priceProvider.getPriceChange(widget.tokenSymbol) ?? 0.69);
                              
                              final isPositive = displayChange >= 0;
                              final priceColor = isPositive 
                                  ? const Color(0xFF0BAB9B) 
                                  : const Color(0xFFF43672);
                              
                              return Column(
                                children: [
                                  Text(
                                    '\$${displayPrice.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isPositive ? Icons.trending_up : Icons.trending_down,
                                        color: priceColor,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '\$${(displayPrice * displayChange / 100).abs().toStringAsFixed(2)} (${isPositive ? '+' : ''}${displayChange.toStringAsFixed(2)}%)',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: priceColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                          
                          const SizedBox(height: 48), // 3x spacing above chart (16 x 3 = 48)
                          
                          // Beautiful Chart - full width
                          Container(
                            height: 200,
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(horizontal: 0), // No horizontal margin for full width
                            child: CryptoChart(
                              key: ValueKey('${widget.tokenSymbol}_$_selectedTimeframe'), // Force rebuild on timeframe change
                              symbol: widget.tokenSymbol,
                              height: 200,
                              mode: CryptoChartMode.interactive,
                              showTimeframeSelector: false, // We'll add custom selector below
                              initialTimeframe: _convertTimeframeToAPI(_selectedTimeframe),
                              onPointSelected: (point, isPriceDown) {
                                if (point != null) {
                                  // Calculate change percentage relative to current live price
                                  final livePrice = Provider.of<PriceProvider>(context, listen: false)
                                      .getPrice(widget.tokenSymbol) ?? 4322.67;
                                  final change = ((point.price - livePrice) / livePrice) * 100;
                                  _onChartPointSelected(point.price, change);
                                }
                              },
                              onPointDeselected: () {
                                _onChartInteractionEnd();
                              },
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Timeframe selector - exactly like image
                          Container(
                            height: 40,
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildTimeframeButton('1H', _selectedTimeframe == '1H'),
                                _buildTimeframeButton('1D', _selectedTimeframe == '1D'),
                                _buildTimeframeButton('1W', _selectedTimeframe == '1W'),
                                _buildTimeframeButton('1M', _selectedTimeframe == '1M'),
                                _buildTimeframeButton('1Y', _selectedTimeframe == '1Y'),
                                _buildTimeframeButton('All', _selectedTimeframe == 'All'),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Tab bar - exactly like image
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildTabButton('Holdings', _selectedTabIndex == 0, () {
                            setState(() {
                              _selectedTabIndex = 0;
                            });
                          }),
                          _buildTabButton('History', _selectedTabIndex == 1, () {
                            setState(() {
                              _selectedTabIndex = 1;
                            });
                          }),
                          _buildTabButton('About', _selectedTabIndex == 2, () {
                            setState(() {
                              _selectedTabIndex = 2;
                            });
                          }),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Tab content based on selection
                    if (_selectedTabIndex == 0) ...[
                      // Holdings tab - exactly like image
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'My Balance',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Balance row - exactly like image
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  // Token icon - use actual crypto logo
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: _buildTokenIcon(widget.iconUrl),
                                  ),
                                  const SizedBox(width: 12),
                                  
                                  // Token info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.tokenName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black,
                                          ),
                                        ),
                                        Text(
                                          '${tokenBalance.toStringAsFixed(5)} ${widget.tokenSymbol}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // Balance value
                                  Consumer<PriceProvider>(
                                    builder: (context, priceProvider, child) {
                                      final price = priceProvider.getPrice(widget.tokenSymbol) ?? 0.0;
                                      final balanceInUSD = tokenBalance * price;
                                      final priceChange = priceProvider.getPriceChange(widget.tokenSymbol) ?? 0.0;
                                      final changeInUSD = balanceInUSD * priceChange / 100;
                                      final isPositive = changeInUSD >= 0;
                                      
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            '\$${balanceInUSD.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black,
                                            ),
                                          ),
                                          Text(
                                            '${isPositive ? '+' : ''}\$${changeInUSD.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: isPositive 
                                                  ? const Color(0xFF0BAB9B)
                                                  : const Color(0xFFF43672),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(height: 24),
                            
                            // Stake banner - exactly like image
                            // Container(
                            //   padding: const EdgeInsets.all(16),
                            //   decoration: BoxDecoration(
                            //     color: const Color(0xFFFFF4E6),
                            //     borderRadius: BorderRadius.circular(16),
                            //   ),
                            //   child: Row(
                            //     children: [
                            //       Container(
                            //         width: 40,
                            //         height: 40,
                            //         decoration: const BoxDecoration(
                            //           color: Color(0xFF4285F4),
                            //           shape: BoxShape.circle,
                            //         ),
                            //         child: const Icon(
                            //           Icons.trending_up,
                            //           color: Colors.white,
                            //           size: 20,
                            //         ),
                            //       ),
                            //       const SizedBox(width: 12),
                                  
                            //       const Expanded(
                            //         child: Text(
                            //           'Earn up to 2,97% APY on your ETH today.',
                            //           style: TextStyle(
                            //             fontSize: 15,
                            //             fontWeight: FontWeight.w600,
                            //             color: Colors.black,
                            //           ),
                            //         ),
                            //       ),
                                  
                            //       Container(
                            //         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            //         decoration: BoxDecoration(
                            //           color: const Color(0xFF4285F4),
                            //           borderRadius: BorderRadius.circular(20),
                            //         ),
                            //         child: const Row(
                            //           mainAxisSize: MainAxisSize.min,
                            //           children: [
                            //             Text(
                            //               'Stake now',
                            //               style: TextStyle(
                            //                 fontSize: 14,
                            //                 fontWeight: FontWeight.w600,
                            //                 color: Colors.white,
                            //               ),
                            //             ),
                            //             SizedBox(width: 4),
                            //             Icon(
                            //               Icons.arrow_forward,
                            //               color: Colors.white,
                            //               size: 16,
                            //             ),
                            //           ],
                            //         ),
                            //       ),
                            //     ],
                            //   ),
                            // ),
                          ],
                        ),
                      ),
                    ] else if (_selectedTabIndex == 1) ...[
                      // History tab
                      _buildHistoryTab(),
                    ] else if (_selectedTabIndex == 2) ...[
                      // About tab
                      _buildAboutTab(),
                    ],
                    
                    const SizedBox(height: 100), // Space for bottom buttons
                  ],
                ),
              ),
            ),
            
            // Bottom action buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _BottomActionButton(
                    assetIcon: 'assets/images/send.png',
                    label: _safeTranslate('send', 'Send'),
                    onTap: () => _navigateToSendScreen(),
                  ),
                  _BottomActionButton(
                    assetIcon: 'assets/images/receive.png',
                    label: _safeTranslate('receive', 'Receive'),
                    onTap: () async {
                      try {
                        final address = await _getWalletAddress();
                        if (address != null && address.isNotEmpty) {
                          AppNavigation.pushNamed(
                            context,
                            RoutePaths.receiveWallet,
                            arguments: {
                              'cryptoName': widget.tokenName,
                              'blockchainName': widget.blockchainName,
                              'address': address,
                              'symbol': widget.tokenSymbol,
                            },
                          );
                        }
                      } catch (e) {
                        // Silent failure
                      }
                    },
                  ),
                  // _BottomActionButton(
                  //   icon: Icons.swap_horiz,
                  //   label: _safeTranslate('swap', 'Swap'),
                  //   onTap: () {
                  //     // TODO: Implement swap functionality
                  //     ScaffoldMessenger.of(context).showSnackBar(
                  //       SnackBar(
                  //         content: Text(_safeTranslate('swap_coming_soon', 'Swap feature coming soon')),
                  //         backgroundColor: const Color(0xFF0BAB9B),
                  //       ),
                  //     );
                  //   },
                  // ),
                ],
              ),
            ),
          ],
        ),
      ),

      ),
    );
  }

  Widget _buildHoldingsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text(
            _safeTranslate('My Balance', 'My Balance'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _buildTokenIcon(widget.iconUrl, size: 40),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.blockchainName} ${widget.tokenSymbol}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        isLoadingBalance 
                            ? 'Loading...' 
                            : '${NumberFormatter.formatDouble(tokenBalance)} ${widget.tokenSymbol}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // نمایش مقدار سود/ضرر
                    if (isLoadingPortfolio)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
                        ),
                      )
                    else if (portfolioSummary != null)
                      Text(
                        portfolioSummary!.formattedAmount,
                        style: TextStyle(
                          fontSize: 14,
                          color: portfolioSummary!.profitLossPercentage == 0.0
                              ? Colors.grey[400]
                              : (portfolioSummary!.profitLossPercentage >= 0 
                                  ? const Color(0xFF0BAB9B) 
                                  : const Color(0xFFF43672)),
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else
                      Text(
                        '+\$0.00',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[400],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Use PriceProvider data with fallback to other sources
          Consumer<PriceProvider>(
            builder: (context, priceProvider, child) {
              final price = priceProvider.getPrice(widget.tokenSymbol) ?? livePrice?.price ?? currentPriceData?.price ?? 0.0;
              final marketChange = priceProvider.getPriceChange(widget.tokenSymbol) ?? livePrice?.change24h ?? currentPriceData?.change24h ?? 0.0;
              
              if (price > 0) {
                return Column(
                  children: [
                    _buildInfoRow('Current Price', '\$${price.toStringAsFixed(2)}'),
                    if (portfolioSummary != null) ...[
                      _buildInfoRow('Average Purchase Price', '\$${portfolioSummary!.averagePurchasePrice.toStringAsFixed(2)}'),
                      _buildInfoRow('Your Profit/Loss', portfolioSummary!.formattedPercentage),
                    ],
                    if (livePrice != null)
                      _buildInfoRow('24h Volume', '\$${_formatLargeNumber(livePrice!.volume24h)}'),
                    if (currentPriceData != null) ...[
                      _buildInfoRow('Market Cap', '\$${_formatLargeNumber(currentPriceData!.marketCap)}'),
                      _buildInfoRow('24h Volume', '\$${_formatLargeNumber(currentPriceData!.volume24h)}'),
                    ],
                    _buildInfoRow('Market 24h Change', '${marketChange >= 0 ? '+' : ''}${marketChange.toStringAsFixed(2)}%'),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildInfoRow('Current Price', '\$0.00'),
                    _buildInfoRow('Market Cap', 'Not available'),
                    _buildInfoRow('24h Volume', 'Not available'),
                    _buildInfoRow('Market 24h Change', '0.00%'),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          if (isLoading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0BAB9B)),
                ),
              ),
            )
          else if (errorMessage != null)
            Expanded(
              child: Center(
                child: Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          else
            Expanded(
              child: _TransactionHistorySection(
                transactions: transactions,
                tokenSymbol: widget.tokenSymbol,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAboutTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text(
            '${_safeTranslate('about', 'About')} ${widget.tokenName}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoRow('Symbol', widget.tokenSymbol),
          _buildInfoRow('Blockchain', widget.blockchainName),
          _buildInfoRow('Type', widget.isToken ? 'Token' : 'Coin'),
          // Use PriceProvider data with fallback to other sources
          Consumer<PriceProvider>(
            builder: (context, priceProvider, child) {
              final price = priceProvider.getPrice(widget.tokenSymbol) ?? livePrice?.price ?? currentPriceData?.price ?? 0.0;
              final marketChange = priceProvider.getPriceChange(widget.tokenSymbol) ?? livePrice?.change24h ?? currentPriceData?.change24h ?? 0.0;
              
              if (price > 0) {
                return Column(
                  children: [
                    _buildInfoRow('Current Price', '\$${price.toStringAsFixed(2)}'),
                    if (portfolioSummary != null) ...[
                      _buildInfoRow('Average Purchase Price', '\$${portfolioSummary!.averagePurchasePrice.toStringAsFixed(2)}'),
                      _buildInfoRow('Your Profit/Loss', portfolioSummary!.formattedPercentage),
                    ],
                    if (livePrice != null)
                      _buildInfoRow('24h Volume', '\$${_formatLargeNumber(livePrice!.volume24h)}'),
                    if (currentPriceData != null) ...[
                      _buildInfoRow('Market Cap', '\$${_formatLargeNumber(currentPriceData!.marketCap)}'),
                      _buildInfoRow('24h Volume', '\$${_formatLargeNumber(currentPriceData!.volume24h)}'),
                    ],
                    _buildInfoRow('Market 24h Change', '${marketChange >= 0 ? '+' : ''}${marketChange.toStringAsFixed(2)}%'),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildInfoRow('Current Price', '\$0.00'),
                    _buildInfoRow('Market Cap', 'Not available'),
                    _buildInfoRow('24h Volume', 'Not available'),
                    _buildInfoRow('Market 24h Change', '0.00%'),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  String _formatLargeNumber(double number) {
    if (number >= 1e12) {
      return '${(number / 1e12).toStringAsFixed(2)}T';
    } else if (number >= 1e9) {
      return '${(number / 1e9).toStringAsFixed(2)}B';
    } else if (number >= 1e6) {
      return '${(number / 1e6).toStringAsFixed(2)}M';
    } else if (number >= 1e3) {
      return '${(number / 1e3).toStringAsFixed(2)}K';
    } else {
      return number.toStringAsFixed(2);
    }
  }
}

// Bottom action button widget
class _BottomActionButton extends StatelessWidget {
  final IconData? icon;
  final String? assetIcon;
  final String label;
  final VoidCallback onTap;

  const _BottomActionButton({
    this.icon,
    this.assetIcon,
    required this.label,
    required this.onTap,
  }) : assert(icon != null || assetIcon != null, 'Either icon or assetIcon must be provided');

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                color: Color(0xFF0BAB9B),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: assetIcon != null
                    ? Image.asset(
                        assetIcon!,
                        width: 24,
                        height: 24,
                        color: Colors.white,
                        errorBuilder: (context, error, stackTrace) {
                          // Fallback to icon if asset fails
                          return Icon(
                            icon ?? Icons.help,
                            color: Colors.white,
                            size: 24,
                          );
                        },
                      )
                    : Icon(
                        icon!,
                        color: Colors.white,
                        size: 24,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String assetIcon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.assetIcon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Image.asset(
                assetIcon,
                width: 28,
                height: 28,
                color: Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// Transaction history section widget
class _TransactionHistorySection extends StatelessWidget {
  final List<Transaction> transactions;
  final String tokenSymbol;
  const _TransactionHistorySection({required this.transactions, required this.tokenSymbol});

  // Safe translate method with fallback
  String _safeTranslate(BuildContext context, String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  String _getDateGroup(BuildContext context, String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final transactionDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
      if (transactionDate.isAtSameMomentAs(today)) {
        return _safeTranslate(context, 'today', 'Today');
      } else if (transactionDate.isAtSameMomentAs(yesterday)) {
        return _safeTranslate(context, 'yesterday', 'Yesterday');
      } else {
        return "${dateTime.year}/${dateTime.month}/${dateTime.day}";
      }
    } catch (e) {
      return _safeTranslate(context, 'unknown_date', 'Unknown Date');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Image.asset('assets/images/notransaction.png', width: 80, height: 80),
            const SizedBox(height: 12),
            Text(_safeTranslate(context, 'no_transactions_found', 'No transactions found'), style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    // Group transactions by date
    final grouped = <String, List<Transaction>>{};
    for (final tx in transactions) {
      final group = _getDateGroup(context, tx.timestamp);
      grouped.putIfAbsent(group, () => []).add(tx);
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(0),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final date in grouped.keys)
            ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Text(date, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
              ),
              ...grouped[date]!.map((tx) => _TransactionItem(tx: tx)),
            ],
        ],
      ),
    );
  }
}

class _TransactionItem extends StatelessWidget {
  final Transaction tx;
  const _TransactionItem({required this.tx});

  // Safe translate method with fallback
  String _safeTranslate(BuildContext context, String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  String _formatAmount(String amount) {
    return NumberFormatter.formatAmount(amount);
  }

  @override
  Widget build(BuildContext context) {
    final isReceived = tx.direction == "inbound";
    final icon = isReceived ? Icons.arrow_downward : Icons.arrow_upward;
    final iconColor = isReceived ? const Color(0xFF0BAB9B) : const Color(0xFFF43672);
    final bgColor = isReceived ? const Color(0xFF0BAB9B).withOpacity(0.1) : const Color(0xFFF43672).withOpacity(0.1);
    final address = isReceived ? tx.from : tx.to;
    final shortAddress = address.length > 15 ? "${address.substring(0, 10)}...${address.substring(address.length - 5)}" : address;
    final amountPrefix = isReceived ? "+" : "-";
    final amountValue = "$amountPrefix${_formatAmount(tx.amount)}";
    final isPending = !isReceived && (tx.status ?? '').toLowerCase() == "pending";
    
    return GestureDetector(
      onTap: () {
        // Navigate to transaction detail screen with txHash for API loading
        AppNavigation.pushNamed(
          context,
          '/transaction_detail',
          arguments: {            'transactionId': tx.txHash, // ارسال txHash برای دریافت جزئیات از API
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Center(
              child: isPending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Color(0xFFF43672),
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(icon, color: iconColor, size: 16),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(isReceived ? _safeTranslate(context, 'receive', 'Receive') : _safeTranslate(context, 'send', 'Send'), style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                    if (isPending) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9A825),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(_safeTranslate(context, 'pending', 'pending'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                Text(shortAddress, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Text(amountValue, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: amountValue.startsWith("-") ? const Color(0xFFF43672) : const Color(0xFF0BAB9B))),
                  const SizedBox(width: 2),
                  Text(tx.tokenSymbol, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: Colors.black)),
                ],
              ),
              Consumer<PriceProvider>(
                builder: (context, priceProvider, child) {
                  final currencySymbol = priceProvider.getCurrencySymbol();
                  try {
                    final price = tx.price ?? 0.0;
                    if (price > 0.0) {
                      final value = price * double.parse(tx.amount);
                      return Text(
                        "≈ $currencySymbol${value.toStringAsFixed(2)}",
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      );
                    } else {
                      return Text(
                        "≈ $currencySymbol${0.00.toStringAsFixed(2)}",
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      );
                    }
                  } catch (e) {
                    return Text(
                      "≈ $currencySymbol${0.00.toStringAsFixed(2)}",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    );
                  }
                },
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }
} 
