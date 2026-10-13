import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbsFeedbackStyle', () {
    for (final brightness in Brightness.values) {
      final scheme = CbsTheme.essentials(brightness: brightness).colorScheme;

      test('resolves info from the $brightness color scheme', () {
        final style = CbsFeedbackStyle.resolve(scheme, CbsFeedbackType.info);

        expect(style.background, scheme.primaryContainer);
        expect(style.foreground, scheme.onPrimaryContainer);
        expect(style.icon, Icons.info_outline);
      });

      test('resolves success from the $brightness color scheme', () {
        final style = CbsFeedbackStyle.resolve(scheme, CbsFeedbackType.success);

        expect(style.background, scheme.secondaryContainer);
        expect(style.foreground, scheme.onSecondaryContainer);
        expect(style.icon, Icons.check_circle_outline);
      });

      test('resolves warning from the $brightness color scheme', () {
        final style = CbsFeedbackStyle.resolve(scheme, CbsFeedbackType.warning);

        expect(style.background, scheme.tertiaryContainer);
        expect(style.foreground, scheme.onTertiaryContainer);
        expect(style.icon, Icons.warning_amber_outlined);
      });

      test('resolves error from the $brightness color scheme', () {
        final style = CbsFeedbackStyle.resolve(scheme, CbsFeedbackType.error);

        expect(style.background, scheme.errorContainer);
        expect(style.foreground, scheme.onErrorContainer);
        expect(style.icon, Icons.error_outline);
      });
    }

    test('supports value equality', () {
      final scheme = CbsTheme.essentials().colorScheme;

      final a = CbsFeedbackStyle.resolve(scheme, CbsFeedbackType.info);
      final b = CbsFeedbackStyle.resolve(scheme, CbsFeedbackType.info);
      final c = CbsFeedbackStyle.resolve(scheme, CbsFeedbackType.error);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('keeps the four feedback severities', () {
      expect(CbsFeedbackType.values, [
        CbsFeedbackType.info,
        CbsFeedbackType.success,
        CbsFeedbackType.warning,
        CbsFeedbackType.error,
      ]);
    });
  });

  group('CbsFeedbackMessage layout tokens', () {
    testWidgets('uses the CBS spacing and radius tokens', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: CbsTheme.essentials(),
          home: const Scaffold(body: CbsFeedbackMessage(message: 'Layout')),
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(CbsFeedbackMessage),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;

      expect(container.padding, const EdgeInsets.all(CbsSpacing.md));
      expect(decoration.borderRadius, BorderRadius.circular(CbsRadius.md));
    });
  });
}
