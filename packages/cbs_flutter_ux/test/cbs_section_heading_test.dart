import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cbs_test_matrix.dart';

const String _title = 'À la une';
const String _longTitle =
    'Un titre de section volontairement très long qui doit passer à la '
    'ligne sur une largeur compacte avec un facteur de texte agrandi sans '
    'jamais provoquer de dépassement';

/// Reproduction of the CURRENT AMH-USR Home section heading (Featured,
/// Categories, Nearby, Upcoming), used as the equivalence reference.
/// The `SizedBox(height: CbsSpacing.sm)` that follows it in Home belongs to
/// the consumer layout and is not part of the heading.
Widget _currentHomeHeading(BuildContext context, String title) {
  final theme = Theme.of(context);
  return Semantics(
    header: true,
    child: Text(
      title,
      key: const ValueKey('current-home-heading'),
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

Text _headingText(WidgetTester tester) => tester.widget<Text>(
  find.descendant(
    of: find.byType(CbsSectionHeading),
    matching: find.byType(Text),
  ),
);

void main() {
  testWidgets('renders the provided title', (tester) async {
    await pumpCbs(tester, child: const CbsSectionHeading(title: _title));

    expect(find.byType(CbsSectionHeading), findsOneWidget);
    expect(find.text(_title), findsOneWidget);
  });

  testWidgets('renders only the title: no description, icon or action', (
    tester,
  ) async {
    await pumpCbs(tester, child: const CbsSectionHeading(title: 'Heading'));

    expect(
      find.descendant(
        of: find.byType(CbsSectionHeading),
        matching: find.byType(Text),
      ),
      findsOneWidget,
    );
    expect(_headingText(tester).data, 'Heading');
    for (final type in [Icon, ButtonStyleButton, InkResponse, Row]) {
      expect(
        find.descendant(
          of: find.byType(CbsSectionHeading),
          matching: find.byElementPredicate(
            (element) => element.widget.runtimeType == type,
          ),
        ),
        findsNothing,
        reason: '$type must not be part of the heading',
      );
    }
  });

  testWidgets('is exposed as a semantics header carrying the title', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await pumpCbs(tester, child: const CbsSectionHeading(title: _title));

    final node = tester.getSemantics(find.byType(CbsSectionHeading));
    expect(node.flagsCollection.isHeader, isTrue);
    expect(node.label, _title);
    expect(find.bySemanticsLabel(_title), findsOneWidget);

    semantics.dispose();
  });

  for (final variant in cbsTestThemes) {
    testWidgets('style follows titleMedium w700: ${variant.name}', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        theme: variant.theme,
        child: const CbsSectionHeading(title: _title),
      );

      // The effective theme is the one the app localizes from the
      // configured ThemeData.
      final themeStyle = Theme.of(
        tester.element(find.byType(CbsSectionHeading)),
      ).textTheme.titleMedium!;
      final style = _headingText(tester).style!;

      expect(style.fontSize, isNotNull);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.fontSize, themeStyle.fontSize);
      expect(style.fontFamily, themeStyle.fontFamily);
      expect(style.letterSpacing, themeStyle.letterSpacing);
      expect(style.height, themeStyle.height);
      expect(style.color, themeStyle.color);
      // Light and dark appearance come from the theme color scheme.
      expect(style.color, variant.theme.colorScheme.onSurface);
      expect(style, themeStyle.copyWith(fontWeight: FontWeight.w700));
    });
  }

  testWidgets('Branded typography customizes the heading style', (
    tester,
  ) async {
    final theme = CbsTheme.branded(
      primaryColor: Colors.green,
      textTheme: const TextTheme(
        titleMedium: TextStyle(
          fontFamily: 'BrandFont',
          fontSize: 22,
          fontWeight: FontWeight.w400,
        ),
      ),
    );

    await pumpCbs(
      tester,
      theme: theme,
      child: const CbsSectionHeading(title: _title),
    );

    final style = _headingText(tester).style!;
    expect(style.fontFamily, 'BrandFont');
    expect(style.fontSize, 22);
    // The weight is imposed by the heading, not by the theme.
    expect(style.fontWeight, FontWeight.w700);
  });

  for (final scale in cbsTestTextScales) {
    testWidgets(
      'long title at width 320 wraps without overflow: text x$scale',
      (tester) async {
        await pumpCbs(
          tester,
          width: 320,
          textScale: scale,
          child: const CbsSectionHeading(title: _longTitle),
        );

        expect(tester.takeException(), isNull);

        final rect = tester.getRect(find.byType(CbsSectionHeading));
        expect(rect.left, 0);
        expect(rect.width, lessThanOrEqualTo(320));

        // The title wraps instead of being clipped or truncated.
        final text = _headingText(tester);
        expect(text.overflow, isNull);
        expect(text.maxLines, isNull);
        final singleLine = TextPainter(
          text: TextSpan(text: _longTitle, style: text.style),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(scale),
        )..layout();
        expect(singleLine.width, greaterThan(320));
        expect(rect.height, greaterThan(singleLine.height));
        singleLine.dispose();
      },
    );
  }

  testWidgets('adds no external spacing', (tester) async {
    await pumpCbs(
      tester,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CbsSectionHeading(title: _title),
          SizedBox(key: ValueKey('next'), height: 10, width: 10),
        ],
      ),
    );

    final heading = tester.getRect(find.byType(CbsSectionHeading));
    final text = tester.getRect(find.text(_title));
    final next = tester.getRect(find.byKey(const ValueKey('next')));

    // The heading occupies exactly its text: no padding, margin or gap.
    expect(heading, text);
    expect(heading.topLeft, Offset.zero);
    expect(next.top, heading.bottom);

    // No layout widget that could add spacing is built by the heading.
    for (final type in [Padding, SizedBox, Align, Center, Container]) {
      expect(
        find.descendant(
          of: find.byType(CbsSectionHeading),
          matching: find.byElementPredicate(
            (element) => element.widget.runtimeType == type,
          ),
        ),
        findsNothing,
        reason: '$type must not be part of the heading',
      );
    }
  });

  for (final variant in cbsTestThemes) {
    testWidgets('equals the CURRENT Home heading: ${variant.name}, '
        'width 320, text x2', (tester) async {
      await pumpCbs(
        tester,
        theme: variant.theme,
        width: 320,
        textScale: 2,
        child: Builder(
          builder: (context) => _currentHomeHeading(context, _longTitle),
        ),
      );
      final currentFinder = find.byKey(const ValueKey('current-home-heading'));
      final currentRect = tester.getRect(currentFinder);
      final currentStyle = tester.widget<Text>(currentFinder).style;

      final semantics = tester.ensureSemantics();
      final currentNode = tester.getSemantics(currentFinder);
      final currentHeader = currentNode.flagsCollection.isHeader;
      final currentLabel = currentNode.label;
      semantics.dispose();

      await pumpCbs(
        tester,
        theme: variant.theme,
        width: 320,
        textScale: 2,
        child: const CbsSectionHeading(title: _longTitle),
      );
      final handle = tester.ensureSemantics();
      final node = tester.getSemantics(find.byType(CbsSectionHeading));

      expect(tester.getRect(find.byType(CbsSectionHeading)), currentRect);
      expect(_headingText(tester).style, currentStyle);
      expect(node.flagsCollection.isHeader, currentHeader);
      expect(node.label, currentLabel);

      handle.dispose();
    });
  }

  testWidgets('composes with existing resources under consumer spacing', (
    tester,
  ) async {
    await pumpCbs(
      tester,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CbsSectionHeading(title: _title),
          SizedBox(height: CbsSpacing.sm),
          CbsStatePanel(child: Text('Aucun contenu')),
        ],
      ),
    );

    final heading = tester.getRect(find.byType(CbsSectionHeading));
    final panel = tester.getRect(find.byType(CbsStatePanel));

    // The 8 logical pixel gap of Home comes from the consumer layout.
    expect(panel.top - heading.bottom, CbsSpacing.sm);
    expect(panel.width, 600);
  });
}
