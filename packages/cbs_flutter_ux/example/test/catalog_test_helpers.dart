import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cbs_flutter_ux_example/catalog/catalog_keys.dart';

/// Vertical scrollable of the whole catalog page.
///
/// The simulated viewport adds a nested horizontal scrollable, so
/// `find.byType(Scrollable)` alone is ambiguous; the page scrollable is
/// the first one in tree order.
Finder pageScrollable() => find
    .descendant(
      of: find.byKey(CatalogKeys.pageScroll),
      matching: find.byType(Scrollable),
    )
    .first;

/// Makes [finder] visible in the page, taps it and lets the theme and
/// chip animations complete.
///
/// `pumpAndSettle` is avoided on purpose: the indeterminate loading
/// indicator animates forever.
Future<void> selectOption(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Lets the `AnimatedTheme` of `MaterialApp` reach its final value.
///
/// The theme animation starts at the first frame following a change, so
/// `selectOption` alone leaves `Theme.of(context)` at its previous value
/// (`MaterialApp.theme` is already final, which is why it must not be used
/// to assert the effective theme).
Future<void> settleThemeAnimation(WidgetTester tester) {
  return tester.pump(const Duration(milliseconds: 300));
}

/// `MediaQuery` seen by the simulated preview content.
MediaQueryData previewMediaQuery(WidgetTester tester) {
  return MediaQuery.of(tester.element(find.byKey(CatalogKeys.previewContent)));
}

/// `MediaQuery` seen by the page, outside the simulated viewport.
MediaQueryData pageMediaQuery(WidgetTester tester) {
  return MediaQuery.of(tester.element(find.byKey(CatalogKeys.scenarioSummary)));
}

/// Theme of the running application.
ThemeData appTheme(WidgetTester tester) {
  return tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
}

/// Theme effectively received by the first widget matching [finder], read
/// with `Theme.of(context)` from that widget's own `BuildContext`.
ThemeData effectiveTheme(WidgetTester tester, Finder finder) {
  return Theme.of(tester.element(finder.first));
}

/// Sets the logical size of the test surface (device pixel ratio 1) and
/// restores it when the test ends.
void setSurfaceSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Whether the [ChoiceChip] identified by [key] is selected.
bool isSelected(WidgetTester tester, Key key) {
  return tester.widget<ChoiceChip>(find.byKey(key)).selected;
}
