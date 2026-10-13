import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
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

/// Widgets matching [matching] inside the labelled demonstration [demoId].
///
/// Demonstrations are targeted by `Key` instead of global widget counts, so
/// that sections can gain instances without breaking unrelated assertions.
Finder inDemo(String demoId, Finder matching) {
  return find.descendant(
    of: find.byKey(CatalogKeys.demo(demoId)),
    matching: matching,
  );
}

/// Widgets matching [matching] inside the catalog section [sectionId].
Finder inSection(String sectionId, Finder matching) {
  return find.descendant(
    of: find.byKey(CatalogKeys.section(sectionId)),
    matching: matching,
  );
}

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

/// Makes [finder] visible, taps it and lets the resulting rebuild happen.
///
/// Uses a single bounded `pump`, never `pumpAndSettle`: the indeterminate
/// loading indicators animate forever.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
}

/// Text displayed by the counter of the demonstration [id].
String counterText(WidgetTester tester, String id) {
  return tester.widget<Text>(find.byKey(CatalogKeys.counter(id))).data!;
}

/// Retry button of the `CbsRetryMessage` of the retry demonstration [id].
Finder retryButton(String id) {
  return find.descendant(
    of: find.byKey(CatalogKeys.retryMessage(id)),
    matching: find.byType(CbsButton),
  );
}
