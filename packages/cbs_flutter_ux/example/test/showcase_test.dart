import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cbs_flutter_ux_example/catalog/catalog_keys.dart';
import 'package:cbs_flutter_ux_example/catalog/catalog_scenario.dart';
import 'package:cbs_flutter_ux_example/main.dart';

import 'catalog_test_helpers.dart';

void main() {
  // D03b-C.2 adaptation: the theme switch is now the `Design` selection
  // control, and the page scrollable is identified by a stable key because
  // the simulated viewport adds a nested horizontal scrollable.
  // Every functional assertion of the CURRENT test is preserved.
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
        scrollable: pageScrollable(),
      );
      expect(find.text(message), findsOneWidget);
    }

    await tester.scrollUntilVisible(
      find.byKey(CatalogKeys.designOption(CatalogDesign.branded)),
      -150,
      scrollable: pageScrollable(),
    );

    final essentialsTheme = appTheme(tester);

    expect(
      essentialsTheme.colorScheme.primary,
      CbsTheme.essentials().colorScheme.primary,
    );

    await tester.tap(
      find.byKey(CatalogKeys.designOption(CatalogDesign.branded)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Branded / Teal'), findsOneWidget);

    final brandedTheme = appTheme(tester);

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
        scrollable: pageScrollable(),
      );
      expect(find.text(message), findsOneWidget);
    }

    await tester.scrollUntilVisible(
      find.byKey(CatalogKeys.designOption(CatalogDesign.branded)),
      -150,
      scrollable: pageScrollable(),
    );
  });
}
