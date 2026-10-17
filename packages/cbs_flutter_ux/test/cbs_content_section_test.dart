import 'dart:math' as math;
import 'dart:ui' show SemanticsAction;

import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cbs_a11y_support.dart';
import 'support/cbs_test_matrix.dart';

const String _title = 'À la une';
const String _subtitle = 'Sélection de la semaine';
const String _actionLabel = 'Voir tout';
const String _contentText = 'Contenu de la section';
const String _longTitle =
    'Un titre de section volontairement très long qui doit passer à la '
    'ligne sur une largeur compacte avec un facteur de texte agrandi sans '
    'jamais provoquer de dépassement';
const String _longSubtitle =
    'Un sous-titre volontairement très long qui doit lui aussi passer à la '
    'ligne sur une largeur compacte avec un facteur de texte agrandi sans '
    'jamais provoquer de dépassement';

/// Tolerance of the layout comparisons (logical pixels).
const double _epsilon = 0.001;

const Key _contentKey = ValueKey('content');
const Key _actionKey = ValueKey('action');

/// Columns of the adaptive grid (default `minItemWidth` 240 and `spacing`
/// 12) at each width of the qualification matrix.
final Map<double, int> _gridColumns = {320: 1, 600: 2, 840: 3, 1280: 5};

final Finder _section = find.byType(CbsContentSection);
final Finder _heading = find.byType(CbsSectionHeading);
final Finder _subtitleText = find.text(_subtitle);
final Finder _content = find.byKey(_contentKey);
final Finder _action = find.byKey(_actionKey);

/// Plain content with a fixed height; it fills the width it receives.
Widget _plainContent({double height = 40}) =>
    SizedBox(key: _contentKey, height: height, child: const Text(_contentText));

Widget _textButton({VoidCallback? onPressed}) => TextButton(
  key: _actionKey,
  onPressed: onPressed ?? () {},
  child: const Text(_actionLabel),
);

Widget _gridItem(int index) =>
    SizedBox(key: ValueKey('item-$index'), height: 40, child: Text('$index'));

Widget _card(int index, {bool media = true}) => CbsContentCard(
  key: ValueKey('card-$index'),
  media: media
      ? CbsMediaFrame(
          key: ValueKey('frame-$index'),
          child: const ColoredBox(color: Colors.grey),
        )
      : null,
  content: Text('Carte $index'),
  action: TextButton(onPressed: () {}, child: const Text('Ouvrir')),
);

/// Section whose child is a grid of cards with media: it composes VP-01,
/// VP-02 and VP-03 inside the section.
Widget _fullSection({
  String title = _title,
  String? subtitle = _subtitle,
  bool withAction = true,
}) => CbsContentSection(
  title: title,
  subtitle: subtitle,
  action: withAction ? _textButton() : null,
  child: CbsAdaptiveCollection(
    layout: CbsCollectionLayout.grid,
    children: [for (var i = 0; i < 4; i++) _card(i)],
  ),
);

Rect _rect(WidgetTester tester, Finder finder) => tester.getRect(finder);

/// Bottom of the header: the lowest edge of the title, the [subtitle] and the
/// action that are present.
///
/// [subtitle] is the exact subtitle text built by the test. It must be
/// displayed exactly once: a subtitle that is not found makes the lookup
/// fail instead of being silently left out of the measure.
double _headerBottom(WidgetTester tester, {String subtitle = _subtitle}) {
  final subtitleFinder = find.text(subtitle);
  expect(subtitleFinder, findsOneWidget);
  var bottom = math.max(
    _rect(tester, _heading).bottom,
    _rect(tester, subtitleFinder).bottom,
  );
  if (_action.evaluate().isNotEmpty) {
    bottom = math.max(bottom, _rect(tester, _action).bottom);
  }
  return bottom;
}

/// Texts of the section header: the title and the optional subtitle.
Finder _textsOf(Finder owner) =>
    find.descendant(of: owner, matching: find.byType(Text));

Text _headingText(WidgetTester tester) => tester.widget<Text>(
  find.descendant(of: _heading, matching: find.byType(Text)),
);

