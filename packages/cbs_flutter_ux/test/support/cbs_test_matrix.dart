import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Logical widths: compact (320), medium boundary (600), expanded
/// boundary (840) and a wider window (1280).
const List<double> cbsTestWidths = [320, 600, 840, 1280];

/// Standard and enlarged text scale factors.
const List<double> cbsTestTextScales = [1, 2];

/// Themes covered by the qualification matrix: Essentials and Branded,
/// each in light and dark appearance.
final List<({String name, ThemeData theme})> cbsTestThemes = [
  (name: 'Essentials light', theme: CbsTheme.essentials()),
  (
    name: 'Essentials dark',
    theme: CbsTheme.essentials(brightness: Brightness.dark),
  ),
  (name: 'Branded light', theme: CbsTheme.branded(primaryColor: Colors.green)),
  (
    name: 'Branded dark',
    theme: CbsTheme.branded(
      primaryColor: Colors.green,
      brightness: Brightness.dark,
    ),
  ),
];

/// Pumps [child] in a [MaterialApp] with the given viewport [width] and
/// [textScale].
///
/// The child is placed at the top start of a vertically scrollable body:
/// its width constraint is loose and bounded by [width], its height is
/// unbounded.
Future<void> pumpCbs(
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
        body: SingleChildScrollView(
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    ),
  );
}
