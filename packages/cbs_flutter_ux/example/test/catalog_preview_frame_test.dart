import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cbs_flutter_ux_example/catalog/catalog_keys.dart';
import 'package:cbs_flutter_ux_example/catalog/catalog_preview_frame.dart';
import 'package:cbs_flutter_ux_example/catalog/catalog_scenario.dart';
import 'package:cbs_flutter_ux_example/main.dart';

import 'catalog_test_helpers.dart';

// D03b-C.2-R1 (M1, M2): the simulated width must equal the width really
// given to the previewed content, and the decorative margins, padding and
// border must stay outside the simulated surface.

/// Android device used by the initial presentation review (dp).
const _android360 = Size(360, 800);

/// Horizontal scroll extent of the preview, 0 when nothing scrolls.
double _previewScrollExtent(WidgetTester tester) {
  final scrollable = find
      .descendant(
        of: find.byKey(CatalogKeys.previewScroll),
        matching: find.byType(Scrollable),
      )
      .first;
  return tester.state<ScrollableState>(scrollable).position.maxScrollExtent;
}

/// Records what a child of [CatalogPreviewFrame] actually receives.
class _Probe extends StatelessWidget {
  const _Probe(this.onBuild);

  final void Function(BoxConstraints constraints, MediaQueryData media) onBuild;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        onBuild(constraints, MediaQuery.of(context));
        return const SizedBox(height: 10);
      },
    );
  }
}

void main() {
  group('MediaQuery / constraints consistency (M2)', () {
    for (final width in CatalogWidth.values) {
      testWidgets('frame gives the child ${width.label} on both', (
        tester,
      ) async {
        setSurfaceSize(tester, const Size(1400, 800));
        BoxConstraints? constraints;
        MediaQueryData? media;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CatalogPreviewFrame(
                scenario: CatalogScenario(
                  width: width,
                  textScale: CatalogTextScale.x2,
                ),
                child: _Probe((c, m) {
                  constraints = c;
                  media = m;
                }),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(constraints, isNotNull);
        // Tight width constraint equal to the simulated width...
        expect(constraints!.minWidth, width.logicalPixels);
        expect(constraints!.maxWidth, width.logicalPixels);
        // ... and the very same value in MediaQuery.
        expect(media!.size.width, width.logicalPixels);
        expect(media!.size.width, constraints!.maxWidth);
        expect(media!.textScaler.scale(10), 20);
      });
    }

    for (final width in CatalogWidth.values) {
      testWidgets('catalog content is ${width.label} wide, as its MediaQuery', (
        tester,
      ) async {
        setSurfaceSize(tester, _android360);
        await tester.pumpWidget(const CbsUxShowcase());
        await selectOption(tester, CatalogKeys.widthOption(width));

        final mediaWidth = previewMediaQuery(tester).size.width;
        expect(mediaWidth, width.logicalPixels);
        expect(
          tester.getSize(find.byKey(CatalogKeys.previewViewport)).width,
          mediaWidth,
        );
        expect(
          tester.getSize(find.byKey(CatalogKeys.previewContent)).width,
          mediaWidth,
        );
        // Sections use the whole simulated width: no inner padding.
        expect(
          tester.getSize(find.byKey(CatalogKeys.section('feedback'))).width,
          mediaWidth,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('keep the border and margins outside the simulated surface', (
      tester,
    ) async {
      setSurfaceSize(tester, _android360);
      await tester.pumpWidget(const CbsUxShowcase());

      final frame = tester.getRect(find.byKey(CatalogKeys.previewFrame));
      final viewport = tester.getRect(find.byKey(CatalogKeys.previewViewport));

      expect(viewport.width, 320);
      // The frame stays identifiable: it strictly surrounds the surface.
      expect(frame.left, lessThan(viewport.left));
      expect(frame.right, greaterThan(viewport.right));
      expect(frame.top, lessThan(viewport.top));
      expect(frame.bottom, greaterThan(viewport.bottom));
      // The frame decoration is the only thing around the surface.
      expect(viewport.left - frame.left, frame.right - viewport.right);
    });
  });

  group('initial presentation (M1)', () {
    testWidgets('320 px fits a 360 dp screen without horizontal scroll', (
      tester,
    ) async {
      setSurfaceSize(tester, _android360);
      await tester.pumpWidget(const CbsUxShowcase());

      expect(tester.takeException(), isNull);
      expect(_previewScrollExtent(tester), 0);

      final frame = tester.getRect(find.byKey(CatalogKeys.previewFrame));
      expect(frame.left, greaterThanOrEqualTo(0));
      expect(frame.right, lessThanOrEqualTo(_android360.width));

      // The simulated width is not changed silently.
      expect(
        tester.getSize(find.byKey(CatalogKeys.previewViewport)).width,
        320,
      );
      expect(
        tester.widget<Text>(find.byKey(CatalogKeys.scenarioSummary)).data,
        CatalogScenario.initial.summary,
      );
      expect(
        isSelected(tester, CatalogKeys.widthOption(CatalogWidth.w320)),
        isTrue,
      );
    });

    testWidgets('widths above the screen scroll horizontally, 320 does not', (
      tester,
    ) async {
      setSurfaceSize(tester, _android360);
      await tester.pumpWidget(const CbsUxShowcase());

      for (final width in [
        CatalogWidth.w600,
        CatalogWidth.w840,
        CatalogWidth.w1280,
        CatalogWidth.w320,
      ]) {
        await selectOption(tester, CatalogKeys.widthOption(width));

        expect(
          tester.getSize(find.byKey(CatalogKeys.previewViewport)).width,
          width.logicalPixels,
        );
        if (width == CatalogWidth.w320) {
          expect(_previewScrollExtent(tester), 0);
        } else {
          expect(_previewScrollExtent(tester), greaterThan(0));
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('a scrollable preview can be dragged to its far edge', (
      tester,
    ) async {
      setSurfaceSize(tester, _android360);
      await tester.pumpWidget(const CbsUxShowcase());
      await selectOption(tester, CatalogKeys.widthOption(CatalogWidth.w1280));

      // D03b-C.3 adaptation: the catalog is now taller than the screen, so
      // the centre of the preview (used by `tester.drag`) is off-screen.
      // The drag starts inside the visible top of the preview instead.
      await tester.ensureVisible(find.byKey(CatalogKeys.previewFrame));
      await tester.pump();
      final before = tester.getTopLeft(find.byKey(CatalogKeys.previewViewport));
      await tester.dragFrom(
        tester.getTopLeft(find.byKey(CatalogKeys.previewScroll)) +
            const Offset(20, 20),
        const Offset(-2000, 0),
      );
      await tester.pump();
      final after = tester.getTopLeft(find.byKey(CatalogKeys.previewViewport));

      expect(after.dx, lessThan(before.dx));
      // The far edge of the frame is reachable on screen.
      expect(
        tester.getRect(find.byKey(CatalogKeys.previewFrame)).right,
        lessThanOrEqualTo(_android360.width),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 320 dp screen keeps the horizontal scroll', (tester) async {
      setSurfaceSize(tester, const Size(320, 640));
      await tester.pumpWidget(const CbsUxShowcase());

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(CatalogKeys.previewViewport)).width,
        320,
      );
      expect(_previewScrollExtent(tester), greaterThan(0));
    });
  });
}