/// Index of the first widget matching [finder] in the depth-first order of
/// the widget tree, which is the order the section builds its parts.
int _treeIndex(WidgetTester tester, Finder finder) {
  final target = finder.evaluate().first.widget;
  return tester.allWidgets.toList().indexWhere((w) => identical(w, target));
}

/// Semantics labels in the order of the simulated accessibility traversal.
List<String> _traversalLabels(WidgetTester tester) => [
  for (final node in tester.semantics.simulatedAccessibilityTraversal())
    if (node.label.isNotEmpty) node.label,
];

void main() {
  group('public API', () {
    test('requires a title and a child, and defaults the optional parts', () {
      const section = CbsContentSection(title: _title, child: SizedBox());

      expect(section.title, _title);
      expect(section.child, isA<SizedBox>());
      expect(section.subtitle, isNull);
      expect(section.action, isNull);
      expect(section.key, isNull);
      expect(section, isA<StatelessWidget>());
    });

    test('accepts a key, a subtitle and an action', () {
      const action = SizedBox();
      const section = CbsContentSection(
        key: ValueKey('section'),
        title: _title,
        subtitle: _subtitle,
        action: action,
        child: SizedBox(),
      );

      expect(section.key, const ValueKey('section'));
      expect(section.subtitle, _subtitle);
      expect(section.action, same(action));
    });
  });

  group('content', () {
    testWidgets('shows the title and the child', (tester) async {
      await pumpCbs(
        tester,
        child: const CbsContentSection(title: _title, child: Text('Enfant')),
      );

      expect(_section, findsOneWidget);
      expect(find.text(_title), findsOneWidget);
      expect(find.text('Enfant'), findsOneWidget);
    });

    testWidgets('title and child only: no subtitle and no action', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(title: _title, child: _plainContent()),
      );

      // The title and the content text are the only texts; no row is
      // needed without an action.
      expect(_textsOf(_section), findsNWidgets(2));
      expect(
        find.descendant(of: _section, matching: find.byType(Row)),
        findsNothing,
      );
    });

    testWidgets('shows the subtitle when it is provided', (tester) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          subtitle: _subtitle,
          child: _plainContent(),
        ),
      );

      expect(_subtitleText, findsOneWidget);
      expect(_textsOf(_section), findsNWidgets(3));
    });

    for (final subtitle in <String?>[null, '']) {
      testWidgets('shows no subtitle when it is '
          '${subtitle == null ? 'null' : 'empty'}', (tester) async {
        await pumpCbs(
          tester,
          child: CbsContentSection(
            title: _title,
            subtitle: subtitle,
            child: _plainContent(),
          ),
        );

        expect(_textsOf(_section), findsNWidgets(2));
        // No gap is reserved for the missing subtitle.
        expect(
          _rect(tester, _content).top - _rect(tester, _heading).bottom,
          closeTo(CbsSpacing.sm, _epsilon),
        );
      });
    }

    testWidgets('shows the action when it is provided', (tester) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          action: _textButton(),
          child: _plainContent(),
        ),
      );

      expect(_action, findsOneWidget);
      expect(find.text(_actionLabel), findsOneWidget);
      expect(find.descendant(of: _section, matching: _action), findsOneWidget);
    });

    testWidgets('shows the child as provided', (tester) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(title: _title, child: _plainContent()),
      );

      expect(_content, findsOneWidget);
      expect(find.text(_contentText), findsOneWidget);
      expect(find.descendant(of: _section, matching: _content), findsOneWidget);
    });

    testWidgets('keeps the keyed state of the child on rebuild', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: const CbsContentSection(
          title: _title,
          child: _Counter(key: ValueKey('counter')),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('counter')));
      await tester.pump();
      expect(find.text('Count: 1'), findsOneWidget);

      await pumpCbs(
        tester,
        child: const CbsContentSection(
          title: 'Autre titre',
          subtitle: _subtitle,
          child: _Counter(key: ValueKey('counter')),
        ),
      );

      expect(find.text('Autre titre'), findsOneWidget);
      expect(find.text('Count: 1'), findsOneWidget);
    });
  });

  group('CbsSectionHeading reuse', () {
    testWidgets('draws the title with a CbsSectionHeading', (tester) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          subtitle: _subtitle,
          action: _textButton(),
          child: _plainContent(),
        ),
      );

      expect(find.descendant(of: _section, matching: _heading), findsOneWidget);
      expect(tester.widget<CbsSectionHeading>(_heading).title, _title);
      expect(
        find.descendant(of: _heading, matching: find.text(_title)),
        findsOneWidget,
      );
      // The title is drawn once: the subtitle is not a second heading.
      expect(find.text(_title), findsOneWidget);
      expect(
        find.descendant(of: _heading, matching: _subtitleText),
        findsNothing,
      );
    });

    for (final variant in cbsTestThemes) {
      testWidgets('the title keeps the heading style: ${variant.name}', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          theme: variant.theme,
          child: CbsContentSection(
            title: _title,
            subtitle: _subtitle,
            child: _plainContent(),
          ),
        );

        final themeStyle = Theme.of(tester.element(_section))
            .textTheme
            .titleMedium!;
        expect(
          _headingText(tester).style,
          themeStyle.copyWith(fontWeight: FontWeight.w700),
        );
      });
    }

    testWidgets('the title is exposed as a heading', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          subtitle: _subtitle,
          child: _plainContent(),
        ),
      );

      final node = tester.getSemantics(_heading);
      expect(node.flagsCollection.isHeader, isTrue);
      expect(node.label, _title);

      // The subtitle is plain text, not a heading.
      final subtitleNode = tester.getSemantics(_subtitleText);
      expect(subtitleNode.flagsCollection.isHeader, isFalse);
      expect(subtitleNode.label, _subtitle);

      semantics.dispose();
    });
  });

  group('order', () {
    testWidgets('stacks title, subtitle and content from top to bottom', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          subtitle: _subtitle,
          child: _plainContent(),
        ),
      );

      final heading = _rect(tester, _heading);
      final subtitle = _rect(tester, _subtitleText);
      final content = _rect(tester, _content);

      expect(heading.bottom, lessThanOrEqualTo(subtitle.top));
      expect(subtitle.bottom, lessThanOrEqualTo(content.top));
      expect(heading.left, 0);
      expect(subtitle.left, 0);
      expect(content.left, 0);
    });

    testWidgets('places the action at the end edge, centered on the texts', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          subtitle: _subtitle,
          action: _textButton(),
          child: _plainContent(),
        ),
      );

      final heading = _rect(tester, _heading);
      final subtitle = _rect(tester, _subtitleText);
      final action = _rect(tester, _action);
      final content = _rect(tester, _content);

      // End edge (right in a left-to-right language), after the texts.
      expect(action.right, closeTo(600, _epsilon));
      expect(heading.right, closeTo(action.left - CbsSpacing.md, _epsilon));
      expect(subtitle.right, closeTo(heading.right, _epsilon));

      // The title and the subtitle are on the same row as the action,
      // centered together with it.
      final textsCenter = (heading.top + subtitle.bottom) / 2;
      expect(action.center.dy, closeTo(textsCenter, 0.5));
      expect(content.top, greaterThanOrEqualTo(action.bottom));
    });

    testWidgets('mirrors the header in a right-to-left language', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: CbsContentSection(
            title: _title,
            subtitle: _subtitle,
            action: _textButton(),
            child: _plainContent(),
          ),
        ),
      );

      final heading = _rect(tester, _heading);
      final action = _rect(tester, _action);

      // The end edge is the left one.
      expect(action.left, closeTo(0, _epsilon));
      expect(heading.left, closeTo(action.right + CbsSpacing.md, _epsilon));
      expect(heading.right, closeTo(600, _epsilon));
    });

    testWidgets('builds the title, the subtitle, the action and the child '
        'in this order', (tester) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          subtitle: _subtitle,
          action: _textButton(),
          child: _plainContent(),
        ),
      );

      final indices = [
        _treeIndex(tester, _heading),
        _treeIndex(tester, _subtitleText),
        _treeIndex(tester, _action),
        _treeIndex(tester, _content),
      ];
      expect(indices, everyElement(greaterThanOrEqualTo(0)));
      expect(indices, orderedEquals([...indices]..sort()));
      expect(indices.toSet(), hasLength(indices.length));
    });

    testWidgets('exposes the title, the subtitle and then the content to '
        'assistive technologies', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          subtitle: _subtitle,
          child: _plainContent(),
        ),
      );

      final labels = _traversalLabels(tester);
      expect(labels, containsAllInOrder([_title, _subtitle, _contentText]));

      semantics.dispose();
    });

    testWidgets('exposes the action before the content', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          subtitle: _subtitle,
          action: _textButton(),
          child: _plainContent(),
        ),
      );

      final labels = _traversalLabels(tester);
      expect(labels, containsAllInOrder([_title, _subtitle, _contentText]));
      expect(labels, containsAllInOrder([_actionLabel, _contentText]));

      semantics.dispose();
    });
  });

  group('spacing', () {
    testWidgets('adds no outer margin and no inner padding', (tester) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(title: _title, child: _plainContent()),
      );

      final section = _rect(tester, _section);
      final heading = _rect(tester, _heading);
      final content = _rect(tester, _content);

      expect(section.topLeft, Offset.zero);
      expect(section.width, 600);
      expect(heading.topLeft, Offset.zero);
      expect(content.width, 600);
      // No trailing space under the content.
      expect(section.bottom, closeTo(content.bottom, _epsilon));
    });

    testWidgets('separates the title from the content by CbsSpacing.sm', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(title: _title, child: _plainContent()),
      );

      final heading = _rect(tester, _heading);
      final content = _rect(tester, _content);

      expect(content.top - heading.bottom, closeTo(CbsSpacing.sm, _epsilon));
      expect(
        _rect(tester, _section).height,
        closeTo(heading.height + CbsSpacing.sm + content.height, _epsilon),
      );
    });

    testWidgets('separates the title from the subtitle by CbsSpacing.xs and '
        'the subtitle from the content by CbsSpacing.sm', (tester) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          subtitle: _subtitle,
          child: _plainContent(),
        ),
      );

      final heading = _rect(tester, _heading);
      final subtitle = _rect(tester, _subtitleText);
      final content = _rect(tester, _content);

      expect(subtitle.top - heading.bottom, closeTo(CbsSpacing.xs, _epsilon));
      expect(content.top - subtitle.bottom, closeTo(CbsSpacing.sm, _epsilon));
    });

    testWidgets('separates the header with an action from the content by '
        'CbsSpacing.sm', (tester) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          action: _textButton(),
          child: _plainContent(),
        ),
      );

      final action = _rect(tester, _action);
      final heading = _rect(tester, _heading);

      // The action is taller than the title, so it sets the header height.
      expect(action.height, greaterThan(heading.height));
      expect(
        _rect(tester, _content).top - action.bottom,
        closeTo(CbsSpacing.sm, _epsilon),
      );
    });

    for (final scale in cbsTestTextScales) {
      testWidgets('keeps CbsSpacing.sm under the header: text x$scale', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          width: 320,
          textScale: scale,
          child: CbsContentSection(
            title: _longTitle,
            subtitle: _longSubtitle,
            action: _textButton(),
            child: _plainContent(),
          ),
        );

        expect(tester.takeException(), isNull);
        // The header shows the long subtitle, not the default one.
        expect(
          _rect(tester, _content).top -
              _headerBottom(tester, subtitle: _longSubtitle),
          closeTo(CbsSpacing.sm, _epsilon),
        );
      });
    }
  });

  group('subtitle style', () {
    for (final variant in cbsTestThemes) {
      testWidgets('follows bodyMedium and onSurfaceVariant: ${variant.name}', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          theme: variant.theme,
          child: CbsContentSection(
            title: _title,
            subtitle: _subtitle,
            child: _plainContent(),
          ),
        );

        final themeStyle = Theme.of(tester.element(_section))
            .textTheme
            .bodyMedium!;
        final style = tester.widget<Text>(_subtitleText).style!;

        expect(style.fontSize, isNotNull);
        expect(style.fontSize, themeStyle.fontSize);
        expect(style.fontFamily, themeStyle.fontFamily);
        expect(style.fontWeight, themeStyle.fontWeight);
        // Light and dark appearance come from the theme color scheme.
        expect(style.color, variant.theme.colorScheme.onSurfaceVariant);
      });
    }

    testWidgets('Branded typography customizes the subtitle', (tester) async {
      final theme = CbsTheme.branded(
        primaryColor: Colors.green,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontFamily: 'BrandFont', fontSize: 18),
        ),
      );

      await pumpCbs(
        tester,
        theme: theme,
        child: CbsContentSection(
          title: _title,
          subtitle: _subtitle,
          child: _plainContent(),
        ),
      );

      final style = tester.widget<Text>(_subtitleText).style!;
      expect(style.fontFamily, 'BrandFont');
      expect(style.fontSize, 18);
    });
  });

  group('widths', () {
    for (final width in cbsTestWidths) {
      testWidgets('fills the width at $width dp', (tester) async {
        await pumpCbs(
          tester,
          width: width,
          child: CbsContentSection(
            title: _title,
            subtitle: _subtitle,
            action: _textButton(),
            child: _plainContent(),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(_rect(tester, _section).width, width);
        expect(_rect(tester, _content).width, width);
        expect(_rect(tester, _action).right, closeTo(width, _epsilon));
        expect(_rect(tester, _heading).left, 0);
      });
    }

    testWidgets('a long title and subtitle wrap at 320 dp, text x2', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        width: 320,
        textScale: 2,
        child: CbsContentSection(
          title: _longTitle,
          subtitle: _longSubtitle,
          action: _textButton(),
          child: _plainContent(),
        ),
      );

      expect(tester.takeException(), isNull);

      final heading = _headingText(tester);
      expect(heading.overflow, isNull);
      expect(heading.maxLines, isNull);
      // The section shows the long subtitle: the default one is absent.
      final longSubtitleText = find.text(_longSubtitle);
      expect(longSubtitleText, findsOneWidget);
      expect(_subtitleText, findsNothing);
      final subtitle = tester.widget<Text>(longSubtitleText);
      expect(subtitle.maxLines, isNull);
      expect(subtitle.overflow, isNull);

      final singleLine = TextPainter(
        text: TextSpan(text: _longTitle, style: heading.style),
        textDirection: TextDirection.ltr,
        textScaler: const TextScaler.linear(2),
      )..layout();
      expect(singleLine.width, greaterThan(320));
      expect(
        _rect(tester, _heading).height,
        greaterThan(singleLine.height * 2),
      );
      singleLine.dispose();

      final singleSubtitleLine = TextPainter(
        text: TextSpan(text: _longSubtitle, style: subtitle.style),
        textDirection: TextDirection.ltr,
        textScaler: const TextScaler.linear(2),
      )..layout();
      expect(singleSubtitleLine.width, greaterThan(320));
      expect(
        _rect(tester, longSubtitleText).height,
        greaterThan(singleSubtitleLine.height * 2),
      );
      expect(_rect(tester, longSubtitleText).right, lessThanOrEqualTo(320));
      singleSubtitleLine.dispose();

      expect(_rect(tester, _section).width, 320);
      expect(_rect(tester, _heading).right, lessThanOrEqualTo(320));
      expect(_rect(tester, _action).right, closeTo(320, _epsilon));
    });
  });

  group('qualification matrix', () {
    for (final variant in cbsTestThemes) {
      for (final width in cbsTestWidths) {
        for (final scale in cbsTestTextScales) {
          testWidgets(
            'full section without overflow: ${variant.name}, $width dp, '
            'text x$scale',
            (tester) async {
              await pumpCbs(
                tester,
                theme: variant.theme,
                width: width,
                textScale: scale,
                child: _fullSection(title: _longTitle),
              );

              expect(tester.takeException(), isNull);

              final section = _rect(tester, _section);
              final heading = _rect(tester, _heading);
              final subtitle = _rect(tester, _subtitleText);
              final action = _rect(tester, _action);
              final collection = _rect(
                tester,
                find.byType(CbsAdaptiveCollection),
              );

              expect(section.left, 0);
              expect(section.width, width);
              expect(action.right, closeTo(width, _epsilon));
              expect(heading.right, lessThanOrEqualTo(action.left));
              expect(heading.bottom, lessThanOrEqualTo(subtitle.top));
              expect(
                collection.top - _headerBottom(tester),
                closeTo(CbsSpacing.sm, _epsilon),
              );
              expect(collection.width, width);
              expect(section.bottom, closeTo(collection.bottom, _epsilon));
            },
          );
        }
      }
    }
  });

  group('interactions', () {
    testWidgets('the action reacts to taps', (tester) async {
      var presses = 0;
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          subtitle: _subtitle,
          action: _textButton(onPressed: () => presses++),
          child: _plainContent(),
        ),
      );

      await tester.tap(_action);
      await tester.pump();
      await tester.tap(find.text(_actionLabel));
      await tester.pump();

      expect(presses, 2);
    });

    testWidgets('a disabled action stays disabled', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          action: const CbsButton(label: _actionLabel, onPressed: null),
          child: _plainContent(),
        ),
      );

      final button = tester.widget<CbsButton>(find.byType(CbsButton));
      expect(button.onPressed, isNull);
      final node = tester.getSemantics(find.byType(CbsButton));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      expect(tester.takeException(), isNull);

      semantics.dispose();
    });

    testWidgets('the action keeps its semantics inside the section', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await pumpCbs(
        tester,
        child: CbsButton(label: _actionLabel, onPressed: () {}),
      );
      final alone = tester.getSemantics(find.byType(CbsButton));
      final aloneIsButton = alone.flagsCollection.isButton;
      final aloneLabel = alone.label;
      final aloneTap = alone.getSemanticsData().hasAction(SemanticsAction.tap);

      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          action: CbsButton(label: _actionLabel, onPressed: () {}),
          child: _plainContent(),
        ),
      );
      final inside = tester.getSemantics(find.byType(CbsButton));

      expect(aloneIsButton, isTrue);
      expect(aloneTap, isTrue);
      final insideTap = inside.getSemanticsData().hasAction(
        SemanticsAction.tap,
      );
      expect(inside.flagsCollection.isButton, aloneIsButton);
      expect(inside.label, aloneLabel);
      expect(insideTap, aloneTap);

      semantics.dispose();
    });

    testWidgets('the content keeps its interactions', (tester) async {
      var presses = 0;
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          child: CbsButton(label: 'Contenu', onPressed: () => presses++),
        ),
      );

      await tester.tap(find.text('Contenu'));
      await tester.pump();

      expect(presses, 1);
    });

    testWidgets('the action and the content are independent', (tester) async {
      var actions = 0;
      var cards = 0;
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          subtitle: _subtitle,
          action: _textButton(onPressed: () => actions++),
          child: CbsContentCard(
            content: const Text('Carte'),
            onTap: () => cards++,
          ),
        ),
      );

      await tester.tap(find.text('Carte'));
      await tester.pump();
      expect((actions, cards), (0, 1));

      await tester.tap(_action);
      await tester.pump();
      expect((actions, cards), (1, 1));
    });

    testWidgets('the content keeps its semantics and its tap action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          subtitle: _subtitle,
          action: _textButton(),
          child: CbsContentCard(
            content: const Text('Carte'),
            semanticLabel: 'Carte interactive',
            onTap: () {},
          ),
        ),
      );

      final data = tester
          .getSemantics(find.byType(CbsContentCard))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.label, contains('Carte interactive'));
      expect(data.label, contains('Carte'));

      semantics.dispose();
    });

    testWidgets('the action then the content follow the keyboard order', (
      tester,
    ) async {
      const contentButtonKey = ValueKey('content-button');
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          action: _textButton(),
          child: CbsButton(
            key: contentButtonKey,
            label: 'Contenu',
            onPressed: () {},
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(hasPrimaryFocusWithin(tester, _action), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        hasPrimaryFocusWithin(tester, find.byKey(contentButtonKey)),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('composition with VP-01, VP-02 and VP-03', () {
    testWidgets('frames a CbsContentCard under the title', (tester) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(title: _title, child: _card(0, media: false)),
      );

      final heading = _rect(tester, _heading);
      final card = _rect(tester, find.byType(CbsContentCard));

      expect(card.top - heading.bottom, closeTo(CbsSpacing.sm, _epsilon));
      expect(card.width, 600);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a CbsMediaFrame keeps its ratio inside the section', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: const CbsContentSection(
          title: _title,
          subtitle: _subtitle,
          child: CbsMediaFrame(child: ColoredBox(color: Colors.grey)),
        ),
      );

      final frame = _rect(tester, find.byType(CbsMediaFrame));
      expect(frame.width, 600);
      expect(frame.height, closeTo(600 * 9 / 16, 0.001));
      expect(frame.left, 0);
      expect(tester.takeException(), isNull);
    });

    for (final width in cbsTestWidths) {
      testWidgets('a CbsAdaptiveCollection adapts its columns at $width dp', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          width: width,
          child: CbsContentSection(
            title: _title,
            subtitle: _subtitle,
            action: _textButton(),
            child: CbsAdaptiveCollection(
              layout: CbsCollectionLayout.grid,
              children: [for (var i = 0; i < 6; i++) _gridItem(i)],
            ),
          ),
        );

        final firstTop = tester
            .getTopLeft(find.byKey(const ValueKey('item-0')))
            .dy;
        final firstRow = [
          for (var i = 0; i < 6; i++)
            tester.getTopLeft(find.byKey(ValueKey('item-$i'))).dy,
        ].where((top) => (top - firstTop).abs() < 0.001).length;

        expect(firstRow, _gridColumns[width]);
        expect(_rect(tester, find.byType(CbsAdaptiveCollection)).width, width);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('composes a card with media and an action in a grid', (
      tester,
    ) async {
      await pumpCbs(tester, width: 840, child: _fullSection());

      expect(find.byType(CbsContentCard), findsNWidgets(4));
      expect(find.byType(CbsMediaFrame), findsNWidgets(4));

      // Three columns at 840 dp: the cards share the width equally.
      final cell = (840 - 12 * 2) / 3;
      expect(
        _rect(tester, find.byKey(const ValueKey('card-0'))).width,
        closeTo(cell, 0.001),
      );
      expect(
        _rect(tester, find.byKey(const ValueKey('frame-0'))).width,
        closeTo(cell, 0.001),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('nested sections keep their own headings and spacing', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          child: CbsContentSection(
            title: 'Sous-section',
            subtitle: _subtitle,
            child: _plainContent(),
          ),
        ),
      );

      expect(_heading, findsNWidgets(2));
      final outer = _rect(tester, _heading.first);
      final inner = _rect(tester, find.text('Sous-section'));
      expect(inner.top - outer.bottom, closeTo(CbsSpacing.sm, _epsilon));
      expect(tester.takeException(), isNull);
    });
  });

  group('no internal scroll', () {
    testWidgets('does not build a scrollable of its own', (tester) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          subtitle: _subtitle,
          action: _textButton(),
          child: _plainContent(),
        ),
      );

      expect(
        find.descendant(of: _section, matching: find.byType(Scrollable)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _section,
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
    });

    testWidgets('is as tall as its content and lets a parent scroll', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: _title,
          child: _plainContent(height: 3000),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(_rect(tester, _content).height, 3000);
      expect(
        _rect(tester, _section).height,
        closeTo(
          _rect(tester, _heading).height + CbsSpacing.sm + 3000,
          _epsilon,
        ),
      );
    });
  });
}

/// Counter whose state must survive a rebuild of its section.
class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => setState(() => count++),
      child: Text('Count: $count'),
    );
  }
}
