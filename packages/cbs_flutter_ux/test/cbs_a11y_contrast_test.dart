// D03c-A.2 / C2 — contrast qualification.
//
// Scope and limits of these checks:
//
// * `textContrastGuideline` is Flutter's text contrast heuristic (WCAG 2.x
//   1.4.3 ratios, measured on rendered pixels). It is NOT a WCAG
//   certification: it only evaluates `Text` nodes, ignores icons and
//   non-text contrast (1.4.11), and uses the Ahem test font.
// * The guideline skips disabled nodes (`isEnabled == false`). WCAG 1.4.3
//   also exempts inactive components, so disabled states are
//   NOT_APPLICABLE; this is documented by a characterization test.
// * The guideline looks the text up with `find.text(<semantic label>)`. When
//   `semanticLabel` replaces the visible text (`excludeSemantics`), nothing is
//   found and the guideline passes vacuously. Those cases are covered by an
//   independent computed contrast ratio on the resolved colors.
// * Negative controls prove the harness actually detects low contrast on the
//   CBS widgets.

import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cbs_a11y_support.dart';
import 'support/cbs_test_matrix.dart';

const String _message = 'Les contenus n’ont pas pu être chargés.';
const String _retryLabel = 'Réessayer';
const Color _almostWhite = Color(0xFFEEEEEE);

void _noop() {}

/// WCAG 2.x contrast ratio between two opaque colors.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

ThemeData _lowContrastButtonTheme() {
  return CbsTheme.essentials().copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: _almostWhite,
        disabledBackgroundColor: Colors.white,
        disabledForegroundColor: _almostWhite,
      ),
    ),
  );
}

ThemeData _lowContrastFeedbackTheme() {
  final base = CbsTheme.essentials();
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      errorContainer: Colors.white,
      onErrorContainer: _almostWhite,
    ),
  );
}

ThemeData _lowContrastHeadingTheme() {
  return CbsTheme.branded(
    primaryColor: Colors.green,
    textTheme: const TextTheme(titleMedium: TextStyle(color: _almostWhite)),
  );
}

void main() {
  group('harness sensitivity (negative controls)', () {
    testWidgets('CbsButton text with low contrast fails the guideline', (
      tester,
    ) async {
      await pumpA11y(
        tester,
        theme: _lowContrastButtonTheme(),
        child: CbsButton(label: 'Continue', onPressed: _noop),
      );

      await expectLater(tester, doesNotMeetGuideline(textContrastGuideline));
    });

    testWidgets('CbsFeedbackMessage text with low contrast fails', (
      tester,
    ) async {
      await pumpA11y(
        tester,
        theme: _lowContrastFeedbackTheme(),
        child: const CbsFeedbackMessage(
          message: _message,
          type: CbsFeedbackType.error,
        ),
      );

      await expectLater(tester, doesNotMeetGuideline(textContrastGuideline));
    });

    testWidgets('CbsRetryMessage text with low contrast fails', (tester) async {
      await pumpA11y(
        tester,
        theme: _lowContrastFeedbackTheme(),
        child: const CbsRetryMessage(
          message: _message,
          retryLabel: _retryLabel,
          onRetry: _noop,
        ),
      );

      await expectLater(tester, doesNotMeetGuideline(textContrastGuideline));
    });

    testWidgets('CbsSectionHeading text with low contrast fails', (
      tester,
    ) async {
      await pumpA11y(
        tester,
        theme: _lowContrastHeadingTheme(),
        child: const CbsSectionHeading(title: 'À la une'),
      );

      await expectLater(tester, doesNotMeetGuideline(textContrastGuideline));
    });
  });

  group('known blind spots of the guideline (characterization)', () {
    // NOT_APPLICABLE: Flutter skips disabled nodes; WCAG 1.4.3 exempts
    // inactive components. If this test starts failing after an SDK upgrade,
    // the guideline now evaluates disabled controls: revisit the disabled
    // contrast decision instead of deleting the test.
    testWidgets('a disabled CbsButton is not evaluated by the guideline', (
      tester,
    ) async {
      await pumpA11y(
        tester,
        theme: _lowContrastButtonTheme(),
        child: const CbsButton(label: 'Continue', onPressed: null),
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });

    // NOT_VERIFIED by the guideline: with semanticLabel the visible text is
    // excluded from semantics, so the guideline finds no text to measure.
    // The independent computed ratio group below covers this case.
    testWidgets('semanticLabel makes the guideline blind to the message', (
      tester,
    ) async {
      await pumpA11y(
        tester,
        theme: _lowContrastFeedbackTheme(),
        child: const CbsFeedbackMessage(
          message: _message,
          type: CbsFeedbackType.error,
          semanticLabel: 'Erreur : contenus non chargés',
        ),
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });
  });

  for (final variant in cbsTestThemes) {
    group('textContrastGuideline — ${variant.name}', () {
      testWidgets('CbsButton enabled', (tester) async {
        await pumpA11y(
          tester,
          theme: variant.theme,
          child: CbsButton(label: 'Continue', onPressed: _noop),
        );

        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });

      for (final type in CbsFeedbackType.values) {
        testWidgets('CbsFeedbackMessage ${type.name}', (tester) async {
          await pumpA11y(
            tester,
            theme: variant.theme,
            child: CbsFeedbackMessage(message: _message, type: type),
          );

          await expectLater(tester, meetsGuideline(textContrastGuideline));
        });

        testWidgets('CbsFeedbackMessage ${type.name} expanded', (tester) async {
          await pumpA11y(
            tester,
            theme: variant.theme,
            width: 320,
            child: CbsFeedbackMessage(
              message: _message,
              type: type,
              expand: true,
            ),
          );

          await expectLater(tester, meetsGuideline(textContrastGuideline));
        });
      }

      testWidgets('CbsRetryMessage', (tester) async {
        await pumpA11y(
          tester,
          theme: variant.theme,
          child: const CbsRetryMessage(
            message: _message,
            retryLabel: _retryLabel,
            onRetry: _noop,
          ),
        );

        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });

      testWidgets('CbsSectionHeading', (tester) async {
        await pumpA11y(
          tester,
          theme: variant.theme,
          child: const CbsSectionHeading(title: 'À la une'),
        );

        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });

      testWidgets('CbsSectionHeading with text scale x2 at 320 px', (
        tester,
      ) async {
        await pumpA11y(
          tester,
          theme: variant.theme,
          width: 320,
          textScale: 2,
          child: const CbsSectionHeading(title: 'À la une'),
        );

        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });
    });

    // Independent of rendering and of the guideline blind spots: covers
    // the semanticLabel variants and the feedback icon (same foreground
    // color). WCAG 1.4.3 requires 4.5:1 for normal text; the feedback text
    // uses the default body style (below the large-text threshold).
    group('computed contrast of feedback colors — ${variant.name}', () {
      for (final type in CbsFeedbackType.values) {
        test('${type.name} foreground on background >= 4.5:1', () {
          final style = CbsFeedbackStyle.resolve(
            variant.theme.colorScheme,
            type,
          );

          expect(
            _contrastRatio(style.foreground, style.background),
            greaterThanOrEqualTo(4.5),
          );
        });
      }
    });
  }
}
