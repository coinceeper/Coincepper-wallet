import 'package:flutter/material.dart';
import '../models/crypto_token.dart';
import 'filter_widgets.dart';
import 'app_search_bar.dart';
import 'blockchain_filter_chips.dart';

// =============================================================================
// 🔁 REUSABLE TOKEN LIST VIEW – search, blockchain filter, Majors/Others
// =============================================================================

/// A self-contained, reusable token list widget with:
///
/// * Search bar
/// * [BlockchainFilterChips] for filtering by network
/// * Two-section layout: **Majors** (well-known coins) then **Others** (sorted
///   by market cap), or a flat list when a search/network filter is active
/// * Lazy / chunked loading to keep the UI responsive
///
/// Place it inside a [RefreshIndicator] or any scrollable parent. The widget
/// manages its own scroll controller and pagination state internally.
class CryptoTokenListView extends StatefulWidget {
  /// The full (or pre‑filtered) token list. The widget further filters by
  /// search query and selected blockchain, then splits into Majors / Others.
  final List<CryptoToken> allTokens;

  /// Market‑cap map (symbol → double). Used only for the "Others" sort.
  final Map<String, double>? marketCaps;

  /// Builds each token row. Called once per visible token.
  final Widget Function(BuildContext context, CryptoToken token) itemBuilder;

  /// Accent colour used by the blockchain chips when selected.
  final Color selectedColor;

  /// Label shown for the "All" chip (e.g. "All Blockchains").
  final String allNetworksLabel;

  /// Optional search field hint.
  final String? searchHint;

  /// Optional extra filter callback – return `false` to exclude a token.
  /// This runs *before* the built‑in search/blockchain filters, so it is
  /// useful for screen‑specific constraints (e.g. "show only enabled").
  final bool Function(CryptoToken)? extraFilter;

  /// Bump this number to force the widget to re‑apply filters without
  /// changing [allTokens] (e.g. when [extraFilter] semantics change in the
  /// parent without creating a new closure).
  final int filterVersion;

  /// Sort mode. Pass `'marketcap'` (default) to show the Majors + Others
  /// two‑section layout. Any other value shows a flat list without sections.
  /// The parent is responsible for sorting [allTokens] appropriately when
  /// using a non‑default sort mode.
  final String sortOption;

  /// Override padding for the list slivers. Default matches the original
  /// AddTokenScreen layout.
  final EdgeInsetsGeometry? contentPadding;

  /// Optional widgets shown after the search field (e.g. sort / filter icon
  /// buttons). Appended to the right of the search row.
  final List<Widget>? searchActions;

  /// Optional widgets shown between the blockchain chips and the token list
  /// (e.g. advanced‑filter chips from AddTokenScreen).
  final List<Widget>? headerChildren;

  /// Dynamic blockchain list from backend API.
  /// If null, falls back to the built‑in static list.
  final List<String>? blockchains;

  const CryptoTokenListView({
    super.key,
    required this.allTokens,
    this.marketCaps,
    required this.itemBuilder,
    this.selectedColor = const Color(0xFF0BAB9B),
    this.allNetworksLabel = 'All',
    this.searchHint,
    this.extraFilter,
    this.filterVersion = 0,
    this.sortOption = 'marketcap',
    this.contentPadding,
    this.searchActions,
    this.headerChildren,
    this.blockchains,
  });

  @override
  State<CryptoTokenListView> createState() => _CryptoTokenListViewState();
}

class _CryptoTokenListViewState extends State<CryptoTokenListView> {
  // ─── Known major coin symbols ───────────────────────────────────────────
  static const List<String> _majorSymbols = [
    'BTC', 'ETH', 'BNB', 'SOL', 'XRP', 'ADA', 'DOGE', 'AVAX', 'DOT', 'LINK',
  ];

  // ─── Local state ────────────────────────────────────────────────────────
  final _searchController = TextEditingController();
  String _query = '';
  String _selectedNetwork = '';
  List<CryptoToken> _filteredTokens = [];
  List<CryptoToken> _majorTokens = [];
  List<CryptoToken> _otherTokens = [];

  bool get _showSections =>
      _query.isEmpty && _selectedNetwork.isEmpty && widget.sortOption == 'marketcap';

  // ⚡ Lazy loading
  static const int _pageSize = 50;
  static const double _scrollThreshold = 300.0;
  int _displayedOtherCount = _pageSize;
  bool _isLoadingMore = false;
  late ScrollController _scrollController;

