import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cbs_flutter_ux_example/catalog/catalog_entries.dart';
import 'package:cbs_flutter_ux_example/catalog/catalog_keys.dart';
import 'package:cbs_flutter_ux_example/catalog/catalog_scenario.dart';
import 'package:cbs_flutter_ux_example/catalog/sections/category_selector_section.dart';
import 'package:cbs_flutter_ux_example/main.dart';

import 'catalog_test_helpers.dart';

// D05 VP-05: the "category-selector" section of the catalog. Assertions
// target a labelled demonstration by `Key`; they never rely on global widget
// counts and never use `pumpAndSettle` (the indeterminate loading indicators
// of the page animate forever).

/// Demonstrations of the "category-selector" section, in display order.
const _demoIds = <String>[
  'category-single',
  'category-multiple',
  'category-disabled',
  'category-empty',
  'category-preselected',
  'category-long',
  'category-full',
];

const _single = 'category-single';
const _disabled = 'category-disabled';

const _narrowLargeText = CatalogScenario(textScale: CatalogTextScale.x2);

Future<void> _pump(
  WidgetTester tester, [
  CatalogScenario scenario = CatalogScenario.initial,
]) async {
  await tester.pumpWidget(CbsUxShowcase(initialScenario: scenario));
  await tester.pump(const Duration(milliseconds: 300));
}

Finder _selector(String demoId) =>
    inDemo(demoId, find.byType(CbsCategorySelector<String>));

Finder _chip(String demoId, Type type, String label) =>
    inDemo(demoId, find.widgetWithText(type, label));

bool _isSelected(WidgetTester tester, String demoId, Type type, String label) {
  final chip = tester.widget(_chip(demoId, type, label));
  return chip is ChoiceChip ? chip.selected : (chip as FilterChip).selected;
}

ValueChanged<bool>? _onSelected(
  WidgetTester tester,
  String demoId,
  Type type,
  String label,
) {
  final chip = tester.widget(_chip(demoId, type, label));
  return chip is ChoiceChip ? chip.onSelected : (chip as FilterChip).onSelected;
}

Future<void> _tapChip(WidgetTester tester, String demoId, String label) {
  return tapVisible(tester, inDemo(demoId, find.text(label)));
}

Finder _selectorScrollable(String demoId) =>
    find.descendant(of: _selector(demoId), matching: find.byType(Scrollable));

