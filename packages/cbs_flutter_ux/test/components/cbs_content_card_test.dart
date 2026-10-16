import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders content without optional slots', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CbsContentCard(content: Text('Title'))),
    ));
    expect(find.text('Title'), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('renders optional media and action in vertical layout', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CbsContentCard(
        content: Text('Title'),
        media: Text('Media'),
        action: Text('Action'),
      )),
    ));
    expect(find.text('Media'), findsOneWidget);
    expect(find.text('Action'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal layout supports optional media', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SizedBox(
        width: 320,
        child: CbsContentCard(
          layout: CbsContentCardLayout.horizontal,
          content: Text('Title'),
          media: Text('Media'),
        ),
      )),
    ));
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Media'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invokes callback only when interactive', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CbsContentCard(
        content: const Text('Tap target'),
        onTap: () => taps++,
      )),
    ));
    await tester.tap(find.text('Tap target'));
    expect(taps, 1);
  });

  testWidgets('exposes an optional semantic label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CbsContentCard(
        content: Text('Title'),
        semanticLabel: 'Generic content card',
      )),
    ));
    expect(find.bySemanticsLabel('Generic content card'), findsOneWidget);
    handle.dispose();
  });
}
