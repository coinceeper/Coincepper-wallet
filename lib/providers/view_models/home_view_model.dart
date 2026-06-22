import 'package:flutter/material.dart';
import '../../domain/services/token_filter_service.dart';
import '../../domain/services/portfolio_service.dart';
import '../../services/home_init_service.dart';
import '../../services/price_refresh_service.dart';
import '../../services/security_settings_manager.dart';
import '../../providers/app_provider.dart';
import '../../providers/price_provider.dart';
import '../../models/crypto_token.dart';

/// Coordinator for the Home screen.
///
/// This ViewModel no longer contains business logic inline. Instead it
/// composes four specialized services, each with a single responsibility:
///
/// - [TokenFilterService] — filtering & sorting tokens
/// - [PortfolioService] — portfolio value calculation & formatting
/// - [HomeInitService] — initialization orchestration
/// - [PriceRefreshService] — price refresh & periodic timer
///
/// The ViewModel's own responsibilities are limited to:
/// - UI state (selected tab, hidden balance, refresh in flight)
/// - Filter/sort preference state (sort option, hide zero, show only enabled)
/// - Delegating user actions to the appropriate service
/// - Wrapping results as notifiable state for the UI
class HomeViewModel extends ChangeNotifier {
  // ==================== COMPOSED SERVICES ====================
  final TokenFilterService tokenFilterService;
  final PortfolioService portfolioService;
  final HomeInitService initService;
  final PriceRefreshService priceRefreshService;

  // ==================== EXTERNAL DEPENDENCIES ====================
  final AppProvider appProvider;
  final PriceProvider priceProvider;
  final SecuritySettingsManager securityManager;

  HomeViewModel({
    required this.appProvider,
    required this.priceProvider,
    required this.securityManager,
    this.tokenFilterService = const TokenFilterService(),
    this.portfolioService = const PortfolioService(),
    HomeInitService? initService,
    PriceRefreshService? priceRefreshService,
  })  : initService = initService ?? HomeInitService(),
        priceRefreshService = priceRefreshService ?? PriceRefreshService();

  // ==================== UI STATE ====================
  bool isHidden = false;
  int selectedTab = 0;

  // Sort and filter preferences (UI state only — logic delegated)
  String sortOption = 'balance';
  bool hideZeroBalances = false;
  bool showOnlyEnabled = false;
  final List<String> selectedBlockchains = [];

  // Computed delegates

  /// Whether initialization has completed.
  bool get initialized => initService.isInitialized;

  /// Whether a refresh is in flight.
  bool get isRefreshing => priceRefreshService.isRefreshing;

  // ==================== COMPUTED: FILTERING & SORTING ====================
  List<CryptoToken> get filteredAndSortedTokens {
    final tokenProvider = appProvider.tokenProvider;
    if (tokenProvider == null) return [];

    return tokenFilterService.filterAndSort(
      tokens: tokenProvider.activeTokens,
      priceQuery: priceProvider,
      sortOption: sortOption,
      hideZeroBalances: hideZeroBalances,
      showOnlyEnabled: showOnlyEnabled,
      selectedBlockchains: selectedBlockchains,
    );
  }

  // ==================== COMPUTED: PORTFOLIO ====================
  double get totalPortfolioValue {
    return portfolioService.calculateTotalValue(
      tokens: filteredAndSortedTokens,
      priceQuery: priceProvider,
    );
  }

  double getTokenPrice(String symbol) {
    return portfolioService.getTokenPrice(priceProvider, symbol);
  }

  String formatPortfolioValue(double value) {
    return portfolioService.formatValue(value);
  }

  // ==================== INITIALIZATION (DELEGATED) ====================
  Future<void> initialize() async {
    final tokenProvider = appProvider.tokenProvider;
    await initService.initialize(
      securityManager: securityManager,
      apiService: appProvider.apiService,
      currentUserId: appProvider.currentUserId,
      currentWalletName: appProvider.currentWalletName,
      ensureBitcoinEthereumEnabled: tokenProvider == null
          ? null
          : () => tokenProvider.ensureBitcoinEthereumEnabled(),
      getEnabledTokenSymbols: tokenProvider == null
          ? null
          : () => tokenProvider.enabledTokens
              .map((t) => t.symbol ?? '')
              .where((s) => s.isNotEmpty)
              .toList(),
      loadPrices: (symbols) => priceProvider.fetchPrices(symbols),
    );

    if (initService.isInitialized) {
      priceRefreshService.startPeriodicUpdates(
        getEnabledTokenSymbols: () => appProvider.tokenProvider?.enabledTokens
                .map((t) => t.symbol ?? '')
                .where((s) => s.isNotEmpty)
                .toList() ??
            [],
        loadPrices: (symbols) => priceProvider.fetchPrices(symbols),
      );
    }

    notifyListeners();
  }

  // ==================== REFRESH (DELEGATED) ====================
  Future<void> refreshPricesAndBalances() async {
    final tokenProvider = appProvider.tokenProvider;
    if (tokenProvider == null) return;
    await priceRefreshService.refreshPricesAndBalances(
      refreshActiveTokens: () => tokenProvider.refreshActiveTokens(),
      getEnabledTokenSymbols: () => tokenProvider.enabledTokens
          .map((t) => t.symbol ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
      loadPrices: (symbols) => priceProvider.fetchPrices(symbols),
    );
    notifyListeners();
  }

  Future<void> refreshPricesForEnabledTokens() async {
    final tokenProvider = appProvider.tokenProvider;
    if (tokenProvider == null) return;
    await priceRefreshService.refreshPricesForEnabledTokens(
      getEnabledTokenSymbols: () => tokenProvider.enabledTokens
          .map((t) => t.symbol ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
      loadPrices: (symbols) => priceProvider.fetchPrices(symbols),
    );
  }

  // ==================== TOGGLE ACTIONS ====================
  void toggleHidden() {
    isHidden = !isHidden;
    notifyListeners();
  }

  void setSortOption(String option) {
    sortOption = option;
    notifyListeners();
  }

  void toggleZeroBalances() {
    hideZeroBalances = !hideZeroBalances;
    notifyListeners();
  }

  void toggleShowOnlyEnabled() {
    showOnlyEnabled = !showOnlyEnabled;
    notifyListeners();
  }

  void toggleBlockchainFilter(String blockchain) {
    if (selectedBlockchains.contains(blockchain)) {
      selectedBlockchains.remove(blockchain);
    } else {
      selectedBlockchains.add(blockchain);
    }
    notifyListeners();
  }

  // ==================== SEARCH (DELEGATED) ====================
  List<CryptoToken> searchTokens(String query) {
    final tokens = filteredAndSortedTokens;
    return tokenFilterService.search(tokens, query);
  }

  // ==================== TAB MANAGEMENT ====================
  void selectTab(int index) {
    selectedTab = index;
    notifyListeners();
  }

  // ==================== TOKEN ACTIONS ====================
  Future<void> disableToken(CryptoToken token) async {
    final tokenProvider = appProvider.tokenProvider;
    if (tokenProvider == null) return;
    await tokenProvider.toggleToken(token, false);
    notifyListeners();
  }

  // ==================== RESET ON WALLET SWITCH ====================
  void reset() {
    initService.reset();
    isHidden = false;
    selectedTab = 0;
    sortOption = 'balance';
    hideZeroBalances = false;
    showOnlyEnabled = false;
    selectedBlockchains.clear();
    notifyListeners();
  }

  // ==================== LIFE CYCLE ====================
  @override
  void dispose() {
    priceRefreshService.dispose();
    super.dispose();
  }
}
