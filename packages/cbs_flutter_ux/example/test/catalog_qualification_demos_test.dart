import 'dart:ui' show SemanticsRole;

import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cbs_flutter_ux_example/catalog/catalog_entries.dart';
import 'package:cbs_flutter_ux_example/catalog/catalog_keys.dart';
import 'package:cbs_flutter_ux_example/catalog/catalog_preview_frame.dart';
import 'package:cbs_flutter_ux_example/catalog/catalog_scenario.dart';
import 'package:cbs_flutter_ux_example/catalog/sections/dynamic_feedback_demo.dart';
import 'package:cbs_flutter_ux_example/catalog/sections/dynamic_progress_demo.dart';
import 'package:cbs_flutter_ux_example/main.dart';

import 'catalog_test_helpers.dart';

// D03c-A.2 / C3.2: complements of the catalog for the manual Android and
// TalkBack qualification (C4 dynamic feedback, D3 loading without label,
// D4 dynamic progress, F3b Device text scale).
//
// These tests read the Flutter widget tree and semantics tree. They prove
// what the example builds and exposes to Flutter; they do NOT prove what
// TalkBack announces, nor that the Android font size setting changes the
// catalog on a real device. Both stay NOT_VERIFIED until observed on a
// device. They never use `pumpAndSettle` (indeterminate indicators animate
// forever).

const _narrowLargeText = CatalogScenario(textScale: CatalogTextScale.x2);
const _deviceScenario = CatalogScenario(textScale: CatalogTextScale.device);

Future<void> _pump(
  WidgetTester tester, [
  CatalogScenario scenario = CatalogScenario.initial,
]) async {
  await tester.pumpWidget(CbsUxShowcase(initialScenario: scenario));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Simulates the Android font size setting (device `TextScaler`).
void _setDeviceTextScale(WidgetTester tester, double factor) {
  tester.platformDispatcher.textScaleFactorTestValue = factor;
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

Finder _dynamicMessage() =>
    inDemo('feedback-dynamic', find.byType(CbsFeedbackMessage));

/// `Semantics` widgets of the demonstration that declare a live region.
///
/// The qualification demonstrations must not add one: CURRENT behaviour is
/// observed, not corrected.
Finder _liveRegions(String demoId) => inDemo(
  demoId,
  find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.liveRegion == true,
  ),
);

Finder _progressSemanticsTarget() => find.descendant(
  of: find.byKey(CatalogKeys.progressIndicator),
  matching: find.byType(CircularProgressIndicator),
);

Finder _unlabeledSemanticsTarget() => find.descendant(
  of: find.byKey(CatalogKeys.unlabeledLoading),
  matching: find.byType(CircularProgressIndicator),
);

String _readoutText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(CatalogKeys.textScaleReadout)).data!;

