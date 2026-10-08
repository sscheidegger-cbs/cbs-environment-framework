import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loading indicator forwards its semantic label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CbsTheme.essentials(),
        home: const Scaffold(
          body: CbsLoadingIndicator(semanticLabel: 'Chargement des données'),
        ),
      ),
    );

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );

    expect(indicator.semanticsLabel, 'Chargement des données');
  });
}
