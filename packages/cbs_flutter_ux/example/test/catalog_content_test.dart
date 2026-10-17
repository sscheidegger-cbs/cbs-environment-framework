import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cbs_flutter_ux_example/catalog/catalog_keys.dart';
import 'package:cbs_flutter_ux_example/catalog/catalog_scenario.dart';
import 'package:cbs_flutter_ux_example/catalog/sections/adaptive_collection_section.dart';
import 'package:cbs_flutter_ux_example/catalog/sections/buttons_section.dart';
import 'package:cbs_flutter_ux_example/catalog/sections/feedback_section.dart';
import 'package:cbs_flutter_ux_example/catalog/sections/media_frame_section.dart';
import 'package:cbs_flutter_ux_example/catalog/sections/section_heading_section.dart';
import 'package:cbs_flutter_ux_example/catalog/sections/state_panel_section.dart';
import 'package:cbs_flutter_ux_example/main.dart';

import 'catalog_test_helpers.dart';

// D03b-C.3: content of the catalog. Assertions target a section or a
// labelled demonstration by `Key`; they never rely on global widget counts,
// and they never use `pumpAndSettle` (the indeterminate loading indicators
// animate forever).

/// Every labelled demonstration of the catalog.
const _demoIds = <String>[
  'buttons-states',
  'buttons-long-label',
  'buttons-interaction',
  'loading-states',
  'loading-range',
  'loading-no-label',
  'loading-progress',
  'feedback-types',
  'feedback-expand',
  'feedback-long',
  'feedback-semantic',
  'feedback-dynamic',
  'state-panel-content',
  'state-panel-constrained',
  'retry-short',
  'retry-long',
  'heading-short',
  'heading-long',
  'heading-hierarchy',
  'state-loading',
  'state-empty',
  'state-error',
  'state-ready',
  'media-16-9',
  'media-1-1',
  'media-custom',
  'media-placeholder',
  'collection-list',
  'collection-grid',
  'collection-cards',
  'collection-media',
  'collection-narrow',
];

/// Columns of the adaptive grid (default `minItemWidth` 240 and `spacing`
/// 12) at each simulated width.
const _collectionColumns = <CatalogWidth, int>{
  CatalogWidth.w320: 1,
  CatalogWidth.w600: 2,
  CatalogWidth.w840: 3,
  CatalogWidth.w1280: 5,
};

/// Scenario of the "narrow screen, large text" worst case.
const _narrowLargeText = CatalogScenario(textScale: CatalogTextScale.x2);

Future<void> _pump(
  WidgetTester tester, [
  CatalogScenario scenario = CatalogScenario.initial,
]) async {
  await tester.pumpWidget(CbsUxShowcase(initialScenario: scenario));
  await tester.pump(const Duration(milliseconds: 300));
}

Size _size(WidgetTester tester, Finder finder) => tester.getSize(finder);

Finder _text(String demoId, String data) => inDemo(demoId, find.text(data));

CbsFeedbackMessage _feedback(WidgetTester tester, Finder finder) =>
    tester.widget<CbsFeedbackMessage>(finder);

