import 'dart:ui' show SemanticsAction, Tristate;

import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cbs_test_matrix.dart';

const String _message = 'Les contenus n’ont pas pu être chargés.';
const String _retryLabel = 'Réessayer';
const String _longMessage =
    'Les contenus à la une n’ont pas pu être chargés pour le moment, merci '
    'de vérifier votre connexion puis de réessayer dans quelques instants.';

void _noop() {}

void main() {
  testWidgets('composes CbsFeedbackMessage (error) and CbsButton', (
    tester,
  ) async {
    await pumpCbs(
      tester,
      child: const CbsRetryMessage(
        message: _message,
        retryLabel: _retryLabel,
        onRetry: _noop,
      ),
    );

    final feedback = tester.widget<CbsFeedbackMessage>(
      find.descendant(
        of: find.byType(CbsRetryMessage),
        matching: find.byType(CbsFeedbackMessage),
      ),
    );
    expect(feedback.type, CbsFeedbackType.error);
    expect(feedback.expand, isTrue);
    expect(feedback.message, _message);
    expect(find.text(_message), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    expect(find.byType(CbsButton), findsOneWidget);
    expect(find.text(_retryLabel), findsOneWidget);
  });

  testWidgets('renders only the texts provided by the consumer', (
    tester,
  ) async {
    await pumpCbs(
      tester,
      child: const CbsRetryMessage(
        message: 'Load failed',
        retryLabel: 'Try again',
        onRetry: _noop,
      ),
    );

    final texts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(CbsRetryMessage),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data)
        .toList();

    expect(texts, ['Load failed', 'Try again']);
  });

  testWidgets('uses the error colors of the active theme', (tester) async {
    final theme = CbsTheme.essentials();

    await pumpCbs(
      tester,
      theme: theme,
      child: const CbsRetryMessage(
        message: _message,
        retryLabel: _retryLabel,
        onRetry: _noop,
      ),
    );

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(CbsFeedbackMessage),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;

    expect(decoration.color, theme.colorScheme.errorContainer);
    expect(
      tester.widget<Text>(find.text(_message)).style?.color,
      theme.colorScheme.onErrorContainer,
    );
  });

  group('interaction', () {
    testWidgets('tap calls onRetry once', (tester) async {
      var retries = 0;

      await pumpCbs(
        tester,
        child: CbsRetryMessage(
          message: _message,
          retryLabel: _retryLabel,
          onRetry: () => retries++,
        ),
      );

      await tester.tap(find.text(_retryLabel));
      await tester.pump();

      expect(retries, 1);
    });

    testWidgets('does not call onRetry without user action', (tester) async {
      var retries = 0;

      await pumpCbs(
        tester,
        child: CbsRetryMessage(
          message: _message,
          retryLabel: _retryLabel,
          onRetry: () => retries++,
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(retries, 0);
    });

    testWidgets('tapping the message does not call onRetry', (tester) async {
      var retries = 0;

      await pumpCbs(
        tester,
        child: CbsRetryMessage(
          message: _message,
          retryLabel: _retryLabel,
          onRetry: () => retries++,
        ),
      );

      await tester.tap(find.text(_message));
      await tester.pump();

      expect(retries, 0);
    });

    testWidgets('keyboard activation calls onRetry', (tester) async {
      var retries = 0;

      await pumpCbs(
        tester,
        child: CbsRetryMessage(
          message: _message,
          retryLabel: _retryLabel,
          onRetry: () => retries++,
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(retries, 1);
    });

    testWidgets('a keyed instance stays activatable by key', (tester) async {
      var retries = 0;

      await pumpCbs(
        tester,
        child: CbsRetryMessage(
          key: const ValueKey('consumer-retry'),
          message: _message,
          retryLabel: _retryLabel,
          onRetry: () => retries++,
        ),
      );

      expect(find.byKey(const ValueKey('consumer-retry')), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('consumer-retry')),
          matching: find.byType(CbsButton),
        ),
      );
      await tester.pump();

      expect(retries, 1);
    });
  });

  for (final variant in cbsTestThemes) {
    for (final width in cbsTestWidths) {
      for (final scale in cbsTestTextScales) {
        testWidgets(
          'layout contract: ${variant.name}, width $width, text x$scale',
          (tester) async {
            await pumpCbs(
              tester,
              theme: variant.theme,
              width: width,
              textScale: scale,
              child: const CbsRetryMessage(
                message: _longMessage,
                retryLabel: _retryLabel,
                onRetry: _noop,
              ),
            );

            expect(tester.takeException(), isNull);

            final feedback = tester.getRect(find.byType(CbsFeedbackMessage));
            final button = tester.getRect(find.byType(CbsButton));

            // Message at maximum width, button aligned to the start.
            expect(feedback.left, 0);
            expect(feedback.width, width);
            expect(button.left, 0);
            expect(button.width, lessThanOrEqualTo(width));

            // Vertical gap of 8 between message and button.
            expect(button.top - feedback.bottom, CbsSpacing.sm);
          },
        );
      }
    }
  }

  testWidgets('keeps the CURRENT Home layout', (tester) async {
    Widget current() => const Column(
      key: ValueKey('current-home-retry'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: CbsFeedbackMessage(
            type: CbsFeedbackType.error,
            message: _message,
          ),
        ),
        SizedBox(height: CbsSpacing.sm),
        CbsButton(label: _retryLabel, onPressed: _noop),
      ],
    );

    for (final width in cbsTestWidths) {
      for (final scale in cbsTestTextScales) {
        await pumpCbs(tester, width: width, textScale: scale, child: current());
        final expected = (
          tester.getRect(find.byType(CbsFeedbackMessage)),
          tester.getRect(find.byType(CbsButton)),
          tester.getSize(find.byKey(const ValueKey('current-home-retry'))),
        );

        await pumpCbs(
          tester,
          width: width,
          textScale: scale,
          child: const CbsRetryMessage(
            message: _message,
            retryLabel: _retryLabel,
            onRetry: _noop,
          ),
        );
        final actual = (
          tester.getRect(find.byType(CbsFeedbackMessage)),
          tester.getRect(find.byType(CbsButton)),
          tester.getSize(find.byType(CbsRetryMessage)),
        );

        expect(actual, expected, reason: 'width $width, text x$scale');
      }
    }
  });

  group('semantics', () {
    testWidgets('semanticLabel describes the message only', (tester) async {
      final semantics = tester.ensureSemantics();

      await pumpCbs(
        tester,
        child: const CbsRetryMessage(
          message: _message,
          retryLabel: _retryLabel,
          semanticLabel: 'Erreur : les contenus n’ont pas pu être chargés.',
          onRetry: _noop,
        ),
      );

      expect(
        find.bySemanticsLabel(
          'Erreur : les contenus n’ont pas pu être chargés.',
        ),
        findsOneWidget,
      );
      // The visual text is excluded in favour of the semantic label.
      expect(find.bySemanticsLabel(_message), findsNothing);

      // The retry button keeps its own role and label.
      final button = tester.getSemantics(find.byType(FilledButton));
      expect(button.flagsCollection.isButton, isTrue);
      expect(button.label, _retryLabel);

      semantics.dispose();
    });

    testWidgets('without semanticLabel the message text is exposed', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await pumpCbs(
        tester,
        child: const CbsRetryMessage(
          message: _message,
          retryLabel: _retryLabel,
          onRetry: _noop,
        ),
      );

      expect(find.bySemanticsLabel(_message), findsOneWidget);

      semantics.dispose();
    });

    testWidgets('retry button is an enabled button with a tap action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await pumpCbs(
        tester,
        child: const CbsRetryMessage(
          message: _message,
          retryLabel: _retryLabel,
          onRetry: _noop,
        ),
      );

      final node = tester.getSemantics(find.byType(FilledButton));

      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isTrue);
      expect(node.label, _retryLabel);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      semantics.dispose();
    });
  });
}