void main() {
  group('C4 - dynamic feedback', () {
    testWidgets('is hidden at start and counts no display', (tester) async {
      await _pump(tester);

      expect(find.byKey(CatalogKeys.demo('feedback-dynamic')), findsOneWidget);
      expect(_dynamicMessage(), findsNothing);
      expect(find.text(CatalogDynamicFeedbackDemo.message), findsNothing);
      expect(counterText(tester, 'feedback-dynamic'), 'Feedback displays: 0');
    });

    testWidgets('appears on user action, hides, then appears again', (
      tester,
    ) async {
      await _pump(tester);

      await tapVisible(tester, find.byKey(CatalogKeys.dynamicFeedbackShow));
      expect(_dynamicMessage(), findsOneWidget);
      expect(find.text(CatalogDynamicFeedbackDemo.message), findsOneWidget);
      expect(counterText(tester, 'feedback-dynamic'), 'Feedback displays: 1');

      await tapVisible(tester, find.byKey(CatalogKeys.dynamicFeedbackHide));
      expect(_dynamicMessage(), findsNothing);
      expect(find.text(CatalogDynamicFeedbackDemo.message), findsNothing);
      expect(counterText(tester, 'feedback-dynamic'), 'Feedback displays: 1');

      await tapVisible(tester, find.byKey(CatalogKeys.dynamicFeedbackShow));
      expect(_dynamicMessage(), findsOneWidget);
      expect(counterText(tester, 'feedback-dynamic'), 'Feedback displays: 2');
      expect(tester.takeException(), isNull);
    });

    testWidgets('showing twice in a row displays one message and counts once', (
      tester,
    ) async {
      await _pump(tester);

      await tapVisible(tester, find.byKey(CatalogKeys.dynamicFeedbackShow));
      await tapVisible(tester, find.byKey(CatalogKeys.dynamicFeedbackShow));

      expect(_dynamicMessage(), findsOneWidget);
      expect(counterText(tester, 'feedback-dynamic'), 'Feedback displays: 1');
    });

    testWidgets('hiding while hidden is harmless', (tester) async {
      await _pump(tester);

      await tapVisible(tester, find.byKey(CatalogKeys.dynamicFeedbackHide));

      expect(_dynamicMessage(), findsNothing);
      expect(counterText(tester, 'feedback-dynamic'), 'Feedback displays: 0');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the message is a plain CbsFeedbackMessage, unmodified', (
      tester,
    ) async {
      await _pump(tester);
      await tapVisible(tester, find.byKey(CatalogKeys.dynamicFeedbackShow));

      final message = tester.widget<CbsFeedbackMessage>(_dynamicMessage());
      expect(message.message, CatalogDynamicFeedbackDemo.message);
      expect(message.type, CbsFeedbackType.info);
      // No artificial semantic label: CURRENT behaviour is observed.
      expect(message.semanticLabel, isNull);
    });

    testWidgets('no liveRegion is added around or inside the message', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await tapVisible(tester, find.byKey(CatalogKeys.dynamicFeedbackShow));

      expect(_liveRegions('feedback-dynamic'), findsNothing);
      final node = tester.getSemantics(
        find.bySemanticsLabel(CatalogDynamicFeedbackDemo.message),
      );
      expect(node.flagsCollection.isLiveRegion, isFalse);
      handle.dispose();
    });

    testWidgets('the message is in the semantics tree only while displayed', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      expect(
        find.bySemanticsLabel(CatalogDynamicFeedbackDemo.message),
        findsNothing,
      );

      await tapVisible(tester, find.byKey(CatalogKeys.dynamicFeedbackShow));
      expect(
        find.bySemanticsLabel(CatalogDynamicFeedbackDemo.message),
        findsOneWidget,
      );
      // Visual order only: the message is laid out below the two buttons.
      // The screen reader traversal order itself is not asserted here.
      final message = tester.getTopLeft(_dynamicMessage());
      expect(
        message.dy,
        greaterThan(
          tester.getBottomLeft(find.byKey(CatalogKeys.dynamicFeedbackHide)).dy,
        ),
      );

      await tapVisible(tester, find.byKey(CatalogKeys.dynamicFeedbackHide));
      expect(
        find.bySemanticsLabel(CatalogDynamicFeedbackDemo.message),
        findsNothing,
      );
      handle.dispose();
    });

    testWidgets('the show and hide buttons have an onPressed handler', (
      tester,
    ) async {
      await _pump(tester);

      for (final key in [
        CatalogKeys.dynamicFeedbackShow,
        CatalogKeys.dynamicFeedbackHide,
      ]) {
        expect(tester.widget<CbsButton>(find.byKey(key)).onPressed, isNotNull);
      }
      expect(find.text('Show feedback'), findsOneWidget);
      expect(find.text('Hide feedback'), findsOneWidget);
    });

    for (final scenario in [_narrowLargeText, _deviceScenario]) {
      testWidgets('shows without overflow at 320 px, ${scenario.summary}', (
        tester,
      ) async {
        _setDeviceTextScale(tester, 2);
        await _pump(tester, scenario);

        await tapVisible(tester, find.byKey(CatalogKeys.dynamicFeedbackShow));

        expect(_dynamicMessage(), findsOneWidget);
        expect(tester.getSize(_dynamicMessage()).width, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('D3 - loading indicator without semanticLabel', () {
    testWidgets('shows one indeterminate indicator with no label', (
      tester,
    ) async {
      await _pump(tester);

      final demo = find.byKey(CatalogKeys.demo('loading-no-label'));
      expect(demo, findsOneWidget);
      final indicator = tester.widget<CbsLoadingIndicator>(
        inDemo('loading-no-label', find.byType(CbsLoadingIndicator)),
      );
      expect(indicator.semanticLabel, isNull);
      expect(indicator.value, isNull);
      expect(
        tester
            .widget<CircularProgressIndicator>(_unlabeledSemanticsTarget())
            .semanticsLabel,
        isNull,
      );
    });

    testWidgets('no replacement label is exposed to the semantics tree', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      final data = tester
          .getSemantics(_unlabeledSemanticsTarget())
          .getSemanticsData();
      // CURRENT behaviour, as characterized by the package tests: a
      // spinner role, with neither label nor value.
      expect(data.label, isEmpty);
      expect(data.value, isEmpty);
      expect(data.role, SemanticsRole.loadingSpinner);
      expect(_liveRegions('loading-no-label'), findsNothing);
      // No `Semantics` widget wraps the indicator inside the demonstration
      // (the indicator's own `Semantics` is a descendant, not an ancestor).
      expect(
        find.ancestor(
          of: find.byKey(CatalogKeys.unlabeledLoading),
          matching: find.descendant(
            of: find.byKey(CatalogKeys.demo('loading-no-label')),
            matching: find.byType(Semantics),
          ),
        ),
        findsNothing,
      );
      handle.dispose();
    });

    testWidgets('the CURRENT labelled indicators keep their labels', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      for (final label in [
        'Indeterminate loading',
        '60 percent complete',
        '0 percent complete',
        '100 percent complete',
        'Loading content',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      handle.dispose();
    });

    testWidgets('keeps animating and does not overflow at 320 px, x2', (
      tester,
    ) async {
      await _pump(tester, _narrowLargeText);

      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('D4 - determinate indicator with changing progress', () {
    testWidgets('offers the five simple values', (tester) async {
      await _pump(tester);

      expect(CatalogDynamicProgressDemo.steps, [0, 25, 50, 75, 100]);
      for (final step in CatalogDynamicProgressDemo.steps) {
        expect(
          find.byKey(CatalogKeys.progressOption(step)),
          findsOneWidget,
          reason: '$step',
        );
        expect(find.text('Set $step %'), findsOneWidget);
      }
    });

    testWidgets('starts at 0 %', (tester) async {
      await _pump(tester);

      expect(
        tester
            .widget<CbsLoadingIndicator>(
              find.byKey(CatalogKeys.progressIndicator),
            )
            .value,
        0,
      );
      expect(find.text('Progress: 0 %'), findsOneWidget);
    });

    for (final step in CatalogDynamicProgressDemo.steps) {
      testWidgets('$step % updates the indicator, the readout and semantics', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _pump(tester);

        await tapVisible(tester, find.byKey(CatalogKeys.progressOption(step)));

        final indicator = tester.widget<CbsLoadingIndicator>(
          find.byKey(CatalogKeys.progressIndicator),
        );
        expect(indicator.value, step / 100);
        expect(
          indicator.semanticLabel,
          CatalogDynamicProgressDemo.semanticLabel,
        );
        expect(
          tester.widget<Text>(find.byKey(CatalogKeys.progressReadout)).data,
          'Progress: $step %',
        );

        // CURRENT behaviour of Flutter 3.47.6's progress indicator (it may
        // change with the Flutter version): the value is exposed as a
        // number without a percent sign, next to the constant label.
        final data = tester
            .getSemantics(_progressSemanticsTarget())
            .getSemanticsData();
        expect(data.label, CatalogDynamicProgressDemo.semanticLabel);
        expect(data.value, '$step');
        expect(data.minValue, '0');
        expect(data.maxValue, '100');
        expect(data.role, SemanticsRole.progressBar);
        expect(tester.takeException(), isNull);
        handle.dispose();
      });
    }

    testWidgets('goes up and down in any order, ending on the last choice', (
      tester,
    ) async {
      await _pump(tester);

      for (final step in [100, 25, 75, 0, 50]) {
        await tapVisible(tester, find.byKey(CatalogKeys.progressOption(step)));
        expect(
          tester
              .widget<CbsLoadingIndicator>(
                find.byKey(CatalogKeys.progressIndicator),
              )
              .value,
          step / 100,
          reason: '$step',
        );
      }
      expect(find.text('Progress: 50 %'), findsOneWidget);
    });

    testWidgets('no liveRegion is added, whatever the progress', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      for (final step in CatalogDynamicProgressDemo.steps) {
        await tapVisible(tester, find.byKey(CatalogKeys.progressOption(step)));

        expect(_liveRegions('loading-progress'), findsNothing, reason: '$step');
        expect(
          tester
              .getSemantics(_progressSemanticsTarget())
              .flagsCollection
              .isLiveRegion,
          isFalse,
          reason: '$step',
        );
      }
      handle.dispose();
    });

    testWidgets('the progress buttons are enabled', (tester) async {
      await _pump(tester);

      final buttons = inDemo('loading-progress', find.byType(CbsButton));
      expect(buttons, findsNWidgets(5));
      for (final button in tester.widgetList<CbsButton>(buttons)) {
        expect(button.onPressed, isNotNull, reason: button.label);
      }
    });

    testWidgets('fits without overflow at 320 px, x2', (tester) async {
      await _pump(tester, _narrowLargeText);

      await tapVisible(tester, find.byKey(CatalogKeys.progressOption(75)));

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(CatalogKeys.demo('loading-progress'))).width,
        lessThanOrEqualTo(320),
      );
    });
  });

  group('demonstrations keep their state when the scenario changes', () {
    testWidgets('dynamic feedback and progress survive a Device switch', (
      tester,
    ) async {
      await _pump(tester);
      await tapVisible(tester, find.byKey(CatalogKeys.dynamicFeedbackShow));
      await tapVisible(tester, find.byKey(CatalogKeys.progressOption(50)));

      await selectOption(
        tester,
        CatalogKeys.textScaleOption(CatalogTextScale.device),
      );
      await selectOption(
        tester,
        CatalogKeys.designOption(CatalogDesign.branded),
      );

      expect(_dynamicMessage(), findsOneWidget);
      expect(counterText(tester, 'feedback-dynamic'), 'Feedback displays: 1');
      expect(find.text('Progress: 50 %'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('F3b - Device text scale: model', () {
    test('appends Device after x1 and x2, which are unchanged', () {
      expect(CatalogTextScale.values, [
        CatalogTextScale.x1,
        CatalogTextScale.x2,
        CatalogTextScale.device,
      ]);
      expect(CatalogTextScale.values.map((s) => s.label), [
        'x1',
        'x2',
        'Device',
      ]);
      expect(CatalogTextScale.x1.factor, 1);
      expect(CatalogTextScale.x2.factor, 2);
      expect(CatalogTextScale.device.factor, isNull);
      expect(CatalogTextScale.device.followsDevice, isTrue);
      expect(CatalogTextScale.x1.followsDevice, isFalse);
      expect(CatalogTextScale.x2.followsDevice, isFalse);
      expect(CatalogTextScale.simulated, [
        CatalogTextScale.x1,
        CatalogTextScale.x2,
      ]);
    });

    test('x1 and x2 ignore the device scaler, Device returns it as is', () {
      final device = TextScaler.linear(1.5).clamp(maxScaleFactor: 1.2);

      expect(CatalogTextScale.x1.resolve(device).scale(10), 10);
      expect(CatalogTextScale.x2.resolve(device).scale(10), 20);
      expect(
        identical(CatalogTextScale.device.resolve(device), device),
        isTrue,
      );
    });

    test('keeps the 32 scenarios and keeps Device out of that matrix', () {
      final all = CatalogScenario.all.toList();

      expect(all, hasLength(32));
      expect(all.toSet(), hasLength(32));
      expect(all.map((s) => s.textScale).toSet(), {
        CatalogTextScale.x1,
        CatalogTextScale.x2,
      });
    });

    test('enumerates 16 distinct Device scenarios, disjoint from the 32', () {
      final device = CatalogScenario.allDeviceTextScale.toList();

      expect(device, hasLength(16));
      expect(device.toSet(), hasLength(16));
      expect(device.every((s) => s.textScale.followsDevice), isTrue);
      expect(device.toSet().intersection(CatalogScenario.all.toSet()), isEmpty);
    });

    test('summarizes the Device scenario', () {
      expect(
        _deviceScenario.summary,
        'Essentials · Light · 320 px · Text Device',
      );
    });
  });

  group('F3b - Device text scale: control', () {
    testWidgets('the control offers x1, x2 and Device, x1 selected', (
      tester,
    ) async {
      await tester.pumpWidget(const CbsUxShowcase());

      for (final scale in CatalogTextScale.values) {
        expect(
          find.byKey(CatalogKeys.textScaleOption(scale)),
          findsOneWidget,
          reason: scale.label,
        );
        expect(
          isSelected(tester, CatalogKeys.textScaleOption(scale)),
          scale == CatalogTextScale.x1,
          reason: scale.label,
        );
      }
    });

    testWidgets('selecting Device updates the selection and the summary', (
      tester,
    ) async {
      await tester.pumpWidget(const CbsUxShowcase());

      await selectOption(
        tester,
        CatalogKeys.textScaleOption(CatalogTextScale.device),
      );

      expect(
        isSelected(
          tester,
          CatalogKeys.textScaleOption(CatalogTextScale.device),
        ),
        isTrue,
      );
      expect(
        isSelected(tester, CatalogKeys.textScaleOption(CatalogTextScale.x1)),
        isFalse,
      );
      expect(
        tester.widget<Text>(find.byKey(CatalogKeys.scenarioSummary)).data,
        'Essentials · Light · 320 px · Text Device',
      );
    });
  });

  group('F3b - Device text scale: behaviour', () {
    testWidgets('the preview uses the device scaler, not an absolute value', (
      tester,
    ) async {
      _setDeviceTextScale(tester, 1.5);
      await _pump(tester, _deviceScenario);

      expect(previewMediaQuery(tester).textScaler.scale(10), 15);
      expect(pageMediaQuery(tester).textScaler.scale(10), 15);
      expect(
        previewMediaQuery(tester).textScaler,
        pageMediaQuery(tester).textScaler,
      );
    });

    testWidgets('a change of the device font size is observed in Device', (
      tester,
    ) async {
      _setDeviceTextScale(tester, 1);
      await _pump(tester, _deviceScenario);
      final titleAt1 = tester.getSize(find.text('Buttons')).height;
      expect(previewMediaQuery(tester).textScaler.scale(10), 10);
      expect(
        _readoutText(tester),
        'Device text size: 14 sp → 14.0 sp · Preview: 14 sp → 14.0 sp',
      );

      _setDeviceTextScale(tester, 2);
      await tester.pump(const Duration(milliseconds: 300));

      expect(previewMediaQuery(tester).textScaler.scale(10), 20);
      expect(pageMediaQuery(tester).textScaler.scale(10), 20);
      expect(
        tester.getSize(find.text('Buttons')).height,
        greaterThan(titleAt1 * 1.9),
      );
      expect(
        _readoutText(tester),
        'Device text size: 14 sp → 28.0 sp · Preview: 14 sp → 28.0 sp',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Device selected at runtime follows the device scale', (
      tester,
    ) async {
      _setDeviceTextScale(tester, 1.5);
      await _pump(tester);
      expect(previewMediaQuery(tester).textScaler.scale(10), 10);

      await selectOption(
        tester,
        CatalogKeys.textScaleOption(CatalogTextScale.device),
      );

      expect(previewMediaQuery(tester).textScaler.scale(10), 15);
    });

    testWidgets('a non-linear device scaler is passed through untouched', (
      tester,
    ) async {
      final injected = TextScaler.linear(3).clamp(maxScaleFactor: 1.2);
      TextScaler? seen;

      Widget app(CatalogScenario scenario) => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: injected),
          child: child!,
        ),
        home: Scaffold(
          body: CatalogPreviewFrame(
            scenario: scenario,
            child: Builder(
              builder: (context) {
                seen = MediaQuery.textScalerOf(context);
                return const SizedBox(height: 10);
              },
            ),
          ),
        ),
      );

      await tester.pumpWidget(app(_deviceScenario));
      expect(identical(seen, injected), isTrue);
      expect(seen!.scale(10), 12);

      await tester.pumpWidget(app(const CatalogScenario()));
      expect(seen!.scale(10), 10);
      await tester.pumpWidget(app(_narrowLargeText));
      expect(seen!.scale(10), 20);
    });

    testWidgets('the Device scale applies to the whole preview content', (
      tester,
    ) async {
      _setDeviceTextScale(tester, 2);
      await _pump(tester);
      final heightX1 = tester.getSize(find.text('Buttons')).height;

      await selectOption(
        tester,
        CatalogKeys.textScaleOption(CatalogTextScale.device),
      );

      // Device (×2 here) renders the section title as large as x2 would.
      expect(
        tester.getSize(find.text('Buttons')).height,
        greaterThan(heightX1 * 1.9),
      );
      await selectOption(
        tester,
        CatalogKeys.textScaleOption(CatalogTextScale.x1),
      );
      expect(tester.getSize(find.text('Buttons')).height, heightX1);
    });
  });

  group('F3b - x1 and x2 are unchanged whatever the device font size', () {
    for (final deviceFactor in [1.0, 1.5, 2.0]) {
      testWidgets('device ×$deviceFactor: x1 stays 10, x2 stays 20', (
        tester,
      ) async {
        _setDeviceTextScale(tester, deviceFactor);

        await _pump(tester);
        expect(previewMediaQuery(tester).textScaler.scale(10), 10);
        expect(pageMediaQuery(tester).textScaler.scale(10), 10 * deviceFactor);

        await selectOption(
          tester,
          CatalogKeys.textScaleOption(CatalogTextScale.x2),
        );
        expect(previewMediaQuery(tester).textScaler.scale(10), 20);
        expect(pageMediaQuery(tester).textScaler.scale(10), 10 * deviceFactor);

        await selectOption(
          tester,
          CatalogKeys.textScaleOption(CatalogTextScale.x1),
        );
        expect(previewMediaQuery(tester).textScaler.scale(10), 10);
      });
    }

    testWidgets('the readout shows the simulated preview scale for x2', (
      tester,
    ) async {
      _setDeviceTextScale(tester, 1.5);
      await _pump(tester, _narrowLargeText);

      expect(
        _readoutText(tester),
        'Device text size: 14 sp → 21.0 sp · Preview: 14 sp → 28.0 sp',
      );
    });
  });

  group('F3b - Device scenarios: no exception, no overflow', () {
    for (final scenario in CatalogScenario.allDeviceTextScale) {
      testWidgets(scenario.summary, (tester) async {
        _setDeviceTextScale(tester, 1.5);
        await _pump(tester, scenario);

        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(CatalogKeys.previewViewport)).width,
          scenario.width.logicalPixels,
        );
        expect(previewMediaQuery(tester).textScaler.scale(10), 15);
        expect(
          appTheme(tester).colorScheme.brightness,
          scenario.appearance.brightness,
        );
        expect(
          tester.widget<Text>(find.byKey(CatalogKeys.scenarioSummary)).data,
          scenario.summary,
        );
        for (final entry in catalogEntries) {
          expect(find.byKey(CatalogKeys.section(entry.id)), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }

    for (final appearance in CatalogAppearance.values) {
      testWidgets('phone-sized surface (320 x 640), ${appearance.label}, '
          'device font ×2 for the whole page', (tester) async {
        setSurfaceSize(tester, const Size(320, 640));
        _setDeviceTextScale(tester, 2);

        await _pump(
          tester,
          CatalogScenario(
            design: CatalogDesign.branded,
            appearance: appearance,
            textScale: CatalogTextScale.device,
          ),
        );

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

  group('catalog completeness', () {
    testWidgets('keeps the twelve sections and the six widgets', (
      tester,
    ) async {
      await _pump(tester);

      expect(catalogEntries.map((e) => e.id), [
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
      ]);
      expect(inSection('buttons', find.byType(CbsButton)), findsWidgets);
      expect(
        inSection('loading', find.byType(CbsLoadingIndicator)),
        findsWidgets,
      );
      expect(
        inSection('feedback', find.byType(CbsFeedbackMessage)),
        findsWidgets,
      );
      expect(
        inSection('state-panel', find.byType(CbsStatePanel)),
        findsWidgets,
      );
      expect(
        inSection('retry-message', find.byType(CbsRetryMessage)),
        findsWidgets,
      );
      expect(
        inSection('section-heading', find.byType(CbsSectionHeading)),
        findsWidgets,
      );
    });
  });
}
