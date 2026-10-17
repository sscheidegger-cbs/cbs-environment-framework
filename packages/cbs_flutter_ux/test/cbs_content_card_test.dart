import 'dart:ui' show Tristate;

import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cbs_test_matrix.dart';

const Key _mediaKey = ValueKey('media');
const Key _contentKey = ValueKey('content');
const Key _actionKey = ValueKey('action');
const Key _nextKey = ValueKey('next');

const String _title = 'Titre de la carte';
const String _subtitle = 'Sous-titre de démonstration';
const String _actionLabel = 'Ouvrir';
const String _longTitle =
    'Un titre de carte volontairement très long qui doit passer à la ligne '
    'sur une largeur compacte avec un facteur de texte agrandi sans jamais '
    'provoquer de dépassement';

Widget _media() => const SizedBox(key: _mediaKey, height: 100);

Widget _content({String title = _title}) => Column(
  key: _contentKey,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [Text(title), const Text(_subtitle)],
);

Widget _action({VoidCallback? onPressed}) => TextButton(
  key: _actionKey,
  onPressed: onPressed ?? () {},
  child: const Text(_actionLabel),
);

Finder _inCard(Finder matching) =>
    find.descendant(of: find.byType(CbsContentCard), matching: matching);

Rect _rect(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

Material _cardMaterial(WidgetTester tester) => tester.widget<Material>(
  find
      .descendant(
        of: find.byType(CbsContentCard),
        matching: find.byType(Material),
      )
      .first,
);

void main() {
  group('API', () {
    test('has a vertical layout by default and no interaction', () {
      const card = CbsContentCard(content: SizedBox());

      expect(card.layout, CbsContentCardLayout.vertical);
      expect(card.media, isNull);
      expect(card.action, isNull);
      expect(card.onTap, isNull);
      expect(card.semanticLabel, isNull);
      expect(CbsContentCardLayout.values, [
        CbsContentCardLayout.vertical,
        CbsContentCardLayout.horizontal,
      ]);
    });
  });

  group('slots', () {
    testWidgets('renders the content alone', (tester) async {
      await pumpCbs(tester, child: CbsContentCard(content: _content()));

      expect(find.text(_title), findsOneWidget);
      expect(find.text(_subtitle), findsOneWidget);
      expect(_inCard(find.byKey(_mediaKey)), findsNothing);
      expect(_inCard(find.byType(TextButton)), findsNothing);
    });

    testWidgets('is built from Card, Row and Column', (tester) async {
      await pumpCbs(
        tester,
        child: CbsContentCard(
          layout: CbsContentCardLayout.horizontal,
          media: _media(),
          content: _content(),
        ),
      );

      expect(_inCard(find.byType(Row)), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(CbsContentCard),
          matching: find.byType(Card),
        ),
        findsOneWidget,
      );
      // The card is a Material Card without external margin.
      expect(tester.widget<Card>(find.byType(Card)).margin, EdgeInsets.zero);
    });

    testWidgets('vertical layout stacks media, content and action', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: CbsContentCard(
          media: _media(),
          content: _content(),
          action: _action(),
        ),
      );

      final card = tester.getRect(find.byType(CbsContentCard));
      final media = _rect(tester, _mediaKey);
      final content = _rect(tester, _contentKey);
      final action = _rect(tester, _actionKey);

      // The media is at the top edge, as wide as the card.
      expect(media.top, card.top);
      expect(media.left, card.left);
      expect(media.width, card.width);
      expect(media.height, 100);
      // Order: media, content, action.
      expect(content.top, greaterThanOrEqualTo(media.bottom));
      expect(action.top, greaterThanOrEqualTo(content.bottom));
      // The content is inset by CbsSpacing.md; the action ends the line.
      expect(content.left, card.left + CbsSpacing.md);
      expect(action.right, card.right - CbsSpacing.md);
      expect(action.bottom, card.bottom - CbsSpacing.md);
    });

    testWidgets('horizontal layout places the media beside the content', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        width: 600,
        child: CbsContentCard(
          layout: CbsContentCardLayout.horizontal,
          media: _media(),
          content: _content(),
          action: _action(),
        ),
      );

      final card = tester.getRect(find.byType(CbsContentCard));
      final media = _rect(tester, _mediaKey);
      final content = _rect(tester, _contentKey);
      final action = _rect(tester, _actionKey);

      expect(media.left, card.left);
      expect(media.width, closeTo(card.width / 3, 0.01));
      expect(content.left, media.right + CbsSpacing.md);
      expect(content.top, lessThan(media.bottom));
      expect(action.top, greaterThanOrEqualTo(content.bottom));
      expect(action.right, card.right - CbsSpacing.md);
    });

    testWidgets('horizontal layout without media gives the width to the body', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: CbsContentCard(
          layout: CbsContentCardLayout.horizontal,
          content: _content(),
        ),
      );

      final card = tester.getRect(find.byType(CbsContentCard));
      expect(_rect(tester, _contentKey).left, card.left + CbsSpacing.md);
      expect(card.width, 600);
    });

    testWidgets('horizontal layout follows the text direction', (tester) async {
      await pumpCbs(
        tester,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: CbsContentCard(
            layout: CbsContentCardLayout.horizontal,
            media: _media(),
            content: _content(),
            action: _action(),
          ),
        ),
      );

      final card = tester.getRect(find.byType(CbsContentCard));
      expect(_rect(tester, _mediaKey).right, card.right);
      expect(_rect(tester, _actionKey).left, card.left + CbsSpacing.md);
    });

    testWidgets('adds no external spacing', (tester) async {
      await pumpCbs(
        tester,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CbsContentCard(content: _content()),
            const SizedBox(key: _nextKey, height: 10, width: 10),
          ],
        ),
      );

      final card = tester.getRect(find.byType(CbsContentCard));
      expect(card.topLeft, Offset.zero);
      expect(_rect(tester, _nextKey).top, card.bottom);
    });

    testWidgets('updates when the slots change', (tester) async {
      await pumpCbs(
        tester,
        child: CbsContentCard(content: _content(), media: _media()),
      );
      expect(find.byKey(_mediaKey), findsOneWidget);

      await pumpCbs(
        tester,
        child: CbsContentCard(
          content: _content(),
          action: _action(),
          layout: CbsContentCardLayout.horizontal,
        ),
      );

      expect(find.byKey(_mediaKey), findsNothing);
      expect(find.byKey(_actionKey), findsOneWidget);
    });
  });

  group('without onTap', () {
    testWidgets('is not interactive', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCbs(tester, child: CbsContentCard(content: _content()));

      expect(_inCard(find.byType(InkWell)), findsNothing);
      expect(_inCard(find.byType(InkResponse)), findsNothing);

      final node = tester.getSemantics(find.byType(CbsContentCard));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      expect(node.flagsCollection.isEnabled, Tristate.none);

      await tester.tap(find.text(_title));
      await tester.pump();
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('the action works without card interaction', (tester) async {
      var pressed = 0;
      await pumpCbs(
        tester,
        child: CbsContentCard(
          content: _content(),
          action: _action(onPressed: () => pressed++),
        ),
      );

      await tester.tap(find.byKey(_actionKey));
      expect(pressed, 1);
    });
  });

  group('with onTap', () {
    testWidgets('is an InkWell that calls onTap', (tester) async {
      var taps = 0;
      await pumpCbs(
        tester,
        child: CbsContentCard(content: _content(), onTap: () => taps++),
      );

      expect(_inCard(find.byType(InkWell)), findsOneWidget);

      await tester.tap(find.text(_title));
      await tester.pump();
      expect(taps, 1);

      await tester.tap(find.text(_subtitle));
      await tester.pump();
      expect(taps, 2);
    });

    testWidgets('shows the native ripple feedback', (tester) async {
      await pumpCbs(
        tester,
        child: CbsContentCard(content: _content(), onTap: () {}),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text(_title)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // The ink splash is painted on the Material of the card.
      final controller = Material.of(tester.element(find.byType(InkWell)));
      expect((controller as dynamic).debugInkFeatures, isNotEmpty);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('exposes a tap action to assistive technologies', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: CbsContentCard(content: _content(), onTap: () {}),
      );

      final node = tester.getSemantics(find.byType(CbsContentCard));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      // The texts of the content stay readable on the activatable node.
      expect(node.label, contains(_title));
      expect(node.label, contains(_subtitle));
      handle.dispose();
    });

    testWidgets('semantic tap performs onTap', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await pumpCbs(
        tester,
        child: CbsContentCard(content: _content(), onTap: () => taps++),
      );

      tester.semantics.tap(find.semantics.byLabel(RegExp(_title)));
      await tester.pump();

      expect(taps, 1);
      handle.dispose();
    });

    testWidgets('can be focused and activated with the keyboard', (
      tester,
    ) async {
      var taps = 0;
      await pumpCbs(
        tester,
        child: CbsContentCard(content: _content(), onTap: () => taps++),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus;
      expect(focused, isNotNull);
      // The focus is held by the card, not by another widget.
      expect(
        focused!.context!.findAncestorWidgetOfExactType<CbsContentCard>(),
        isNotNull,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('pressing the action does not activate the card', (
      tester,
    ) async {
      var taps = 0;
      var pressed = 0;
      await pumpCbs(
        tester,
        child: CbsContentCard(
          content: _content(),
          action: _action(onPressed: () => pressed++),
          onTap: () => taps++,
        ),
      );

      await tester.tap(find.byKey(_actionKey));
      await tester.pump();

      expect(pressed, 1);
      expect(taps, 0);
    });

    testWidgets('the action stays a separate accessible button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: CbsContentCard(
          content: _content(),
          action: _action(),
          onTap: () {},
        ),
      );

      final action = tester.getSemantics(find.byKey(_actionKey));
      expect(action.flagsCollection.isButton, isTrue);
      expect(action.label, _actionLabel);
      expect(action.label, isNot(contains(_title)));

      final card = tester
          .getSemantics(find.byType(CbsContentCard))
          .getSemanticsData();
      expect(card.label, isNot(contains(_actionLabel)));
      handle.dispose();
    });
  });

  group('semantic label', () {
    testWidgets('is added without hiding the texts of the slots', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: CbsContentCard(
          content: _content(),
          semanticLabel: 'Carte de démonstration',
          onTap: () {},
        ),
      );

      final data = tester
          .getSemantics(find.byType(CbsContentCard))
          .getSemanticsData();
      expect(data.label, contains('Carte de démonstration'));
      expect(data.label, contains(_title));
      expect(data.label, contains(_subtitle));
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('works on a non interactive card', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: CbsContentCard(
          content: _content(),
          semanticLabel: 'Carte de démonstration',
        ),
      );

      final data = tester
          .getSemantics(find.byType(CbsContentCard))
          .getSemanticsData();
      expect(data.label, contains('Carte de démonstration'));
      expect(data.label, contains(_title));
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });

    testWidgets('without label the semantics contain only the slot texts', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpCbs(tester, child: CbsContentCard(content: _content()));

      final data = tester
          .getSemantics(find.byType(CbsContentCard))
          .getSemanticsData();
      expect(data.label, '$_title\n$_subtitle');
      handle.dispose();
    });
  });

  group('themes', () {
    for (final variant in cbsTestThemes) {
      for (final layout in CbsContentCardLayout.values) {
        testWidgets('${variant.name}, ${layout.name}', (tester) async {
          await pumpCbs(
            tester,
            theme: variant.theme,
            child: CbsContentCard(
              layout: layout,
              media: _media(),
              content: _content(),
              action: _action(),
              onTap: () {},
            ),
          );

          expect(tester.takeException(), isNull);
          // The surface is the Material 3 card color of the theme.
          expect(
            _cardMaterial(tester).color,
            variant.theme.colorScheme.surfaceContainerLow,
          );
          expect(
            _cardMaterial(tester).shape,
            variant.theme.cardTheme.shape ??
                const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
          );
        });
      }
    }

    testWidgets('follows the card theme of a Branded customization', (
      tester,
    ) async {
      final theme = CbsTheme.branded(primaryColor: Colors.green).copyWith(
        cardTheme: const CardThemeData(
          color: Colors.amber,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(CbsRadius.xl)),
          ),
        ),
      );

      await pumpCbs(
        tester,
        theme: theme,
        child: CbsContentCard(content: _content(), onTap: () {}),
      );

      final material = _cardMaterial(tester);
      expect(material.color, Colors.amber);
      expect(
        material.shape,
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(CbsRadius.xl)),
        ),
      );
    });
  });

  group('responsive and text scale', () {
    for (final layout in CbsContentCardLayout.values) {
      for (final width in [320.0, 600.0, 1280.0]) {
        for (final scale in cbsTestTextScales) {
          testWidgets(
            'long content at width $width, text x$scale: ${layout.name}',
            (tester) async {
              await pumpCbs(
                tester,
                width: width,
                textScale: scale,
                child: CbsContentCard(
                  layout: layout,
                  media: _media(),
                  content: _content(title: _longTitle),
                  action: _action(),
                  onTap: () {},
                ),
              );

              expect(tester.takeException(), isNull);
              final rect = tester.getRect(find.byType(CbsContentCard));
              expect(rect.left, 0);
              expect(rect.width, width);
              // Every slot stays inside the card.
              for (final key in [_mediaKey, _contentKey, _actionKey]) {
                final slot = _rect(tester, key);
                expect(
                  slot.left,
                  greaterThanOrEqualTo(rect.left),
                  reason: '$key',
                );
                expect(
                  slot.right,
                  lessThanOrEqualTo(rect.right),
                  reason: '$key',
                );
              }
            },
          );
        }
      }
    }

    testWidgets('the content grows with the text scale', (tester) async {
      await pumpCbs(
        tester,
        width: 320,
        child: CbsContentCard(content: _content(title: _longTitle)),
      );
      final regular = tester.getSize(find.byType(CbsContentCard)).height;

      await pumpCbs(
        tester,
        width: 320,
        textScale: 2,
        child: CbsContentCard(content: _content(title: _longTitle)),
      );
      final large = tester.getSize(find.byType(CbsContentCard)).height;

      expect(large, greaterThan(regular * 1.5));
    });
  });

  group('non-coupling', () {
    testWidgets('composes with existing CBS resources', (tester) async {
      await pumpCbs(
        tester,
        child: CbsContentCard(
          content: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CbsSectionHeading(title: _title),
              SizedBox(height: CbsSpacing.sm),
              CbsFeedbackMessage(message: _subtitle),
            ],
          ),
          action: CbsButton(label: _actionLabel, onPressed: () {}),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(CbsSectionHeading), findsOneWidget);
      expect(find.byType(CbsFeedbackMessage), findsOneWidget);
      expect(find.byType(CbsButton), findsOneWidget);
    });
  });
}
