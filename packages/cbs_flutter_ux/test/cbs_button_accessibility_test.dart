import 'dart:ui' show Tristate;

import 'package:flutter/services.dart';

import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('exposes button role and accessible label', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CbsButton(label: 'Continue', onPressed: () {}),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Continue'), findsOneWidget);

    final node = tester.getSemantics(find.byType(FilledButton));

    expect(node.flagsCollection.isButton, isTrue);
    expect(node.label, 'Continue');

    semantics.dispose();
  });

  testWidgets('exposes disabled state to accessibility', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CbsButton(label: 'Continue', onPressed: null)),
      ),
    );

    final node = tester.getSemantics(find.byType(FilledButton));

    expect(node.flagsCollection.isButton, isTrue);
    expect(node.flagsCollection.isEnabled, Tristate.isFalse);
    expect(node.label, 'Continue');

    semantics.dispose();
  });

  testWidgets('supports keyboard activation', (tester) async {
    var activationCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CbsButton(
            label: 'Continue',
            onPressed: () => activationCount++,
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(activationCount, 1);
  });
}
