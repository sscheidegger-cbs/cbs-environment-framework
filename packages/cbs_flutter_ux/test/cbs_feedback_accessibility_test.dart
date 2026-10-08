import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('exposes a custom semantic label', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CbsFeedbackMessage(
            message: 'Connexion impossible',
            type: CbsFeedbackType.error,
            semanticLabel: 'Erreur : connexion impossible',
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel('Erreur : connexion impossible'),
      findsOneWidget,
    );

    expect(find.text('Connexion impossible'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('excludes duplicate child semantics', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CbsFeedbackMessage(
            message: 'Connexion impossible',
            type: CbsFeedbackType.error,
            semanticLabel: 'Erreur : connexion impossible',
          ),
        ),
      ),
    );

    final feedback = find.byType(CbsFeedbackMessage);

    final semanticWidget = find.descendant(
      of: feedback,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Erreur : connexion impossible',
      ),
    );

    expect(semanticWidget, findsOneWidget);

    final widget = tester.widget<Semantics>(semanticWidget);

    expect(widget.excludeSemantics, isTrue);
    expect(widget.properties.label, 'Erreur : connexion impossible');

    semantics.dispose();
  });
}
