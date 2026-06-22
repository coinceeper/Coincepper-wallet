import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../models/crypto_token.dart';

class TokenIcon extends StatelessWidget {
  final CryptoToken token;
  final double size;
  final CacheManager? cacheManager;

  const TokenIcon({
    super.key,
    required this.token,
    this.size = 40,
    this.cacheManager,
  });

  @override
  Widget build(BuildContext context) {
    final symbol = (token.symbol ?? '').toUpperCase();
    final assetIcon = _getAssetIcon(symbol);

    // ✅ قانون ساده: توکن‌ها (isToken=true) باید badge بلاکچین داشته باشند
    // ✅ کوین‌ها (isToken=false) هرگز badge ندارند
    final showBadge = token.isToken;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Main Token Logo
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: _buildMainIcon(context, assetIcon),
            ),
          ),
          // Blockchain Badge
          if (showBadge)
            Positioned(
              right: 0,
              bottom: 0,
              child: _buildBadge(context),
            ),
        ],
      ),
    );
  }

  /// ساختن badge بلاکچین — اگر آیکون اختصاصی باشد، نمایش تصویر
  /// در غیر این صورت حرف اول نام بلاکچین روی دایره سفید
  Widget _buildBadge(BuildContext context) {
    final blockchainIcon = _getBlockchainIcon(token.blockchainName);
    final badgeSize = size / 2.5;

    if (blockchainIcon != null) {
      return Container(
        width: badgeSize,
        height: badgeSize,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            blockchainIcon,
            fit: BoxFit.contain,
          ),
        ),
      );
    }

    // Fallback متنی: حرف اول اسم بلاکچین
    final initial = (token.blockchainName ?? '?').substring(0, 1).toUpperCase();
    return Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: badgeSize * 0.5,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildMainIcon(BuildContext context, String? assetIcon) {
    if ((token.symbol ?? '').toUpperCase() == 'NCC' && (token.iconUrl ?? '').startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: token.iconUrl!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        cacheManager: cacheManager,
        errorWidget: (context, url, error) => assetIcon != null
            ? Image.asset(assetIcon, width: size, height: size, fit: BoxFit.contain)
            : _buildFallback(context),
      );
    }

    if (assetIcon != null) {
      return Image.asset(
        assetIcon,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          if ((token.iconUrl ?? '').startsWith('http')) {
            return CachedNetworkImage(
              imageUrl: token.iconUrl!,
              width: size,
              height: size,
              fit: BoxFit.contain,
              cacheManager: cacheManager,
              errorWidget: (context, url, error) => _buildFallback(context),
            );
          }
          return _buildFallback(context);
        },
      );
    }

    if ((token.iconUrl ?? '').startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: token.iconUrl!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        cacheManager: cacheManager,
        errorWidget: (context, url, error) => _buildFallback(context),
      );
    }

    if ((token.iconUrl ?? '').startsWith('assets/')) {
      return Image.asset(
        token.iconUrl!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildFallback(context),
      );
    }

    return _buildFallback(context);
  }

  Widget _buildFallback(BuildContext context) {
    return Center(
      child: Text(
        (token.symbol ?? '?').substring(0, 1).toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// آیکون‌های اختصاصی موجود در assets (فقط فایل‌های واقعی)
  String? _getAssetIcon(String symbol) {
    const assetIcons = {
      'BTC': 'assets/images/btc.png',
      'ETH': 'assets/images/ethereum_logo.png',
      'BNB': 'assets/images/binance_logo.png',
      'TRX': 'assets/images/tron.png',
      'USDT': 'assets/images/usdt.png',
      'USDC': 'assets/images/usdc.png',
      'SOL': 'assets/images/sol.png',
      'AVAX': 'assets/images/avax.png',
      'MATIC': 'assets/images/pol.png',
      'XRP': 'assets/images/xrp.png',
      'DOT': 'assets/images/dot.png',
      'DOGE': 'assets/images/dogecoin.png',
      'LTC': 'assets/images/litecoin_logo.png',
      'SHIB': 'assets/images/shiba.png',
      'NCC': 'assets/images/ncc.png',
      'NCCOLD': 'assets/images/hold.png',
      'ARB': 'assets/images/arb.png',
    };
    return assetIcons[symbol];
  }

  /// نگاشت نام بلاکچین به آیکون اختصاصی assets (فقط فایل‌های واقعی)
  String? _getBlockchainIcon(String? blockchainName) {
    if (blockchainName == null) return null;
    final name = blockchainName.toLowerCase();
    if (name.contains('bitcoin')) return 'assets/images/btc.png';
    if (name.contains('ethereum')) return 'assets/images/ethereum_logo.png';
    if (name.contains('bsc') || name.contains('binance')) return 'assets/images/binance_logo.png';
    if (name.contains('tron')) return 'assets/images/tron.png';
    if (name.contains('solana')) return 'assets/images/sol.png';
    if (name.contains('avalanche')) return 'assets/images/avax.png';
    if (name.contains('polygon')) return 'assets/images/pol.png';
    if (name.contains('ripple') || name.contains('xrp')) return 'assets/images/xrp.png';
    if (name.contains('polkadot')) return 'assets/images/dot.png';
    if (name.contains('arbitrum')) return 'assets/images/arb.png';
    if (name.contains('litecoin')) return 'assets/images/litecoin_logo.png';
    return null; // fallback متنی در _buildBadge
  }
}