void main() {
  group('six CBS components', () {
    const sections = <String, Type>{
      'buttons': CbsButton,
      'loading': CbsLoadingIndicator,
      'feedback': CbsFeedbackMessage,
      'state-panel': CbsStatePanel,
      'retry-message': CbsRetryMessage,
      'section-heading': CbsSectionHeading,
    };

    for (final MapEntry(key: id, value: type) in sections.entries) {
      testWidgets('$type is shown in the "$id" section', (tester) async {
        await _pump(tester);

        expect(inSection(id, find.byType(type)), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('every labelled demonstration exists exactly once', (
      tester,
    ) async {
      await _pump(tester);

      for (final id in _demoIds) {
        expect(find.byKey(CatalogKeys.demo(id)), findsOneWidget, reason: id);
      }
    });
  });

  group('CbsButton', () {
    testWidgets('shows enabled, disabled and long-label variants', (
      tester,
    ) async {
      await _pump(tester);

      final states = tester
          .widgetList<CbsButton>(
            inDemo('buttons-states', find.byType(CbsButton)),
          )
          .toList();
      expect(states.map((b) => b.onPressed != null), [true, false]);

      final long = tester.widget<CbsButton>(
        inDemo('buttons-long-label', find.byType(CbsButton)),
      );
      expect(long.label, ButtonsSection.longLabel);
      expect(long.onPressed, isNotNull);
    });

    testWidgets('long label wraps instead of overflowing at 320 px, x2', (
      tester,
    ) async {
      await _pump(tester, _narrowLargeText);

      final regular = _size(
        tester,
        inDemo('buttons-states', find.byType(CbsButton)).first,
      );
      final long = _size(
        tester,
        inDemo('buttons-long-label', find.byType(CbsButton)),
      );
      expect(long.height, greaterThan(regular.height));
      expect(long.width, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    });

    testWidgets('pressing the enabled button updates the counter', (
      tester,
    ) async {
      await _pump(tester);
      expect(counterText(tester, 'buttons-interaction'), 'Button presses: 0');

      final button = inDemo('buttons-interaction', find.byType(CbsButton));
      await tapVisible(tester, button);
      await tapVisible(tester, button);

      expect(counterText(tester, 'buttons-interaction'), 'Button presses: 2');
    });

    testWidgets('the disabled button does not react', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      // The disabled button is identified by its demonstration and label.
      final disabled = inDemo(
        'buttons-states',
        find.widgetWithText(CbsButton, 'Disabled action'),
      );
      expect(disabled, findsOneWidget);
      expect(tester.widget<CbsButton>(disabled).onPressed, isNull);
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(
                of: disabled,
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      final node = tester.getSemantics(disabled);
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);

      // Its visible counter and the enabled counter stay unchanged.
      expect(
        counterText(tester, 'buttons-disabled'),
        'Disabled button presses: 0',
      );
      await tapVisible(tester, disabled);
      await tapVisible(tester, disabled);

      expect(
        counterText(tester, 'buttons-disabled'),
        'Disabled button presses: 0',
      );
      expect(counterText(tester, 'buttons-interaction'), 'Button presses: 0');
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('the counter survives scenario changes', (tester) async {
      await _pump(tester);
      await tapVisible(
        tester,
        inDemo('buttons-interaction', find.byType(CbsButton)),
      );

      await selectOption(
        tester,
        CatalogKeys.designOption(CatalogDesign.branded),
      );
      await selectOption(
        tester,
        CatalogKeys.appearanceOption(CatalogAppearance.dark),
      );
      await selectOption(tester, CatalogKeys.widthOption(CatalogWidth.w840));

      expect(counterText(tester, 'buttons-interaction'), 'Button presses: 1');
    });
  });

  group('CbsLoadingIndicator', () {
    testWidgets('shows indeterminate and determinate variants', (tester) async {
      await _pump(tester);

      final states = tester.widgetList<CbsLoadingIndicator>(
        inDemo('loading-states', find.byType(CbsLoadingIndicator)),
      );
      expect(states.map((i) => i.value), [null, 0.6]);

      final range = tester.widgetList<CbsLoadingIndicator>(
        inDemo('loading-range', find.byType(CbsLoadingIndicator)),
      );
      expect(range.map((i) => i.value), [0, 1]);
      expect(range.map((i) => i.semanticLabel), [
        '0 percent complete',
        '100 percent complete',
      ]);
    });

    testWidgets('exposes its semantic labels', (tester) async {
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

    testWidgets('indeterminate indicators keep animating', (tester) async {
      await _pump(tester);

      // No pumpAndSettle: the animation never settles, by design.
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('CbsFeedbackMessage', () {
    testWidgets('keeps the four types', (tester) async {
      await _pump(tester);

      expect(
        tester
            .widgetList<CbsFeedbackMessage>(
              inDemo('feedback-types', find.byType(CbsFeedbackMessage)),
            )
            .map((m) => m.type),
        CbsFeedbackType.values,
      );
    });

    testWidgets('expand false is compact and expand true fills the width', (
      tester,
    ) async {
      await _pump(tester, const CatalogScenario(width: CatalogWidth.w600));

      final messages = inDemo(
        'feedback-expand',
        find.byType(CbsFeedbackMessage),
      );
      expect(
        tester.widgetList<CbsFeedbackMessage>(messages).map((m) => m.expand),
        [false, true],
      );

      final compact = _size(tester, messages.first);
      final expanded = _size(tester, messages.last);
      expect(compact.width, lessThan(600));
      expect(expanded.width, 600);
    });

    testWidgets('long messages wrap inside the width at 320 px, x2', (
      tester,
    ) async {
      await _pump(tester, _narrowLargeText);

      final messages = inDemo('feedback-long', find.byType(CbsFeedbackMessage));
      for (final message in tester.widgetList<CbsFeedbackMessage>(messages)) {
        expect(message.message, FeedbackSection.longMessage);
      }
      for (var i = 0; i < messages.evaluate().length; i++) {
        final size = tester.getSize(messages.at(i));
        expect(size.width, lessThanOrEqualTo(320));
        // Several lines: much taller than a one-line message.
        expect(size.height, greaterThan(150));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('semantic label replaces the visible text for assistive tech', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      expect(find.bySemanticsLabel('Error: upload failed'), findsOneWidget);
      expect(
        _feedback(
          tester,
          inDemo('feedback-semantic', find.byType(CbsFeedbackMessage)),
        ).semanticLabel,
        'Error: upload failed',
      );
      handle.dispose();
    });
  });

  group('CbsStatePanel', () {
    testWidgets('frames representative consumer content', (tester) async {
      await _pump(tester);

      final panel = inDemo('state-panel-content', find.byType(CbsStatePanel));
      expect(panel, findsOneWidget);
      expect(
        find.descendant(of: panel, matching: find.byType(CbsSectionHeading)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.byType(CbsButton)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('Panel title')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('Panel action')),
        findsOneWidget,
      );
    });

    for (final width in CatalogWidth.values) {
      testWidgets('respects the width constraints at ${width.label}', (
        tester,
      ) async {
        await _pump(tester, CatalogScenario(width: width));

        expect(
          _size(
            tester,
            inDemo('state-panel-content', find.byType(CbsStatePanel)),
          ).width,
          width.logicalPixels,
        );
        expect(
          _size(
            tester,
            inDemo('state-panel-constrained', find.byType(CbsStatePanel)),
          ).width,
          200,
        );
        expect(tester.takeException(), isNull);
      });
    }

    for (final textScale in CatalogTextScale.simulated) {
      testWidgets('fills a 200 px parent instead of hugging its short content, '
          '${textScale.label}', (tester) async {
        await _pump(tester, CatalogScenario(textScale: textScale));

        final panel = inDemo(
          'state-panel-constrained',
          find.byType(CbsStatePanel),
        );
        final text = _text(
          'state-panel-constrained',
          StatePanelSection.constrainedText,
        );

        // The content stays on one line and its natural width is narrower
        // than the parent, so a panel hugging it would be narrower than
        // 200 px. The laid-out text is tight (it already fills the panel),
        // hence the intrinsic width.
        final contentWidth = tester
            .renderObject<RenderBox>(text)
            .getMaxIntrinsicWidth(double.infinity);
        final huggingWidth = contentWidth + 2 * CbsSpacing.lg;
        expect(huggingWidth, lessThan(StatePanelSection.constrainedWidth - 20));
        expect(_size(tester, text).height, lessThan(30 * textScale.factor!));

        // The panel fills the parent anyway.
        expect(_size(tester, panel).width, StatePanelSection.constrainedWidth);
        expect(_size(tester, panel).width, greaterThan(huggingWidth));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('uses the surface color of the effective theme', (
      tester,
    ) async {
      await _pump(tester);

      Color surface() {
        final panel = inDemo('state-panel-content', find.byType(CbsStatePanel));
        final box = tester.widget<DecoratedBox>(
          find.descendant(of: panel, matching: find.byType(DecoratedBox)).first,
        );
        return (box.decoration as BoxDecoration).color!;
      }

      final light = surface();
      expect(light, CbsTheme.essentials().colorScheme.surfaceContainerHighest);

      await selectOption(
        tester,
        CatalogKeys.appearanceOption(CatalogAppearance.dark),
      );
      await settleThemeAnimation(tester);

      final dark = surface();
      expect(
        dark,
        CbsTheme.essentials(brightness: Brightness.dark)
            .colorScheme
            .surfaceContainerHighest,
      );
      expect(dark, isNot(light));
    });
  });

  group('CbsRetryMessage', () {
    testWidgets('shows message and retry label, short and long', (
      tester,
    ) async {
      await _pump(tester);

      final short = tester.widget<CbsRetryMessage>(
        find.byKey(CatalogKeys.retryMessage('retry-short')),
      );
      expect(short.message, 'Content could not be loaded.');
      expect(short.retryLabel, 'Retry');
      expect(short.semanticLabel, 'Error: content could not be loaded');

      final long = tester.widget<CbsRetryMessage>(
        find.byKey(CatalogKeys.retryMessage('retry-long')),
      );
      expect(long.message, FeedbackSection.longMessage);
      expect(long.retryLabel, 'Try loading the content again');

      expect(_text('retry-short', 'Retry'), findsOneWidget);
      expect(
        _text('retry-long', 'Try loading the content again'),
        findsOneWidget,
      );
    });

    testWidgets('the callback is functional and visibly counted', (
      tester,
    ) async {
      await _pump(tester);
      expect(counterText(tester, 'retry-short'), 'Retry requests: 0');
      expect(counterText(tester, 'retry-long'), 'Retry requests: 0');

      await tapVisible(tester, retryButton('retry-short'));
      await tapVisible(tester, retryButton('retry-short'));
      await tapVisible(tester, retryButton('retry-long'));

      expect(counterText(tester, 'retry-short'), 'Retry requests: 2');
      expect(counterText(tester, 'retry-long'), 'Retry requests: 1');
      expect(counterText(tester, 'state-error'), 'Retry requests: 0');
    });

    testWidgets('the retry button is an enabled button for assistive tech', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      final node = tester.getSemantics(retryButton('retry-short'));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isTrue);
      expect(node.label, 'Retry');
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('long message and label fit at 320 px, x2', (tester) async {
      await _pump(tester, _narrowLargeText);

      for (final id in ['retry-short', 'retry-long']) {
        final size = _size(tester, find.byKey(CatalogKeys.retryMessage(id)));
        expect(size.width, lessThanOrEqualTo(320), reason: id);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('CbsSectionHeading', () {
    testWidgets('shows short and long titles', (tester) async {
      await _pump(tester);

      expect(
        _text('heading-short', SectionHeadingSection.shortTitle),
        findsOneWidget,
      );
      expect(
        _text('heading-long', SectionHeadingSection.longTitle),
        findsOneWidget,
      );
    });

    testWidgets('every heading is exposed as a heading', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      final headings = find.byType(CbsSectionHeading);
      final count = headings.evaluate().length;
      // Panel content, three heading demos, states Empty and Ready.
      expect(count, 6);
      for (var i = 0; i < count; i++) {
        final node = tester.getSemantics(headings.at(i));
        expect(node.flagsCollection.isHeader, isTrue, reason: 'heading $i');
      }
      handle.dispose();
    });

    testWidgets('keeps the consumer spacing and a typographic hierarchy', (
      tester,
    ) async {
      await _pump(tester);

      final heading = inDemo('heading-short', find.byType(CbsSectionHeading));
      final content = _text(
        'heading-short',
        'Content below the heading, separated by CbsSpacing.sm.',
      );
      expect(
        tester.getRect(content).top - tester.getRect(heading).bottom,
        CbsSpacing.sm,
      );

      TextStyle styleOf(Finder finder) => tester.widget<Text>(finder).style!;
      final screenTitle = styleOf(
        _text('heading-hierarchy', 'Screen title (titleLarge)'),
      );
      final section = styleOf(
        find.descendant(
          of: inDemo('heading-hierarchy', find.byType(CbsSectionHeading)),
          matching: find.byType(Text),
        ),
      );
      final body = styleOf(
        _text('heading-hierarchy', 'Body text (bodyMedium)'),
      );

      expect(screenTitle.fontSize, greaterThan(section.fontSize!));
      expect(section.fontSize, greaterThan(body.fontSize!));
      expect(section.fontWeight, FontWeight.w700);
    });

    testWidgets('a long title wraps and follows the text scale', (
      tester,
    ) async {
      await _pump(tester);
      final shortX1 = _size(
        tester,
        inDemo('heading-short', find.byType(CbsSectionHeading)),
      );
      final longX1 = _size(
        tester,
        inDemo('heading-long', find.byType(CbsSectionHeading)),
      );
      expect(longX1.height, greaterThan(shortX1.height));
      expect(longX1.width, lessThanOrEqualTo(320));

      await selectOption(
        tester,
        CatalogKeys.textScaleOption(CatalogTextScale.x2),
      );

      final shortX2 = _size(
        tester,
        inDemo('heading-short', find.byType(CbsSectionHeading)),
      );
      expect(shortX2.height, greaterThan(shortX1.height * 1.9));
      expect(tester.takeException(), isNull);
    });
  });

  group('application states', () {
    testWidgets('shows Loading, Empty, Error and Ready in order', (
      tester,
    ) async {
      await _pump(tester);

      var previousTop = double.negativeInfinity;
      for (final state in ['loading', 'empty', 'error', 'ready']) {
        final demo = find.byKey(CatalogKeys.demo('state-$state'));
        expect(demo, findsOneWidget);
        final top = tester.getTopLeft(demo).dy;
        expect(top, greaterThan(previousTop), reason: state);
        previousTop = top;
      }
    });

    testWidgets('are composed from existing CBS widgets', (tester) async {
      await _pump(tester);

      Finder within(String id, Type type) => inDemo(id, find.byType(type));

      // Loading: panel + indicator.
      expect(within('state-loading', CbsStatePanel), findsOneWidget);
      expect(within('state-loading', CbsLoadingIndicator), findsOneWidget);
      // Empty: panel + heading.
      expect(within('state-empty', CbsStatePanel), findsOneWidget);
      expect(within('state-empty', CbsSectionHeading), findsOneWidget);
      // Error: retry message.
      expect(within('state-error', CbsRetryMessage), findsOneWidget);
      expect(within('state-error', CbsFeedbackMessage), findsOneWidget);
      expect(
        _feedback(tester, within('state-error', CbsFeedbackMessage)).type,
        CbsFeedbackType.error,
      );
      // Ready: heading + content + action, no panel.
      expect(within('state-ready', CbsSectionHeading), findsOneWidget);
      expect(within('state-ready', CbsButton), findsOneWidget);
      expect(within('state-ready', CbsStatePanel), findsNothing);
      expect(_text('state-ready', 'First sample item'), findsOneWidget);
    });

    testWidgets('Error offers an interactive retry', (tester) async {
      await _pump(tester);
      expect(counterText(tester, 'state-error'), 'Retry requests: 0');

      await tapVisible(tester, retryButton('state-error'));

      expect(counterText(tester, 'state-error'), 'Retry requests: 1');
      // The error stays displayed: the example loads nothing.
      expect(
        find.byKey(CatalogKeys.retryMessage('state-error')),
        findsOneWidget,
      );
      expect(counterText(tester, 'retry-short'), 'Retry requests: 0');
    });

    testWidgets('Error keeps its count when the scenario changes', (
      tester,
    ) async {
      await _pump(tester);
      await tapVisible(tester, retryButton('state-error'));

      await selectOption(
        tester,
        CatalogKeys.designOption(CatalogDesign.branded),
      );
      await selectOption(tester, CatalogKeys.widthOption(CatalogWidth.w1280));
      await selectOption(
        tester,
        CatalogKeys.textScaleOption(CatalogTextScale.x2),
      );

      expect(counterText(tester, 'state-error'), 'Retry requests: 1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Loading exposes its semantic label', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      expect(
        tester
            .widget<CbsLoadingIndicator>(
              inDemo('state-loading', find.byType(CbsLoadingIndicator)),
            )
            .semanticLabel,
        'Loading content',
      );
      handle.dispose();
    });

    testWidgets('use the effective theme colors in dark Branded', (
      tester,
    ) async {
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
      final errorStyle = CbsFeedbackStyle.resolve(
        scheme,
        CbsFeedbackType.error,
      );

      final feedback = find.descendant(
        of: find.byKey(CatalogKeys.demo('state-error')),
        matching: find.byType(CbsFeedbackMessage),
      );
      final decoration =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: feedback,
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      expect(decoration.color, errorStyle.background);

      final emptyPanel = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: inDemo('state-empty', find.byType(CbsStatePanel)),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (emptyPanel.decoration as BoxDecoration).color,
        scheme.surfaceContainerHighest,
      );
    });
  });

  group('CbsMediaFrame', () {
    Finder frame(String demoId) => inDemo(demoId, find.byType(CbsMediaFrame));

    CbsMediaFrame widgetOf(WidgetTester tester, String demoId) =>
        tester.widget<CbsMediaFrame>(frame(demoId));

    BorderRadiusGeometry radiusOf(WidgetTester tester, String demoId) => tester
        .widget<ClipRRect>(
          find.descendant(of: frame(demoId), matching: find.byType(ClipRRect)),
        )
        .borderRadius;

    testWidgets('is shown in its section, once per variant', (tester) async {
      await _pump(tester);

      expect(
        inSection('media-frame', find.byType(CbsMediaFrame)),
        findsNWidgets(4),
      );
      for (final id in [
        'media-16-9',
        'media-1-1',
        'media-custom',
        'media-placeholder',
      ]) {
        expect(frame(id), findsOneWidget, reason: id);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the 16:9, 1:1, custom and placeholder variants', (
      tester,
    ) async {
      await _pump(tester);

      expect(widgetOf(tester, 'media-16-9').aspectRatio, 16 / 9);
      expect(widgetOf(tester, 'media-1-1').aspectRatio, 1);
      expect(
        widgetOf(tester, 'media-custom').aspectRatio,
        MediaFrameSection.customAspectRatio,
      );
      expect(widgetOf(tester, 'media-placeholder').aspectRatio, 16 / 9);

      expect(
        _text('media-16-9', MediaFrameSection.ratioWideCaption),
        findsOneWidget,
      );
      expect(
        _text('media-1-1', MediaFrameSection.ratioSquareCaption),
        findsOneWidget,
      );
      expect(
        _text('media-custom', MediaFrameSection.customCaption),
        findsOneWidget,
      );
      expect(
        inDemo('media-placeholder', find.byIcon(Icons.image_outlined)),
        findsOneWidget,
      );
    });

    testWidgets('the custom variant sets its own radius and label', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        widgetOf(tester, 'media-custom').semanticLabel,
        MediaFrameSection.customSemanticLabel,
      );
      expect(
        radiusOf(tester, 'media-custom'),
        BorderRadius.circular(CbsRadius.xl),
      );
      for (final id in ['media-16-9', 'media-1-1', 'media-placeholder']) {
        expect(
          radiusOf(tester, id),
          BorderRadius.circular(CbsRadius.md),
          reason: id,
        );
      }
    });

    testWidgets('exposes the semantic labels of the labelled variants', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      for (final label in [
        MediaFrameSection.customSemanticLabel,
        MediaFrameSection.placeholderSemanticLabel,
      ]) {
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(label))),
          findsOneWidget,
          reason: label,
        );
      }
      handle.dispose();
    });

    for (final width in CatalogWidth.values) {
      testWidgets('keeps its ratio at ${width.label}', (tester) async {
        await _pump(tester, CatalogScenario(width: width));

        final available = width.logicalPixels;
        final compact = available < MediaFrameSection.compactMaxWidth
            ? available
            : MediaFrameSection.compactMaxWidth;

        for (final id in ['media-16-9', 'media-placeholder']) {
          final size = _size(tester, frame(id));
          expect(size.width, available, reason: id);
          expect(size.height, closeTo(available * 9 / 16, 0.001), reason: id);
        }
        expect(_size(tester, frame('media-1-1')), Size(compact, compact));
        final custom = _size(tester, frame('media-custom'));
        expect(custom.width, compact);
        expect(
          custom.height,
          closeTo(compact / MediaFrameSection.customAspectRatio, 0.001),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('does not overflow at 320 px, text x2', (tester) async {
      await _pump(tester, _narrowLargeText);

      expect(tester.takeException(), isNull);
      expect(_size(tester, frame('media-16-9')).width, 320);
      expect(_size(tester, frame('media-custom')).height, closeTo(180, 0.001));
    });

    testWidgets('the placeholder uses the surface color of the theme', (
      tester,
    ) async {
      await _pump(tester);

      Color placeholder() => tester
          .widget<ColoredBox>(
            find
                .descendant(
                  of: frame('media-placeholder'),
                  matching: find.byType(ColoredBox),
                )
                .first,
          )
          .color;

      expect(
        placeholder(),
        CbsTheme.essentials().colorScheme.surfaceContainerHighest,
      );

      await selectOption(
        tester,
        CatalogKeys.appearanceOption(CatalogAppearance.dark),
      );
      await settleThemeAnimation(tester);

      expect(
        placeholder(),
        CbsTheme.essentials(brightness: Brightness.dark)
            .colorScheme
            .surfaceContainerHighest,
      );
    });
  });

  group('CbsAdaptiveCollection', () {
    Finder collection(String demoId) =>
        inDemo(demoId, find.byType(CbsAdaptiveCollection));

    CbsAdaptiveCollection widgetOf(WidgetTester tester, String demoId) =>
        tester.widget<CbsAdaptiveCollection>(collection(demoId));

    Finder cards(String demoId) => inDemo(demoId, find.byType(CbsContentCard));

    /// Title of [card]: tapping it activates the whole card.
    Finder cardTitle(Finder card) => find.descendant(
      of: card,
      matching: find.text(AdaptiveCollectionSection.cardTitle),
    );

    /// Texts of the tiles of [demoId], in the order of the children.
    List<Finder> tiles(String demoId, String prefix, int count) => [
      for (var i = 1; i <= count; i++)
        _text(demoId, AdaptiveCollectionSection.tileText(prefix, i)),
    ];

    /// Number of finders laid out on the same row as the first one.
    int firstRow(WidgetTester tester, List<Finder> finders) {
      final firstTop = tester.getTopLeft(finders.first).dy;
      return finders
          .where((f) => (tester.getTopLeft(f).dy - firstTop).abs() < 0.001)
          .length;
    }

    double cell(CatalogWidth width) {
      final columns = _collectionColumns[width]!;
      return (width.logicalPixels - 12 * (columns - 1)) / columns;
    }

    testWidgets('is shown in its section, once per variant', (tester) async {
      await _pump(tester);

      expect(
        inSection('adaptive-collection', find.byType(CbsAdaptiveCollection)),
        findsNWidgets(5),
      );
      for (final id in [
        'collection-list',
        'collection-grid',
        'collection-cards',
        'collection-media',
        'collection-narrow',
      ]) {
        expect(collection(id), findsOneWidget, reason: id);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the list and grid layouts with their children', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        widgetOf(tester, 'collection-list').layout,
        CbsCollectionLayout.list,
      );
      expect(
        widgetOf(tester, 'collection-list').children,
        hasLength(AdaptiveCollectionSection.listCount),
      );
      for (final (id, count) in [
        ('collection-grid', AdaptiveCollectionSection.gridCount),
        ('collection-cards', AdaptiveCollectionSection.cardCount),
        ('collection-media', AdaptiveCollectionSection.mediaCount),
        ('collection-narrow', AdaptiveCollectionSection.narrowCount),
      ]) {
        expect(
          widgetOf(tester, id).layout,
          CbsCollectionLayout.grid,
          reason: id,
        );
        expect(widgetOf(tester, id).children, hasLength(count), reason: id);
      }

      for (final finder in [
        ...tiles(
          'collection-list',
          AdaptiveCollectionSection.listPrefix,
          AdaptiveCollectionSection.listCount,
        ),
        ...tiles(
          'collection-grid',
          AdaptiveCollectionSection.gridPrefix,
          AdaptiveCollectionSection.gridCount,
        ),
      ]) {
        expect(finder, findsOneWidget);
      }
    });

    testWidgets('composes CbsContentCard and CbsMediaFrame', (tester) async {
      await _pump(tester);

      expect(
        cards('collection-cards'),
        findsNWidgets(AdaptiveCollectionSection.cardCount),
      );
      expect(
        cards('collection-media'),
        findsNWidgets(AdaptiveCollectionSection.mediaCount),
      );
      expect(
        inDemo('collection-media', find.byType(CbsMediaFrame)),
        findsNWidgets(AdaptiveCollectionSection.mediaCount),
      );
      expect(
        cards('collection-narrow'),
        findsNWidgets(AdaptiveCollectionSection.narrowCount),
      );
      expect(
        inDemo('collection-narrow', find.byType(CbsMediaFrame)),
        findsNWidgets(AdaptiveCollectionSection.narrowCount),
      );
    });

    for (final width in CatalogWidth.values) {
      testWidgets('the list stacks the tiles over the full width at '
          '${width.label}', (tester) async {
        await _pump(tester, CatalogScenario(width: width));

        final texts = tiles(
          'collection-list',
          AdaptiveCollectionSection.listPrefix,
          AdaptiveCollectionSection.listCount,
        );
        expect(
          _size(tester, collection('collection-list')).width,
          width.logicalPixels,
        );
        expect(firstRow(tester, texts), 1);
        var previousTop = double.negativeInfinity;
        for (final text in texts) {
          final top = tester.getTopLeft(text).dy;
          expect(top, greaterThan(previousTop));
          previousTop = top;
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('the grid adapts its columns at ${width.label}', (
        tester,
      ) async {
        await _pump(tester, CatalogScenario(width: width));

        final columns = _collectionColumns[width]!;
        final texts = tiles(
          'collection-grid',
          AdaptiveCollectionSection.gridPrefix,
          AdaptiveCollectionSection.gridCount,
        );
        expect(
          _size(tester, collection('collection-grid')).width,
          width.logicalPixels,
        );
        expect(firstRow(tester, texts), columns);

        // The cards of the grids follow the same columns; the first row
        // cannot hold more cards than the grid has.
        for (final id in ['collection-cards', 'collection-media']) {
          final list = cards(id);
          expect(
            _size(tester, list.first).width,
            closeTo(cell(width), 0.001),
            reason: id,
          );
          expect(
            firstRow(tester, [
              for (var i = 0; i < AdaptiveCollectionSection.cardCount; i++)
                list.at(i),
            ]),
            math.min(columns, AdaptiveCollectionSection.cardCount),
            reason: id,
          );
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('the narrow parent gives a single column at '
          '${width.label}', (tester) async {
        await _pump(tester, CatalogScenario(width: width));

        expect(
          _size(tester, collection('collection-narrow')).width,
          AdaptiveCollectionSection.narrowWidth,
        );
        final list = cards('collection-narrow');
        var previousTop = double.negativeInfinity;
        for (var i = 0; i < AdaptiveCollectionSection.narrowCount; i++) {
          expect(
            _size(tester, list.at(i)).width,
            AdaptiveCollectionSection.narrowWidth,
          );
          final top = tester.getTopLeft(list.at(i)).dy;
          expect(top, greaterThan(previousTop));
          previousTop = top;
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the cards react to taps and to their action', (tester) async {
      await _pump(tester, const CatalogScenario(width: CatalogWidth.w1280));
      expect(
        counterText(tester, 'collection-cards'),
        'Collection card taps: 0',
      );
      expect(
        counterText(tester, 'collection-action'),
        'Collection action presses: 0',
      );

      final list = cards('collection-cards');
      await tapVisible(tester, cardTitle(list.at(0)));
      await tapVisible(tester, cardTitle(list.at(2)));

      expect(
        counterText(tester, 'collection-cards'),
        'Collection card taps: 2',
      );
      expect(
        counterText(tester, 'collection-action'),
        'Collection action presses: 0',
      );

      // The action is independent from the card.
      await tapVisible(
        tester,
        inDemo('collection-cards', find.byType(TextButton)).at(1),
      );

      expect(
        counterText(tester, 'collection-cards'),
        'Collection card taps: 2',
      );
      expect(
        counterText(tester, 'collection-action'),
        'Collection action presses: 1',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the counters survive scenario changes', (tester) async {
      await _pump(tester);
      await tapVisible(tester, cardTitle(cards('collection-cards').at(1)));

      await selectOption(tester, CatalogKeys.widthOption(CatalogWidth.w840));
      await selectOption(
        tester,
        CatalogKeys.designOption(CatalogDesign.branded),
      );

      expect(
        counterText(tester, 'collection-cards'),
        'Collection card taps: 1',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('exposes the semantic labels of the media', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);

      for (var i = 1; i <= AdaptiveCollectionSection.mediaCount; i++) {
        expect(
          find.bySemanticsLabel(
            RegExp(RegExp.escape(AdaptiveCollectionSection.mediaLabel(i))),
          ),
          findsOneWidget,
          reason: 'media $i',
        );
      }
      handle.dispose();
    });

    testWidgets('does not overflow at 320 px, text x2', (tester) async {
      await _pump(tester, _narrowLargeText);

      expect(tester.takeException(), isNull);
      for (final id in [
        'collection-list',
        'collection-grid',
        'collection-cards',
        'collection-media',
      ]) {
        expect(_size(tester, collection(id)).width, 320, reason: id);
      }
      expect(
        _size(tester, collection('collection-narrow')).width,
        AdaptiveCollectionSection.narrowWidth,
      );
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
      final card = tester.widget<Material>(
        find
            .descendant(
              of: cards('collection-cards').first,
              matching: find.byType(Material),
            )
            .first,
      );
      expect(card.color, scheme.surfaceContainerLow);
      expect(tester.takeException(), isNull);
    });
  });

  group('scenario matrix: content, interactions and width coherence', () {
    for (final scenario in CatalogScenario.all) {
      testWidgets(scenario.summary, (tester) async {
        await _pump(tester, scenario);
        final width = scenario.width.logicalPixels;

        // MediaQuery and constraints agree for the whole preview.
        expect(previewMediaQuery(tester).size.width, width);
        expect(
          _size(tester, find.byKey(CatalogKeys.previewContent)).width,
          width,
        );
        expect(
          _size(
            tester,
            inDemo('state-panel-content', find.byType(CbsStatePanel)),
          ).width,
          width,
        );
        expect(
          _size(
            tester,
            inDemo('feedback-expand', find.byType(CbsFeedbackMessage)).last,
          ).width,
          width,
        );
        expect(
          _size(
            tester,
            find.byKey(CatalogKeys.retryMessage('retry-long')),
          ).width,
          width,
        );

        // Interactions keep working in every scenario.
        await tapVisible(
          tester,
          inDemo('buttons-interaction', find.byType(CbsButton)),
        );
        await tapVisible(tester, retryButton('state-error'));
        await tapVisible(tester, retryButton('retry-long'));

        expect(counterText(tester, 'buttons-interaction'), 'Button presses: 1');
        expect(counterText(tester, 'state-error'), 'Retry requests: 1');
        expect(counterText(tester, 'retry-long'), 'Retry requests: 1');
        expect(counterText(tester, 'retry-short'), 'Retry requests: 0');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