  // ─── Derived getters ────────────────────────────────────────────────────

  List<CryptoToken> get _displayedOtherTokens {
    if (_showSections) {
      final count = _displayedOtherCount.clamp(0, _otherTokens.length);
      return _otherTokens.sublist(0, count);
    }
    final count = _displayedOtherCount.clamp(0, _filteredTokens.length);
    return _filteredTokens.sublist(0, count);
  }

  bool get _hasMoreTokens {
    if (_showSections) {
      return _displayedOtherCount < _otherTokens.length;
    }
    return _displayedOtherCount < _filteredTokens.length;
  }

  /// لیست ثابت بلاکچین‌های شناخته‌شده — از این لیست برای فیلتر استفاده می‌شود
  /// هر توکنی که blockchainName اش در این لیست نباشد، در All نمایش داده می‌شود
  static const Set<String> _knownBlockchains = {
    'Bitcoin',
    'Ethereum',
    'Tron',
    'Solana',
    'Ripple',
    'Binance Smart Chain',
    'Polygon',
    'Avalanche',
    'Arbitrum',
    'Polkadot',
    'Litecoin',
    'Cardano',
    'Cosmos',
    'Near',
  };

  /// برگرداندن بلاکچین‌های شناخته‌شده به صورت مرتب
  /// اولویت با blockchains داینامیک (از Backend API) است، در غیر این صورت Fallback به لیست استاتیک
  /// نام‌ها با normalizeBlockchainName برای نمایش مناسب فرمت می‌شوند
  List<String> get _blockchains {
    final chains = widget.blockchains ?? [];
    final source = (chains.isNotEmpty ? chains : _knownBlockchains.toList())
        .map(normalizeBlockchainName)
        .toList();
    final list = ['All', ...source]..sort((a, b) {
      if (a == 'All') return -1;
      if (b == 'All') return 1;
      return a.compareTo(b);
    });
    return list;
  }

  /// تبدیل نام بلاکچین از API (lowercase) به فرمت مناسب نمایش
  /// مثال: "bsc" → "BSC", "bitcoin" → "Bitcoin"
  static String normalizeBlockchainName(String name) {
    if (name.isEmpty) return name;
    final lower = name.toLowerCase();
    // اختصارات معروف را به uppercase نگه می‌داریم
    const acronyms = {'bsc', 'xrp', 'btc', 'eth', 'bnb', 'trx', 'nft'};
    if (acronyms.contains(lower)) return lower.toUpperCase();
    // Capitalize each word
    return lower.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _applyFilters(shouldSetState: false);
  }

