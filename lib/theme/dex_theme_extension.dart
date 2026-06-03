import 'package:flutter/material.dart';

/// Optional accent tuning for DEX-heavy screens (uses same seed as app).
@immutable
class DexThemeExtension extends ThemeExtension<DexThemeExtension> {
  const DexThemeExtension({
    required this.accent,
    required this.accentMuted,
  });

  final Color accent;
  final Color accentMuted;

  static DexThemeExtension from(ColorScheme scheme) {
    return DexThemeExtension(
      accent: scheme.primary,
      accentMuted: scheme.primaryContainer,
    );
  }

  @override
  DexThemeExtension copyWith({Color? accent, Color? accentMuted}) {
    return DexThemeExtension(
      accent: accent ?? this.accent,
      accentMuted: accentMuted ?? this.accentMuted,
    );
  }

  @override
  DexThemeExtension lerp(DexThemeExtension? other, double t) {
    if (other is! DexThemeExtension) return this;
    return DexThemeExtension(
      accent: Color.lerp(accent, other.accent, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
    );
  }
}

extension DexThemeContext on BuildContext {
  DexThemeExtension get dexTheme =>
      Theme.of(this).extension<DexThemeExtension>() ??
      DexThemeExtension.from(Theme.of(this).colorScheme);
}
