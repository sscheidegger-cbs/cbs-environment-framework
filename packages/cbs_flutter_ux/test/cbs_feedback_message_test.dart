import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cbs_test_matrix.dart';

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

  group('expand', () {
    const message = 'Les contenus n’ont pas pu être chargés.';

    testWidgets('defaults to false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CbsFeedbackMessage(message: message)),
        ),
      );

      final feedback = tester.widget<CbsFeedbackMessage>(
        find.byType(CbsFeedbackMessage),
      );

      expect(feedback.expand, isFalse);
    });

    testWidgets('false keeps the width of the content', (tester) async {
      await pumpCbs(
        tester,
        width: 840,
        child: const CbsFeedbackMessage(message: message),
      );

      expect(
        tester.getSize(find.byType(CbsFeedbackMessage)).width,
        lessThan(840),
      );
    });

    for (final variant in cbsTestThemes) {
      for (final width in cbsTestWidths) {
        for (final scale in cbsTestTextScales) {
          testWidgets('true takes the maximum width: ${variant.name}, '
              'width $width, text x$scale', (tester) async {
            await pumpCbs(
              tester,
              theme: variant.theme,
              width: width,
              textScale: scale,
              child: const CbsFeedbackMessage(
                message: message,
                type: CbsFeedbackType.error,
                expand: true,
              ),
            );

            expect(tester.takeException(), isNull);
            expect(
              tester.getSize(find.byType(CbsFeedbackMessage)).width,
              width,
            );
          });
        }
      }
    }

    testWidgets('true matches the CURRENT SizedBox(width: infinity) wrapper', (
      tester,
    ) async {
      for (final width in cbsTestWidths) {
        await pumpCbs(
          tester,
          width: width,
          child: const SizedBox(
            width: double.infinity,
            child: CbsFeedbackMessage(message: message),
          ),
        );
        final expected = tester.getRect(find.byType(CbsFeedbackMessage));

        await pumpCbs(
          tester,
          width: width,
          child: const CbsFeedbackMessage(message: message, expand: true),
        );

        expect(tester.getRect(find.byType(CbsFeedbackMessage)), expected);
      }
    });

    testWidgets('true preserves colors, icon and alignment', (tester) async {
      final theme = CbsTheme.essentials();

      await pumpCbs(
        tester,
        theme: theme,
        child: const CbsFeedbackMessage(
          message: message,
          type: CbsFeedbackType.error,
          expand: true,
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(CbsFeedbackMessage),
          matching: find.byType(Container),
        ),
      );

      expect(
        (container.decoration! as BoxDecoration).color,
        theme.colorScheme.errorContainer,
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      // Icon stays at the start; the content is not centered.
      final feedbackRect = tester.getRect(find.byType(CbsFeedbackMessage));
      final iconRect = tester.getRect(find.byIcon(Icons.error_outline));
      expect(iconRect.left - feedbackRect.left, CbsSpacing.md);
    });

    testWidgets('true keeps the custom semantic label', (tester) async {
      final semantics = tester.ensureSemantics();

      await pumpCbs(
        tester,
        child: const CbsFeedbackMessage(
          message: message,
          type: CbsFeedbackType.error,
          semanticLabel: 'Erreur : chargement impossible',
          expand: true,
        ),
      );

      expect(
        find.bySemanticsLabel('Erreur : chargement impossible'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(message), findsNothing);

      semantics.dispose();
    });
  });
}
