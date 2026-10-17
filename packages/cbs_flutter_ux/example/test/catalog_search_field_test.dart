import 'dart:ui' show SemanticsAction, Tristate;

import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cbs_flutter_ux_example/catalog/catalog_entries.dart';
import 'package:cbs_flutter_ux_example/catalog/catalog_keys.dart';
import 'package:cbs_flutter_ux_example/catalog/catalog_scenario.dart';
import 'package:cbs_flutter_ux_example/catalog/sections/search_field_section.dart';
import 'package:cbs_flutter_ux_example/main.dart';

import 'catalog_test_helpers.dart';

// D05 VP-06: the "search-field" section of the catalog. Assertions target a
// labelled demonstration by `Key`; they never rely on global widget counts
// and never use `pumpAndSettle` (the indeterminate loading indicators of the
// page animate forever).

/// Demonstrations of the "search-field" section, in display order.
const _demoIds = <String>[
  'search-empty',
  'search-interactive',
  'search-prefilled',
  'search-clear',
  'search-disabled',
  'search-submit',
  'search-long',
  'search-long-text',
];

/// Sections of the catalog before VP-06, in display order.
const _previousSectionIds = <String>[
  'buttons',
  'loading',
  'feedback',
  'state-panel',
  'retry-message',
  'section-heading',
  'application-states',
  'content-card',
  'media-frame',
  'adaptive-collection',
  'content-section',
  'category-selector',
];

const _narrowLargeText = CatalogScenario(textScale: CatalogTextScale.x2);

