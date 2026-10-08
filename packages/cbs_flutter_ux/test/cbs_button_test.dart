import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('inherits branded button radius', (tester) async {
    final theme = CbsTheme.branded(
      primaryColor: Colors.green,
      buttonRadius: CbsRadius.lg,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: CbsButton(label: 'Continue', onPressed: () {}),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));

    final shape =
        button.style?.shape?.resolve(<WidgetState>{}) ??
        theme.filledButtonTheme.style?.shape?.resolve(<WidgetState>{});

    expect(shape, isA<RoundedRectangleBorder>());

    final border = shape! as RoundedRectangleBorder;

    expect(border.borderRadius, BorderRadius.circular(CbsRadius.lg));
  });

  Widget buildApp({
    required ThemeData theme,
    required VoidCallback? onPressed,
  }) {
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: CbsButton(label: 'Continue', onPressed: onPressed),
        ),
      ),
    );
  }

  testWidgets('renders its label', (tester) async {
    await tester.pumpWidget(
      buildApp(theme: CbsTheme.essentials(), onPressed: () {}),
    );

    expect(find.text('Continue'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
  });

  testWidgets('invokes its callback when tapped', (tester) async {
    var count = 0;

    await tester.pumpWidget(
      buildApp(theme: CbsTheme.essentials(), onPressed: () => count++),
    );

    await tester.tap(find.byType(CbsButton));

    expect(count, 1);
  });

  testWidgets('supports disabled state', (tester) async {
    await tester.pumpWidget(
      buildApp(theme: CbsTheme.essentials(), onPressed: null),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));

    expect(button.onPressed, isNull);
  });

  testWidgets('renders with Essentials theme', (tester) async {
    await tester.pumpWidget(
      buildApp(theme: CbsTheme.essentials(), onPressed: () {}),
    );

    expect(find.byType(CbsButton), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('renders with Branded theme', (tester) async {
    await tester.pumpWidget(
      buildApp(
        theme: CbsTheme.branded(primaryColor: Colors.green),
        onPressed: () {},
      ),
    );

    expect(find.byType(CbsButton), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
