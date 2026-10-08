import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cbs_flutter_ux_example/main.dart';

void main() {
  testWidgets('Showcase displays Essentials and Branded themes', (
    tester,
  ) async {
    await tester.pumpWidget(const CbsUxShowcase());

    expect(find.text('Design System Showcase'), findsOneWidget);
    expect(find.text('Essentials / Indigo'), findsOneWidget);

    expect(find.byType(CbsButton), findsNWidgets(2));
    expect(find.byType(CbsLoadingIndicator), findsNWidgets(2));
    for (final message in [
      'Information message',
      'Success message',
      'Warning message',
      'Error message',
    ]) {
      await tester.scrollUntilVisible(
        find.text(message),
        150,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text(message), findsOneWidget);
    }

    await tester.scrollUntilVisible(
      find.byType(SwitchListTile),
      -150,
      scrollable: find.byType(Scrollable),
    );

    final essentialsTheme = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .theme!;

    expect(
      essentialsTheme.colorScheme.primary,
      CbsTheme.essentials().colorScheme.primary,
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Branded / Teal'), findsOneWidget);

    final brandedTheme = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .theme!;

    expect(
      brandedTheme.colorScheme.primary,
      CbsTheme.branded(
        primaryColor: Colors.teal,
        buttonRadius: CbsRadius.lg,
      ).colorScheme.primary,
    );

    expect(
      brandedTheme.colorScheme.primary,
      isNot(essentialsTheme.colorScheme.primary),
    );

    expect(find.byType(CbsButton), findsNWidgets(2));
    expect(find.byType(CbsLoadingIndicator), findsNWidgets(2));
    for (final message in [
      'Information message',
      'Success message',
      'Warning message',
      'Error message',
    ]) {
      await tester.scrollUntilVisible(
        find.text(message),
        150,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text(message), findsOneWidget);
    }

    await tester.scrollUntilVisible(
      find.byType(SwitchListTile),
      -150,
      scrollable: find.byType(Scrollable),
    );
  });
}