Future<void> _pump(
  WidgetTester tester, [
  CatalogScenario scenario = CatalogScenario.initial,
]) async {
  await tester.pumpWidget(CbsUxShowcase(initialScenario: scenario));
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _search(String demoId) => inDemo(demoId, find.byType(CbsSearchField));

Finder _input(String demoId) => inDemo(demoId, find.byType(TextField));

Finder _clear(String demoId) =>
    inDemo(demoId, find.widgetWithIcon(IconButton, Icons.clear));

TextField _nativeInput(WidgetTester tester, String demoId) =>
    tester.widget<TextField>(_input(demoId));

Future<void> _enterText(WidgetTester tester, String demoId, String text) async {
  await tester.ensureVisible(_input(demoId));
  await tester.pump();
  await tester.enterText(_input(demoId), text);
  await tester.pump();
}

Future<void> _tapClear(WidgetTester tester, String demoId) {
  return tapVisible(tester, _clear(demoId));
}

void main() {
  group('search field section', () {
    testWidgets('is the last entry of the catalog, once, with its title', (
      tester,
    ) async {
      expect(catalogEntries.last.id, 'search-field');
      expect(catalogEntries.last.title, 'Search field');

      await _pump(tester);

      expect(find.byKey(CatalogKeys.section('search-field')), findsOneWidget);
      expect(find.text('Search field'), findsOneWidget);
    });

    testWidgets('keeps the previous sections, in their order', (tester) async {
      expect(catalogEntries.length, _previousSectionIds.length + 1);
      expect(
        catalogEntries.take(_previousSectionIds.length).map((e) => e.id),
        _previousSectionIds,
      );
      expect(catalogEntries.map((e) => e.id).toSet(), hasLength(13));
    });

    testWidgets('shows every labelled demonstration exactly once', (
      tester,
    ) async {
      await _pump(tester);

      for (final id in _demoIds) {
        expect(find.byKey(CatalogKeys.demo(id)), findsOneWidget, reason: id);
        expect(_search(id), findsOneWidget, reason: id);
        expect(_input(id), findsOneWidget, reason: id);
      }
      expect(
        inSection('search-field', find.byType(CbsSearchField)),
        findsNWidgets(_demoIds.length),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('builds only the native text field, without any backend '
        'widget', (tester) async {
      await _pump(tester);

      expect(
        inSection('search-field', find.byType(TextField)),
        findsNWidgets(_demoIds.length),
      );
      expect(inSection('search-field', find.byType(SearchBar)), findsNothing);
      expect(
        inSection('search-field', find.byType(SearchAnchor)),
        findsNothing,
      );
      expect(
        inSection('search-field', find.byType(ListTile)),
        findsNothing,
        reason: 'no suggestion list',
      );
    });
  });

  group('empty field demonstration', () {
    testWidgets('shows the hint and the search icon, with no clear action', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        inDemo('search-empty', find.text(SearchFieldSection.hint)),
        findsOneWidget,
      );
      expect(inDemo('search-empty', find.byIcon(Icons.search)), findsOneWidget);
      expect(_clear('search-empty'), findsNothing);
    });

    testWidgets('exposes its semantic label', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      final node = tester.getSemantics(_input('search-empty'));
      expect(node.flagsCollection.isTextField, isTrue);
      expect(node.label, contains(SearchFieldSection.emptySemanticLabel));
      expect(
        tester.widget<CbsSearchField>(_search('search-empty')).semanticLabel,
        SearchFieldSection.emptySemanticLabel,
      );
      handle.dispose();
    });
  });

  group('interactive demonstration', () {
    testWidgets('reports each edit, and shows the clear action while there is '
        'a text', (tester) async {
      await _pump(tester);
      expect(
        counterText(tester, 'search-interactive'),
        SearchFieldSection.changesText(0, ''),
      );
      expect(_clear('search-interactive'), findsNothing);

      await _enterText(tester, 'search-interactive', 'jazz');

      expect(
        counterText(tester, 'search-interactive'),
        SearchFieldSection.changesText(1, 'jazz'),
      );
      expect(_clear('search-interactive'), findsOneWidget);

      await _enterText(tester, 'search-interactive', 'jazz night');

      expect(
        counterText(tester, 'search-interactive'),
        SearchFieldSection.changesText(2, 'jazz night'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('clearing empties the text and reports it', (tester) async {
      await _pump(tester);
      await _enterText(tester, 'search-interactive', 'jazz');

      await _tapClear(tester, 'search-interactive');

      expect(
        counterText(tester, 'search-interactive'),
        SearchFieldSection.changesText(2, ''),
      );
      expect(_nativeInput(tester, 'search-interactive').controller!.text, '');
      expect(_clear('search-interactive'), findsNothing);
    });

    testWidgets('the demonstrations keep independent texts', (tester) async {
      await _pump(tester);

      await _enterText(tester, 'search-interactive', 'jazz');

      expect(
        counterText(tester, 'search-submit'),
        SearchFieldSection.submittedText(null),
      );
      expect(
        counterText(tester, 'search-prefilled'),
        SearchFieldSection.controllerText(SearchFieldSection.prefilledText),
      );
      expect(_nativeInput(tester, 'search-empty').controller!.text, '');
    });
  });

  group('prefilled demonstration', () {
    testWidgets('shows the text of its external controller and the clear '
        'action', (tester) async {
      await _pump(tester);

      expect(
        counterText(tester, 'search-prefilled'),
        SearchFieldSection.controllerText(SearchFieldSection.prefilledText),
      );
      expect(
        inDemo('search-prefilled', find.text(SearchFieldSection.prefilledText)),
        findsOneWidget,
      );
      expect(_clear('search-prefilled'), findsOneWidget);
    });

    testWidgets('follows a text set from outside the field', (tester) async {
      await _pump(tester);

      await tapVisible(
        tester,
        inDemo(
          'search-prefilled',
          find.text(SearchFieldSection.replaceButtonLabel),
        ),
      );

      expect(
        counterText(tester, 'search-prefilled'),
        SearchFieldSection.controllerText(SearchFieldSection.replacementText),
      );
      expect(
        inDemo(
          'search-prefilled',
          find.text(SearchFieldSection.replacementText),
        ),
        findsOneWidget,
      );
      expect(_clear('search-prefilled'), findsOneWidget);
    });

    testWidgets('clearing empties the external controller', (tester) async {
      await _pump(tester);

      await _tapClear(tester, 'search-prefilled');

      expect(
        counterText(tester, 'search-prefilled'),
        SearchFieldSection.controllerText(''),
      );
      expect(_clear('search-prefilled'), findsNothing);
    });
  });

  group('clear demonstration', () {
    testWidgets('empties the text, reports it, then calls onClear', (
      tester,
    ) async {
      await _pump(tester);
      expect(
        counterText(tester, 'search-clear'),
        SearchFieldSection.clearText(0, 0, SearchFieldSection.prefilledText),
      );

      await _tapClear(tester, 'search-clear');

      expect(
        counterText(tester, 'search-clear'),
        SearchFieldSection.clearText(1, 1, ''),
      );
      expect(_nativeInput(tester, 'search-clear').controller!.text, '');
      expect(_clear('search-clear'), findsNothing);
    });

    testWidgets('can be filled and cleared again', (tester) async {
      await _pump(tester);
      await _tapClear(tester, 'search-clear');

      await _enterText(tester, 'search-clear', 'opera');
      expect(
        counterText(tester, 'search-clear'),
        SearchFieldSection.clearText(1, 2, 'opera'),
      );

      await _tapClear(tester, 'search-clear');
      expect(
        counterText(tester, 'search-clear'),
        SearchFieldSection.clearText(2, 3, ''),
      );
    });
  });

  group('disabled demonstration', () {
    testWidgets('is disabled, keeps its text and has an inert clear action', (
      tester,
    ) async {
      await _pump(tester);

      expect(_nativeInput(tester, 'search-disabled').enabled, isFalse);
      expect(
        tester.widget<CbsSearchField>(_search('search-disabled')).enabled,
        isFalse,
      );
      expect(
        inDemo('search-disabled', find.text(SearchFieldSection.prefilledText)),
        findsOneWidget,
      );
      expect(_clear('search-disabled'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              inDemo('search-disabled', find.byType(IconButton)),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('ignores taps and does not take the focus', (tester) async {
      await _pump(tester);
      await tester.ensureVisible(_input('search-disabled'));
      await tester.pump();

      await tester.tap(_input('search-disabled'), warnIfMissed: false);
      await tester.tap(_clear('search-disabled'), warnIfMissed: false);
      await tester.pump();

      expect(
        _nativeInput(tester, 'search-disabled').focusNode!.hasFocus,
        isFalse,
      );
      expect(
        _nativeInput(tester, 'search-disabled').controller!.text,
        SearchFieldSection.prefilledText,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('is exposed as a disabled text field', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      final node = tester.getSemantics(
        find
            .descendant(
              of: _input('search-disabled'),
              matching: find.byType(EditableText),
            )
            .first,
      );
      expect(node.flagsCollection.isTextField, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });
  });

  group('submit demonstration', () {
    testWidgets('reports the text when the keyboard submits it', (
      tester,
    ) async {
      await _pump(tester);
      expect(
        counterText(tester, 'search-submit'),
        SearchFieldSection.submittedText(null),
      );

      await _enterText(tester, 'search-submit', 'opera');
      expect(
        counterText(tester, 'search-submit'),
        SearchFieldSection.submittedText(null),
        reason: 'typing alone does not submit',
      );

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(
        counterText(tester, 'search-submit'),
        SearchFieldSection.submittedText('opera'),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('long demonstrations', () {
    testWidgets('a long hint keeps the height of the field at 320 px', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        _nativeInput(tester, 'search-long').decoration!.hintText,
        SearchFieldSection.longHint,
      );
      expect(
        tester.getSize(_search('search-long')),
        tester.getSize(_search('search-empty')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long text keeps the height of the field at 320 px', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        _nativeInput(tester, 'search-long-text').controller!.text,
        SearchFieldSection.longText,
      );
      expect(
        tester.getSize(_search('search-long-text')),
        tester.getSize(_search('search-empty')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('both stay on one line at 320 px, text x2', (tester) async {
      await _pump(tester, _narrowLargeText);

      for (final id in ['search-long', 'search-long-text']) {
        expect(_nativeInput(tester, id).maxLines, 1, reason: id);
        expect(
          tester.getSize(_search(id)).height,
          tester.getSize(_search('search-empty')).height,
          reason: id,
        );
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('widths, text scales and themes', () {
    for (final width in CatalogWidth.values) {
      testWidgets('every field fits the width and nothing overflows at '
          '${width.label}', (tester) async {
        await _pump(tester, CatalogScenario(width: width));

        for (final id in _demoIds) {
          expect(
            tester.getSize(_search(id)).width,
            width.logicalPixels,
            reason: id,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('does not overflow at 320 px, text x2', (tester) async {
      await _pump(tester, _narrowLargeText);

      expect(tester.takeException(), isNull);
      for (final id in _demoIds) {
        expect(
          tester.getSize(_search(id)).width,
          CatalogWidth.w320.logicalPixels,
          reason: id,
        );
      }
    });

    testWidgets('the fields grow with the text scale', (tester) async {
      await _pump(tester);
      final x1 = tester.getSize(_search('search-empty')).height;

      await selectOption(
        tester,
        CatalogKeys.textScaleOption(CatalogTextScale.x2),
      );
      final x2 = tester.getSize(_search('search-empty')).height;

      expect(x2, greaterThan(x1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the texts survive scenario changes', (tester) async {
      await _pump(tester);
      await _enterText(tester, 'search-interactive', 'jazz');
      await _tapClear(tester, 'search-clear');

      await selectOption(tester, CatalogKeys.widthOption(CatalogWidth.w840));
      await selectOption(
        tester,
        CatalogKeys.designOption(CatalogDesign.branded),
      );
      await selectOption(
        tester,
        CatalogKeys.appearanceOption(CatalogAppearance.dark),
      );

      expect(
        counterText(tester, 'search-interactive'),
        SearchFieldSection.changesText(1, 'jazz'),
      );
      expect(
        counterText(tester, 'search-clear'),
        SearchFieldSection.clearText(1, 1, ''),
      );
      expect(tester.takeException(), isNull);
    });

    for (final design in CatalogDesign.values) {
      for (final appearance in CatalogAppearance.values) {
        testWidgets('every field gets the ${design.label} ${appearance.label} '
            'theme', (tester) async {
          final scenario = CatalogScenario(
            design: design,
            appearance: appearance,
          );
          await _pump(tester, scenario);
          final expected = scenario.buildTheme();

          for (final id in _demoIds) {
            final theme = Theme.of(tester.element(_search(id)));
            expect(theme.colorScheme, expected.colorScheme, reason: id);
            expect(theme.brightness, appearance.brightness, reason: id);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the fields work in dark Branded', (tester) async {
      await _pump(
        tester,
        const CatalogScenario(
          design: CatalogDesign.branded,
          appearance: CatalogAppearance.dark,
        ),
      );

      await _enterText(tester, 'search-interactive', 'jazz');
      await _tapClear(tester, 'search-interactive');

      expect(
        counterText(tester, 'search-interactive'),
        SearchFieldSection.changesText(2, ''),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
