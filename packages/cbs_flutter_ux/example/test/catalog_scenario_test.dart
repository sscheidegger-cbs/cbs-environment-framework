import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cbs_flutter_ux_example/catalog/catalog_entries.dart';
import 'package:cbs_flutter_ux_example/catalog/catalog_keys.dart';
import 'package:cbs_flutter_ux_example/catalog/catalog_scenario.dart';
import 'package:cbs_flutter_ux_example/main.dart';

import 'catalog_test_helpers.dart';

/// Messages of the CURRENT demonstrations, expected in every scenario.
const _currentFeedbackMessages = [
  'Information message',
  'Success message',
  'Warning message',
  'Error message',
];

/// CURRENT demonstrations, each scoped to its own labelled demo.
///
/// D03b-C.3 adaptation: global widget counts (`CbsButton` = 2, ...) were
/// replaced by counts scoped to the CURRENT demos, because the new sections
/// add instances of the same widgets. Every CURRENT assertion is kept.
void _expectCurrentDemonstrations() {
  expect(inDemo('buttons-states', find.byType(CbsButton)), findsNWidgets(2));
  expect(find.text('Enabled action'), findsOneWidget);
  expect(find.text('Disabled action'), findsOneWidget);
  expect(
    inDemo('loading-states', find.byType(CbsLoadingIndicator)),
    findsNWidgets(2),
  );
  expect(find.text('Indeterminate'), findsOneWidget);
  expect(find.text('Determinate - 60 %'), findsOneWidget);
  expect(
    inDemo('feedback-types', find.byType(CbsFeedbackMessage)),
    findsNWidgets(4),
  );
  for (final message in _currentFeedbackMessages) {
    expect(find.text(message), findsOneWidget);
  }
}

/// The six public CBS components and the four application states.
void _expectNewContent() {
  expect(find.byType(CbsButton), findsWidgets);
  expect(find.byType(CbsLoadingIndicator), findsWidgets);
  expect(find.byType(CbsFeedbackMessage), findsWidgets);
  expect(find.byType(CbsStatePanel), findsWidgets);
  expect(find.byType(CbsRetryMessage), findsWidgets);
  expect(find.byType(CbsSectionHeading), findsWidgets);
  for (final state in ['loading', 'empty', 'error', 'ready']) {
    expect(find.byKey(CatalogKeys.demo('state-$state')), findsOneWidget);
  }
}

