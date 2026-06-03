import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Use app seed primary ([ColorScheme.primary]) instead of hard-coded teal.
Color appPrimary(BuildContext context) =>
    Theme.of(context).colorScheme.primary;

/// Darker teal from the same [appPrimary] (second KPI cards, alternate accents).
Color appPrimaryDark(BuildContext context) {
  return Theme.of(context).extension<AppColors>()?.primaryDark ??
      Color.lerp(appPrimary(context), Colors.black, 0.22) ??
      appPrimary(context);
}

/// Lighter teal from the same [appPrimary] (tertiary chips / icons).
Color appPrimaryLight(BuildContext context) {
  return Theme.of(context).extension<AppColors>()?.primaryLight ??
      Color.lerp(appPrimary(context), Colors.white, 0.26) ??
      appPrimary(context);
}

Color appMuted(BuildContext context) =>
    Theme.of(context).extension<AppColors>()?.muted ??
    Theme.of(context).colorScheme.onSurfaceVariant;

Color appSuccess(BuildContext context) =>
    Theme.of(context).extension<AppColors>()!.success;

Color appDanger(BuildContext context) =>
    Theme.of(context).extension<AppColors>()!.danger;
