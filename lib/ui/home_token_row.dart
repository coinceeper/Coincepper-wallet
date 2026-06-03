import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/crypto_token.dart';
import '../providers/price_provider.dart';
import '../theme/app_radius.dart';
import '../utils/shared_preferences_utils.dart';
import 'token_avatar.dart';

/// Widget قابل swipe برای disable کردن توکن - مشابه TokenRow در Android
class SwipeableTokenRow extends StatefulWidget {
  final CryptoToken token;
  final bool isHidden;
  final CacheManager? tokenLogoCacheManager;
  final double price;
  final double displayAmount;
  final VoidCallback onSwipeToDisable;
  final VoidCallback onTap;
  final Object? heroTag;

  const SwipeableTokenRow({
    super.key,
    required this.token,
    required this.isHidden,
    this.tokenLogoCacheManager,
    required this.price,
    required this.displayAmount,
    required this.onSwipeToDisable,
    required this.onTap,
    this.heroTag,
  });

  @override
  State<SwipeableTokenRow> createState() => SwipeableTokenRowState();
}

class SwipeableTokenRowState extends State<SwipeableTokenRow>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0.0;
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;

  static const double _maxSwipe = -80.0;
  static const double _disableThreshold = -48.0; // 60% of maxSwipe - مشابه Android

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<double>(
      begin: 0.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(_maxSwipe * 1.2, 0.0);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_dragOffset <= _disableThreshold) {
      // اگر از threshold گذشت، توکن را disable کن
      widget.onSwipeToDisable();
      _resetPosition();
    } else {
      // در غیر این صورت، برگردان به موقعیت اولیه
      _resetPosition();
    }
  }

  void _resetPosition() {
    _slideAnimation = Tween<double>(
      begin: _dragOffset,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _animationController.forward().then((_) {
      setState(() {
        _dragOffset = 0.0;
      });
      _animationController.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dragOffset == 0 ? widget.onTap : _resetPosition,
      child: Stack(
        children: [
          // Background قرمز با متن "Disable" - مشابه Android
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFF1961).withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  width: 80,
                  height: 68,
                  alignment: Alignment.center,
                  child: const Text(
                    'Disable',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // محتوای اصلی توکن - مشابه Android
          AnimatedBuilder(
            animation: _slideAnimation,
            builder: (context, child) {
              final currentOffset = _animationController.isAnimating
                  ? _slideAnimation.value
                  : _dragOffset;

              return Transform.translate(
                offset: Offset(currentOffset, 0),
                child: GestureDetector(
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: HomeTokenRow(
                    token: widget.token,
                    isHidden: widget.isHidden,
                    tokenLogoCacheManager: widget.tokenLogoCacheManager,
                    price: widget.price,
                    displayAmount: widget.displayAmount,
                    heroTag: widget.heroTag,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class HomeTokenRow extends StatelessWidget {
  final CryptoToken token;
  final bool isHidden;
  final CacheManager? tokenLogoCacheManager;
  final double price;
  final double displayAmount;
  final Object? heroTag;

  const HomeTokenRow({super.key, 
    required this.token,
    required this.isHidden,
    this.tokenLogoCacheManager,
    required this.price,
    required this.displayAmount,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    // استفاده از موجودی نمایشی که از parent دریافت شده
    final tokenValue = displayAmount * price;

    // Format amount using the same logic as Android
    final formattedAmount = isHidden ? '****' : SharedPreferencesUtils.formatAmount(displayAmount, price);

    // لوگوهای معروف را از asset نمایش بده
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
      'NCC': 'assets/images/ncc.png', // اضافه کردن NCC
    };
    final symbol = (token.symbol ?? '').toUpperCase();
    final assetIcon = assetIcons[symbol];

    // Debug log for NCC specifically
    if (symbol == 'NCC') {
      print('🔍 HomeScreen NCC Debug:');
      print('  - Symbol: $symbol');
      print('  - AssetIcon path: $assetIcon');
      print('  - Token iconUrl: ${token.iconUrl}');
      print('  - Token name: ${token.name}');
      print('  - Will use network: ${(symbol == 'NCC' && (token.iconUrl ?? '').startsWith('http'))}');
      print('  - iconUrl starts with http: ${(token.iconUrl ?? '').startsWith('http')}');
    }

    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.smAll,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      child: Row(
        children: [
          Hero(
            tag: heroTag ?? 'token_$symbol',
            child: ClipOval(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: symbol == 'NCC' ? Colors.grey[100] : Colors.white, // Different background for NCC
                shape: BoxShape.circle,
              ),
              child: (symbol == 'NCC' && (token.iconUrl ?? '').startsWith('http'))
                  ? CachedNetworkImage(
                imageUrl: token.iconUrl ?? '',
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                cacheManager: tokenLogoCacheManager,
                errorWidget: (context, url, error) {
                  // Fallback to asset if network fails for NCC
                  return assetIcon != null
                      ? Image.asset(
                    assetIcon,
                    width: 40,
                    height: 40,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
                  )
                      : const Icon(Icons.error);
                },
              )
                  : assetIcon != null
                  ? Image.asset(
                assetIcon,
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  print('❌ Asset error for $symbol: $error');
                  // Fallback to network image if asset fails
                  if ((token.iconUrl ?? '').startsWith('http')) {
                    return CachedNetworkImage(
                      imageUrl: token.iconUrl ?? '',
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                      cacheManager: tokenLogoCacheManager,
                      errorWidget: (context, url, error) => const Icon(Icons.error),
                    );
                  }
                  return const Icon(Icons.error);
                },
              )
                  : (token.iconUrl ?? '').startsWith('http')
                  ? CachedNetworkImage(
                imageUrl: token.iconUrl ?? '',
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                cacheManager: tokenLogoCacheManager,
                errorWidget: (context, url, error) => const Icon(Icons.error),
              )
                  : (token.iconUrl ?? '').startsWith('assets/')
                  ? Image.asset(
                token.iconUrl ?? '',
                width: 40,
                height: 40,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
              )
                  : const Icon(Icons.error),
            ),
          ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(token.name ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(width: 4),
                  Text('(${token.symbol ?? ''})', style: const TextStyle(fontSize: 12, color: Color(0xff2b2b2b))),
                ],
              ),
              const SizedBox(height: 1),
              Consumer<PriceProvider>(
                builder: (context, priceProvider, child) {
                  final currencySymbol = priceProvider.getCurrencySymbol();
                  final formattedPrice = NumberFormat.currency(symbol: currencySymbol, decimalDigits: 2).format(price);
                  return Text(formattedPrice, style: const TextStyle(fontSize: 14, color: Color(0xFF666666)));
                },
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formattedAmount, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Consumer<PriceProvider>(
                builder: (context, priceProvider, child) {
                  final currencySymbol = priceProvider.getCurrencySymbol();
                  final formattedValue = SharedPreferencesUtils.formatTokenValue(tokenValue, currencySymbol);
                  return Text(isHidden ? '****' : formattedValue, style: const TextStyle(fontSize: 12, color: Color(0xFF666666)));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
