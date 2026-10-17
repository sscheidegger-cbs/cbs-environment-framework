import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Arrangement of the children of a [CbsAdaptiveCollection].
enum CbsCollectionLayout {
  /// The children are stacked vertically, one per row, each as wide as the
  /// collection.
  list,

  /// The children are laid out in as many columns as the available width
  /// allows, wrapping onto new rows.
  grid,
}

/// Generic collection that arranges widgets provided by the consuming
/// application as a vertical list or as an adaptive grid.
///
/// Presentation only: the application builds the [children]. The collection
/// knows no business model, holds no state, loads nothing and performs no
/// navigation. It is built from native Flutter primitives only
/// ([LayoutBuilder], [Wrap], [Column], [SizedBox]); it is not a layout
/// engine and it does not scroll by itself.
///
/// Order: the [children] are shown in the order given, one after the
/// other, from the start edge and from the top (a row is filled before the
/// next one in the [CbsCollectionLayout.grid] layout). An empty list of
/// [children] builds nothing and takes no space.
///
/// [CbsCollectionLayout.list]: the children are stacked vertically and each
/// one is as wide as the collection. The gap between two children is
/// [runSpacing]; [spacing] and [minItemWidth] are not used.
///
/// [CbsCollectionLayout.grid]: the number of columns is the greatest number
/// of columns that are at least [minItemWidth] wide once separated by
/// [spacing], and at least one. The columns share the width equally, so
/// every child is given the same tight width and the grid fills the
/// available width. The number of columns depends on the width only: with
/// fewer children than columns, the free cells stay empty. [spacing] is the
/// gap between two columns and [runSpacing] the gap between two rows. A
/// child owns its height; the children of a row are aligned at the top.
///
/// Narrow widths: when the available width is smaller than [minItemWidth],
/// the grid has a single column as wide as the collection. [minItemWidth]
/// is a wish, never a width imposed to a child, so nothing overflows
/// horizontally.
///
/// Constraints: the collection takes the maximum width allowed by its
/// parent, which should be bounded. When the width is unbounded (for
/// instance in a horizontal scroll view), both layouts fall back to one
/// column whose children are [minItemWidth] wide, so that no child receives
/// an infinite width. The height is never constrained by the collection:
/// when the children can be taller than the room available, place it in a
/// scroll view. Because it relies on [LayoutBuilder], it cannot be sized by
/// an intrinsic-dimension widget such as [IntrinsicHeight].
///
/// Children: they keep their own semantics, interactions and state. The
/// collection adds no semantics, no gesture detector and no external
/// margin. A child keeps its state when the list is reordered as long as it
/// has a [Key].
///
/// Compatibility: the children are wrapped in a tight width, which is what
/// width-filling widgets such as `CbsContentCard` and `CbsMediaFrame`
/// expect.
class CbsAdaptiveCollection extends StatelessWidget {
  const CbsAdaptiveCollection({
    required this.children,
    super.key,
    this.layout = CbsCollectionLayout.list,
    this.spacing = 12,
    this.runSpacing = 12,
    this.minItemWidth = 240,
  }) : assert(
         spacing >= 0 && spacing < double.infinity,
         'spacing must be zero or positive and finite.',
       ),
       assert(
         runSpacing >= 0 && runSpacing < double.infinity,
         'runSpacing must be zero or positive and finite.',
       ),
       assert(
         minItemWidth > 0 && minItemWidth < double.infinity,
         'minItemWidth must be positive and finite.',
       );

  /// Widgets arranged by the collection, built by the consuming
  /// application. Their order is preserved.
  final List<Widget> children;

  /// Arrangement of the [children]. Defaults to
  /// [CbsCollectionLayout.list].
  final CbsCollectionLayout layout;

  /// Gap between two columns of the [CbsCollectionLayout.grid] layout, in
  /// logical pixels. It must be zero or positive and finite. Defaults to 12.
  final double spacing;

  /// Gap between two rows, in logical pixels. In the
  /// [CbsCollectionLayout.list] layout it is the gap between two children.
  /// It must be zero or positive and finite. Defaults to 12.
  final double runSpacing;

  /// Minimum width wished for a child of the [CbsCollectionLayout.grid]
  /// layout, in logical pixels. It must be positive and finite. Defaults to
  /// 240.
  final double minItemWidth;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite) return _unbounded();
        return switch (layout) {
          CbsCollectionLayout.list => _list(),
          CbsCollectionLayout.grid => _grid(maxWidth),
        };
      },
    );
  }

  /// Number of columns that fit [availableWidth]: the greatest count of
  /// columns of at least [minItemWidth] separated by [spacing], and at
  /// least one.
  int _columns(double availableWidth) {
    final fitting = ((availableWidth + spacing) / (minItemWidth + spacing))
        .floor();
    return math.max(1, fitting);
  }

  Widget _list() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: runSpacing,
      children: [for (final child in children) _slot(child)],
    );
  }

  Widget _grid(double availableWidth) {
    final columns = _columns(availableWidth);
    final itemWidth = math.max(
      0.0,
      (availableWidth - spacing * (columns - 1)) / columns,
    );
    return SizedBox(
      width: availableWidth,
      child: Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: [for (final child in children) _slot(child, itemWidth)],
      ),
    );
  }

  /// Fallback when the width is unbounded: one column of children that are
  /// [minItemWidth] wide, whatever the layout.
  Widget _unbounded() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: runSpacing,
      children: [for (final child in children) _slot(child, minItemWidth)],
    );
  }

  /// Gives [child] its [width] (the constraints it receives when null).
  ///
  /// The slot is keyed after the key of [child], so that a keyed child
  /// keeps its state when the children are reordered.
  Widget _slot(Widget child, [double? width]) {
    final key = child.key;
    return SizedBox(
      key: key == null ? null : ValueKey<Key>(key),
      width: width,
      child: child,
    );
  }
}