void main() {
  group('CatalogScenario model', () {
    test('starts with Essentials, light, 320 px and text x1', () {
      const scenario = CatalogScenario.initial;

      expect(scenario.design, CatalogDesign.essentials);
      expect(scenario.appearance, CatalogAppearance.light);
      expect(scenario.width, CatalogWidth.w320);
      expect(scenario.textScale, CatalogTextScale.x1);
      expect(scenario.summary, 'Essentials · Light · 320 px · Text x1');
    });

    test('exposes the requested widths and text scales', () {
      expect(CatalogWidth.values.map((w) => w.logicalPixels), [
        320,
        600,
        840,
        1280,
      ]);
      expect(CatalogTextScale.values.map((s) => s.factor), [1, 2]);
    });

    test('enumerates the 2 x 2 x 4 x 2 scenario matrix without duplicates', () {
      final all = CatalogScenario.all.toList();

      expect(all, hasLength(32));
      expect(all.toSet(), hasLength(32));
    });

    test('copyWith replaces only the given dimension', () {
      final scenario = CatalogScenario.initial.copyWith(
        appearance: CatalogAppearance.dark,
      );

      expect(scenario.appearance, CatalogAppearance.dark);
      expect(scenario.design, CatalogDesign.essentials);
      expect(scenario.width, CatalogWidth.w320);
      expect(scenario.textScale, CatalogTextScale.x1);
    });

    test('builds CBS themes matching design and appearance', () {
      for (final brightness in Brightness.values) {
        final appearance = CatalogAppearance.values.firstWhere(
          (a) => a.brightness == brightness,
        );
        final essentials = CatalogScenario(appearance: appearance);
        final branded = CatalogScenario(
          design: CatalogDesign.branded,
          appearance: appearance,
        );

        expect(
          essentials.buildTheme().colorScheme,
          CbsTheme.essentials(brightness: brightness).colorScheme,
        );
        expect(
          branded.buildTheme().colorScheme,
          CbsTheme.branded(
            primaryColor: Colors.teal,
            buttonRadius: CbsRadius.lg,
            brightness: brightness,
          ).colorScheme,
        );
        expect(essentials.buildTheme().colorScheme.brightness, brightness);
        expect(branded.buildTheme().colorScheme.brightness, brightness);
      }
    });
  });

  group('catalog entries', () {
    test('lists the CURRENT demonstrations with unique identifiers', () {
      final ids = catalogEntries.map((e) => e.id).toList();

      // The three CURRENT entries keep their identifiers and their order;
      // D03b-C.3 appends the three missing components and the states.
      expect(ids.take(3), ['buttons', 'loading', 'feedback']);
      expect(ids, [
        'buttons',
        'loading',
        'feedback',
        'state-panel',
        'retry-message',
        'section-heading',
        'application-states',
      ]);
      expect(ids.toSet(), hasLength(ids.length));
    });

    testWidgets('renders one keyed section per entry, in order', (
      tester,
    ) async {
      await tester.pumpWidget(const CbsUxShowcase());

      var previousTop = double.negativeInfinity;
      for (final entry in catalogEntries) {
        final section = find.byKey(CatalogKeys.section(entry.id));
        expect(section, findsOneWidget);
        expect(find.text(entry.title), findsOneWidget);

        final top = tester.getTopLeft(section).dy;
        expect(top, greaterThan(previousTop));
        previousTop = top;
      }
    });
  });

  group('scenario controls', () {
    testWidgets('start on the initial scenario', (tester) async {
      await tester.pumpWidget(const CbsUxShowcase());

      expect(find.byKey(CatalogKeys.scenarioSummary), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(CatalogKeys.scenarioSummary)).data,
        'Essentials · Light · 320 px · Text x1',
      );
      expect(
        isSelected(tester, CatalogKeys.designOption(CatalogDesign.essentials)),
        isTrue,
      );
      expect(
        isSelected(tester, CatalogKeys.designOption(CatalogDesign.branded)),
        isFalse,
      );
      expect(
        isSelected(
          tester,
          CatalogKeys.appearanceOption(CatalogAppearance.light),
        ),
        isTrue,
      );
      expect(
        isSelected(
          tester,
          CatalogKeys.appearanceOption(CatalogAppearance.dark),
        ),
        isFalse,
      );
      expect(
        isSelected(tester, CatalogKeys.widthOption(CatalogWidth.w320)),
        isTrue,
      );
      expect(
        isSelected(tester, CatalogKeys.textScaleOption(CatalogTextScale.x1)),
        isTrue,
      );
      expect(
        isSelected(tester, CatalogKeys.textScaleOption(CatalogTextScale.x2)),
        isFalse,
      );
    });

    testWidgets('select the design and apply the matching CbsTheme', (
      tester,
    ) async {
      await tester.pumpWidget(const CbsUxShowcase());
      final essentials = appTheme(tester);

      await selectOption(
        tester,
        CatalogKeys.designOption(CatalogDesign.branded),
      );

      final branded = appTheme(tester);
      expect(find.text('Branded / Teal'), findsOneWidget);
      expect(find.text('Essentials / Indigo'), findsNothing);
      expect(
        branded.colorScheme.primary,
        isNot(essentials.colorScheme.primary),
      );
      expect(
        branded.colorScheme.primary,
        CbsTheme.branded(
          primaryColor: Colors.teal,
          buttonRadius: CbsRadius.lg,
        ).colorScheme.primary,
      );
      expect(
        isSelected(tester, CatalogKeys.designOption(CatalogDesign.branded)),
        isTrue,
      );
      expect(
        isSelected(tester, CatalogKeys.designOption(CatalogDesign.essentials)),
        isFalse,
      );
      expect(
        tester.widget<Text>(find.byKey(CatalogKeys.scenarioSummary)).data,
        startsWith('Branded'),
      );

      await selectOption(
        tester,
        CatalogKeys.designOption(CatalogDesign.essentials),
      );

      expect(find.text('Essentials / Indigo'), findsOneWidget);
      expect(
        appTheme(tester).colorScheme.primary,
        essentials.colorScheme.primary,
      );
    });

    testWidgets('switch appearance for both designs', (tester) async {
      await tester.pumpWidget(const CbsUxShowcase());
      expect(appTheme(tester).colorScheme.brightness, Brightness.light);

      await selectOption(
        tester,
        CatalogKeys.appearanceOption(CatalogAppearance.dark),
      );

      expect(appTheme(tester).colorScheme.brightness, Brightness.dark);
      expect(
        appTheme(tester).colorScheme,
        CbsTheme.essentials(brightness: Brightness.dark).colorScheme,
      );
      expect(
        isSelected(
          tester,
          CatalogKeys.appearanceOption(CatalogAppearance.dark),
        ),
        isTrue,
      );
      expect(
        isSelected(
          tester,
          CatalogKeys.appearanceOption(CatalogAppearance.light),
        ),
        isFalse,
      );

      await selectOption(
        tester,
        CatalogKeys.designOption(CatalogDesign.branded),
      );

      expect(appTheme(tester).colorScheme.brightness, Brightness.dark);
      expect(
        appTheme(tester).colorScheme,
        CbsTheme.branded(
          primaryColor: Colors.teal,
          buttonRadius: CbsRadius.lg,
          brightness: Brightness.dark,
        ).colorScheme,
      );

      await selectOption(
        tester,
        CatalogKeys.appearanceOption(CatalogAppearance.light),
      );

      expect(appTheme(tester).colorScheme.brightness, Brightness.light);
    });

    testWidgets('change the simulated width and its MediaQuery', (
      tester,
    ) async {
      await tester.pumpWidget(const CbsUxShowcase());

      for (final width in CatalogWidth.values) {
        await selectOption(tester, CatalogKeys.widthOption(width));

        final viewport = find.byKey(CatalogKeys.previewViewport);
        expect(tester.getSize(viewport).width, width.logicalPixels);
        expect(previewMediaQuery(tester).size.width, width.logicalPixels);
        expect(isSelected(tester, CatalogKeys.widthOption(width)), isTrue);
        expect(
          tester.widget<Text>(find.byKey(CatalogKeys.scenarioSummary)).data,
          contains(width.label),
        );

        // Controls and page keep the real device width.
        expect(
          pageMediaQuery(tester).size.width,
          tester.view.physicalSize.width / tester.view.devicePixelRatio,
        );
      }
    });

    testWidgets('lay content out with the simulated width constraint', (
      tester,
    ) async {
      await tester.pumpWidget(const CbsUxShowcase());

      await selectOption(tester, CatalogKeys.widthOption(CatalogWidth.w320));
      final narrow = tester.getSize(
        find.byKey(CatalogKeys.section('feedback')),
      );

      await selectOption(tester, CatalogKeys.widthOption(CatalogWidth.w840));
      final wide = tester.getSize(find.byKey(CatalogKeys.section('feedback')));

      // D03b-C.2-R1 (M2): decorative padding is outside the simulated
      // surface, so the content width is the simulated width itself
      // (previously `width - 2 * CbsSpacing.md`).
      expect(narrow.width, 320);
      expect(wide.width, 840);
    });

    testWidgets('scroll horizontally when the width exceeds the page', (
      tester,
    ) async {
      await tester.pumpWidget(const CbsUxShowcase());
      await selectOption(tester, CatalogKeys.widthOption(CatalogWidth.w1280));

      // Default test surface is 800 logical pixels wide.
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(CatalogKeys.previewViewport)).width,
        1280,
      );
      expect(
        tester.getSize(find.byKey(CatalogKeys.previewScroll)).width,
        lessThan(1280),
      );
    });

    testWidgets('change the text scale of the preview only', (tester) async {
      await tester.pumpWidget(const CbsUxShowcase());

      final pageTitleBefore = tester.getSize(find.text('Design'));
      final sectionTitleBefore = tester.getSize(find.text('Buttons'));
      expect(previewMediaQuery(tester).textScaler.scale(10), 10);

      await selectOption(
        tester,
        CatalogKeys.textScaleOption(CatalogTextScale.x2),
      );

      expect(previewMediaQuery(tester).textScaler.scale(10), 20);
      expect(pageMediaQuery(tester).textScaler.scale(10), 10);
      expect(
        isSelected(tester, CatalogKeys.textScaleOption(CatalogTextScale.x2)),
        isTrue,
      );
      expect(
        isSelected(tester, CatalogKeys.textScaleOption(CatalogTextScale.x1)),
        isFalse,
      );
      expect(tester.getSize(find.text('Design')), pageTitleBefore);
      expect(
        tester.getSize(find.text('Buttons')).height,
        greaterThan(sectionTitleBefore.height * 1.9),
      );

      await selectOption(
        tester,
        CatalogKeys.textScaleOption(CatalogTextScale.x1),
      );

      expect(previewMediaQuery(tester).textScaler.scale(10), 10);
      expect(tester.getSize(find.text('Buttons')), sectionTitleBefore);
    });

    testWidgets('keep the other dimensions when one changes', (tester) async {
      await tester.pumpWidget(const CbsUxShowcase());

      await selectOption(
        tester,
        CatalogKeys.designOption(CatalogDesign.branded),
      );
      await selectOption(
        tester,
        CatalogKeys.appearanceOption(CatalogAppearance.dark),
      );
      await selectOption(tester, CatalogKeys.widthOption(CatalogWidth.w840));
      await selectOption(
        tester,
        CatalogKeys.textScaleOption(CatalogTextScale.x2),
      );

      expect(
        tester.widget<Text>(find.byKey(CatalogKeys.scenarioSummary)).data,
        'Branded · Dark · 840 px · Text x2',
      );
      expect(appTheme(tester).colorScheme.brightness, Brightness.dark);
      expect(
        tester.getSize(find.byKey(CatalogKeys.previewViewport)).width,
        840,
      );
      expect(previewMediaQuery(tester).textScaler.scale(10), 20);
      expect(find.text('Branded / Teal'), findsOneWidget);
    });
  });

  group('CURRENT demonstrations', () {
    testWidgets('remain visible after every control change', (tester) async {
      await tester.pumpWidget(const CbsUxShowcase());
      _expectCurrentDemonstrations();

      for (final key in [
        CatalogKeys.designOption(CatalogDesign.branded),
        CatalogKeys.appearanceOption(CatalogAppearance.dark),
        CatalogKeys.widthOption(CatalogWidth.w1280),
        CatalogKeys.textScaleOption(CatalogTextScale.x2),
      ]) {
        await selectOption(tester, key);
        _expectCurrentDemonstrations();
      }
    });

    testWidgets('keep the CbsButton enabled and disabled states', (
      tester,
    ) async {
      await tester.pumpWidget(const CbsUxShowcase());

      final buttons = tester
          .widgetList<CbsButton>(
            inDemo('buttons-states', find.byType(CbsButton)),
          )
          .toList();
      expect(buttons.where((b) => b.onPressed != null), hasLength(1));
      expect(buttons.where((b) => b.onPressed == null), hasLength(1));
    });

    testWidgets('keep the CbsLoadingIndicator semantic labels', (tester) async {
      await tester.pumpWidget(const CbsUxShowcase());

      final indicators = tester
          .widgetList<CbsLoadingIndicator>(
            inDemo('loading-states', find.byType(CbsLoadingIndicator)),
          )
          .toList();
      expect(indicators.map((i) => i.value), [null, 0.6]);
      expect(indicators.map((i) => i.semanticLabel), [
        'Indeterminate loading',
        '60 percent complete',
      ]);
    });

    testWidgets('keep the four CbsFeedbackMessage types', (tester) async {
      await tester.pumpWidget(const CbsUxShowcase());

      expect(
        tester
            .widgetList<CbsFeedbackMessage>(
              inDemo('feedback-types', find.byType(CbsFeedbackMessage)),
            )
            .map((m) => m.type),
        [
          CbsFeedbackType.info,
          CbsFeedbackType.success,
          CbsFeedbackType.warning,
          CbsFeedbackType.error,
        ],
      );
    });
  });

  group('scenario matrix: no exception, no overflow', () {
    for (final scenario in CatalogScenario.all) {
      testWidgets(scenario.summary, (tester) async {
        await tester.pumpWidget(CbsUxShowcase(initialScenario: scenario));
        await tester.pump(const Duration(milliseconds: 300));

        // Layout overflows are reported as FlutterError exceptions.
        expect(tester.takeException(), isNull);

        expect(
          tester.getSize(find.byKey(CatalogKeys.previewViewport)).width,
          scenario.width.logicalPixels,
        );
        expect(
          previewMediaQuery(tester).textScaler.scale(10),
          10 * scenario.textScale.factor,
        );
        expect(
          appTheme(tester).colorScheme.brightness,
          scenario.appearance.brightness,
        );
        expect(
          tester.widget<Text>(find.byKey(CatalogKeys.scenarioSummary)).data,
          scenario.summary,
        );
        _expectCurrentDemonstrations();
        _expectNewContent();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('scroll through every section at 320 px and text x2', (
      tester,
    ) async {
      const scenario = CatalogScenario(textScale: CatalogTextScale.x2);
      await tester.pumpWidget(const CbsUxShowcase(initialScenario: scenario));

      for (final entry in catalogEntries) {
        await tester.scrollUntilVisible(
          find.byKey(CatalogKeys.section(entry.id)),
          150,
          scrollable: pageScrollable(),
        );
        expect(tester.takeException(), isNull);
      }
    });

    for (final appearance in CatalogAppearance.values) {
      testWidgets('phone-sized surface (320 x 640), ${appearance.label}, '
          'text x2 for the whole page', (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearAllTestValues);

        await tester.pumpWidget(
          CbsUxShowcase(
            initialScenario: CatalogScenario(
              design: CatalogDesign.branded,
              appearance: appearance,
              textScale: CatalogTextScale.x2,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Controls (real device text scale x2 on 320 px) must not overflow.
        expect(tester.takeException(), isNull);

        for (final entry in catalogEntries) {
          await tester.scrollUntilVisible(
            find.byKey(CatalogKeys.section(entry.id)),
            150,
            scrollable: pageScrollable(),
          );
          expect(tester.takeException(), isNull);
        }
      });
    }
  });
}
