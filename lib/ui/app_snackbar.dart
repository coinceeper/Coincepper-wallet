import 'package:flutter/material.dart';

class AppSnackbar {
  static void show(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class AppBottomSheet {
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: Material(
          borderRadius: Theme.of(ctx).bottomSheetTheme.shape is RoundedRectangleBorder
              ? (Theme.of(ctx).bottomSheetTheme.shape! as RoundedRectangleBorder)
                  .borderRadius
              : null,
          clipBehavior: Clip.antiAlias,
          color: Theme.of(ctx).colorScheme.surface,
          child: child,
        ),
      ),
    );
  }
}
