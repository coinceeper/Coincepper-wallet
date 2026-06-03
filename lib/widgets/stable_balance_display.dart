import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/crypto_token.dart';
import '../providers/price_provider.dart';
import '../providers/app_provider.dart';
import '../utils/shared_preferences_utils.dart';
import '../services/balance_display_manager.dart';
import '../services/balance_manager.dart';

/// Widget پایدار برای نمایش موجودی توکن‌ها در همه دستگاه‌ها
/// این widget از BalanceManager برای دریافت موجودی‌های پایدار استفاده می‌کند
class StableBalanceDisplay extends StatefulWidget {
  final CryptoToken token;
  final String userId;
  final bool isHidden;
  final VoidCallback? onTap;
  final double? customWidth;
  final bool showIcon;
  final bool showValue;
  final TextStyle? amountStyle;
  final TextStyle? valueStyle;

  const StableBalanceDisplay({
    super.key,
    required this.token,
    required this.userId,
    this.isHidden = false,
    this.onTap,
    this.customWidth,
    this.showIcon = true,
    this.showValue = true,
    this.amountStyle,
    this.valueStyle,
  });

  @override
  State<StableBalanceDisplay> createState() => _StableBalanceDisplayState();
}

class _StableBalanceDisplayState extends State<StableBalanceDisplay>
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true;
  
  @override
  void initState() {
    super.initState();
    // Listen to BalanceManager updates for automatic UI refresh
    BalanceManager.instance.addListener(_onBalanceUpdate);
  }
  
  @override
  void dispose() {
    BalanceManager.instance.removeListener(_onBalanceUpdate);
    super.dispose();
  }
  
  void _onBalanceUpdate() {
    if (mounted) {
      setState(() {
        // This will trigger a rebuild with updated balance data
      });
    }
  }

  /// دریافت موجودی پایدار از BalanceManager با fallback به token amount
  double get _stableBalance {
    // ⚡ FIXED: Use blockchain-specific balance for multi-chain tokens
    final tokenSymbol = widget.token.symbol ?? '';
    final tokenBlockchain = widget.token.blockchainName ?? '';
    
    double balanceFromManager = 0.0;
    
    // Try blockchain-specific balance first
    if (tokenBlockchain.isNotEmpty) {
      final blockchainKey = '${tokenSymbol}_$tokenBlockchain';
      balanceFromManager = BalanceManager.instance.getTokenBalance(widget.userId, blockchainKey);
      
      // ⚡ COMPATIBILITY FIX: Try alternative blockchain name mappings
      if (balanceFromManager == 0.0) {
        final alternativeKeys = _getAlternativeBlockchainKeys(tokenSymbol, tokenBlockchain);
        for (final altKey in alternativeKeys) {
          final altBalance = BalanceManager.instance.getTokenBalance(widget.userId, altKey);
          if (altBalance > 0.0) {
            balanceFromManager = altBalance;
            break;
          }
        }
      }
    }
    
    // ⚡ SMART FALLBACK: Use legacy fallback intelligently
    if (balanceFromManager == 0.0) {
      // Try legacy key
      final legacyBalance = BalanceManager.instance.getTokenBalance(widget.userId, tokenSymbol);
      
      if (legacyBalance > 0.0) {
        // Check if this might be a multi-chain conflict
        final userBalances = BalanceManager.instance.getUserBalances(widget.userId);
        final hasMultipleBlockchains = userBalances.keys.any((key) => 
          key.startsWith('${tokenSymbol}_') && key != '${tokenSymbol}_$tokenBlockchain'
        );
        
        if (hasMultipleBlockchains && tokenBlockchain.isNotEmpty) {
          // This is a multi-chain token without specific blockchain balance
          balanceFromManager = 0.0;
        } else {
          // Safe to use legacy balance
          balanceFromManager = legacyBalance;
        }
      }
    }
    
    // Also get the token's own amount for comparison
    final tokenAmount = widget.token.amount ?? 0.0;
    
    // Priority logic for balance selection:
    // 1. If both are available, prefer the higher value (to prevent showing 0 during transitions)
    // 2. If only one is available, use that
    // 3. If neither is available, return 0
    
    if (balanceFromManager > 0.0 && tokenAmount > 0.0) {
      // Both available - prefer the higher value to avoid showing 0 during sync issues
      return balanceFromManager > tokenAmount ? balanceFromManager : tokenAmount;
    } else if (balanceFromManager > 0.0) {
      // Only BalanceManager has data
      return balanceFromManager;
    } else if (tokenAmount > 0.0) {
      // Only token has data
      return tokenAmount;
    }
    
    // Neither has valid data
    return 0.0;
  }

  /// فرمت‌بندی موجودی با در نظر گیری اندازه صفحه
  String get _formattedAmount {
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Create a copy of the token with the stable balance
    final tokenWithStableBalance = widget.token.copyWith(amount: _stableBalance);
    
    return BalanceDisplayManager.instance.getFormattedBalance(
      tokenWithStableBalance,
      widget.isHidden,
      screenWidth: screenWidth,
    );
  }



  /// فرمت‌بندی ارزش دلاری
  String _getFormattedValue(PriceProvider priceProvider) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Create a copy of the token with the stable balance
    final tokenWithStableBalance = widget.token.copyWith(amount: _stableBalance);
    
    return BalanceDisplayManager.instance.getFormattedValue(
      tokenWithStableBalance,
      priceProvider,
      widget.isHidden,
      screenWidth: screenWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Consumer<PriceProvider>(
      builder: (context, priceProvider, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = widget.customWidth ?? constraints.maxWidth;
            final isNarrow = availableWidth < 300;
            
            return SizedBox(
              width: availableWidth,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12, 
                    vertical: 8
                  ),
                  child: _buildContent(isNarrow),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// ساخت محتوای widget بر اساس اندازه
  Widget _buildContent(bool isNarrow) {
    if (isNarrow) {
      return _buildNarrowLayout();
    } else {
      return _buildWideLayout();
    }
  }

  /// Layout برای صفحات کوچک
  Widget _buildNarrowLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showIcon) _buildTokenInfo(),
        const SizedBox(height: 4),
        _buildAmountRow(),
        if (widget.showValue) ...[
          const SizedBox(height: 2),
          _buildValueRow(),
        ],
      ],
    );
  }

  /// Layout برای صفحات بزرگ
  Widget _buildWideLayout() {
    return Row(
      children: [
        if (widget.showIcon) ...[
          _buildTokenIcon(),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTokenName(),
              if (widget.showValue) _buildValueRow(),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildAmountRow(),
          ],
        ),
      ],
    );
  }

  /// نمایش اطلاعات توکن
  Widget _buildTokenInfo() {
    return Row(
      children: [
        _buildTokenIcon(),
        const SizedBox(width: 8),
        Expanded(child: _buildTokenName()),
      ],
    );
  }

  /// آیکون توکن
  Widget _buildTokenIcon() {
    final symbol = (widget.token.symbol ?? '').toUpperCase();
    final assetIcons = {
      'BTC': 'assets/images/btc.png',
      'ETH': 'assets/images/ethereum_logo.png',
      'BNB': 'assets/images/binance_logo.png',
      'TRX': 'assets/images/tron.png',
      'USDT': 'assets/images/usdt.png',
      'USDC': 'assets/images/usdc.png',
      'MATIC': 'assets/images/pol.png',
      'SOL': 'assets/images/sol.png',
      'ADA': 'assets/images/cardano.png',
      'DOT': 'assets/images/dot.png',
      'AVAX': 'assets/images/avax.png',
      'XRP': 'assets/images/xrp.png',
    };

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: assetIcons[symbol] != null
            ? Image.asset(
                assetIcons[symbol]!,
                width: 32,
                height: 32,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => 
                    _buildFallbackIcon(),
              )
            : _buildFallbackIcon(),
      ),
    );
  }

  /// آیکون fallback
  Widget _buildFallbackIcon() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.currency_bitcoin,
        size: 20,
        color: Colors.grey[600],
      ),
    );
  }

  /// نام توکن
  Widget _buildTokenName() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.token.name ?? 'Unknown',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '(${widget.token.symbol ?? 'UNK'})',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  /// نمایش موجودی
  Widget _buildAmountRow() {
    return Text(
      _formattedAmount,
      style: widget.amountStyle ??
          const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// نمایش ارزش
  Widget _buildValueRow() {
    if (!widget.showValue) return const SizedBox.shrink();
    
    return Consumer<PriceProvider>(
      builder: (context, priceProvider, child) {
        return Text(
          _getFormattedValue(priceProvider),
          style: widget.valueStyle ??
              TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  /// دریافت کلیدهای جایگزین برای blockchain های مختلف
  List<String> _getAlternativeBlockchainKeys(String symbol, String blockchain) {
    final alternatives = <String>[];
    
    // Mapping for common blockchain name variations
    final blockchainMappings = {
      'Ethereum': ['ETH', 'ethereum'],
      'ETH': ['Ethereum', 'ethereum'],
      'Bitcoin': ['BTC', 'bitcoin'],
      'BTC': ['Bitcoin', 'bitcoin'],
      'Tron': ['TRX', 'tron'],
      'TRX': ['Tron', 'tron'],
      'Arbitrum': ['ARB', 'arbitrum'],
      'ARB': ['Arbitrum', 'arbitrum'],
      'Polygon': ['MATIC', 'polygon'],
      'MATIC': ['Polygon', 'polygon'],
      'Binance Smart Chain': ['BSC', 'BNB', 'binance'],
      'BSC': ['Binance Smart Chain', 'BNB', 'binance'],
    };
    
    final possibleNames = blockchainMappings[blockchain] ?? [];
    for (final name in possibleNames) {
      alternatives.add('${symbol}_$name');
    }
    
    return alternatives;
  }
}

/// Widget برای نمایش ارزش کل پورتفولیو
class StableTotalValueDisplay extends StatelessWidget {
  final List<CryptoToken> tokens;
  final bool isHidden;
  final TextStyle? style;

  const StableTotalValueDisplay({
    super.key,
    required this.tokens,
    this.isHidden = false,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PriceProvider>(
      builder: (context, priceProvider, child) {
        final totalValue = BalanceDisplayManager.instance.calculateTotalPortfolioValue(tokens, priceProvider);
        final formattedValue = BalanceDisplayManager.instance.formatTotalPortfolioValue(totalValue, isHidden: isHidden);
        
        return Text(
          formattedValue,
          style: style ??
              const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
        );
      },
    );
  }
}
