import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';


class TokenAvatar extends StatelessWidget {
  const TokenAvatar({
    super.key,
    this.imageUrl,
    this.assetPath,
    this.symbol,
    this.size = 40,
    this.heroTag,
  });

  final String? imageUrl;
  final String? assetPath;
  final String? symbol;
  final double size;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildImage(context, scheme),
    );
    if (heroTag != null) {
      avatar = Hero(tag: heroTag!, child: avatar);
    }
    return avatar;
  }

  Widget _buildImage(BuildContext context, ColorScheme scheme) {
    if (assetPath != null && assetPath!.isNotEmpty) {
      return Image.asset(
        assetPath!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(scheme),
      );
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => _shimmer(scheme),
        errorWidget: (_, __, ___) => _fallback(scheme),
      );
    }
    return _fallback(scheme);
  }

  Widget _shimmer(ColorScheme scheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(size / 2),
      ),
    );
  }

  Widget _fallback(ColorScheme scheme) {
    final letter = (symbol?.isNotEmpty == true)
        ? symbol!.substring(0, 1).toUpperCase()
        : '?';
    return Center(
      child: Text(
        letter,
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}
