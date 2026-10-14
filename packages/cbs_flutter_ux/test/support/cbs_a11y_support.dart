import 'dart:ui' show SemanticsAction;

import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] for Flutter accessibility guideline checks.
///
/// Unlike `pumpCbs`, the child is centered and inset from every edge of the
/// view, with no scrollable ancestor. This matters: Flutter's tap target
/// guideline silently skips nodes that touch the view edge or an implicitly
/// scrolling ancestor, and a skipped node makes `meetsGuideline` pass without
/// having evaluated anything.
///
/// The view uses a device pixel ratio of 1, a height of 1600 logical pixels
/// and the given [width] and [textScale].
Future<void> pumpA11y(
  WidgetTester tester, {
  required Widget child,
  ThemeData? theme,
  double width = 600,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1600);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? CbsTheme.essentials(),
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(CbsSpacing.lg),
          child: Align(alignment: Alignment.center, child: child),
        ),
      ),
    ),
  );
}

/// Asserts that the tap target guidelines had a real candidate in [finder].
///
/// A guideline that skips the node would pass vacuously. This proves the node
/// exposes a tap action, a label, and sits strictly inside the view, which are
/// the conditions under which Flutter evaluates it.
void expectTapTargetEvaluated(WidgetTester tester, Finder finder) {
  final node = tester.getSemantics(finder);
  final data = node.getSemanticsData();

  expect(
    data.hasAction(SemanticsAction.tap),
    isTrue,
    reason: 'a node without a tap action is skipped by the guidelines',
  );
  expect(data.label, isNotEmpty);

  final rect = tester.getRect(finder);
  final view = Offset.zero & tester.view.physicalSize;
  expect(rect.left, greaterThan(view.left));
  expect(rect.top, greaterThan(view.top));
  expect(rect.right, lessThan(view.right));
  expect(rect.bottom, lessThan(view.bottom));
}

/// Whether the primary focus is [finder]'s element or one of its descendants.
bool hasPrimaryFocusWithin(WidgetTester tester, Finder finder) {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  if (focusContext == null) {
    return false;
  }

  final target = tester.element(finder);
  if (identical(focusContext, target)) {
    return true;
  }

  var found = false;
  focusContext.visitAncestorElements((element) {
    if (identical(element, target)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}