  @override
  void didUpdateWidget(CryptoTokenListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-filter when the parent passes a new token list, filter callback,
    // or bumps the version counter.
    if (oldWidget.allTokens != widget.allTokens ||
        oldWidget.extraFilter != widget.extraFilter ||
        oldWidget.filterVersion != widget.filterVersion) {
      _applyFilters();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Filtering ─────────────────────────────────────────────────────────

  void _applyFilters({bool shouldSetState = true}) {
    // 1. Extra filter (screen‑specific) + search + blockchain
    var tokens = widget.allTokens.where((t) {
      if (widget.extraFilter != null && !widget.extraFilter!(t)) return false;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        final name = (t.name ?? '').toLowerCase();
        final sym = (t.symbol ?? '').toLowerCase();
        if (!name.contains(q) && !sym.contains(q)) return false;
      }
      if (_selectedNetwork.isNotEmpty &&
          t.blockchainName != _selectedNetwork) {
        return false;
      }
      return true;
    }).toList();

    // 2. Split into Majors / Others (only for marketcap sort)
    if (widget.sortOption == 'marketcap') {
      _majorTokens = [];
      _otherTokens = [];
      final added = <String>{};
      for (final t in tokens) {
        final sym = (t.symbol ?? '').toUpperCase();
        if (_majorSymbols.contains(sym)) {
          // Only the first occurrence of each symbol goes to Majors;
          // subsequent occurrences (e.g. wrapped DOT on BSC/Ethereum)
          // are treated as Other tokens so nothing gets lost.
          if (added.add(sym)) {
            _majorTokens.add(t);
          } else {
            _otherTokens.add(t);
          }
        } else {
          _otherTokens.add(t);
        }
      }
      // Sort majors by fixed order
      _majorTokens.sort((a, b) {
        final iA = _majorSymbols.indexOf((a.symbol ?? '').toUpperCase());
        final iB = _majorSymbols.indexOf((b.symbol ?? '').toUpperCase());
        return iA.compareTo(iB);
      });
      // Sort others by market cap DESC
      final caps = widget.marketCaps ?? const {};
      _otherTokens.sort((a, b) {
        final capA = caps[(a.symbol ?? '').toUpperCase()] ?? -1;
        final capB = caps[(b.symbol ?? '').toUpperCase()] ?? -1;
        if (capA != capB) return capB.compareTo(capA);
        return (a.name ?? '')
            .toLowerCase()
            .compareTo((b.name ?? '').toLowerCase());
      });
      _filteredTokens = [..._majorTokens, ..._otherTokens];
    } else {
      // Flat list: parent already sorted by name / price / volume
      _majorTokens = [];
      _otherTokens = [];
      _filteredTokens = tokens;
    }
    _resetPagination();

    if (shouldSetState && mounted) {
      setState(() {});
    }
  }

  void _onSearchChanged(String value) {
    _query = value.trim();
    _applyFilters();
  }

  // ⚡ Lazy loading ──────────────────────────────────────────────────────

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoadingMore || !_hasMoreTokens) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll <= _scrollThreshold) {
      _loadNextChunk();
    }
  }

  Future<void> _loadNextChunk() async {
    if (_isLoadingMore || !_hasMoreTokens) return;
    setState(() => _isLoadingMore = true);
    await Future.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;
    final max = _showSections ? _otherTokens.length : _filteredTokens.length;
    setState(() {
      _displayedOtherCount = (_displayedOtherCount + _pageSize).clamp(0, max);
      _isLoadingMore = false;
    });
  }

  void _resetPagination() {
    _displayedOtherCount = _pageSize;
    _isLoadingMore = false;
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasData = _filteredTokens.isNotEmpty ||
        _majorTokens.isNotEmpty ||
        _otherTokens.isNotEmpty;

    return Column(
      children: [
        // ── Header: search + blockchain chips ──
        Padding(
          padding: widget.contentPadding ??
              const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchField(),
              const SizedBox(height: 12),
              BlockchainFilterChips(
                selectedBlockchain:
                    _selectedNetwork.isEmpty ? 'All' : _selectedNetwork,
                blockchains: _blockchains,
                blockchainIcons: BlockchainFilterChips.defaultIcons,
                onChanged: (chain) {
                  setState(() {
                    _selectedNetwork = chain == 'All' ? '' : chain;
                  });
                  _applyFilters();
                },
                selectedColor: widget.selectedColor,
                allLabel: widget.allNetworksLabel,
              ),
              if (widget.headerChildren != null) ...widget.headerChildren!,
              const SizedBox(height: 12),
            ],
          ),
        ),
        // ── Token list ──
        Expanded(
          child: hasData
              ? CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    if (_showSections && _majorTokens.isNotEmpty) ...[
                      // Section 1 – Majors
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
                          child: Text(
                            'Majors',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _buildItem(context, _majorTokens[index]),
                          childCount: _majorTokens.length,
                        ),
                      ),
                      // Section 2 – Others
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 2),
                          child: Text(
                            'Others',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _buildItem(context, _displayedOtherTokens[index]),
                          childCount: _displayedOtherTokens.length,
                        ),
                      ),
                    ] else ...[
                      // Flat list
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _buildItem(context, _displayedOtherTokens[index]),
                          childCount: _displayedOtherTokens.length,
                        ),
                      ),
                    ],
                    // Loading more indicator
                    if (_isLoadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          ),
                        ),
                      ),
                    // Bottom padding
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 100),
                        child: _hasMoreTokens
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    '↓ Scroll for more',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: (widget.allTokens.isEmpty && widget.filterVersion == 0)
                      ? const CircularProgressIndicator(color: Color(0xFF11c699))
                      : Text(
                          'No tokens found',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
                        ),
                ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return AppSearchBar(
      controller: _searchController,
      hintText: widget.searchHint ?? 'Search',
      onChanged: _onSearchChanged,
      actions: widget.searchActions,
    );
  }

  Widget _buildItem(BuildContext context, CryptoToken token) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: widget.itemBuilder(context, token),
    );
  }
}
