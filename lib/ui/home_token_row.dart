import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/crypto_token.dart';
import '../providers/price_provider.dart';
import '../theme/app_radius.dart';
import '../utils/shared_preferences_utils.dart';
import '../widgets/token_icon.dart';

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
              color: const Color(0xFFFF1961).withValues(alpha: 0.8),
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

    final symbol = (token.symbol ?? '').toUpperCase();

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
            child: TokenIcon(
              token: token,
              size: 40,
              cacheManager: tokenLogoCacheManager,
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
                  Text('(${token.symbol ?? ''})', style: TextStyle(fontSize: 12, color: scheme.onSurface)),
                ],
              ),
              const SizedBox(height: 1),
              Consumer<PriceProvider>(
                builder: (context, priceProvider, child) {
                  final currencySymbol = priceProvider.getCurrencySymbol();
                  final formattedPrice = NumberFormat.currency(symbol: currencySymbol, decimalDigits: 2).format(price);
                  return Text(formattedPrice, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant));
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
                  return Text(isHidden ? '****' : formattedValue, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
