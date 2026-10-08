import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildApp({required ThemeData theme, double? value}) {
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(child: CbsLoadingIndicator(value: value)),
      ),
    );
  }

  testWidgets('renders a circular progress indicator', (tester) async {
    await tester.pumpWidget(buildApp(theme: CbsTheme.essentials()));

    expect(find.byType(CbsLoadingIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('supports indeterminate progress', (tester) async {
    await tester.pumpWidget(buildApp(theme: CbsTheme.essentials()));

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );

    expect(indicator.value, isNull);
  });

  testWidgets('supports determinate progress', (tester) async {
    await tester.pumpWidget(buildApp(theme: CbsTheme.essentials(), value: 0.5));

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );

    expect(indicator.value, 0.5);
  });

  testWidgets('renders with Essentials theme', (tester) async {
    await tester.pumpWidget(buildApp(theme: CbsTheme.essentials()));

    expect(find.byType(CbsLoadingIndicator), findsOneWidget);
  });

  testWidgets('renders with Branded theme', (tester) async {
    await tester.pumpWidget(
      buildApp(theme: CbsTheme.branded(primaryColor: Colors.green)),
    );

    expect(find.byType(CbsLoadingIndicator), findsOneWidget);
  });
}
