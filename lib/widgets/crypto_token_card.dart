import 'package:flutter/material.dart';
import '../models/crypto_token.dart';
import 'token_icon.dart';

// =============================================================================
// CryptoTokenCard — زیباترین کارت نمایش یک کریپتو
//
// طراحی: کارت سفید با گوشه‌های گرد 16، حاشیه نازک و سایه ملایم،
// آیکون دایره‌ای 42px، نام + سمبل در یک ردیف، نام بلاکچین در زیر،
// و یک ویجت دلخواه در سمت راست (سوئیچ، دکمه، قیمت، و غیره).
// =============================================================================

class CryptoTokenCard extends StatelessWidget {
  /// توکن یا کریپتو برای نمایش
  final CryptoToken token;

  /// کلیک روی کارت (برای ناوبری)
  final VoidCallback? onTap;

  /// ویجت انتهای کارت (سوئیچ، دکمه‌ها، قیمت، شورون، …)
  final Widget? trailing;

  /// اگر true باشد کارت کمی نیمه‌شفاف می‌شود (برای توکن‌های غیرفعال)
  final bool dimmed;

  const CryptoTokenCard({
    super.key,
    required this.token,
    this.onTap,
    this.trailing,
    this.dimmed = false,
  });

  // ─── استانداردسازی نام ────────────────────────────────────────────────

  static String standardizeTokenName(String? name) {
    if (name == null || name.isEmpty) return '';
    const int maxLength = 20;

    if (name.length <= maxLength) return name;

    const unnecessaryWords = [
      'Token', 'Coin', 'Protocol', 'Network', 'Chain', 'Finance',
      'DeFi', 'Ecosystem', 'Platform', 'Project', 'Foundation',
      'Labs', 'DAO', 'Governance', 'Utility', 'Smart', 'Digital',
      'Crypto', 'Blockchain', 'Decentralized',
    ];

    String s = name;
    for (final word in unnecessaryWords) {
      s = s.replaceAll(RegExp(' $word\$', caseSensitive: false), '');
      s = s.replaceAll(RegExp('^$word ', caseSensitive: false), '');
    }

    if (s.length <= maxLength) return s;

    if (s.contains(' ')) {
      final words = s.split(' ');
      String result = '';
      for (final w in words) {
        if (('$result $w').length <= maxLength) {
          result = result.isEmpty ? w : '$result $w';
        } else {
          break;
        }
      }
      if (result.isNotEmpty && result.length <= maxLength - 3) {
        return '$result...';
      }
    }

    return '${s.substring(0, maxLength - 3)}...';
  }

  static String standardizeTokenSymbol(String? symbol) {
    if (symbol == null || symbol.isEmpty) return '';
    const int maxLength = 8;
    if (symbol.length <= maxLength) return symbol;
    return symbol.substring(0, maxLength);
  }

  // ─── ساختن آیکون ────────────────────────────────────────────────────

  static Widget _buildTokenIcon(CryptoToken token) {
    return TokenIcon(token: token, size: 42);
  }

  // ─── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final name = standardizeTokenName(token.name);
    final symbol = standardizeTokenSymbol(token.symbol);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final card = Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? scheme.surfaceContainerHigh : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
              ? scheme.outlineVariant.withValues(alpha: 0.2) 
              : Colors.grey.withValues(alpha: 0.15)
        ),
        boxShadow: isDark ? [] : [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Opacity(
        opacity: dimmed ? 0.45 : 1.0,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── آیکون ──
            _buildTokenIcon(token),
            const SizedBox(width: 12),

            // ── نام + سمبل + بلاکچین ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Tooltip(
                          message: token.name ?? '',
                          child: Text(
                            name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: scheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        symbol,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    token.blockchainName ?? '',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),

            // ── ویجت انتها ──
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );

    if (onTap != null) {
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: card,
      );
    }

    return card;
  }
}

// =============================================================================
// CustomSwitch — سوئیچ اختصاصی برای فعال/غیرفعال کردن توکن
// =============================================================================

class CustomSwitch extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool> onCheckedChange;

  const CustomSwitch({
    super.key,
    required this.checked,
    required this.onCheckedChange,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onCheckedChange(!checked),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 50,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: checked 
              ? const Color(0xFF27B6AC) 
              : scheme.onSurfaceVariant.withValues(alpha: 0.2),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: checked ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.all(2),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
