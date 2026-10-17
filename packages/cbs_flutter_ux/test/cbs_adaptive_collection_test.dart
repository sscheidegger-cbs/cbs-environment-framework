import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cbs_test_matrix.dart';

const double _itemHeight = 40;
const double _gap = 12;

/// Number of columns expected with the default values (minimum width 240,
/// spacing 12) at each width of the qualification matrix.
final Map<double, int> _expectedColumns = {320: 1, 600: 2, 840: 3, 1280: 5};

const String _longTitle =
    'Un élément de collection volontairement très long qui doit passer à la '
    'ligne sur une largeur compacte avec un facteur de texte agrandi sans '
    'jamais provoquer de dépassement';

Key _key(int index) => ValueKey('item-$index');

Key _cardKey(int index) => ValueKey('card-$index');

Key _frameKey(int index) => ValueKey('frame-$index');

/// Plain child with a fixed height; it fills the width it receives.
Widget _item(int index, {double height = _itemHeight}) =>
    SizedBox(key: _key(index), height: height, child: Text('Item $index'));

List<Widget> _items(int count, {double height = _itemHeight}) => [
  for (var i = 0; i < count; i++) _item(i, height: height),
];

/// Child whose height depends on the width and on the text scale.
Widget _textItem(int index) => Text(_longTitle, key: _key(index));

CbsAdaptiveCollection _collection(
  List<Widget> children, {
  CbsCollectionLayout layout = CbsCollectionLayout.grid,
  double spacing = 12,
  double runSpacing = 12,
  double minItemWidth = 240,
  Key? key,
}) => CbsAdaptiveCollection(
  key: key,
  layout: layout,
  spacing: spacing,
  runSpacing: runSpacing,
  minItemWidth: minItemWidth,
  children: children,
);

Widget _card(
  int index, {
  bool media = true,
  CbsContentCardLayout layout = CbsContentCardLayout.vertical,
  String? title,
  Widget? action,
  VoidCallback? onTap,
  String? semanticLabel,
  String? mediaLabel,
}) => CbsContentCard(
  key: _cardKey(index),
  layout: layout,
  media: media
      ? CbsMediaFrame(
          key: _frameKey(index),
          semanticLabel: mediaLabel,
          child: const ColoredBox(color: Colors.grey),
        )
      : null,
  content: Text(title ?? 'Card $index'),
  action: action,
  onTap: onTap,
  semanticLabel: semanticLabel,
);

Rect _rect(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

Rect _itemRect(WidgetTester tester, int index) => _rect(tester, _key(index));

List<Rect> _itemRects(WidgetTester tester, int count) => [
  for (var i = 0; i < count; i++) _itemRect(tester, i),
];

Size _collectionSize(WidgetTester tester) =>
    tester.getSize(find.byType(CbsAdaptiveCollection));

/// Width of a column when [columns] columns share [width].
double _cellWidth(double width, int columns, {double spacing = _gap}) =>
    (width - spacing * (columns - 1)) / columns;

/// Number of rects on the first row.
int _firstRowCount(List<Rect> rects) =>
    rects.where((r) => (r.top - rects.first.top).abs() < 0.001).length;

void _expectRect(Rect actual, Rect expected, {String? reason}) {
  expect(actual.left, closeTo(expected.left, 0.001), reason: reason);
  expect(actual.top, closeTo(expected.top, 0.001), reason: reason);
  expect(actual.width, closeTo(expected.width, 0.001), reason: reason);
  expect(actual.height, closeTo(expected.height, 0.001), reason: reason);
}

Finder _inCollection(Finder matching) =>
    find.descendant(of: find.byType(CbsAdaptiveCollection), matching: matching);

Material _cardMaterial(WidgetTester tester, int index) =>
    tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(_cardKey(index)),
            matching: find.byType(Material),
          )
          .first,
    );

/// Counter whose state must follow its key when the children are
/// reordered.
class _Counter extends StatefulWidget {
  const _Counter({required this.label, super.key});

  final String label;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => count++),
      child: SizedBox(
        height: _itemHeight,
        child: Text('${widget.label}: $count'),
      ),
    );
  }
}

