// D03c-A.2 / C2 — keyboard and focus qualification.
//
// Complements the existing Tab + Enter activation tests of
// cbs_button_accessibility_test.dart and cbs_retry_message_test.dart, which
// are kept untouched and are not duplicated here. Added coverage:
//
// * Space activation;
// * Tab focus actually landing on the CBS control, exposed in semantics;
// * a disabled CbsButton: not focusable, never activated by Enter or Space,
//   skipped by Tab traversal, and not activated after becoming disabled while
//   focused;
// * focus order, Shift+Tab and wrap-around across several controls;
// * non-interactive CBS parts (feedback message, heading, state panel) never
//   take focus;
// * focus stability across rebuilds and after activation.
//
// CbsRetryMessage has no disabled state (onRetry is required): the disabled
// keyboard checks are NOT_APPLICABLE for it.

import 'dart:ui' show Tristate;

import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cbs_a11y_support.dart';

const String _message = 'Les contenus n’ont pas pu être chargés.';
const String _retryLabel = 'Réessayer';

Future<void> _tab(WidgetTester tester, {bool shift = false}) async {
  if (shift) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (shift) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.pump();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  group('CbsButton keyboard activation', () {
    for (final (name, key) in [
      ('Enter', LogicalKeyboardKey.enter),
      ('Space', LogicalKeyboardKey.space),
    ]) {
      testWidgets('$name activates the focused button exactly once', (
        tester,
      ) async {
        var activations = 0;
        await pumpA11y(
          tester,
          child: CbsButton(label: 'Continue', onPressed: () => activations++),
        );

        await _tab(tester);
        await _press(tester, key);

        expect(activations, 1);
      });
    }

    testWidgets('Enter and Space each activate once, in sequence', (
      tester,
    ) async {
      var activations = 0;
      await pumpA11y(
        tester,
        child: CbsButton(label: 'Continue', onPressed: () => activations++),
      );

      await _tab(tester);
      await _press(tester, LogicalKeyboardKey.enter);
      await _press(tester, LogicalKeyboardKey.space);

      expect(activations, 2);
    });

    testWidgets('Enter and Space do nothing before the button has focus', (
      tester,
    ) async {
      var activations = 0;
      await pumpA11y(
        tester,
        child: CbsButton(label: 'Continue', onPressed: () => activations++),
      );

      await _press(tester, LogicalKeyboardKey.enter);
      await _press(tester, LogicalKeyboardKey.space);

      expect(activations, 0);
    });

    testWidgets('Tab moves focus onto the button and exposes it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpA11y(
        tester,
        child: CbsButton(
          key: const ValueKey('button'),
          label: 'Continue',
          onPressed: () {},
        ),
      );

      expect(
        hasPrimaryFocusWithin(tester, find.byKey(const ValueKey('button'))),
        isFalse,
      );
      expect(
        tester
            .getSemantics(find.byType(FilledButton))
            .flagsCollection
            .isFocused,
        isNot(Tristate.isTrue),
      );

      await _tab(tester);

      expect(
        hasPrimaryFocusWithin(tester, find.byKey(const ValueKey('button'))),
        isTrue,
      );
      expect(
        tester
            .getSemantics(find.byType(FilledButton))
            .flagsCollection
            .isFocused,
        Tristate.isTrue,
      );

      semantics.dispose();
    });
  });

  group('CbsButton disabled', () {
    testWidgets('never takes focus and is never activated', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpA11y(
        tester,
        child: const CbsButton(
          key: ValueKey('button'),
          label: 'Continue',
          onPressed: null,
        ),
      );

      await _tab(tester);
      await _press(tester, LogicalKeyboardKey.enter);
      await _press(tester, LogicalKeyboardKey.space);

      expect(
        hasPrimaryFocusWithin(tester, find.byKey(const ValueKey('button'))),
        isFalse,
      );

      final flags = tester
          .getSemantics(find.byType(FilledButton))
          .flagsCollection;
      expect(flags.isEnabled, Tristate.isFalse);
      expect(flags.isFocused, isNot(Tristate.isTrue));

      semantics.dispose();
    });

    testWidgets('is skipped by Tab: focus goes to the next enabled button', (
      tester,
    ) async {
      var activations = 0;
      await pumpA11y(
        tester,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CbsButton(
              key: ValueKey('disabled'),
              label: 'Disabled',
              onPressed: null,
            ),
            CbsButton(
              key: const ValueKey('enabled'),
              label: 'Enabled',
              onPressed: () => activations++,
            ),
          ],
        ),
      );

      await _tab(tester);

      expect(
        hasPrimaryFocusWithin(tester, find.byKey(const ValueKey('enabled'))),
        isTrue,
      );
      expect(
        hasPrimaryFocusWithin(tester, find.byKey(const ValueKey('disabled'))),
        isFalse,
      );

      await _press(tester, LogicalKeyboardKey.enter);
      expect(activations, 1);
    });

    testWidgets('does not activate an action disabled while focused', (
      tester,
    ) async {
      var activations = 0;
      final enabled = ValueNotifier<bool>(true);
      addTearDown(enabled.dispose);

      await pumpA11y(
        tester,
        child: ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (context, isEnabled, _) => CbsButton(
            key: const ValueKey('button'),
            label: 'Continue',
            onPressed: isEnabled ? () => activations++ : null,
          ),
        ),
      );

      await _tab(tester);
      await _press(tester, LogicalKeyboardKey.enter);
      expect(activations, 1);

      enabled.value = false;
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.enter);
      await _press(tester, LogicalKeyboardKey.space);

      expect(activations, 1);
    });

    testWidgets('re-enabling makes the button reachable again by Tab', (
      tester,
    ) async {
      var activations = 0;
      final enabled = ValueNotifier<bool>(false);
      addTearDown(enabled.dispose);

      await pumpA11y(
        tester,
        child: ValueListenableBuilder<bool>(
          valueListenable: enabled,
          builder: (context, isEnabled, _) => CbsButton(
            key: const ValueKey('button'),
            label: 'Continue',
            onPressed: isEnabled ? () => activations++ : null,
          ),
        ),
      );

      await _tab(tester);
      expect(
        hasPrimaryFocusWithin(tester, find.byKey(const ValueKey('button'))),
        isFalse,
      );

      enabled.value = true;
      await tester.pump();

      await _tab(tester);
      expect(
        hasPrimaryFocusWithin(tester, find.byKey(const ValueKey('button'))),
        isTrue,
      );

      await _press(tester, LogicalKeyboardKey.space);
      expect(activations, 1);
    });
  });

  group('focus order', () {
    Widget threeButtons(List<String> log) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final name in ['first', 'second', 'third'])
            CbsButton(
              key: ValueKey(name),
              label: name,
              onPressed: () => log.add(name),
            ),
        ],
      );
    }

    Future<String?> focused(WidgetTester tester) async {
      for (final name in ['first', 'second', 'third']) {
        if (hasPrimaryFocusWithin(tester, find.byKey(ValueKey(name)))) {
          return name;
        }
      }
      return null;
    }

    testWidgets('Tab follows the visual order top to bottom', (tester) async {
      await pumpA11y(tester, child: threeButtons([]));

      expect(await focused(tester), isNull);
      await _tab(tester);
      expect(await focused(tester), 'first');
      await _tab(tester);
      expect(await focused(tester), 'second');
      await _tab(tester);
      expect(await focused(tester), 'third');
    });

    testWidgets('Shift+Tab goes back in the reverse order', (tester) async {
      await pumpA11y(tester, child: threeButtons([]));

      await _tab(tester);
      await _tab(tester);
      await _tab(tester);
      expect(await focused(tester), 'third');

      await _tab(tester, shift: true);
      expect(await focused(tester), 'second');
      await _tab(tester, shift: true);
      expect(await focused(tester), 'first');
    });

    testWidgets('focus wraps around from the last to the first control', (
      tester,
    ) async {
      await pumpA11y(tester, child: threeButtons([]));

      for (var i = 0; i < 3; i++) {
        await _tab(tester);
      }
      expect(await focused(tester), 'third');

      await _tab(tester);
      expect(await focused(tester), 'first');
    });

    testWidgets('the activated control is the focused one', (tester) async {
      final log = <String>[];
      await pumpA11y(tester, child: threeButtons(log));

      await _tab(tester);
      await _tab(tester);
      await _press(tester, LogicalKeyboardKey.enter);
      await _tab(tester);
      await _press(tester, LogicalKeyboardKey.space);

      expect(log, ['second', 'third']);
    });

    testWidgets('focus order is unchanged under text scale x2 at 320 px', (
      tester,
    ) async {
      await pumpA11y(tester, width: 320, textScale: 2, child: threeButtons([]));

      await _tab(tester);
      expect(await focused(tester), 'first');
      await _tab(tester);
      expect(await focused(tester), 'second');
      await _tab(tester);
      expect(await focused(tester), 'third');
    });
  });

  group('CbsRetryMessage keyboard and focus', () {
    Widget retry(VoidCallback onRetry, {Key? key}) {
      return CbsRetryMessage(
        key: key,
        message: _message,
        retryLabel: _retryLabel,
        onRetry: onRetry,
      );
    }

    testWidgets('Space activates the retry button exactly once', (
      tester,
    ) async {
      var retries = 0;
      await pumpA11y(tester, child: retry(() => retries++));

      await _tab(tester);
      await _press(tester, LogicalKeyboardKey.space);

      expect(retries, 1);
    });

    testWidgets('the first Tab lands on the retry button, not the message', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpA11y(tester, child: retry(() {}));

      await _tab(tester);

      expect(hasPrimaryFocusWithin(tester, find.byType(CbsButton)), isTrue);
      expect(
        hasPrimaryFocusWithin(tester, find.byType(CbsFeedbackMessage)),
        isFalse,
      );
      expect(
        tester
            .getSemantics(find.byType(FilledButton))
            .flagsCollection
            .isFocused,
        Tristate.isTrue,
      );

      semantics.dispose();
    });

    testWidgets(
      'Enter and Space do nothing before the retry button has focus',
      (tester) async {
        var retries = 0;
        await pumpA11y(tester, child: retry(() => retries++));

        await _press(tester, LogicalKeyboardKey.enter);
        await _press(tester, LogicalKeyboardKey.space);

        expect(retries, 0);
      },
    );

    testWidgets('focus stays on the retry button after activation', (
      tester,
    ) async {
      await pumpA11y(tester, child: retry(() {}));

      await _tab(tester);
      await _press(tester, LogicalKeyboardKey.enter);

      expect(hasPrimaryFocusWithin(tester, find.byType(CbsButton)), isTrue);
    });

    testWidgets('focus survives a rebuild that changes the texts', (
      tester,
    ) async {
      var retries = 0;
      const key = ValueKey('retry');
      await pumpA11y(tester, child: retry(() => retries++, key: key));

      await _tab(tester);
      expect(hasPrimaryFocusWithin(tester, find.byType(CbsButton)), isTrue);

      await pumpA11y(
        tester,
        child: CbsRetryMessage(
          key: key,
          message: 'Autre message',
          retryLabel: 'Relancer',
          onRetry: () => retries++,
        ),
      );

      expect(hasPrimaryFocusWithin(tester, find.byType(CbsButton)), isTrue);
      await _press(tester, LogicalKeyboardKey.enter);
      expect(retries, 1);
    });
  });

  group('non-interactive parts never take focus', () {
    testWidgets('feedback, heading, state panel and loading are skipped', (
      tester,
    ) async {
      var activations = 0;
      await pumpA11y(
        tester,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CbsSectionHeading(title: 'À la une'),
            const CbsFeedbackMessage(message: _message),
            const CbsStatePanel(
              child: CbsLoadingIndicator(semanticLabel: 'Chargement'),
            ),
            CbsButton(
              key: const ValueKey('button'),
              label: 'Continue',
              onPressed: () => activations++,
            ),
          ],
        ),
      );

      await _tab(tester);

      expect(
        hasPrimaryFocusWithin(tester, find.byKey(const ValueKey('button'))),
        isTrue,
      );

      await _tab(tester);

      // Wraps back to the only focusable control: still the button.
      expect(
        hasPrimaryFocusWithin(tester, find.byKey(const ValueKey('button'))),
        isTrue,
      );

      await _press(tester, LogicalKeyboardKey.enter);
      expect(activations, 1);
    });

    testWidgets('a composition keeps reading order: retry before next button', (
      tester,
    ) async {
      final order = <String>[];
      await pumpA11y(
        tester,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CbsSectionHeading(title: 'À la une'),
            CbsRetryMessage(
              key: const ValueKey('retry'),
              message: _message,
              retryLabel: _retryLabel,
              onRetry: () => order.add('retry'),
            ),
            CbsButton(
              key: const ValueKey('after'),
              label: 'After',
              onPressed: () => order.add('after'),
            ),
          ],
        ),
      );

      await _tab(tester);
      await _press(tester, LogicalKeyboardKey.enter);
      await _tab(tester);
      await _press(tester, LogicalKeyboardKey.enter);

      expect(order, ['retry', 'after']);
    });
  });
}
