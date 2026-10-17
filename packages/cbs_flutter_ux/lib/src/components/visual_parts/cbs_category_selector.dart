import 'package:flutter/material.dart';

import '../../foundation/tokens/cbs_spacing.dart';

/// One category offered by a [CbsCategorySelector].
///
/// Presentation only: the consuming application provides the [value] that
/// identifies the category, the visible [label] in its current language and,
/// when the visible text is not enough for assistive technologies, a
/// [semanticLabel].
class CbsCategoryOption<T> {
  const CbsCategoryOption({
    required this.value,
    required this.label,
    this.enabled = true,
    this.semanticLabel,
  });

  /// Value identifying the category. It is what the selector reports in
  /// [CbsCategorySelector.onSelectionChanged]; the values of the options of
  /// one selector are expected to be distinct.
  final T value;

  /// Visible text of the category, provided by the consuming application.
  final String label;

  /// Whether the category can be selected or deselected. A category that is
  /// not enabled stays visible, keeps its selected state and is not
  /// interactive. Defaults to true.
  final bool enabled;

  /// Optional description announced by assistive technologies instead of
  /// [label]. The role, the selected state and the enabled state remain
  /// those of the chip.
  final String? semanticLabel;
}

/// How many categories a [CbsCategorySelector] allows to select.
enum CbsCategorySelectionMode {
  /// At most one category is selected: selecting another category replaces
  /// the previous one, and a selected category stays selected when it is
  /// activated again. Drawn with [ChoiceChip]s.
  single,

  /// Any number of categories can be selected: activating a category adds it
  /// to the selection or removes it. Drawn with [FilterChip]s.
  multiple,
}

/// Generic selector of one or several categories, presented as a horizontal
/// row of Material chips.
///
/// Presentation only: the application provides the [options], the labels and
/// the current selection. The selector knows no business model, holds no
/// state, loads nothing and performs no navigation. It is not a selection
/// engine: it composes native Flutter widgets ([ChoiceChip], [FilterChip],
/// [SingleChildScrollView], [Row], [Text]) and adds only the translation of a
/// chip activation into a new selection.
///
/// Controlled by its parent: [selectedValues] is the current selection and
/// the only source of truth. Activating a category never changes what is
/// displayed by itself: the selector reports the new selection through
/// [onSelectionChanged] and the parent rebuilds it with the new
/// [selectedValues].
///
/// [CbsCategorySelectionMode.single] ([ChoiceChip]): activating a category
/// that is not selected reports a set holding only its value, which replaces
/// the previous selection. Activating the selected category changes nothing
/// and does not call [onSelectionChanged]: it stays selected.
///
/// [CbsCategorySelectionMode.multiple] ([FilterChip]): activating a category
/// reports a copy of [selectedValues] with its value added when it was not
/// selected, or removed when it was. The values of [selectedValues] that
/// match no option are kept as they are. The selection can be empty.
///
/// Disabled interactions: when [onSelectionChanged] is null no category is
/// interactive, and a category whose [CbsCategoryOption.enabled] is false is
/// not interactive either. Both stay visible, with their selected state, in
/// the disabled style of the active [ChipThemeData] and are skipped by the
/// keyboard focus traversal.
///
/// Order and layout: the categories are laid out in the order of [options],
/// on one row, from the start edge, separated by [CbsSpacing.sm]. The row
/// scrolls horizontally with the native behavior of
/// [SingleChildScrollView] when the chips are wider than the available
/// width; a chip is never wrapped, clipped or shrunk, and a long label makes
/// its chip wider instead. The row is as tall as its tallest chip, which
/// follows the text scale of the device, and as wide as its chips, up to the
/// width allowed by the parent. The selector adds no external margin and no
/// padding. An empty list of [options] builds nothing and takes no space.
///
/// Theme: the chips take their colors, shape, label style, density and tap
/// target from the active [ThemeData] and [ChipThemeData] (Essentials or
/// Branded, light or dark); the selector overrides none of them. Like every
/// Material chip, they need a [Material] ancestor, which a [Scaffold]
/// provides.
///
/// Interaction and accessibility: the chips keep their native ripple, hover,
/// keyboard focus and Enter / Space activation, a minimum tap target of
/// [kMinInteractiveDimension] and their semantics: a button that exposes its
/// label, its selected state and its enabled state. The reading order is the
/// order of [options].
class CbsCategorySelector<T> extends StatelessWidget {
  const CbsCategorySelector({
    super.key,
    required this.options,
    required this.selectedValues,
    required this.onSelectionChanged,
    this.mode = CbsCategorySelectionMode.single,
  });

  /// Categories offered, in display order, built by the consuming
  /// application.
  final List<CbsCategoryOption<T>> options;

  /// Values of the selected categories: the current selection, owned by the
  /// parent.
  final Set<T> selectedValues;

  /// Called with the new selection when the user changes it. No category is
  /// interactive when it is null.
  final ValueChanged<Set<T>>? onSelectionChanged;

  /// Whether one or several categories can be selected. Defaults to
  /// [CbsCategorySelectionMode.single].
  final CbsCategorySelectionMode mode;

  /// Gap between two chips.
  static const double _chipGap = CbsSpacing.sm;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: _chipGap,
        children: [for (final option in options) _chip(option)],
      ),
    );
  }

  /// Chip of [option], according to [mode].
  Widget _chip(CbsCategoryOption<T> option) {
    final label = _label(option);
    final selected = selectedValues.contains(option.value);
    final onSelected = _onSelected(option);
    return switch (mode) {
      CbsCategorySelectionMode.single => ChoiceChip(
        label: label,
        selected: selected,
        onSelected: onSelected,
      ),
      CbsCategorySelectionMode.multiple => FilterChip(
        label: label,
        selected: selected,
        onSelected: onSelected,
      ),
    };
  }

  /// Visible label of [option]. Its [CbsCategoryOption.semanticLabel], when
  /// given, replaces the text for assistive technologies only; the chip keeps
  /// the role and the states.
  Widget _label(CbsCategoryOption<T> option) {
    final text = Text(option.label);
    final semanticLabel = option.semanticLabel;
    if (semanticLabel == null) return text;
    return Semantics(label: semanticLabel, excludeSemantics: true, child: text);
  }

  /// Activation handler of the chip of [option], or null when the chip must
  /// not be interactive (no callback, or [option] disabled).
  ValueChanged<bool>? _onSelected(CbsCategoryOption<T> option) {
    final onChanged = onSelectionChanged;
    if (onChanged == null || !option.enabled) return null;

    return switch (mode) {
      CbsCategorySelectionMode.single => (bool _) {
        // A single selection is the option itself: activating the selected
        // category again changes nothing and is not reported.
        if (selectedValues.length == 1 &&
            selectedValues.contains(option.value)) {
          return;
        }
        onChanged(<T>{option.value});
      },
      CbsCategorySelectionMode.multiple => (bool selected) {
        final next = <T>{...selectedValues};
        if (selected) {
          next.add(option.value);
        } else {
          next.remove(option.value);
        }
        onChanged(next);
      },
    };
  }
}