void main() {
  group('API', () {
    test('defaults to a list, spacings of 12 and a minimum width of 240', () {
      const collection = CbsAdaptiveCollection(children: []);

      expect(collection.layout, CbsCollectionLayout.list);
      expect(collection.spacing, 12);
      expect(collection.runSpacing, 12);
      expect(collection.minItemWidth, 240);
      expect(collection.children, isEmpty);
      expect(collection.key, isNull);
    });

    test('keeps the provided values', () {
      final children = [const SizedBox(), const SizedBox()];
      final collection = CbsAdaptiveCollection(
        key: const ValueKey('collection'),
        layout: CbsCollectionLayout.grid,
        spacing: 4,
        runSpacing: 6,
        minItemWidth: 100,
        children: children,
      );

      expect(collection.layout, CbsCollectionLayout.grid);
      expect(collection.spacing, 4);
      expect(collection.runSpacing, 6);
      expect(collection.minItemWidth, 100);
      expect(collection.children, same(children));
      expect(collection.key, const ValueKey('collection'));
    });

    test('is a StatelessWidget', () {
      expect(const CbsAdaptiveCollection(children: []), isA<StatelessWidget>());
    });

    test('has the list and grid layouts', () {
      expect(CbsCollectionLayout.values, [
        CbsCollectionLayout.list,
        CbsCollectionLayout.grid,
      ]);
    });

    test('accepts no spacing', () {
      expect(
        const CbsAdaptiveCollection(
          spacing: 0,
          runSpacing: 0,
          children: [],
        ).spacing,
        0,
      );
    });

    for (final value in <double>[
      -1,
      double.infinity,
      double.negativeInfinity,
      double.nan,
    ]) {
      test('rejects a spacing of $value', () {
        expect(
          () => CbsAdaptiveCollection(spacing: value, children: const []),
          throwsAssertionError,
        );
      });

      test('rejects a runSpacing of $value', () {
        expect(
          () => CbsAdaptiveCollection(runSpacing: value, children: const []),
          throwsAssertionError,
        );
      });
    }

    for (final value in <double>[
      0,
      -1,
      double.infinity,
      double.negativeInfinity,
      double.nan,
    ]) {
      test('rejects a minItemWidth of $value', () {
        expect(
          () => CbsAdaptiveCollection(minItemWidth: value, children: const []),
          throwsAssertionError,
        );
      });
    }
  });

  group('children count', () {
    for (final layout in CbsCollectionLayout.values) {
      testWidgets('empty list builds nothing: ${layout.name}', (tester) async {
        await pumpCbs(tester, child: _collection(const [], layout: layout));

        expect(tester.takeException(), isNull);
        expect(_collectionSize(tester), Size.zero);
        expect(_inCollection(find.byType(LayoutBuilder)), findsNothing);
        expect(_inCollection(find.byType(Wrap)), findsNothing);
        expect(_inCollection(find.byType(Column)), findsNothing);
      });

      testWidgets('empty list can become filled: ${layout.name}', (
        tester,
      ) async {
        await pumpCbs(tester, child: _collection(const [], layout: layout));
        await pumpCbs(tester, child: _collection(_items(2), layout: layout));

        expect(tester.takeException(), isNull);
        expect(find.byKey(_key(0)), findsOneWidget);
        expect(find.byKey(_key(1)), findsOneWidget);
      });
    }

    testWidgets('one child in a list fills the width', (tester) async {
      await pumpCbs(
        tester,
        child: _collection(_items(1), layout: CbsCollectionLayout.list),
      );

      _expectRect(
        _itemRect(tester, 0),
        const Rect.fromLTWH(0, 0, 600, _itemHeight),
      );
      expect(_collectionSize(tester), const Size(600, _itemHeight));
    });

    testWidgets('one child in a grid takes one column', (tester) async {
      await pumpCbs(tester, child: _collection(_items(1)));

      // Two columns at 600: the cell does not stretch with its row.
      _expectRect(
        _itemRect(tester, 0),
        const Rect.fromLTWH(0, 0, 294, _itemHeight),
      );
      expect(_collectionSize(tester), const Size(600, _itemHeight));
    });

    testWidgets('several children in a list', (tester) async {
      await pumpCbs(
        tester,
        child: _collection(_items(5), layout: CbsCollectionLayout.list),
      );

      for (var i = 0; i < 5; i++) {
        expect(find.byKey(_key(i)), findsOneWidget);
      }
      expect(
        _collectionSize(tester),
        const Size(600, 5 * _itemHeight + 4 * _gap),
      );
    });

    testWidgets('several children in a grid', (tester) async {
      await pumpCbs(tester, child: _collection(_items(5)));

      for (var i = 0; i < 5; i++) {
        expect(find.byKey(_key(i)), findsOneWidget);
      }
      // Two columns: three rows.
      expect(
        _collectionSize(tester),
        const Size(600, 3 * _itemHeight + 2 * _gap),
      );
    });

    testWidgets('updates when the children change', (tester) async {
      await pumpCbs(tester, child: _collection(_items(2)));
      expect(find.byKey(_key(2)), findsNothing);

      await pumpCbs(tester, child: _collection(_items(4)));
      expect(find.byKey(_key(2)), findsOneWidget);
      expect(find.byKey(_key(3)), findsOneWidget);

      await pumpCbs(tester, child: _collection(_items(1)));
      expect(find.byKey(_key(1)), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('order of the children', () {
    testWidgets('list: top to bottom', (tester) async {
      await pumpCbs(
        tester,
        child: _collection(_items(6), layout: CbsCollectionLayout.list),
      );

      for (var i = 0; i < 6; i++) {
        _expectRect(
          _itemRect(tester, i),
          Rect.fromLTWH(0, i * (_itemHeight + _gap), 600, _itemHeight),
          reason: 'item $i',
        );
      }
    });

    testWidgets('grid: left to right, then top to bottom', (tester) async {
      await pumpCbs(tester, width: 840, child: _collection(_items(8)));

      const cell = 272.0; // (840 - 2 * 12) / 3
      for (var i = 0; i < 8; i++) {
        _expectRect(
          _itemRect(tester, i),
          Rect.fromLTWH(
            (i % 3) * (cell + _gap),
            (i ~/ 3) * (_itemHeight + _gap),
            cell,
            _itemHeight,
          ),
          reason: 'item $i',
        );
      }
    });

    testWidgets('grid: follows the text direction', (tester) async {
      await pumpCbs(
        tester,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: _collection(_items(4)),
        ),
      );

      const cell = 294.0;
      _expectRect(
        _itemRect(tester, 0),
        const Rect.fromLTWH(600 - cell, 0, cell, _itemHeight),
      );
      _expectRect(
        _itemRect(tester, 1),
        const Rect.fromLTWH(600 - 2 * cell - _gap, 0, cell, _itemHeight),
      );
      _expectRect(
        _itemRect(tester, 2),
        const Rect.fromLTWH(600 - cell, _itemHeight + _gap, cell, _itemHeight),
      );
    });

    for (final layout in CbsCollectionLayout.values) {
      testWidgets('children of different heights keep their order: '
          '${layout.name}', (tester) async {
        await pumpCbs(
          tester,
          child: _collection([
            _item(0),
            _item(1, height: 80),
            _item(2),
            _item(3, height: 60),
          ], layout: layout),
        );

        if (layout == CbsCollectionLayout.list) {
          expect(_itemRect(tester, 1).top, _itemHeight + _gap);
          expect(_itemRect(tester, 2).top, _itemHeight + _gap + 80 + _gap);
          expect(
            _itemRect(tester, 3).top,
            _itemHeight + _gap + 80 + _gap + _itemHeight + _gap,
          );
        } else {
          // Two columns: the row is as tall as its tallest child and its
          // children are aligned at the top.
          expect(_itemRect(tester, 0).top, 0);
          expect(_itemRect(tester, 1).top, 0);
          expect(_itemRect(tester, 2).top, 80 + _gap);
          expect(_itemRect(tester, 3).top, 80 + _gap);
          expect(_itemRect(tester, 2).left, 0);
          expect(_itemRect(tester, 3).left, greaterThan(0));
        }
      });
    }

    testWidgets('the order follows the children after a reorder', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: _collection(_items(3), layout: CbsCollectionLayout.list),
      );
      await pumpCbs(
        tester,
        child: _collection([
          _item(2),
          _item(0),
          _item(1),
        ], layout: CbsCollectionLayout.list),
      );

      expect(_itemRect(tester, 2).top, 0);
      expect(_itemRect(tester, 0).top, _itemHeight + _gap);
      expect(_itemRect(tester, 1).top, 2 * (_itemHeight + _gap));
    });
  });

  group('list layout', () {
    CbsAdaptiveCollection list({
      int count = 4,
      double spacing = 12,
      double runSpacing = 12,
      double minItemWidth = 240,
    }) => _collection(
      _items(count),
      layout: CbsCollectionLayout.list,
      spacing: spacing,
      runSpacing: runSpacing,
      minItemWidth: minItemWidth,
    );

    testWidgets('is a vertical composition of native primitives', (
      tester,
    ) async {
      await pumpCbs(tester, child: list());

      expect(_inCollection(find.byType(LayoutBuilder)), findsOneWidget);
      expect(_inCollection(find.byType(Column)), findsOneWidget);
      expect(_inCollection(find.byType(Wrap)), findsNothing);
      final column = tester.widget<Column>(_inCollection(find.byType(Column)));
      expect(column.direction, Axis.vertical);
      expect(column.mainAxisSize, MainAxisSize.min);
      expect(column.crossAxisAlignment, CrossAxisAlignment.stretch);
    });

    for (final width in cbsTestWidths) {
      testWidgets('stacks the children over the full width at $width', (
        tester,
      ) async {
        await pumpCbs(tester, width: width, child: list());

        expect(tester.takeException(), isNull);
        expect(_collectionSize(tester).width, width);
        for (var i = 0; i < 4; i++) {
          final rect = _itemRect(tester, i);
          expect(rect.left, 0, reason: 'item $i');
          expect(rect.width, width, reason: 'item $i');
          expect(rect.top, i * (_itemHeight + _gap), reason: 'item $i');
        }
      });
    }

    testWidgets('separates the children by runSpacing', (tester) async {
      for (final runSpacing in <double>[0, 12, 30]) {
        await pumpCbs(tester, child: list(runSpacing: runSpacing));

        for (var i = 1; i < 4; i++) {
          expect(
            _itemRect(tester, i).top - _itemRect(tester, i - 1).bottom,
            runSpacing,
            reason: 'runSpacing $runSpacing, item $i',
          );
        }
        expect(
          tester.widget<Column>(_inCollection(find.byType(Column))).spacing,
          runSpacing,
        );
      }
    });

    testWidgets('ignores spacing and minItemWidth', (tester) async {
      await pumpCbs(tester, width: 320, child: list());
      final reference = _itemRects(tester, 4);

      await pumpCbs(
        tester,
        width: 320,
        child: list(spacing: 99, minItemWidth: 1000),
      );

      expect(tester.takeException(), isNull);
      expect(_itemRects(tester, 4), reference);
    });

    testWidgets('adds no external spacing', (tester) async {
      await pumpCbs(
        tester,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            list(count: 1),
            const SizedBox(key: ValueKey('next'), height: 10, width: 10),
          ],
        ),
      );

      expect(_itemRect(tester, 0).topLeft, Offset.zero);
      expect(_rect(tester, const ValueKey('next')).top, _itemHeight);
    });
  });

  group('grid layout', () {
    List<Widget> items([int count = 24]) => _items(count);

    testWidgets('is built from LayoutBuilder and Wrap', (tester) async {
      await pumpCbs(tester, child: _collection(items()));

      expect(_inCollection(find.byType(LayoutBuilder)), findsOneWidget);
      expect(_inCollection(find.byType(Wrap)), findsOneWidget);
      expect(_inCollection(find.byType(Column)), findsNothing);
      final wrap = tester.widget<Wrap>(_inCollection(find.byType(Wrap)));
      expect(wrap.direction, Axis.horizontal);
      expect(wrap.spacing, 12);
      expect(wrap.runSpacing, 12);
    });

    for (final width in cbsTestWidths) {
      final columns = _expectedColumns[width]!;
      testWidgets('has $columns column(s) at $width', (tester) async {
        await pumpCbs(tester, width: width, child: _collection(items()));

        expect(tester.takeException(), isNull);
        final rects = _itemRects(tester, 24);
        expect(_firstRowCount(rects), columns);

        final cell = _cellWidth(width, columns);
        for (var i = 0; i < rects.length; i++) {
          expect(rects[i].width, closeTo(cell, 0.001), reason: 'item $i');
          expect(rects[i].height, _itemHeight, reason: 'item $i');
          expect(
            rects[i].left,
            closeTo((i % columns) * (cell + _gap), 0.001),
            reason: 'item $i',
          );
        }
        // The first row spans the whole width.
        expect(rects[columns - 1].right, closeTo(width, 0.001));
        expect(_collectionSize(tester).width, width);
      });
    }

    testWidgets('the columns do not depend on the number of children', (
      tester,
    ) async {
      for (final count in [1, 2, 7]) {
        await pumpCbs(tester, width: 840, child: _collection(items(count)));

        expect(
          _itemRect(tester, 0).width,
          closeTo(_cellWidth(840, 3), 0.001),
          reason: '$count children',
        );
      }
    });

    final columnCases = <(double, double, double, int)>[
      // (width, minItemWidth, spacing, columns)
      (600.0, 200.0, 0.0, 3),
      (600.0, 100.0, 0.0, 6),
      (600.0, 300.0, 0.0, 2),
      (600.0, 300.0, 12.0, 1),
      (600.0, 294.0, 12.0, 2),
      (600.0, 600.0, 0.0, 1),
      (600.0, 601.0, 0.0, 1),
      (200.0, 240.0, 12.0, 1),
      (1280.0, 100.0, 20.0, 10),
      (600.0, 50.0, 700.0, 1),
    ];
    for (final (width, minItemWidth, spacing, columns) in columnCases) {
      testWidgets('computes $columns column(s) for width $width, minimum '
          '$minItemWidth, spacing $spacing', (tester) async {
        await pumpCbs(
          tester,
          width: width,
          child: _collection(
            items(),
            spacing: spacing,
            minItemWidth: minItemWidth,
          ),
        );

        expect(tester.takeException(), isNull);
        final rects = _itemRects(tester, 24);
        expect(_firstRowCount(rects), columns);
        expect(
          rects.first.width,
          closeTo(_cellWidth(width, columns, spacing: spacing), 0.001),
        );
        expect(rects.first.width, lessThanOrEqualTo(width));
      });
    }

    for (final width in cbsTestWidths) {
      testWidgets('keeps the children at least minItemWidth wide at $width', (
        tester,
      ) async {
        await pumpCbs(tester, width: width, child: _collection(items()));

        for (final rect in _itemRects(tester, 24)) {
          expect(rect.width, greaterThanOrEqualTo(240 - 0.001));
        }
      });
    }

    testWidgets('shrinks the children below minItemWidth on a narrow width', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        width: 200,
        child: _collection(items(3), minItemWidth: 400),
      );

      expect(tester.takeException(), isNull);
      for (final rect in _itemRects(tester, 3)) {
        expect(rect.left, 0);
        expect(rect.width, 200);
      }
      expect(_firstRowCount(_itemRects(tester, 3)), 1);
    });

    testWidgets('separates the columns by spacing and the rows by '
        'runSpacing', (tester) async {
      await pumpCbs(
        tester,
        child: _collection(items(6), spacing: 20, runSpacing: 30),
      );

      // (600 - 20) / 2 = 290: two columns.
      final first = _itemRect(tester, 0);
      final second = _itemRect(tester, 1);
      final third = _itemRect(tester, 2);
      expect(first.width, 290);
      expect(second.left - first.right, 20);
      expect(second.right, 600);
      expect(third.top - first.bottom, 30);
      expect(third.left, first.left);
      final wrap = tester.widget<Wrap>(_inCollection(find.byType(Wrap)));
      expect(wrap.spacing, 20);
      expect(wrap.runSpacing, 30);
    });

    testWidgets('spacing and runSpacing are independent', (tester) async {
      await pumpCbs(
        tester,
        child: _collection(items(4), spacing: 4, runSpacing: 40),
      );

      expect(_itemRect(tester, 1).left - _itemRect(tester, 0).right, 4);
      expect(_itemRect(tester, 2).top - _itemRect(tester, 0).bottom, 40);

      await pumpCbs(
        tester,
        child: _collection(items(4), spacing: 40, runSpacing: 4),
      );

      expect(_itemRect(tester, 1).left - _itemRect(tester, 0).right, 40);
      expect(_itemRect(tester, 2).top - _itemRect(tester, 0).bottom, 4);
    });

    testWidgets('accepts no spacing', (tester) async {
      await pumpCbs(
        tester,
        child: _collection(items(4), spacing: 0, runSpacing: 0),
      );

      expect(_itemRect(tester, 0).width, 300);
      expect(_itemRect(tester, 1).left, _itemRect(tester, 0).right);
      expect(_itemRect(tester, 2).top, _itemRect(tester, 0).bottom);
    });

    testWidgets('gives its children a tight width', (tester) async {
      await pumpCbs(
        tester,
        child: _collection([
          const SizedBox(key: ValueKey('small'), width: 10, height: 20),
          const SizedBox(key: ValueKey('wide'), width: 5000, height: 20),
        ]),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(const ValueKey('small'))).width, 294);
      expect(tester.getSize(find.byKey(const ValueKey('wide'))).width, 294);
    });

    testWidgets('height is the sum of the rows and of the row gaps', (
      tester,
    ) async {
      await pumpCbs(tester, width: 1280, child: _collection(items(11)));

      // Five columns: three rows.
      expect(
        _collectionSize(tester),
        const Size(1280, 3 * _itemHeight + 2 * _gap),
      );
    });

    testWidgets('adds no external spacing', (tester) async {
      await pumpCbs(
        tester,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _collection(items(1)),
            const SizedBox(key: ValueKey('next'), height: 10, width: 10),
          ],
        ),
      );

      expect(_itemRect(tester, 0).topLeft, Offset.zero);
      expect(_rect(tester, const ValueKey('next')).top, _itemHeight);
    });
  });

  group('constraints', () {
    for (final layout in CbsCollectionLayout.values) {
      testWidgets('takes the width of a tight parent: ${layout.name}', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          child: SizedBox(
            width: 500,
            child: _collection(_items(4), layout: layout),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(_collectionSize(tester).width, 500);
        final cell = layout == CbsCollectionLayout.grid ? 244.0 : 500.0;
        expect(_itemRect(tester, 0).width, cell);
      });

      testWidgets('fits a parent narrower than the window: ${layout.name}', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          width: 1280,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _collection(_items(4), layout: layout),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(_collectionSize(tester).width, 400);
        for (final rect in _itemRects(tester, 4)) {
          expect(rect.left, 0);
          expect(rect.width, 400);
        }
      });

      testWidgets('respects the padding of its parent: ${layout.name}', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          child: Padding(
            padding: const EdgeInsets.all(CbsSpacing.md),
            child: _collection(_items(4), layout: layout),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(_collectionSize(tester).width, 568);
        final first = _itemRect(tester, 0);
        expect(first.left, CbsSpacing.md);
        expect(first.top, CbsSpacing.md);
        final cell = layout == CbsCollectionLayout.grid ? 278.0 : 568.0;
        expect(first.width, cell);
        for (final rect in _itemRects(tester, 4)) {
          expect(rect.right, lessThanOrEqualTo(600 - CbsSpacing.md + 0.001));
        }
      });

      testWidgets('gives an unbounded width one column of minItemWidth: '
          '${layout.name}', (tester) async {
        await pumpCbs(
          tester,
          child: SizedBox(
            height: 400,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _collection(_items(3), layout: layout),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        for (var i = 0; i < 3; i++) {
          _expectRect(
            _itemRect(tester, i),
            Rect.fromLTWH(0, i * (_itemHeight + _gap), 240, _itemHeight),
            reason: 'item $i',
          );
        }
      });

      testWidgets('uses minItemWidth for an unbounded width: ${layout.name}', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          child: SizedBox(
            height: 400,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _collection(_items(2), layout: layout, minItemWidth: 300),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(_itemRect(tester, 0).width, 300);
        expect(_itemRect(tester, 1).width, 300);
      });

      testWidgets('is placed in a vertical scroll view without infinite '
          'constraints: ${layout.name}', (tester) async {
        await pumpCbs(tester, child: _collection(_items(30), layout: layout));

        expect(tester.takeException(), isNull);
        expect(_collectionSize(tester).height.isFinite, isTrue);
        expect(_collectionSize(tester).width, 600);
      });
    }

    testWidgets('recomputes the columns when the width changes', (
      tester,
    ) async {
      for (final width in [320.0, 1280.0, 600.0, 840.0]) {
        await pumpCbs(tester, width: width, child: _collection(_items(12)));

        expect(
          _firstRowCount(_itemRects(tester, 12)),
          _expectedColumns[width],
          reason: 'width $width',
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('follows a change of layout, spacing and minItemWidth', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: _collection(_items(4), layout: CbsCollectionLayout.list),
      );
      expect(_itemRect(tester, 0).width, 600);

      await pumpCbs(tester, child: _collection(_items(4)));
      expect(_itemRect(tester, 0).width, 294);

      await pumpCbs(tester, child: _collection(_items(4), minItemWidth: 150));
      expect(_itemRect(tester, 0).width, closeTo(_cellWidth(600, 3), 0.001));

      await pumpCbs(
        tester,
        child: _collection(_items(4), minItemWidth: 150, spacing: 0),
      );
      expect(_itemRect(tester, 0).width, 150);
    });
  });

  group('no overflow', () {
    for (final layout in CbsCollectionLayout.values) {
      for (final width in cbsTestWidths) {
        for (final scale in cbsTestTextScales) {
          testWidgets(
            'long texts at width $width, text x$scale: ${layout.name}',
            (tester) async {
              await pumpCbs(
                tester,
                width: width,
                textScale: scale,
                child: _collection([
                  for (var i = 0; i < 8; i++) _textItem(i),
                ], layout: layout),
              );

              expect(tester.takeException(), isNull);
              expect(_collectionSize(tester).width, width);
              for (final rect in _itemRects(tester, 8)) {
                expect(rect.left, greaterThanOrEqualTo(0));
                expect(rect.right, lessThanOrEqualTo(width + 0.001));
              }
            },
          );
        }
      }

      testWidgets('minItemWidth larger than the screen: ${layout.name}', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          width: 320,
          child: _collection(
            [for (var i = 0; i < 4; i++) _textItem(i)],
            layout: layout,
            minItemWidth: 1000,
          ),
        );

        expect(tester.takeException(), isNull);
        for (final rect in _itemRects(tester, 4)) {
          expect(rect.left, 0);
          expect(rect.width, 320);
        }
      });

      testWidgets('large spacings on a narrow width: ${layout.name}', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          width: 320,
          child: _collection(
            [for (var i = 0; i < 4; i++) _textItem(i)],
            layout: layout,
            spacing: 500,
            runSpacing: 500,
          ),
        );

        expect(tester.takeException(), isNull);
        for (final rect in _itemRects(tester, 4)) {
          expect(rect.left, 0);
          expect(rect.width, 320);
        }
      });
    }
  });

  group('text scale', () {
    for (final layout in CbsCollectionLayout.values) {
      testWidgets('the content grows with the text scale and the columns do '
          'not change: ${layout.name}', (tester) async {
        Future<(double, int)> measure(double scale) async {
          await pumpCbs(
            tester,
            width: 840,
            textScale: scale,
            child: _collection([
              for (var i = 0; i < 6; i++) _textItem(i),
            ], layout: layout),
          );
          return (
            _collectionSize(tester).height,
            _firstRowCount(_itemRects(tester, 6)),
          );
        }

        final (regularHeight, regularColumns) = await measure(1);
        final (largeHeight, largeColumns) = await measure(2);

        expect(largeColumns, regularColumns);
        expect(largeHeight, greaterThan(regularHeight * 1.5));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('themes', () {
    for (final variant in cbsTestThemes) {
      for (final layout in CbsCollectionLayout.values) {
        testWidgets('${variant.name}, ${layout.name}', (tester) async {
          await pumpCbs(
            tester,
            theme: variant.theme,
            child: _collection([
              for (var i = 0; i < 4; i++) _card(i, onTap: () {}),
            ], layout: layout),
          );

          expect(tester.takeException(), isNull);
          final cell = layout == CbsCollectionLayout.grid ? 294.0 : 600.0;
          for (var i = 0; i < 4; i++) {
            expect(_rect(tester, _cardKey(i)).width, cell, reason: 'card $i');
            // The surface belongs to the card and follows the theme.
            expect(
              _cardMaterial(tester, i).color,
              variant.theme.colorScheme.surfaceContainerLow,
              reason: 'card $i',
            );
          }
        });
      }
    }

    testWidgets('paints nothing and adds nothing of its own', (tester) async {
      for (final layout in CbsCollectionLayout.values) {
        // Bare children: any widget found below the collection is its own.
        await pumpCbs(
          tester,
          child: _collection([
            for (var i = 0; i < 4; i++)
              SizedBox(key: _key(i), height: _itemHeight),
          ], layout: layout),
        );

        for (final type in <Type>[
          Padding,
          Align,
          DecoratedBox,
          ColoredBox,
          Material,
          Card,
          GestureDetector,
          InkWell,
          Scrollable,
          Semantics,
        ]) {
          expect(
            _inCollection(find.byType(type)),
            findsNothing,
            reason: '$type in ${layout.name}',
          );
        }
      }
    });
  });

  group('interactions', () {
    for (final layout in CbsCollectionLayout.values) {
      testWidgets('each child receives its own taps: ${layout.name}', (
        tester,
      ) async {
        final taps = List<int>.filled(4, 0);
        await pumpCbs(
          tester,
          child: _collection([
            for (var i = 0; i < 4; i++) _card(i, onTap: () => taps[i]++),
          ], layout: layout),
        );

        await tester.tap(find.byKey(_cardKey(2)));
        await tester.pump();
        expect(taps, [0, 0, 1, 0]);

        for (var i = 0; i < 4; i++) {
          await tester.tap(find.byKey(_cardKey(i)));
          await tester.pump();
        }
        expect(taps, [1, 1, 2, 1]);
      });

      testWidgets('the action of a child does not activate its card: '
          '${layout.name}', (tester) async {
        final taps = List<int>.filled(3, 0);
        final presses = List<int>.filled(3, 0);
        await pumpCbs(
          tester,
          child: _collection([
            for (var i = 0; i < 3; i++)
              _card(
                i,
                onTap: () => taps[i]++,
                action: TextButton(
                  key: ValueKey('action-$i'),
                  onPressed: () => presses[i]++,
                  child: const Text('Ouvrir'),
                ),
              ),
          ], layout: layout),
        );

        await tester.tap(find.byKey(const ValueKey('action-1')));
        await tester.pump();

        expect(presses, [0, 1, 0]);
        expect(taps, [0, 0, 0]);
      });

      testWidgets('plain buttons keep working: ${layout.name}', (tester) async {
        var presses = 0;
        await pumpCbs(
          tester,
          child: _collection([
            CbsButton(label: 'Un', onPressed: () => presses++),
            const CbsButton(label: 'Deux', onPressed: null),
          ], layout: layout),
        );

        await tester.tap(find.text('Un'));
        await tester.tap(find.text('Deux'), warnIfMissed: false);
        await tester.pump();

        expect(presses, 1);
      });

      testWidgets('keyboard focus follows the order of the children: '
          '${layout.name}', (tester) async {
        final order = <int>[];
        await pumpCbs(
          tester,
          child: _collection([
            for (var i = 0; i < 6; i++)
              _card(i, media: false, onTap: () => order.add(i)),
          ], layout: layout),
        );

        for (var i = 0; i < 6; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
        }

        expect(order, [0, 1, 2, 3, 4, 5]);
      });

      testWidgets('a keyed child keeps its state when the children are '
          'reordered: ${layout.name}', (tester) async {
        const a = ValueKey('a');
        const b = ValueKey('b');
        await pumpCbs(
          tester,
          child: _collection(const [
            _Counter(key: a, label: 'A'),
            _Counter(key: b, label: 'B'),
          ], layout: layout),
        );

        await tester.tap(find.text('A: 0'));
        await tester.pump();
        expect(find.text('A: 1'), findsOneWidget);

        await pumpCbs(
          tester,
          child: _collection(const [
            _Counter(key: b, label: 'B'),
            _Counter(key: a, label: 'A'),
          ], layout: layout),
        );

        // The state followed the key, and the order changed.
        expect(find.text('A: 1'), findsOneWidget);
        expect(find.text('B: 0'), findsOneWidget);
        final aRect = tester.getRect(find.text('A: 1'));
        final bRect = tester.getRect(find.text('B: 0'));
        expect(
          layout == CbsCollectionLayout.list
              ? aRect.top > bRect.top
              : aRect.left > bRect.left,
          isTrue,
        );

        await tester.tap(find.text('A: 1'));
        await tester.pump();
        expect(find.text('A: 2'), findsOneWidget);
      });
    }
  });

  group('semantics', () {
    for (final layout in CbsCollectionLayout.values) {
      testWidgets('preserves the semantics of the children: ${layout.name}', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pumpCbs(
          tester,
          child: _collection([
            Semantics(
              header: true,
              child: const Text('Titre', key: ValueKey('h')),
            ),
            const Text('Visible'),
            const ExcludeSemantics(child: Text('Masqué')),
            Semantics(
              label: 'Étiquette',
              child: const SizedBox(width: 20, height: 20),
            ),
          ], layout: layout),
        );

        expect(
          tester
              .getSemantics(find.byKey(const ValueKey('h')))
              .flagsCollection
              .isHeader,
          isTrue,
        );
        expect(find.bySemanticsLabel('Visible'), findsOneWidget);
        expect(find.bySemanticsLabel('Étiquette'), findsOneWidget);
        expect(find.bySemanticsLabel('Masqué'), findsNothing);
        handle.dispose();
      });

      testWidgets('exposes the children in their order: ${layout.name}', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pumpCbs(tester, child: _collection(_items(6), layout: layout));

        final labels = tester.semantics
            .simulatedAccessibilityTraversal(
              startNode: find.semantics.byLabel(RegExp(r'^Item 0$')),
              endNode: find.semantics.byLabel(RegExp(r'^Item 5$')),
            )
            .map((node) => node.label)
            .toList();

        expect(labels, [for (var i = 0; i < 6; i++) 'Item $i']);
        handle.dispose();
      });

      testWidgets('a card keeps its tap action and its labels: '
          '${layout.name}', (tester) async {
        final handle = tester.ensureSemantics();
        final taps = List<int>.filled(3, 0);
        await pumpCbs(
          tester,
          child: _collection([
            for (var i = 0; i < 3; i++)
              _card(
                i,
                onTap: () => taps[i]++,
                semanticLabel: 'Fiche $i',
                mediaLabel: 'Visuel $i',
              ),
          ], layout: layout),
        );

        for (var i = 0; i < 3; i++) {
          expect(find.bySemanticsLabel(RegExp('Fiche $i')), findsOneWidget);
          expect(find.bySemanticsLabel(RegExp('Visuel $i')), findsOneWidget);
          expect(find.bySemanticsLabel(RegExp('Card $i')), findsOneWidget);
        }

        tester.semantics.tap(find.semantics.byLabel(RegExp('Card 1')));
        await tester.pump();

        expect(taps, [0, 1, 0]);
        handle.dispose();
      });
    }
  });

  group('composition with CbsContentCard and CbsMediaFrame', () {
    for (final width in cbsTestWidths) {
      testWidgets('cards with media in a grid at $width', (tester) async {
        await pumpCbs(
          tester,
          width: width,
          child: _collection([for (var i = 0; i < 6; i++) _card(i)]),
        );

        expect(tester.takeException(), isNull);
        final columns = _expectedColumns[width]!;
        final cell = _cellWidth(width, columns);
        final cards = [for (var i = 0; i < 6; i++) _rect(tester, _cardKey(i))];
        expect(_firstRowCount(cards), columns);
        for (var i = 0; i < 6; i++) {
          final frame = _rect(tester, _frameKey(i));
          expect(cards[i].width, closeTo(cell, 0.001), reason: 'card $i');
          expect(cards[i].height, cards.first.height, reason: 'card $i');
          // The media is as wide as the card, at the top of it, in 16:9.
          expect(frame.left, cards[i].left, reason: 'frame $i');
          expect(frame.top, cards[i].top, reason: 'frame $i');
          expect(frame.width, closeTo(cell, 0.001), reason: 'frame $i');
          expect(
            frame.height,
            closeTo(cell * 9 / 16, 0.001),
            reason: 'frame $i',
          );
        }
      });

      testWidgets('cards with media in a list at $width', (tester) async {
        await pumpCbs(
          tester,
          width: width,
          child: _collection([
            for (var i = 0; i < 3; i++) _card(i),
          ], layout: CbsCollectionLayout.list),
        );

        expect(tester.takeException(), isNull);
        for (var i = 0; i < 3; i++) {
          final card = _rect(tester, _cardKey(i));
          final frame = _rect(tester, _frameKey(i));
          expect(card.left, 0, reason: 'card $i');
          expect(card.width, width, reason: 'card $i');
          expect(frame.width, width, reason: 'frame $i');
          expect(
            frame.height,
            closeTo(width * 9 / 16, 0.001),
            reason: 'frame $i',
          );
          if (i > 0) {
            expect(
              card.top - _rect(tester, _cardKey(i - 1)).bottom,
              _gap,
              reason: 'card $i',
            );
          }
        }
      });
    }

    for (final width in cbsTestWidths) {
      testWidgets('media frames as children at $width', (tester) async {
        await pumpCbs(
          tester,
          width: width,
          child: _collection([
            for (var i = 0; i < 4; i++)
              CbsMediaFrame(
                key: _frameKey(i),
                aspectRatio: i.isEven ? 16 / 9 : 1,
                child: const ColoredBox(color: Colors.grey),
              ),
          ]),
        );

        expect(tester.takeException(), isNull);
        final cell = _cellWidth(width, _expectedColumns[width]!);
        for (var i = 0; i < 4; i++) {
          final frame = _rect(tester, _frameKey(i));
          expect(frame.width, closeTo(cell, 0.001), reason: 'frame $i');
          expect(
            frame.height,
            closeTo(i.isEven ? cell * 9 / 16 : cell, 0.001),
            reason: 'frame $i',
          );
        }
      });
    }

    testWidgets('horizontal cards fill the cells of a grid', (tester) async {
      await pumpCbs(
        tester,
        width: 840,
        child: _collection([
          for (var i = 0; i < 4; i++)
            _card(i, layout: CbsContentCardLayout.horizontal),
        ]),
      );

      expect(tester.takeException(), isNull);
      final cell = _cellWidth(840, 3);
      for (var i = 0; i < 4; i++) {
        final card = _rect(tester, _cardKey(i));
        expect(card.width, closeTo(cell, 0.001), reason: 'card $i');
        expect(
          _rect(tester, _frameKey(i)).width,
          closeTo(cell / 3, 0.001),
          reason: 'frame $i',
        );
      }
    });

    for (final layout in CbsCollectionLayout.values) {
      for (final cardLayout in CbsContentCardLayout.values) {
        for (final width in cbsTestWidths) {
          for (final scale in cbsTestTextScales) {
            testWidgets('long cards at width $width, text x$scale: '
                '${layout.name}, ${cardLayout.name}', (tester) async {
              await pumpCbs(
                tester,
                width: width,
                textScale: scale,
                child: _collection([
                  for (var i = 0; i < 4; i++)
                    _card(
                      i,
                      layout: cardLayout,
                      title: _longTitle,
                      onTap: () {},
                      action: TextButton(
                        onPressed: () {},
                        child: const Text('Ouvrir'),
                      ),
                    ),
                ], layout: layout),
              );

              expect(tester.takeException(), isNull);
              for (var i = 0; i < 4; i++) {
                final card = _rect(tester, _cardKey(i));
                expect(card.left, greaterThanOrEqualTo(0));
                expect(card.right, lessThanOrEqualTo(width + 0.001));
              }
            });
          }
        }
      }
    }

    for (final variant in cbsTestThemes) {
      testWidgets('mixed content in ${variant.name}', (tester) async {
        await pumpCbs(
          tester,
          theme: variant.theme,
          width: 840,
          child: _collection([
            _card(0),
            _card(1, media: false),
            _card(2, layout: CbsContentCardLayout.horizontal),
            CbsMediaFrame(
              key: _frameKey(3),
              aspectRatio: 1,
              child: const ColoredBox(color: Colors.grey),
            ),
            CbsRetryMessage(
              message: 'Échec du chargement',
              retryLabel: 'Réessayer',
              onRetry: () {},
            ),
            const CbsFeedbackMessage(message: 'Information', expand: true),
          ]),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(CbsContentCard), findsNWidgets(3));
        expect(find.byType(CbsMediaFrame), findsNWidgets(3));
        expect(find.byType(CbsRetryMessage), findsOneWidget);
        expect(find.byType(CbsFeedbackMessage), findsWidgets);
      });
    }
  });
}
