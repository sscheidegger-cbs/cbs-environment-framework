import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildApp({
    required ThemeData theme,
    CbsFeedbackType type = CbsFeedbackType.info,
  }) {
    return MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: CbsFeedbackMessage(message: 'Test feedback', type: type),
        ),
      ),
    );
  }

  testWidgets('renders feedback message', (tester) async {
    await tester.pumpWidget(buildApp(theme: CbsTheme.essentials()));

    expect(find.byType(CbsFeedbackMessage), findsOneWidget);
    expect(find.text('Test feedback'), findsOneWidget);
  });

  testWidgets('defaults to info type', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CbsFeedbackMessage(message: 'Default feedback')),
      ),
    );

    final feedback = tester.widget<CbsFeedbackMessage>(
      find.byType(CbsFeedbackMessage),
    );

    expect(feedback.type, CbsFeedbackType.info);
  });

  for (final type in CbsFeedbackType.values) {
    testWidgets('renders $type with semantic colors', (tester) async {
      final theme = CbsTheme.essentials();

      await tester.pumpWidget(buildApp(theme: theme, type: type));

      final scheme = theme.colorScheme;

      final (
        Color background,
        Color foreground,
        IconData icon,
      ) = switch (type) {
        CbsFeedbackType.info => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          Icons.info_outline,
        ),
        CbsFeedbackType.success => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
          Icons.check_circle_outline,
        ),
        CbsFeedbackType.warning => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          Icons.warning_amber_outlined,
        ),
        CbsFeedbackType.error => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.error_outline,
        ),
      };

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(CbsFeedbackMessage),
          matching: find.byType(Container),
        ),
      );

      final decoration = container.decoration! as BoxDecoration;

      expect(decoration.color, background);
      expect(find.byIcon(icon), findsOneWidget);

      final text = tester.widget<Text>(find.text('Test feedback'));
      expect(text.style?.color, foreground);
    });
  }

  testWidgets('renders with Essentials theme', (tester) async {
    await tester.pumpWidget(buildApp(theme: CbsTheme.essentials()));

    expect(find.byType(CbsFeedbackMessage), findsOneWidget);
  });

  testWidgets('renders with Branded theme', (tester) async {
    await tester.pumpWidget(
      buildApp(
        theme: CbsTheme.branded(primaryColor: Colors.green),
        type: CbsFeedbackType.success,
      ),
    );

    expect(find.byType(CbsFeedbackMessage), findsOneWidget);
  });
}