void main() {
  group('category selector section', () {
    testWidgets('appears once before search field, with its title', (
      tester,
    ) async {
      final categoryEntries = catalogEntries
          .where((entry) => entry.id == 'category-selector')
          .toList();

      expect(categoryEntries, hasLength(1));
      expect(categoryEntries.single.title, 'Category selector');

      final categoryIndex = catalogEntries.indexWhere(
        (entry) => entry.id == 'category-selector',
      );
      final searchIndex = catalogEntries.indexWhere(
        (entry) => entry.id == 'search-field',
      );

      expect(searchIndex, greaterThan(categoryIndex));

      await _pump(tester);

      expect(
        find.byKey(CatalogKeys.section('category-selector')),
        findsOneWidget,
      );
      expect(find.text('Category selector'), findsOneWidget);
    });

    testWidgets('shows every labelled demonstration exactly once', (
      tester,
    ) async {
      await _pump(tester);

      for (final id in _demoIds) {
        expect(find.byKey(CatalogKeys.demo(id)), findsOneWidget, reason: id);
        expect(_selector(id), findsOneWidget, reason: id);
      }
      expect(
        inSection(
          'category-selector',
          find.byType(CbsCategorySelector<String>),
        ),
        findsNWidgets(_demoIds.length),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('uses ChoiceChip for single and FilterChip for multiple', (
      tester,
    ) async {
      await _pump(tester);

      for (final (id, count) in [
        ('category-single', CategorySelectorSection.singleCategories.length),
        ('category-long', CategorySelectorSection.longCategories.length),
      ]) {
        expect(inDemo(id, find.byType(ChoiceChip)), findsNWidgets(count));
        expect(inDemo(id, find.byType(FilterChip)), findsNothing);
        expect(
          tester.widget<CbsCategorySelector<String>>(_selector(id)).mode,
          CbsCategorySelectionMode.single,
          reason: id,
        );
      }
      for (final (id, count) in [
        ('category-multiple', CategorySelectorSection.categories.length),
        (
          'category-disabled',
          CategorySelectorSection.disabledCategories.length,
        ),
        ('category-empty', CategorySelectorSection.categories.length),
        ('category-preselected', CategorySelectorSection.categories.length),
        ('category-full', CategorySelectorSection.fullCategories.length),
      ]) {
        expect(inDemo(id, find.byType(FilterChip)), findsNWidgets(count));
        expect(inDemo(id, find.byType(ChoiceChip)), findsNothing);
        expect(
          tester.widget<CbsCategorySelector<String>>(_selector(id)).mode,
          CbsCategorySelectionMode.multiple,
          reason: id,
        );
      }
    });
  });

  group('single selection demonstration', () {
    testWidgets('starts empty, then keeps exactly one selected category', (
      tester,
    ) async {
      await _pump(tester);
      expect(counterText(tester, 'category-single'), 'Selected: none');

      await _tapChip(tester, 'category-single', 'Sport');
      expect(counterText(tester, 'category-single'), 'Selected: Sport');

      await _tapChip(tester, 'category-single', 'Cinema');
      expect(counterText(tester, 'category-single'), 'Selected: Cinema');
      expect(_isSelected(tester, _single, ChoiceChip, 'Sport'), isFalse);
      expect(_isSelected(tester, _single, ChoiceChip, 'Cinema'), isTrue);

      // A selected category stays selected when activated again.
      await _tapChip(tester, 'category-single', 'Cinema');
      expect(counterText(tester, 'category-single'), 'Selected: Cinema');
      expect(_isSelected(tester, _single, ChoiceChip, 'Cinema'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('exposes the semantic label of the category that has one', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      expect(
        tester
            .widget<CbsCategorySelector<String>>(_selector('category-single'))
            .options
            .where((o) => o.semanticLabel != null)
            .map((o) => o.semanticLabel),
        [CategorySelectorSection.cinemaSemanticLabel],
      );
      expect(
        find.bySemanticsLabel(CategorySelectorSection.cinemaSemanticLabel),
        findsWidgets,
      );
      handle.dispose();
    });
  });

  group('multiple selection demonstration', () {
    testWidgets('adds and removes categories', (tester) async {
      await _pump(tester);
      expect(counterText(tester, 'category-multiple'), 'Selected: none');

      await _tapChip(tester, 'category-multiple', 'Music');
      await _tapChip(tester, 'category-multiple', 'Sport');
      expect(
        counterText(tester, 'category-multiple'),
        'Selected: Music, Sport',
      );

      await _tapChip(tester, 'category-multiple', 'Music');
      expect(counterText(tester, 'category-multiple'), 'Selected: Sport');

      await _tapChip(tester, 'category-multiple', 'Sport');
      expect(counterText(tester, 'category-multiple'), 'Selected: none');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the demonstrations keep independent selections', (
      tester,
    ) async {
      await _pump(tester);

      await _tapChip(tester, 'category-multiple', 'Dance');

      expect(counterText(tester, 'category-multiple'), 'Selected: Dance');
      expect(counterText(tester, 'category-single'), 'Selected: none');
      expect(
        counterText(tester, 'category-preselected'),
        'Selected: Sport, Theatre',
      );
    });
  });

  group('disabled, empty and preexisting selections', () {
    testWidgets('disabled categories are visible, inert and keep their '
        'selection', (tester) async {
      await _pump(tester);
      expect(
        counterText(tester, 'category-disabled'),
        'Selected: Sport, Cinema',
      );

      for (final label in ['Cinema', 'Theatre']) {
        expect(
          inDemo('category-disabled', find.text(label)),
          findsOneWidget,
          reason: label,
        );
        expect(
          _onSelected(tester, 'category-disabled', FilterChip, label),
          isNull,
          reason: label,
        );
        await _tapChip(tester, 'category-disabled', label);
      }
      expect(
        counterText(tester, 'category-disabled'),
        'Selected: Sport, Cinema',
      );
      expect(_isSelected(tester, _disabled, FilterChip, 'Cinema'), isTrue);
      expect(_isSelected(tester, _disabled, FilterChip, 'Theatre'), isFalse);

      // Enabled categories keep working, and the disabled selection stays.
      await _tapChip(tester, 'category-disabled', 'Sport');
      expect(counterText(tester, 'category-disabled'), 'Selected: Cinema');
      await _tapChip(tester, 'category-disabled', 'Music');
      expect(
        counterText(tester, 'category-disabled'),
        'Selected: Music, Cinema',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty selection that the parent does not apply stays '
        'empty', (tester) async {
      await _pump(tester);
      expect(
        counterText(tester, 'category-empty'),
        CategorySelectorSection.requestsText(0),
      );

      await _tapChip(tester, 'category-empty', 'Music');
      await _tapChip(tester, 'category-empty', 'Sport');

      expect(
        counterText(tester, 'category-empty'),
        CategorySelectorSection.requestsText(2),
      );
      for (final option in CategorySelectorSection.categories) {
        expect(
          _isSelected(tester, 'category-empty', FilterChip, option.label),
          isFalse,
          reason: option.label,
        );
      }
    });

    testWidgets('a preexisting selection is shown and can be changed', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        counterText(tester, 'category-preselected'),
        'Selected: Sport, Theatre',
      );
      for (final (label, selected) in [
        ('Music', false),
        ('Sport', true),
        ('Cinema', false),
        ('Theatre', true),
        ('Dance', false),
      ]) {
        expect(
          _isSelected(tester, 'category-preselected', FilterChip, label),
          selected,
          reason: label,
        );
      }

      await _tapChip(tester, 'category-preselected', 'Sport');
      expect(counterText(tester, 'category-preselected'), 'Selected: Theatre');
    });
  });

  group('long label demonstration', () {
    testWidgets('keeps the label on one line and scrolls horizontally at '
        '320 px', (tester) async {
      await _pump(tester);

      final label = inDemo(
        'category-long',
        find.text(CategorySelectorSection.longLabel),
      );
      expect(label, findsOneWidget);
      expect(tester.getSize(label).width, greaterThan(320));
      expect(
        tester.getSize(_selector('category-long')).width,
        CatalogWidth.w320.logicalPixels,
      );
      expect(
        tester
            .state<ScrollableState>(_selectorScrollable('category-long'))
            .position
            .maxScrollExtent,
        greaterThan(0),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a category after the long label can be reached and '
        'selected', (tester) async {
      await _pump(tester);

      await _tapChip(tester, 'category-long', 'Sport');

      expect(counterText(tester, 'category-long'), 'Selected: Sport');
      expect(tester.takeException(), isNull);
    });
  });

  group('complete presentation', () {
    testWidgets('composes a section, the selector and the cards it filters', (
      tester,
    ) async {
      await _pump(tester);

      final section = inDemo('category-full', find.byType(CbsContentSection));
      expect(section, findsOneWidget);
      expect(
        tester.widget<CbsContentSection>(section).title,
        CategorySelectorSection.fullTitle,
      );
      expect(
        tester.widget<CbsContentSection>(section).subtitle,
        CategorySelectorSection.fullSubtitle,
      );
      expect(
        inDemo('category-full', find.byType(CbsAdaptiveCollection)),
        findsOneWidget,
      );

      // Heading, then selector, then cards.
      final heading = tester.getRect(
        inDemo('category-full', find.byType(CbsSectionHeading)),
      );
      final selector = tester.getRect(_selector('category-full'));
      final collection = tester.getRect(
        inDemo('category-full', find.byType(CbsAdaptiveCollection)),
      );
      expect(selector.top, greaterThan(heading.bottom));
      expect(collection.top, greaterThan(selector.bottom));
    });

    testWidgets('filters the cards with the selected categories', (
      tester,
    ) async {
      await _pump(tester, const CatalogScenario(width: CatalogWidth.w1280));
      Finder cards() => inDemo('category-full', find.byType(CbsContentCard));

      expect(cards(), findsNWidgets(CategorySelectorSection.fullCards.length));
      expect(
        counterText(tester, 'category-full'),
        CategorySelectorSection.cardsText(5),
      );

      await _tapChip(tester, 'category-full', 'Music');
      expect(cards(), findsNWidgets(2));
      expect(inDemo('category-full', find.text('Concert')), findsOneWidget);
      expect(inDemo('category-full', find.text('Recital')), findsOneWidget);
      expect(inDemo('category-full', find.text('Match')), findsNothing);
      expect(
        counterText(tester, 'category-full'),
        CategorySelectorSection.cardsText(2),
      );

      await _tapChip(tester, 'category-full', 'Sport');
      expect(cards(), findsNWidgets(3));

      await _tapChip(tester, 'category-full', 'Music');
      await _tapChip(tester, 'category-full', 'Sport');
      expect(cards(), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the disabled category of the section cannot be selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(_onSelected(tester, 'category-full', FilterChip, 'Dance'), isNull);
      await _tapChip(tester, 'category-full', 'Dance');

      expect(
        counterText(tester, 'category-full'),
        CategorySelectorSection.cardsText(5),
      );
    });

    testWidgets('the section title is exposed as a heading', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      final heading = inDemo('category-full', find.byType(CbsSectionHeading));
      expect(tester.getSemantics(heading).flagsCollection.isHeader, isTrue);
      handle.dispose();
    });
  });

  group('widths, text scales and themes', () {
    for (final width in CatalogWidth.values) {
      testWidgets('every selector fits the width and nothing overflows at '
          '${width.label}', (tester) async {
        await _pump(tester, CatalogScenario(width: width));

        for (final id in _demoIds) {
          expect(
            tester.getSize(_selector(id)).width,
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
          tester.getSize(_selector(id)).width,
          CatalogWidth.w320.logicalPixels,
          reason: id,
        );
      }
    });

    testWidgets('the chips grow with the text scale', (tester) async {
      await _pump(tester);
      final x1 = tester
          .getSize(_chip('category-single', ChoiceChip, 'Music'))
          .height;

      await selectOption(
        tester,
        CatalogKeys.textScaleOption(CatalogTextScale.x2),
      );
      final x2 = tester
          .getSize(_chip('category-single', ChoiceChip, 'Music'))
          .height;

      expect(x2, greaterThan(x1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the selections survive scenario changes', (tester) async {
      await _pump(tester);
      await _tapChip(tester, 'category-multiple', 'Music');
      await _tapChip(tester, 'category-single', 'Sport');

      await selectOption(tester, CatalogKeys.widthOption(CatalogWidth.w840));
      await selectOption(
        tester,
        CatalogKeys.designOption(CatalogDesign.branded),
      );
      await selectOption(
        tester,
        CatalogKeys.appearanceOption(CatalogAppearance.dark),
      );

      expect(counterText(tester, 'category-multiple'), 'Selected: Music');
      expect(counterText(tester, 'category-single'), 'Selected: Sport');
      expect(tester.takeException(), isNull);
    });

    testWidgets('follows the effective theme in dark Branded', (tester) async {
      await _pump(
        tester,
        const CatalogScenario(
          design: CatalogDesign.branded,
          appearance: CatalogAppearance.dark,
        ),
      );

      final scheme = CbsTheme.branded(
        primaryColor: CatalogScenario.brandedPrimaryColor,
        buttonRadius: CbsRadius.lg,
        brightness: Brightness.dark,
      ).colorScheme;
      Color? labelColor(String label) {
        final paragraph = tester.widget<RichText>(
          find
              .descendant(
                of: _chip('category-preselected', FilterChip, label),
                matching: find.byType(RichText),
              )
              .first,
        );
        return paragraph.text.style?.color;
      }

      expect(labelColor('Sport'), scheme.onSecondaryContainer);
      expect(labelColor('Music'), scheme.onSurfaceVariant);
      expect(tester.takeException(), isNull);
    });
  });
}
