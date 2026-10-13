import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cbs_test_matrix.dart';

const String _longText =
    'Un texte suffisamment long pour passer à la ligne sur une largeur '
    'compacte avec un facteur de texte agrandi.';

/// Reproduction of the CURRENT AMH-USR Home `_StatePanel` surface,
/// used as the equivalence reference.
Widget _currentHomeStatePanel(BuildContext context, Widget child) {
  return Container(
    key: const ValueKey('current-home-state-panel'),
    width: double.infinity,
    padding: const EdgeInsets.all(CbsSpacing.lg),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(CbsRadius.lg),
    ),
    child: child,
  );
}

void main() {
  testWidgets('renders its child', (tester) async {
    await pumpCbs(
      tester,
      child: const CbsStatePanel(child: Text('Aucun contenu')),
    );

    expect(find.byType(CbsStatePanel), findsOneWidget);
    expect(find.text('Aucun contenu'), findsOneWidget);
  });

  testWidgets('child is required and rendered as provided', (tester) async {
    const child = SizedBox(key: ValueKey('panel-child'), height: 10);

    await pumpCbs(tester, child: const CbsStatePanel(child: child));

    expect(find.byKey(const ValueKey('panel-child')), findsOneWidget);
  });

  for (final variant in cbsTestThemes) {
    for (final width in cbsTestWidths) {
      for (final scale in cbsTestTextScales) {
        testWidgets(
          'surface contract: ${variant.name}, width $width, text x$scale',
          (tester) async {
            await pumpCbs(
              tester,
              theme: variant.theme,
              width: width,
              textScale: scale,
              child: const CbsStatePanel(
                child: Text(_longText, key: ValueKey('content')),
              ),
            );

            expect(tester.takeException(), isNull);

            final panel = find.byType(CbsStatePanel);
            final panelRect = tester.getRect(panel);
            final contentRect = tester.getRect(
              find.byKey(const ValueKey('content')),
            );

            // Full width.
            expect(panelRect.left, 0);
            expect(panelRect.width, width);

            // Padding 24 on every side.
            expect(contentRect.left - panelRect.left, CbsSpacing.lg);
            expect(contentRect.top - panelRect.top, CbsSpacing.lg);
            expect(panelRect.height - contentRect.height, 2 * CbsSpacing.lg);

            // Color and radius.
            final decorated = tester.widget<DecoratedBox>(
              find.descendant(of: panel, matching: find.byType(DecoratedBox)),
            );
            final decoration = decorated.decoration as BoxDecoration;
            expect(
              decoration.color,
              variant.theme.colorScheme.surfaceContainerHighest,
            );
            expect(
              decoration.borderRadius,
              BorderRadius.circular(CbsRadius.lg),
            );
          },
        );
      }
    }
  }

  for (final variant in cbsTestThemes) {
    for (final width in cbsTestWidths) {
      for (final scale in cbsTestTextScales) {
        testWidgets('equals the CURRENT Home surface: ${variant.name}, '
            'width $width, text x$scale', (tester) async {
          late Rect currentRect;
          late BoxDecoration currentDecoration;

          await pumpCbs(
            tester,
            theme: variant.theme,
            width: width,
            textScale: scale,
            child: Builder(
              builder: (context) =>
                  _currentHomeStatePanel(context, const Text(_longText)),
            ),
          );
          final currentFinder = find.byKey(
            const ValueKey('current-home-state-panel'),
          );
          currentRect = tester.getRect(currentFinder);
          currentDecoration =
              tester.widget<Container>(currentFinder).decoration!
                  as BoxDecoration;

          await pumpCbs(
            tester,
            theme: variant.theme,
            width: width,
            textScale: scale,
            child: const CbsStatePanel(child: Text(_longText)),
          );
          final panel = find.byType(CbsStatePanel);
          final panelRect = tester.getRect(panel);
          final panelDecoration =
              tester
                      .widget<DecoratedBox>(
                        find.descendant(
                          of: panel,
                          matching: find.byType(DecoratedBox),
                        ),
                      )
                      .decoration
                  as BoxDecoration;

          expect(panelRect, currentRect);
          expect(panelDecoration.color, currentDecoration.color);
          expect(panelDecoration.borderRadius, currentDecoration.borderRadius);
        });
      }
    }
  }

  testWidgets('does not depend on CardTheme', (tester) async {
    final theme = CbsTheme.essentials().copyWith(
      cardTheme: CardThemeData(
        color: Colors.red,
        margin: const EdgeInsets.all(40),
        shape: const RoundedRectangleBorder(),
      ),
    );

    await pumpCbs(
      tester,
      theme: theme,
      child: const CbsStatePanel(child: SizedBox(height: 10)),
    );

    final panel = find.byType(CbsStatePanel);
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: panel,
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;

    expect(decoration.color, theme.colorScheme.surfaceContainerHighest);
    expect(decoration.borderRadius, BorderRadius.circular(CbsRadius.lg));
    expect(tester.getSize(panel), const Size(600, 10 + 2 * CbsSpacing.lg));
  });

  testWidgets('adds no semantics of its own', (tester) async {
    final semantics = tester.ensureSemantics();

    await pumpCbs(
      tester,
      child: const CbsStatePanel(
        child: Text('Aucun contenu', key: ValueKey('content')),
      ),
    );

    expect(
      find.descendant(
        of: find.byType(CbsStatePanel),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.container,
        ),
      ),
      findsNothing,
    );
    expect(find.bySemanticsLabel('Aucun contenu'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('preserves the semantics of a loading child', (tester) async {
    final semantics = tester.ensureSemantics();

    await pumpCbs(
      tester,
      child: const CbsStatePanel(
        child: Center(
          child: CbsLoadingIndicator(semanticLabel: 'Chargement en cours'),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Chargement en cours'), findsOneWidget);

    semantics.dispose();
  });
}
