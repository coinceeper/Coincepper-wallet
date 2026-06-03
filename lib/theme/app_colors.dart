import 'package:flutter/material.dart';

/// Brand and semantic colors (seed-aligned with [AppTheme]).
abstract final class AppBrandColors {
  static const Color seed = Color(0xFF0BAB9B);
  static const Color seedLegacyAccent = Color(0xFF11C699);
}

/// Semantic colors exposed via [AppColors] [ThemeExtension].
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.chartUp,
    required this.chartDown,
    required this.muted,
    required this.primaryDark,
    required this.primaryLight,
  });

  final Color success;
  final Color warning;
  final Color danger;
  final Color chartUp;
  final Color chartDown;
  final Color muted;
  final Color primaryDark;
  final Color primaryLight;

  static AppColors light(ColorScheme scheme) {
    final p = scheme.primary;
    return AppColors(
      success: const Color(0xFF2E7D32),
      warning: const Color(0xFFF9A825),
      danger: const Color(0xFFC62828),
      chartUp: p,
      chartDown: const Color(0xFFE53935),
      muted: scheme.onSurfaceVariant,
      primaryDark: Color.lerp(p, Colors.black, 0.22) ?? p,
      primaryLight: Color.lerp(p, Colors.white, 0.26) ?? p,
    );
  }

  static AppColors dark(ColorScheme scheme) {
    final p = scheme.primary;
    return AppColors(
      success: const Color(0xFF66BB6A),
      warning: const Color(0xFFFFCA28),
      danger: const Color(0xFFEF5350),
      chartUp: p,
      chartDown: const Color(0xFFEF5350),
      muted: scheme.onSurfaceVariant,
      primaryDark: Color.lerp(p, Colors.black, 0.15) ?? p,
      primaryLight: Color.lerp(p, Colors.white, 0.2) ?? p,
    );
  }

  @override
  AppColors copyWith({
    Color? success,
    Color? warning,
    Color? danger,
    Color? chartUp,
    Color? chartDown,
    Color? muted,
    Color? primaryDark,
    Color? primaryLight,
  }) {
    return AppColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      chartUp: chartUp ?? this.chartUp,
      chartDown: chartDown ?? this.chartDown,
      muted: muted ?? this.muted,
      primaryDark: primaryDark ?? this.primaryDark,
      primaryLight: primaryLight ?? this.primaryLight,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      chartUp: Color.lerp(chartUp, other.chartUp, t)!,
      chartDown: Color.lerp(chartDown, other.chartDown, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
