import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

// ────────────────────────────────────────────────────────────────
// Standalone helper functions (used by various screens)
// ────────────────────────────────────────────────────────────────

Color appPrimary(BuildContext context) =>
    Theme.of(context).colorScheme.primary;

Color appPrimaryDark(BuildContext context) {
  final appColors = Theme.of(context).extension<AppColors>();
  if (appColors != null) return appColors.primaryDark;
  final p = Theme.of(context).colorScheme.primary;
  return Color.lerp(p, Colors.black, 0.22) ?? p;
}

Color appPrimaryLight(BuildContext context) {
  final appColors = Theme.of(context).extension<AppColors>();
  if (appColors != null) return appColors.primaryLight;
  final p = Theme.of(context).colorScheme.primary;
  return Color.lerp(p, Colors.white, 0.26) ?? p;
}

Color appMuted(BuildContext context) {
  final appColors = Theme.of(context).extension<AppColors>();
  if (appColors != null) return appColors.muted;
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

Color appSuccess(BuildContext context) {
  final appColors = Theme.of(context).extension<AppColors>();
  if (appColors != null) return appColors.success;
  return const Color(0xFF2E7D32);
}

Color appDanger(BuildContext context) {
  final appColors = Theme.of(context).extension<AppColors>();
  if (appColors != null) return appColors.danger;
  return const Color(0xFFC62828);
}

// ────────────────────────────────────────────────────────────────
// Extension on BuildContext for convenient theme color access.
// Always use these over hardcoded [Colors.black]/[Colors.white] to
// properly support light, dark, and mixed themes.
// ────────────────────────────────────────────────────────────────

extension ThemeHelpers on BuildContext {
  /// Shortcut to [Theme.of(this)].
  ThemeData get themeData => Theme.of(this);

  /// Shortcut to [Theme.of(this).colorScheme].
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// Primary text/icon color for the current surface (auto-adapts).
  Color get onSurface => colorScheme.onSurface;

  /// Muted text/icon color (secondary info, hints).
  Color get onSurfaceVariant => colorScheme.onSurfaceVariant;

  /// Surface background color (cards, containers).
  Color get surface => colorScheme.surface;

  /// Slightly elevated surface color (containers on cards).
  Color get surfaceContainerLow => colorScheme.surfaceContainerLow;

  /// Primary brand color.
  Color get primary => colorScheme.primary;

  /// Primary container color.
  Color get primaryContainer => colorScheme.primaryContainer;

  /// Error color.
  Color get error => colorScheme.error;

  /// Outline/border color.
  Color get outline => colorScheme.outline;

  /// Muted outline color.
  Color get outlineVariant => colorScheme.outlineVariant;

  /// Divider color.
  Color get divider => colorScheme.outlineVariant;

  /// Returns the correct text color for content placed inside a card.
  /// In mixed mode, cards are dark so text should be white.
  /// In light/dark mode, uses the standard [onSurface].
  Color get onCardSurface {
    final cardColor = Theme.of(this).cardTheme.color;
    if (cardColor != null) {
      final brightness = ThemeData.estimateBrightnessForColor(cardColor);
      return brightness == Brightness.dark ? Colors.white : colorScheme.onSurface;
    }
    return colorScheme.onSurface;
  }

  /// Returns the correct text color for content placed directly on scaffold.
  /// In mixed mode, scaffold is light so text should be dark.
  Color get onScaffoldSurface {
    final scaffoldBg = Theme.of(this).scaffoldBackgroundColor;
    final brightness = ThemeData.estimateBrightnessForColor(scaffoldBg);
    return brightness == Brightness.dark ? Colors.white : colorScheme.onSurface;
  }
}
