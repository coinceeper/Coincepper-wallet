import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../navigation/route_paths.dart';
import 'package:easy_localization/easy_localization.dart';
import '../layout/bottom_menu_with_siri.dart';
import '../theme/dex_theme_extension.dart';

class DexScreen extends StatefulWidget {
  const DexScreen({super.key});

  @override
  State<DexScreen> createState() => _DexScreenState();
}

class _DexScreenState extends State<DexScreen> {
  int selectedTab = 0;

  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  void _showCreatePoolScreen(BuildContext context) {
    context.push(RoutePaths.dexCreatePool);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_safeTranslate('coinceeper_dex', 'COINCEEPER DEX'), style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 28),
            onPressed: () => _showCreatePoolScreen(context),
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: _TabButton(
                      label: _safeTranslate('swap', 'Swap'),
                      selected: selectedTab == 0,
                      onTap: () => setState(() => selectedTab = 0),
                    ),
                  ),
                  Expanded(
                    child: _TabButton(
                      label: _safeTranslate('liquidity_pool', 'Liquidity Pool'),
                      selected: selectedTab == 1,
                      onTap: () => setState(() => selectedTab = 1),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: selectedTab,
                children: const [
                  _SwapTab(),
                  _LiquidityPoolTab(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomMenuWithSiri(),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
              width: 4,
            ),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              color: selected ? Theme.of(context).colorScheme.primary : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}

// --- Swap Tab (moved from previous code) ---
class _SwapTab extends StatefulWidget {
  const _SwapTab({super.key});

  @override
  State<_SwapTab> createState() => _SwapTabState();
}

class _SwapTabState extends State<_SwapTab> {
  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  final List<Map<String, dynamic>> tokens = [
    {
      'symbol': 'USDT',
      'name': 'Tether',
      'icon': 'assets/images/usdt.png',
      'balance': 1200.0,
    },
    {
      'symbol': 'ETH',
      'name': 'Ethereum',
      'icon': 'assets/images/ethereum_logo.png',
      'balance': 2.5,
    },
    {
      'symbol': 'BTC',
      'name': 'Bitcoin',
      'icon': 'assets/images/btc.png',
      'balance': 0.15,
    },
    {
      'symbol': 'BNB',
      'name': 'Binance Coin',
      'icon': 'assets/images/binance_logo.png',
      'balance': 10.0,
    },
  ];

  int fromIndex = 0;
  int toIndex = 1;
  String fromAmount = '';
  String toAmount = '';
  bool isSwapping = false;

  double get rate {
    if (fromIndex == toIndex) return 1.0;
    return 0.0003 * (fromIndex + 1) / (toIndex + 1);
  }

  double get fee => 0.001;

  void _switchTokens() {
    setState(() {
      final temp = fromIndex;
      fromIndex = toIndex;
      toIndex = temp;
      
      // تبدیل مقادیر به جای صفر کردن
      if (fromAmount.isNotEmpty && toAmount.isNotEmpty) {
        final tempAmount = fromAmount;
        fromAmount = toAmount;
        toAmount = tempAmount;
      }
    });
  }

  void _onFromAmountChanged(String value) {
    setState(() {
      fromAmount = value;
      final amt = double.tryParse(value) ?? 0.0;
      toAmount = amt > 0 ? (amt * rate).toStringAsFixed(6) : '';
    });
  }

  void _onToAmountChanged(String value) {
    setState(() {
      toAmount = value;
      final amt = double.tryParse(value) ?? 0.0;
      fromAmount = amt > 0 && rate > 0 ? (amt / rate).toStringAsFixed(6) : '';
    });
  }

  void _onMax() {
    setState(() {
      fromAmount = tokens[fromIndex]['balance'].toString();
      final amt = double.tryParse(fromAmount) ?? 0.0;
      toAmount = amt > 0 ? (amt * rate).toStringAsFixed(6) : '';
    });
  }

  void _onSwap() async {
    setState(() { isSwapping = true; });
    await Future.delayed(const Duration(seconds: 1));
    setState(() { isSwapping = false; });
    // Remove alert dialog - swap completed silently
  }

  void _showSlippageSettings() {
    // Remove modal bottom sheet - slippage settings removed
  }

  Future<int?> _showTokenSelector(BuildContext context, int currentIndex) async {
    // Remove modal bottom sheet - use direct selection or navigation
    return currentIndex; // Return current index to avoid changes
  }

  @override
  Widget build(BuildContext context) {
    final fromToken = tokens[fromIndex];
    final toToken = tokens[toIndex];
    return SafeArea(
      child: Column(
        children: [
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.07),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _TokenInput(
                          token: fromToken,
                          amount: fromAmount,
                          onAmountChanged: _onFromAmountChanged,
                          onSelect: () async {
                            final idx = await _showTokenSelector(context, fromIndex);
                            if (idx != null && idx != toIndex) setState(() => fromIndex = idx);
                          },
                          onMax: _onMax,
                          label: _safeTranslate('from', 'From'),
                          maxButtonStyle: true,
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.18),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: Icon(Icons.swap_vert, color: Theme.of(context).colorScheme.primary, size: 28),
                              onPressed: _switchTokens,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _TokenInput(
                          token: toToken,
                          amount: toAmount,
                          onAmountChanged: _onToAmountChanged,
                          onSelect: () async {
                            final idx = await _showTokenSelector(context, toIndex);
                            if (idx != null && idx != fromIndex) setState(() => toIndex = idx);
                          },
                          onMax: null,
                          label: _safeTranslate('to', 'To'),
                          maxButtonStyle: false,
                        ),
                      ],
                    ),
                  ),
                  // Swap Details
                  Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FC),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // Rate
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.sync_alt, color: Theme.of(context).colorScheme.primary, size: 20),
                                const SizedBox(width: 6),
                                Text(_safeTranslate('rate', 'Rate:'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Text('1 ${fromToken['symbol']} ≈ ${rate.toStringAsFixed(6)} ${toToken['symbol']}', 
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Price Impact
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.trending_up, color: Theme.of(context).colorScheme.primary, size: 20),
                                const SizedBox(width: 6),
                                Text(_safeTranslate('price_impact', 'Price Impact:'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const Text('0.12%', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Slippage Tolerance
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.settings, color: Theme.of(context).colorScheme.primary, size: 20),
                                const SizedBox(width: 6),
                                Text(_safeTranslate('slippage', 'Slippage:'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Row(
                              children: [
                                const Text('0.5%', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _showSlippageSettings(),
                                  child: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary, size: 18),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Minimum Received
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.security, color: Theme.of(context).colorScheme.primary, size: 20),
                                const SizedBox(width: 6),
                                Text(_safeTranslate('min_received', 'Min. Received:'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Text('${(double.tryParse(toAmount) ?? 0.0 * 0.995).toStringAsFixed(6)} ${toToken['symbol']}', 
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Fee
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.local_gas_station, color: Theme.of(context).colorScheme.primary, size: 20),
                                const SizedBox(width: 6),
                                Text(_safeTranslate('fee', 'Fee:'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Text('$fee ${fromToken['symbol']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
          // Swap button at the bottom
          Padding(
            padding: const EdgeInsets.only(left: 24, right: 24, bottom: 32, top: 8),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: (fromAmount.isNotEmpty && toAmount.isNotEmpty && !isSwapping)
                    ? _onSwap
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: (fromAmount.isNotEmpty && toAmount.isNotEmpty && !isSwapping)
                      ? Theme.of(context).colorScheme.primary
                      : const Color(0xFF858585),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                  elevation: 0,
                ),
                child: isSwapping
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        _safeTranslate('swap', 'Swap'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Liquidity Pool Tab ---
class _LiquidityPoolTab extends StatelessWidget {
  const _LiquidityPoolTab({super.key});

  // Safe translate method with fallback
  String _safeTranslate(BuildContext context, String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mock data for pools
    final pools = [
      {
        'pair': 'ETH/USDT',
        'icon1': 'assets/images/ethereum_logo.png',
        'icon2': 'assets/images/usdt.png',
        'tvl': '1,200,000',
        'apr': '8.2%',
        'userShare': '0.25%',
        'userLiquidity': '3,000 USDT',
      },
      {
        'pair': 'BTC/USDT',
        'icon1': 'assets/images/btc.png',
        'icon2': 'assets/images/usdt.png',
        'tvl': '900,000',
        'apr': '6.5%',
        'userShare': '0.10%',
        'userLiquidity': '1,200 USDT',
      },
      {
        'pair': 'BNB/ETH',
        'icon1': 'assets/images/binance_logo.png',
        'icon2': 'assets/images/ethereum_logo.png',
        'tvl': '500,000',
        'apr': '10.1%',
        'userShare': '0.00%',
        'userLiquidity': '0',
      },
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_safeTranslate(context, 'your_pools', 'Your Pools'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                ElevatedButton.icon(
                  onPressed: () {
                    // Remove modal bottom sheet - add liquidity removed
                  },
                  icon: const Icon(Icons.add, size: 26),
                  label: Text(_safeTranslate(context, 'add_liquidity', 'Add Liquidity'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    elevation: 6,
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView.separated(
                itemCount: pools.length,
                separatorBuilder: (_, __) => const SizedBox(height: 18),
                itemBuilder: (context, i) {
                  final pool = pools[i];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: SizedBox(
                            height: 38,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  left: 22,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.white, width: 2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Image.asset(pool['icon2']!, width: 30, height: 30),
                                  ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.white, width: 2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Image.asset(pool['icon1']!, width: 30, height: 30),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Main info (pair, share, liquidity)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(pool['pair']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.account_balance_wallet, size: 15, color: Theme.of(context).colorScheme.primary),
                                      const SizedBox(width: 3),
                                      Text(_safeTranslate(context, 'your_share', 'Your Share:'), style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500, fontSize: 13)),
                                      const SizedBox(width: 2),
                                      Flexible(child: Text(pool['userShare']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 13), overflow: TextOverflow.ellipsis)),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(Icons.monetization_on, size: 15, color: Theme.of(context).colorScheme.primary),
                                      const SizedBox(width: 3),
                                      Text(_safeTranslate(context, 'your_liquidity', 'Your Liquidity:'), style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500, fontSize: 13)),
                                      const SizedBox(width: 2),
                                      Flexible(child: Text(pool['userLiquidity']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 13), overflow: TextOverflow.ellipsis)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // TVL & APR
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.water_drop, size: 15, color: Theme.of(context).colorScheme.primary),
                                    const SizedBox(width: 2),
                                    Text(_safeTranslate(context, 'tvl', 'TVL:'), style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500, fontSize: 13)),
                                    const SizedBox(width: 2),
                                    Text(pool['tvl']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 13), overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(Icons.percent, size: 15, color: Theme.of(context).colorScheme.primary),
                                    const SizedBox(width: 2),
                                    Text(_safeTranslate(context, 'apr', 'APR:'), style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500, fontSize: 13)),
                                    const SizedBox(width: 2),
                                    Text(pool['apr']!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 13), overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Remove button
                                OutlinedButton.icon(
                                  onPressed: () => _showRemoveLiquidityDialog(context, pool),
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                  label: Text(_safeTranslate(context, 'remove', 'Remove'), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.red),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddLiquiditySheet extends StatefulWidget {
  const _AddLiquiditySheet({super.key});

  @override
  State<_AddLiquiditySheet> createState() => _AddLiquiditySheetState();
}

class _AddLiquiditySheetState extends State<_AddLiquiditySheet> {
  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  final List<Map<String, dynamic>> tokens = [
    {'symbol': 'USDT', 'name': 'Tether', 'icon': 'assets/images/usdt.png'},
    {'symbol': 'ETH', 'name': 'Ethereum', 'icon': 'assets/images/ethereum_logo.png'},
    {'symbol': 'BTC', 'name': 'Bitcoin', 'icon': 'assets/images/btc.png'},
    {'symbol': 'BNB', 'name': 'Binance Coin', 'icon': 'assets/images/binance_logo.png'},
  ];
  int token1 = 0;
  int token2 = 1;
  String amount1 = '';
  String amount2 = '';

  double get rate => 0.0003 * (token1 + 1) / (token2 + 1);
  double get fee => 0.001;
  double get share => 0.12; // mock share

  void _selectToken(int which) async {
    // Remove modal bottom sheet - token selection removed
  }

  void _showRemoveLiquidity() {
    // Remove dialog - remove liquidity removed
  }

  @override
  Widget build(BuildContext context) {
    final t1 = tokens[token1];
    final t2 = tokens[token2];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_safeTranslate('add_liquidity', 'Add Liquidity'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Token 1
              _LiquidityTokenInput(
                token: t1,
                amount: amount1,
                onAmountChanged: (v) => setState(() => amount1 = v),
                onSelect: () => _selectToken(0),
                label: _safeTranslate('token_1', 'Token 1'),
              ),
              const SizedBox(height: 14),
              // Token 2
              _LiquidityTokenInput(
                token: t2,
                amount: amount2,
                onAmountChanged: (v) => setState(() => amount2 = v),
                onSelect: () => _selectToken(1),
                label: _safeTranslate('token_2', 'Token 2'),
              ),
              const SizedBox(height: 18),
              // Pool Details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    // Rate
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.sync_alt, color: Theme.of(context).colorScheme.primary, size: 20),
                            const SizedBox(width: 6),
                            Text(_safeTranslate('rate', 'Rate:'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Text('1 ${t1['symbol']} ≈ ${rate.toStringAsFixed(6)} ${t2['symbol']}', 
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Pool Fee
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.local_gas_station, color: Theme.of(context).colorScheme.primary, size: 20),
                            const SizedBox(width: 6),
                            Text(_safeTranslate('pool_fee', 'Pool Fee:'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Text('0.3%', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Your Share
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.pie_chart, color: Theme.of(context).colorScheme.primary, size: 20),
                            const SizedBox(width: 6),
                            Text(_safeTranslate('your_share', 'Your Share:'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Text('${(share * 100).toStringAsFixed(2)}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Impermanent Loss Warning
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning, color: Colors.orange, size: 20),
                            const SizedBox(width: 6),
                            Text(_safeTranslate('impermanent_loss', 'Impermanent Loss:'), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Text(_safeTranslate('risk_low', 'Risk: Low'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Pool TVL
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.account_balance_wallet, color: Theme.of(context).colorScheme.primary, size: 20),
                            const SizedBox(width: 6),
                            Text(_safeTranslate('pool_tvl', 'Pool TVL:'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Text('\$2.5M', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Pool Analytics
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.analytics, color: Theme.of(context).colorScheme.primary, size: 20),
                        const SizedBox(width: 6),
                        Text(_safeTranslate('pool_analytics', 'Pool Analytics'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(_safeTranslate('volume_24h', '24h Volume'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              const SizedBox(height: 4),
                              const Text('\$1.2M', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(_safeTranslate('fees_24h', '24h Fees'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              const SizedBox(height: 4),
                              const Text('\$3.6K', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(_safeTranslate('apr', 'APR'), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              const SizedBox(height: 4),
                              const Text('12.5%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: (amount1.isNotEmpty && amount2.isNotEmpty) ? () => Navigator.pop(context) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                        child: Text(_safeTranslate('add_liquidity', 'Add Liquidity')),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => _showRemoveLiquidity(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.primary,
                          side: BorderSide(color: Theme.of(context).colorScheme.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                        ),
                        child: Text(_safeTranslate('remove', 'Remove')),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiquidityTokenInput extends StatelessWidget {
  final Map<String, dynamic> token;
  final String amount;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onSelect;
  final String label;
  const _LiquidityTokenInput({required this.token, required this.amount, required this.onAmountChanged, required this.onSelect, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onSelect,
            child: Row(
              children: [
                Image.asset(token['icon'], width: 28, height: 28),
                const SizedBox(width: 8),
                Text(token['symbol'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              onChanged: onAmountChanged,
              controller: TextEditingController(text: amount),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: label == 'Token 1' ? '0.0' : '',
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Token Input Widget (unchanged) ---
class _TokenInput extends StatelessWidget {
  final Map<String, dynamic> token;
  final String amount;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback? onSelect;
  final VoidCallback? onMax;
  final String label;
  final bool maxButtonStyle;

  const _TokenInput({
    required this.token,
    required this.amount,
    required this.onAmountChanged,
    required this.onSelect,
    required this.onMax,
    required this.label,
    required this.maxButtonStyle,
  });

  // Safe translate method with fallback
  String _safeTranslate(BuildContext context, String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onSelect,
            child: Row(
              children: [
                Image.asset(token['icon'], width: 32, height: 32),
                const SizedBox(width: 8),
                Text(token['symbol'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              onChanged: onAmountChanged,
              controller: TextEditingController(text: amount),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: label == 'From' ? '0.0' : '',
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (onMax != null && maxButtonStyle)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: GestureDetector(
                onTap: onMax,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.18),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(_safeTranslate(context, 'max', 'Max'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ),
        ],
      ),
    );
  }
} 

class DexCreatePoolScreen extends StatefulWidget {
  const DexCreatePoolScreen({super.key});

  @override
  State<DexCreatePoolScreen> createState() => _DexCreatePoolScreenState();
}

class _DexCreatePoolScreenState extends State<DexCreatePoolScreen> {
  // Safe translate method with fallback
  String _safeTranslate(String key, String fallback) {
    try {
      return context.tr(key);
    } catch (e) {
      return fallback;
    }
  }

  final List<Map<String, dynamic>> availableTokens = [
    {'symbol': 'USDT', 'name': 'Tether', 'icon': 'assets/images/usdt.png', 'address': '0x...'},
    {'symbol': 'ETH', 'name': 'Ethereum', 'icon': 'assets/images/ethereum_logo.png', 'address': '0x...'},
    {'symbol': 'BTC', 'name': 'Bitcoin', 'icon': 'assets/images/btc.png', 'address': '0x...'},
    {'symbol': 'BNB', 'name': 'Binance Coin', 'icon': 'assets/images/binance_logo.png', 'address': '0x...'},
  ];

  int token1Index = 0;
  int token2Index = 1;
  String token1Amount = '';
  String token2Amount = '';
  double poolFee = 0.3;
  String customTokenAddress = '';
  bool isCustomToken = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_safeTranslate('create_pool', 'Create Pool'), style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Create New Pool Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_safeTranslate('create_new_pool', 'Create New Pool'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                    const SizedBox(height: 8),
                    Text(_safeTranslate('create_pool_description', 'Add a new token pair to create a liquidity pool'), style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 20),
                  
                  // Token Selection
                  Row(
                    children: [
                      Expanded(
                        child: _TokenSelector(
                          label: _safeTranslate('token_1', 'Token 1'),
                          token: availableTokens[token1Index],
                          onTap: () => _selectToken(0),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TokenSelector(
                          label: _safeTranslate('token_2', 'Token 2'),
                          token: availableTokens[token2Index],
                          onTap: () => _selectToken(1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Custom Token Option
                  Row(
                    children: [
                      Checkbox(
                        value: isCustomToken,
                        onChanged: (value) => setState(() => isCustomToken = value ?? false),
                        activeColor: Theme.of(context).colorScheme.primary,
                      ),
                      Text(_safeTranslate('add_custom_token', 'Add Custom Token'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (isCustomToken) ...[
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (value) => customTokenAddress = value,
                      decoration: InputDecoration(
                        labelText: _safeTranslate('token_contract_address', 'Token Contract Address'),
                        hintText: '0x...',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  
                  // Pool Fee Selection
                  Text(_safeTranslate('pool_fee', 'Pool Fee'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _FeeOption(
                          fee: 0.01,
                          label: '0.01%',
                          selected: poolFee == 0.01,
                          onTap: () => setState(() => poolFee = 0.01),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FeeOption(
                          fee: 0.05,
                          label: '0.05%',
                          selected: poolFee == 0.05,
                          onTap: () => setState(() => poolFee = 0.05),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FeeOption(
                          fee: 0.3,
                          label: '0.3%',
                          selected: poolFee == 0.3,
                          onTap: () => setState(() => poolFee = 0.3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FeeOption(
                          fee: 1.0,
                          label: '1%',
                          selected: poolFee == 1.0,
                          onTap: () => setState(() => poolFee = 1.0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Initial Liquidity
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.07),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_safeTranslate('initial_liquidity', 'Initial Liquidity'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 16),
                  
                  // Token 1 Amount
                  _LiquidityInput(
                    token: availableTokens[token1Index],
                    amount: token1Amount,
                    onAmountChanged: (value) => setState(() => token1Amount = value),
                    label: _safeTranslate('token_1_amount', 'Token 1 Amount'),
                  ),
                  const SizedBox(height: 12),
                  
                  // Token 2 Amount
                  _LiquidityInput(
                    token: availableTokens[token2Index],
                    amount: token2Amount,
                    onAmountChanged: (value) => setState(() => token2Amount = value),
                    label: _safeTranslate('token_2_amount', 'Token 2 Amount'),
                  ),
                  const SizedBox(height: 16),
                  
                  // Pool Info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_safeTranslate('pool_fee', 'Pool Fee:'), style: const TextStyle(color: Colors.grey)),
                            Text('$poolFee%', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_safeTranslate('initial_price', 'Initial Price:'), style: const TextStyle(color: Colors.grey)),
                            Text('1 ${availableTokens[token1Index]['symbol']} = 1 ${availableTokens[token2Index]['symbol']}', 
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Create Pool Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _canCreatePool() ? _createPool : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                child: Text(_safeTranslate('create_pool', 'Create Pool')),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  void _selectToken(int which) async {
    // Remove modal bottom sheet - token selection removed
  }

  bool _canCreatePool() {
    return token1Index != token2Index && 
           token1Amount.isNotEmpty && 
           token2Amount.isNotEmpty &&
           double.tryParse(token1Amount) != null &&
           double.tryParse(token2Amount) != null;
  }

  void _createPool() {
    // Remove dialog - create pool confirmation removed
    _showSuccessDialog();
  }

  void _showSuccessDialog() {
    // Remove dialog - success dialog removed
  }
}

class _TokenSelector extends StatelessWidget {
  final String label;
  final Map<String, dynamic> token;
  final VoidCallback onTap;

  const _TokenSelector({required this.label, required this.token, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE0E0E0)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Image.asset(token['icon'], width: 24, height: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(token['symbol'], style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _FeeOption extends StatelessWidget {
  final double fee;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FeeOption({required this.fee, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
          border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : const Color(0xFFE0E0E0)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidityInput extends StatelessWidget {
  final Map<String, dynamic> token;
  final String amount;
  final ValueChanged<String> onAmountChanged;
  final String label;

  const _LiquidityInput({required this.token, required this.amount, required this.onAmountChanged, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(
            children: [
              Image.asset(token['icon'], width: 24, height: 24),
              const SizedBox(width: 8),
              Text(token['symbol'], style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Expanded(
                child: TextField(
                  onChanged: onAmountChanged,
                  controller: TextEditingController(text: amount),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '0.0',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
} 

void _showRemoveLiquidityDialog(BuildContext context, Map<String, dynamic> pool) {
  // Remove dialog - remove liquidity dialog removed
} 