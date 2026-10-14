// D03c-A.2 / C2 — tap target qualification.
//
// `androidTapTargetGuideline` (48 x 48 logical pixels) and
// `labeledTapTargetGuideline` (tappable nodes need a label) are evaluated on
// the tappable CBS widgets: CbsButton and the retry button of CbsRetryMessage.
//
// Flutter only evaluates nodes that expose a tap action and do not touch the
// view edge. Two consequences are covered explicitly:
//
// * Enabled controls: `expectTapTargetEvaluated` proves the node is a real
//   candidate, so a passing guideline is not vacuous.
// * Disabled controls expose no tap action: both guidelines are
//   NOT_APPLICABLE. The test asserts the missing action (the reason for the
//   skip) and checks the layout box size as a complementary, non-guideline
//   assertion.
//
// Negative controls prove the harness detects too-small and unlabeled
// targets. Tests run on the default test platform (Android); iOS and desktop
// densities are not qualified here.

import 'dart:ui' show SemanticsAction;

import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cbs_a11y_support.dart';

const String _message = 'Les contenus n’ont pas pu être chargés.';
const String _retryLabel = 'Réessayer';
const String _longLabel =
    'Réessayer le chargement des contenus à la une maintenant';
const String _longMessage =
    'Les contenus à la une n’ont pas pu être chargés pour le moment, merci '
    'de vérifier votre connexion puis de réessayer dans quelques instants.';

void _noop() {}

final List<({String name, ThemeData theme})> _designs = [
  (name: 'Essentials', theme: CbsTheme.essentials()),
  (
    name: 'Branded with button radius',
    theme: CbsTheme.branded(
      primaryColor: Colors.green,
      buttonRadius: CbsRadius.lg,
    ),
  ),
];

const List<double> _widths = [320, 1280];

void main() {
  group('harness sensitivity (negative controls)', () {
    testWidgets('a 20 x 20 tappable node fails androidTapTargetGuideline', (
      tester,
    ) async {
      await pumpA11y(
        tester,
        child: Semantics(
          button: true,
          label: 'Tiny',
          onTap: _noop,
          child: const SizedBox(width: 20, height: 20),
        ),
      );

      await expectLater(
        tester,
        doesNotMeetGuideline(androidTapTargetGuideline),
      );
    });

    testWidgets('an unlabeled tappable node fails labeledTapTargetGuideline', (
      tester,
    ) async {
      await pumpA11y(
        tester,
        child: Semantics(
          button: true,
          onTap: _noop,
          child: const SizedBox(width: 48, height: 48),
        ),
      );

      await expectLater(
        tester,
        doesNotMeetGuideline(labeledTapTargetGuideline),
      );
    });

    testWidgets('a too-small node touching the view edge is skipped', (
      tester,
    ) async {
      // Characterization of the Flutter blind spot that justifies the inset
      // applied by pumpA11y: at the view edge the node is skipped, so a
      // passing guideline would say nothing about it.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 1600);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Semantics(
                button: true,
                label: 'Tiny',
                onTap: _noop,
                child: const SizedBox(width: 20, height: 20),
              ),
            ),
          ),
        ),
      );

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    });
  });

  for (final design in _designs) {
    for (final width in _widths) {
      for (final scale in const [1.0, 2.0]) {
        final scenario = '${design.name}, width $width, text x$scale';

        group('CbsButton enabled — $scenario', () {
          testWidgets('meets androidTapTargetGuideline', (tester) async {
            final semantics = tester.ensureSemantics();
            await pumpA11y(
              tester,
              theme: design.theme,
              width: width,
              textScale: scale,
              child: CbsButton(label: 'Continue', onPressed: _noop),
            );

            expectTapTargetEvaluated(tester, find.byType(FilledButton));
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );

            semantics.dispose();
          });

          testWidgets('meets labeledTapTargetGuideline', (tester) async {
            final semantics = tester.ensureSemantics();
            await pumpA11y(
              tester,
              theme: design.theme,
              width: width,
              textScale: scale,
              child: CbsButton(label: 'Continue', onPressed: _noop),
            );

            expectTapTargetEvaluated(tester, find.byType(FilledButton));
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );

            semantics.dispose();
          });

          testWidgets('long label keeps the minimum tap target', (
            tester,
          ) async {
            final semantics = tester.ensureSemantics();
            await pumpA11y(
              tester,
              theme: design.theme,
              width: width,
              textScale: scale,
              child: CbsButton(label: _longLabel, onPressed: _noop),
            );

            expectTapTargetEvaluated(tester, find.byType(FilledButton));
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );

            semantics.dispose();
          });
        });

        group('CbsRetryMessage — $scenario', () {
          for (final (name, message) in [
            ('short message', _message),
            ('long message', _longMessage),
          ]) {
            testWidgets('$name: retry button meets both guidelines', (
              tester,
            ) async {
              final semantics = tester.ensureSemantics();
              await pumpA11y(
                tester,
                theme: design.theme,
                width: width,
                textScale: scale,
                child: CbsRetryMessage(
                  message: message,
                  retryLabel: _retryLabel,
                  onRetry: _noop,
                ),
              );

              expectTapTargetEvaluated(tester, find.byType(FilledButton));
              await expectLater(
                tester,
                meetsGuideline(androidTapTargetGuideline),
              );
              await expectLater(
                tester,
                meetsGuideline(labeledTapTargetGuideline),
              );

              semantics.dispose();
            });
          }

          testWidgets('semanticLabel leaves the retry button target intact', (
            tester,
          ) async {
            final semantics = tester.ensureSemantics();
            await pumpA11y(
              tester,
              theme: design.theme,
              width: width,
              textScale: scale,
              child: const CbsRetryMessage(
                message: _message,
                retryLabel: _retryLabel,
                semanticLabel: 'Erreur : contenus non chargés',
                onRetry: _noop,
              ),
            );

            expectTapTargetEvaluated(tester, find.byType(FilledButton));
            expect(
              tester.getSemantics(find.byType(FilledButton)).label,
              _retryLabel,
            );
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );

            semantics.dispose();
          });
        });
      }
    }

    group('CbsButton disabled — ${design.name}', () {
      // NOT_APPLICABLE: a disabled button exposes no tap action, so Flutter
      // skips it in both guidelines. The guideline result is vacuous; the
      // assertions below state why and check the layout box instead.
      testWidgets('exposes no tap action (guidelines not applicable)', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pumpA11y(
          tester,
          theme: design.theme,
          child: const CbsButton(label: 'Continue', onPressed: null),
        );

        final data = tester
            .getSemantics(find.byType(FilledButton))
            .getSemanticsData();

        expect(data.hasAction(SemanticsAction.tap), isFalse);
        expect(data.label, 'Continue');

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        semantics.dispose();
      });

      testWidgets('keeps the same 48 x 48 layout box as when enabled', (
        tester,
      ) async {
        await pumpA11y(
          tester,
          theme: design.theme,
          child: const CbsButton(label: 'Continue', onPressed: null),
        );
        final disabled = tester.getSize(find.byType(FilledButton));

        await pumpA11y(
          tester,
          theme: design.theme,
          child: CbsButton(label: 'Continue', onPressed: _noop),
        );
        final enabled = tester.getSize(find.byType(FilledButton));

        expect(disabled, enabled);
        expect(disabled.width, greaterThanOrEqualTo(48));
        expect(disabled.height, greaterThanOrEqualTo(48));
      });
    });
  }
}
