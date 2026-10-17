import 'package:flutter/rendering.dart';
import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cbs_test_matrix.dart';

const Key _childKey = ValueKey('media-child');

const String _frameLabel = 'Photo de couverture';
const String _childLabel = 'Illustration du média';

/// Media built by the consumer: it fills the constraints it receives.
Widget _media() => const SizedBox.expand(key: _childKey);

Finder _inFrame(Finder matching) =>
    find.descendant(of: find.byType(CbsMediaFrame), matching: matching);

ClipRRect _clip(WidgetTester tester) =>
    tester.widget<ClipRRect>(_inFrame(find.byType(ClipRRect)));

Size _frameSize(WidgetTester tester) =>
    tester.getSize(find.byType(CbsMediaFrame));

void main() {
  group('API', () {
    test('defaults to 16:9, the default radius and no semantic label', () {
      const frame = CbsMediaFrame(child: SizedBox());

      expect(frame.aspectRatio, 16 / 9);
      expect(frame.borderRadius, isNull);
      expect(frame.semanticLabel, isNull);
      expect(frame.child, isA<SizedBox>());
    });

    test('keeps the provided values', () {
      final radius = BorderRadius.circular(CbsRadius.lg);
      final frame = CbsMediaFrame(
        aspectRatio: 1,
        borderRadius: radius,
        semanticLabel: _frameLabel,
        key: const ValueKey('frame'),
        child: const SizedBox(),
      );

      expect(frame.aspectRatio, 1);
      expect(frame.borderRadius, radius);
      expect(frame.semanticLabel, _frameLabel);
      expect(frame.key, const ValueKey('frame'));
    });

    test('is a StatelessWidget', () {
      expect(const CbsMediaFrame(child: SizedBox()), isA<StatelessWidget>());
    });
  });

  group('aspectRatio validation', () {
    final invalidRatios = <double>[
      0,
      -1,
      -16 / 9,
      double.infinity,
      double.negativeInfinity,
      double.nan,
    ];

    for (final ratio in invalidRatios) {
      test('rejects $ratio', () {
        expect(
          () => CbsMediaFrame(aspectRatio: ratio, child: const SizedBox()),
          throwsAssertionError,
        );
      });
    }

    for (final ratio in <double>[0.5, 1, 4 / 3, 16 / 9, 21 / 9, 100]) {
      test('accepts $ratio', () {
        expect(
          CbsMediaFrame(aspectRatio: ratio, child: const SizedBox()),
          isA<CbsMediaFrame>(),
        );
      });
    }
  });

  group('structure', () {
    testWidgets('is built from AspectRatio and ClipRRect around the child', (
      tester,
    ) async {
      await pumpCbs(tester, child: CbsMediaFrame(child: _media()));

      expect(_inFrame(find.byType(AspectRatio)), findsOneWidget);
      expect(_inFrame(find.byType(ClipRRect)), findsOneWidget);
      expect(
        find.descendant(
          of: _inFrame(find.byType(ClipRRect)),
          matching: find.byKey(_childKey),
        ),
        findsOneWidget,
      );
    });

    testWidgets('does not manage BoxFit, images or any other media logic', (
      tester,
    ) async {
      await pumpCbs(tester, child: CbsMediaFrame(child: _media()));

      for (final type in [
        FittedBox,
        Image,
        FadeInImage,
        DecoratedBox,
        Padding,
        Align,
        Center,
        Container,
        InkWell,
        GestureDetector,
      ]) {
        expect(
          _inFrame(
            find.byElementPredicate(
              (element) => element.widget.runtimeType == type,
            ),
          ),
          findsNothing,
          reason: '$type must not be part of the frame',
        );
      }
    });

    testWidgets('passes the aspect ratio to AspectRatio', (tester) async {
      await pumpCbs(
        tester,
        child: CbsMediaFrame(aspectRatio: 4 / 3, child: _media()),
      );

      final aspect = tester.widget<AspectRatio>(
        _inFrame(find.byType(AspectRatio)),
      );
      expect(aspect.aspectRatio, 4 / 3);
    });
  });

  group('layout', () {
    testWidgets('is 16:9 by default and fills the available width', (
      tester,
    ) async {
      await pumpCbs(tester, width: 600, child: CbsMediaFrame(child: _media()));

      final size = _frameSize(tester);
      expect(size.width, 600);
      expect(size.height, closeTo(600 * 9 / 16, 0.001));
    });

    testWidgets('1:1 is a square', (tester) async {
      await pumpCbs(
        tester,
        width: 320,
        child: CbsMediaFrame(aspectRatio: 1, child: _media()),
      );

      expect(_frameSize(tester), const Size(320, 320));
    });

    testWidgets('a tall ratio is taller than wide', (tester) async {
      await pumpCbs(
        tester,
        width: 320,
        child: CbsMediaFrame(aspectRatio: 0.5, child: _media()),
      );

      expect(_frameSize(tester), const Size(320, 640));
    });

    testWidgets('gives the child tight constraints equal to the frame', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        width: 600,
        child: CbsMediaFrame(aspectRatio: 2, child: _media()),
      );

      expect(tester.getSize(find.byKey(_childKey)), _frameSize(tester));
      expect(tester.getSize(find.byKey(_childKey)), const Size(600, 300));
    });

    testWidgets('forces a smaller child to fill the frame', (tester) async {
      await pumpCbs(
        tester,
        width: 600,
        child: const CbsMediaFrame(
          aspectRatio: 2,
          child: SizedBox(key: _childKey, width: 10, height: 10),
        ),
      );

      // The frame owns the size; the child cannot shrink it.
      expect(_frameSize(tester), const Size(600, 300));
      expect(tester.getSize(find.byKey(_childKey)), const Size(600, 300));
    });

    testWidgets('adds no external spacing', (tester) async {
      await pumpCbs(
        tester,
        width: 600,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CbsMediaFrame(aspectRatio: 2, child: SizedBox.expand()),
            SizedBox(key: ValueKey('next'), height: 10, width: 10),
          ],
        ),
      );

      final frame = tester.getRect(find.byType(CbsMediaFrame));
      final next = tester.getRect(find.byKey(const ValueKey('next')));
      expect(frame.topLeft, Offset.zero);
      expect(next.top, frame.bottom);
    });

    testWidgets('is a pure placeholder without a child size', (tester) async {
      await pumpCbs(
        tester,
        width: 600,
        child: const CbsMediaFrame(
          aspectRatio: 1,
          child: ColoredBox(color: Colors.grey),
        ),
      );

      expect(_frameSize(tester), const Size(600, 600));
      expect(tester.takeException(), isNull);
    });

    testWidgets('never exceeds a bounded height', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 600);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: CbsTheme.essentials(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                height: 100,
                child: CbsMediaFrame(aspectRatio: 2, child: _media()),
              ),
            ),
          ),
        ),
      );

      expect(_frameSize(tester), const Size(200, 100));
      expect(tester.takeException(), isNull);
    });
  });

  group('corners', () {
    testWidgets('use the CBS md radius token by default', (tester) async {
      await pumpCbs(tester, child: CbsMediaFrame(child: _media()));

      expect(_clip(tester).borderRadius, BorderRadius.circular(CbsRadius.md));
      expect(_clip(tester).clipBehavior, Clip.antiAlias);
    });

    testWidgets('use the provided radius', (tester) async {
      final radius = BorderRadius.circular(CbsRadius.xl);
      await pumpCbs(
        tester,
        child: CbsMediaFrame(borderRadius: radius, child: _media()),
      );

      expect(_clip(tester).borderRadius, radius);
    });

    testWidgets('accept square corners', (tester) async {
      await pumpCbs(
        tester,
        child: CbsMediaFrame(borderRadius: BorderRadius.zero, child: _media()),
      );

      expect(_clip(tester).borderRadius, BorderRadius.zero);
      expect(tester.takeException(), isNull);
    });

    testWidgets('accept a directional radius in both text directions', (
      tester,
    ) async {
      const radius = BorderRadiusDirectional.only(
        topStart: Radius.circular(CbsRadius.lg),
      );

      for (final direction in TextDirection.values) {
        await pumpCbs(
          tester,
          child: Directionality(
            textDirection: direction,
            child: CbsMediaFrame(borderRadius: radius, child: _media()),
          ),
        );

        expect(_clip(tester).borderRadius, radius, reason: '$direction');
        expect(tester.takeException(), isNull, reason: '$direction');
      }
    });

    testWidgets('clip the child on the bounds of the frame', (tester) async {
      await pumpCbs(
        tester,
        width: 200,
        child: const CbsMediaFrame(
          aspectRatio: 1,
          borderRadius: BorderRadius.all(Radius.circular(CbsRadius.xl)),
          child: ColoredBox(key: _childKey, color: Colors.red),
        ),
      );

      final render = tester.renderObject<RenderClipRRect>(
        _inFrame(find.byType(ClipRRect)),
      );
      expect(render.size, const Size(200, 200));
      expect(
        render.borderRadius,
        const BorderRadius.all(Radius.circular(CbsRadius.xl)),
      );
    });
  });

  group('semantics', () {
    testWidgets('adds no semantics of its own without a label', (tester) async {
      await pumpCbs(tester, child: CbsMediaFrame(child: _media()));

      expect(_inFrame(find.byType(Semantics)), findsNothing);
      expect(_inFrame(find.byType(ExcludeSemantics)), findsNothing);
      expect(_inFrame(find.byType(BlockSemantics)), findsNothing);
      expect(_inFrame(find.byType(MergeSemantics)), findsNothing);
    });

    testWidgets('exposes the semantic label', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: CbsMediaFrame(semanticLabel: _frameLabel, child: _media()),
      );

      expect(find.bySemanticsLabel(RegExp(_frameLabel)), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(CbsMediaFrame)).label,
        contains(_frameLabel),
      );
      handle.dispose();
    });

    testWidgets('preserves the semantics of the child without a label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: CbsMediaFrame(
          child: Semantics(label: _childLabel, child: const SizedBox.expand()),
        ),
      );

      expect(find.bySemanticsLabel(RegExp(_childLabel)), findsOneWidget);
      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp(_childLabel)),
      );
      expect(node.label, contains(_childLabel));
      handle.dispose();
    });

    testWidgets('adds the label to the semantics of the child', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: CbsMediaFrame(
          semanticLabel: _frameLabel,
          child: Semantics(label: _childLabel, child: const SizedBox.expand()),
        ),
      );

      // Both descriptions stay available: the label does not replace the
      // semantics of the child.
      expect(find.bySemanticsLabel(RegExp(_frameLabel)), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(_childLabel)), findsOneWidget);
      final node = tester.getSemantics(find.byType(CbsMediaFrame));
      expect(node.label, contains(_frameLabel));
      expect(node.label, contains(_childLabel));
      handle.dispose();
    });

    testWidgets('does not make the media interactive', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: CbsMediaFrame(semanticLabel: _frameLabel, child: _media()),
      );

      final node = tester.getSemantics(find.byType(CbsMediaFrame));
      expect(node.flagsCollection.isButton, isFalse);
      expect(node.flagsCollection.isHeader, isFalse);
      handle.dispose();
    });
  });

  group('interaction', () {
    testWidgets('lets the interactions of the child through', (tester) async {
      var taps = 0;
      await pumpCbs(
        tester,
        child: CbsMediaFrame(
          child: GestureDetector(
            key: _childKey,
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
          ),
        ),
      );

      await tester.tap(find.byKey(_childKey));
      expect(taps, 1);
    });
  });

  group('themes and widths', () {
    for (final variant in cbsTestThemes) {
      for (final width in cbsTestWidths) {
        testWidgets('keeps its ratio and radius: ${variant.name}, $width', (
          tester,
        ) async {
          await pumpCbs(
            tester,
            theme: variant.theme,
            width: width,
            child: CbsMediaFrame(child: _media()),
          );

          final size = _frameSize(tester);
          expect(size.width, width);
          expect(size.height, closeTo(width * 9 / 16, 0.001));
          expect(
            _clip(tester).borderRadius,
            BorderRadius.circular(CbsRadius.md),
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final scale in cbsTestTextScales) {
      testWidgets('is independent from the text scale: x$scale', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          width: 320,
          textScale: scale,
          child: CbsMediaFrame(child: _media()),
        );

        final size = _frameSize(tester);
        expect(size.width, 320);
        expect(size.height, closeTo(320 * 9 / 16, 0.001));
      });
    }
  });

  group('composition', () {
    testWidgets('fills the media slot of CbsContentCard', (tester) async {
      await pumpCbs(
        tester,
        width: 600,
        child: const CbsContentCard(
          media: CbsMediaFrame(
            borderRadius: BorderRadius.zero,
            child: SizedBox.expand(key: _childKey),
          ),
          content: Text('Titre'),
        ),
      );

      final card = tester.getRect(find.byType(CbsContentCard));
      final media = tester.getRect(find.byType(CbsMediaFrame));
      expect(media.top, card.top);
      expect(media.left, card.left);
      expect(media.width, card.width);
      expect(media.height, closeTo(card.width * 9 / 16, 0.001));
      expect(tester.takeException(), isNull);
    });
  });
}
