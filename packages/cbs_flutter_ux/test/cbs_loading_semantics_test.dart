// D03c-A.2 / C2 — CbsLoadingIndicator semantics, tested in isolation.
//
// The existing tests only check that the widget forwards `semanticLabel` to
// the `CircularProgressIndicator` property
// (cbs_loading_accessibility_test.dart) or that the label is findable inside
// CbsStatePanel. These tests read the resulting semantics tree.
//
// CbsLoadingIndicator exposes `value` and `semanticLabel` only: it has no
// `semanticValue` parameter, so the progress value exposed to assistive
// technologies is the one computed by Flutter (percentage of the clamped
// value). No API is added or assumed here.
//
// The indeterminate indicator runs an endless animation: these tests use
// `pump()` and never `pumpAndSettle()`.
//
// Automated checks read the Flutter semantics tree. They do not prove what
// TalkBack or VoiceOver announce: that stays NOT_VERIFIED.

import 'dart:ui' show SemanticsAction, SemanticsRole;

import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsData;
import 'package:flutter_test/flutter_test.dart';

import 'support/cbs_test_matrix.dart';

const String _label = 'Chargement des données';

Widget _app(ThemeData theme, Widget child) {
  return MaterialApp(
    theme: theme,
    home: Scaffold(body: Center(child: child)),
  );
}

SemanticsData _data(WidgetTester tester) {
  return tester
      .getSemantics(find.byType(CircularProgressIndicator))
      .getSemanticsData();
}

void main() {
  for (final variant in cbsTestThemes) {
    group('semantics — ${variant.name}', () {
      testWidgets('indeterminate with label: label and spinner role', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(variant.theme, const CbsLoadingIndicator(semanticLabel: _label)),
        );

        final data = _data(tester);

        expect(data.label, _label);
        expect(data.role, SemanticsRole.loadingSpinner);
        expect(data.value, isEmpty);
        expect(find.bySemanticsLabel(_label), findsOneWidget);

        semantics.dispose();
      });

      testWidgets('determinate with label: label, progress role and 0-100', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            variant.theme,
            const CbsLoadingIndicator(value: 0.5, semanticLabel: _label),
          ),
        );

        final data = _data(tester);

        expect(data.label, _label);
        expect(data.role, SemanticsRole.progressBar);
        expect(data.value, '50');
        expect(data.minValue, '0');
        expect(data.maxValue, '100');
        expect(find.bySemanticsLabel(_label), findsOneWidget);

        semantics.dispose();
      });
    });
  }

  group('determinate progress value', () {
    for (final (value, expected) in [
      (0.0, '0'),
      (0.25, '25'),
      (0.5, '50'),
      (0.99, '99'),
      (1.0, '100'),
    ]) {
      testWidgets('value $value is exposed as $expected', (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            CbsTheme.essentials(),
            CbsLoadingIndicator(value: value, semanticLabel: _label),
          ),
        );

        expect(_data(tester).value, expected);

        semantics.dispose();
      });
    }

    // The documented range is 0.0 to 1.0. Flutter clamps instead of
    // asserting, so the exposed value never leaves the 0-100 range.
    for (final (value, expected) in [(-0.5, '0'), (1.5, '100')]) {
      testWidgets('out-of-range $value is clamped to $expected', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(
            CbsTheme.essentials(),
            CbsLoadingIndicator(value: value, semanticLabel: _label),
          ),
        );

        expect(_data(tester).value, expected);
        expect(tester.takeException(), isNull);

        semantics.dispose();
      });
    }

    testWidgets('a progress update is reflected in the semantics tree', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final progress = ValueNotifier<double>(0.2);
      addTearDown(progress.dispose);

      await tester.pumpWidget(
        _app(
          CbsTheme.essentials(),
          ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (context, value, _) =>
                CbsLoadingIndicator(value: value, semanticLabel: _label),
          ),
        ),
      );
      expect(_data(tester).value, '20');

      progress.value = 0.8;
      await tester.pump();

      expect(_data(tester).value, '80');
      expect(_data(tester).label, _label);

      semantics.dispose();
    });

    testWidgets('switching from indeterminate to determinate updates role', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final progress = ValueNotifier<double?>(null);
      addTearDown(progress.dispose);

      await tester.pumpWidget(
        _app(
          CbsTheme.essentials(),
          ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (context, value, _) =>
                CbsLoadingIndicator(value: value, semanticLabel: _label),
          ),
        ),
      );
      expect(_data(tester).role, SemanticsRole.loadingSpinner);

      progress.value = 0.4;
      await tester.pump();

      expect(_data(tester).role, SemanticsRole.progressBar);
      expect(_data(tester).value, '40');

      progress.value = null;
      await tester.pump();

      expect(_data(tester).role, SemanticsRole.loadingSpinner);
      expect(_data(tester).value, isEmpty);

      semantics.dispose();
    });
  });

  group('without semanticLabel', () {
    // Behaviour characterization. CbsLoadingIndicator adds no default label:
    // like CbsFeedbackMessage and CbsRetryMessage, accessible texts come from
    // the consumer in its current language. Without a label, a screen reader
    // user gets a spinner with no description. Reported as a limitation and
    // a recommendation, not as a defect of the current contract.
    testWidgets('indeterminate: spinner role without any label or value', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(CbsTheme.essentials(), const CbsLoadingIndicator()),
      );

      final data = _data(tester);

      expect(data.label, isEmpty);
      expect(data.value, isEmpty);
      expect(data.role, SemanticsRole.loadingSpinner);

      semantics.dispose();
    });

    testWidgets('determinate: the percentage is exposed without a label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(CbsTheme.essentials(), const CbsLoadingIndicator(value: 0.5)),
      );

      final data = _data(tester);

      expect(data.label, isEmpty);
      expect(data.role, SemanticsRole.progressBar);
      expect(data.value, '50');

      semantics.dispose();
    });

    testWidgets('an empty label is treated as no label', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          CbsTheme.essentials(),
          const CbsLoadingIndicator(semanticLabel: ''),
        ),
      );

      expect(_data(tester).label, isEmpty);
      expect(tester.takeException(), isNull);

      semantics.dispose();
    });
  });

  group('isolation', () {
    testWidgets('renders no visible text and no tap action', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          CbsTheme.essentials(),
          const CbsLoadingIndicator(semanticLabel: _label),
        ),
      );

      expect(find.byType(Text), findsNothing);
      expect(find.text(_label), findsNothing);
      expect(_data(tester).hasAction(SemanticsAction.tap), isFalse);

      semantics.dispose();
    });

    testWidgets('does not take keyboard focus', (tester) async {
      await tester.pumpWidget(
        _app(
          CbsTheme.essentials(),
          const CbsLoadingIndicator(semanticLabel: _label),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(CbsLoadingIndicator),
          matching: find.byType(Focus),
        ),
        findsNothing,
      );
    });
  });
}
