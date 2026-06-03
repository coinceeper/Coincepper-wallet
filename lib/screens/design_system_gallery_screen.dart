import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_theme_notifier.dart';
import '../ui/app_buttons.dart';
import '../ui/app_card.dart';
import '../ui/amount_display.dart';
import '../ui/app_text_field.dart';
import '../ui/token_avatar.dart';

/// Debug-only design system preview.
class DesignSystemGalleryScreen extends StatelessWidget {
  const DesignSystemGalleryScreen({super.key});

  static bool get enabled => kDebugMode;

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<AppThemeNotifier>();
    return Scaffold(
      appBar: AppBar(title: const Text('Design system')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {themeNotifier.mode},
            onSelectionChanged: (s) => themeNotifier.setMode(s.first),
          ),
          const SizedBox(height: 24),
          const AmountDisplay(amount: '12,345.67', currencySymbol: '\$'),
          const SizedBox(height: 16),
          const TokenAvatar(symbol: 'BTC', assetPath: 'assets/images/btc.png'),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppTextField(label: 'Sample', hint: 'Hint'),
                const SizedBox(height: 12),
                AppPrimaryButton(
                  label: 'Primary',
                  onPressed: () {},
                ),
                const SizedBox(height: 8),
                AppOutlinedButton(
                  label: 'Outlined',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
