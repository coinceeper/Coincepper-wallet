import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_flutter_app/theme/app_theme.dart';
import 'package:my_flutter_app/ui/app_card.dart';

void main() {
  testWidgets('AppCard golden light', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: AppCard(
                child: Text('Sample card'),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(AppCard),
      matchesGoldenFile('goldens/app_card_light.png'),
    );
  });

  testWidgets('AppCard golden dark', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: AppCard(
                child: Text('Sample card'),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(AppCard),
      matchesGoldenFile('goldens/app_card_dark.png'),
    );
  });
}
