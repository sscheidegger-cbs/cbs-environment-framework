import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_demo.dart';
import '../catalog_keys.dart';

/// Demonstration of [CbsCategorySelector].
///
/// The public API exposes the `options` ([CbsCategoryOption], each with a
/// `value`, a `label`, an `enabled` flag and an optional `semanticLabel`),
/// the `selectedValues`, the `onSelectionChanged` callback and a `mode`
/// ([CbsCategorySelectionMode] `single` or `multiple`). The selector is
/// controlled: it never keeps the selection itself. Every demonstration
/// below is a small parent that owns the selection, as an application
/// would, and shows it in a readout under the selector. Every category,
/// label and card drawn here belongs to the example and is CBS
/// demonstration data: it does not come from any application.
class CategorySelectorSection extends StatelessWidget {
  const CategorySelectorSection({super.key});

  /// Categories of the plain demonstrations.
  static const List<CbsCategoryOption<String>> categories = [
    CbsCategoryOption<String>(value: 'music', label: 'Music'),
    CbsCategoryOption<String>(value: 'sport', label: 'Sport'),
    CbsCategoryOption<String>(value: 'cinema', label: 'Cinema'),
    CbsCategoryOption<String>(value: 'theatre', label: 'Theatre'),
    CbsCategoryOption<String>(value: 'dance', label: 'Dance'),
  ];

  /// Categories of `category-single`: `Cinema` has a semantic label.
  static const List<CbsCategoryOption<String>> singleCategories = [
    CbsCategoryOption<String>(value: 'music', label: 'Music'),
    CbsCategoryOption<String>(value: 'sport', label: 'Sport'),
    CbsCategoryOption<String>(
      value: 'cinema',
      label: 'Cinema',
      semanticLabel: 'Cinema category',
    ),
    CbsCategoryOption<String>(value: 'theatre', label: 'Theatre'),
    CbsCategoryOption<String>(value: 'dance', label: 'Dance'),
  ];

  /// Semantic label of `Cinema` in `category-single`.
  static const String cinemaSemanticLabel = 'Cinema category';

  /// Categories of `category-disabled`: `Cinema` (selected at the start) and
  /// `Theatre` are disabled.
  static const List<CbsCategoryOption<String>> disabledCategories = [
    CbsCategoryOption<String>(value: 'music', label: 'Music'),
    CbsCategoryOption<String>(value: 'sport', label: 'Sport'),
    CbsCategoryOption<String>(value: 'cinema', label: 'Cinema', enabled: false),
    CbsCategoryOption<String>(
      value: 'theatre',
      label: 'Theatre',
      enabled: false,
    ),
    CbsCategoryOption<String>(value: 'dance', label: 'Dance'),
  ];

  /// Label wider than a 320 px screen, of `category-long`.
  static const String longLabel =
      'A category with a very long label that is wider than a small screen '
      'and stays on one line';

  /// Categories of `category-long`.
  static const List<CbsCategoryOption<String>> longCategories = [
    CbsCategoryOption<String>(value: 'music', label: 'Music'),
    CbsCategoryOption<String>(value: 'long', label: longLabel),
    CbsCategoryOption<String>(value: 'sport', label: 'Sport'),
  ];

  /// Categories of `category-full`: a long label and a disabled category.
  static const List<CbsCategoryOption<String>> fullCategories = [
    CbsCategoryOption<String>(value: 'music', label: 'Music'),
    CbsCategoryOption<String>(value: 'sport', label: 'Sport'),
    CbsCategoryOption<String>(value: 'cinema', label: 'Cinema'),
    CbsCategoryOption<String>(value: 'theatre', label: 'Theatre'),
    CbsCategoryOption<String>(value: 'dance', label: 'Dance', enabled: false),
    CbsCategoryOption<String>(value: 'long', label: longLabel),
    CbsCategoryOption<String>(value: 'food', label: 'Food'),
  ];

  /// Title of the section of `category-full`.
  static const String fullTitle = 'Browse by category';

  /// Subtitle of the section of `category-full`.
  static const String fullSubtitle = 'Select categories to filter the cards';

  /// Cards of `category-full`, as (title, category value).
  static const List<(String, String)> fullCards = [
    ('Concert', 'music'),
    ('Recital', 'music'),
    ('Match', 'sport'),
    ('Film', 'cinema'),
    ('Play', 'theatre'),
  ];

  /// Text of the readout of a selection: the labels of the selected
  /// [options], in the order of the options, or `none`.
  static String readout(
    List<CbsCategoryOption<String>> options,
    Set<String> selected,
  ) {
    final labels = [
      for (final option in options)
        if (selected.contains(option.value)) option.label,
    ];
    final shown = labels.isEmpty ? 'none' : labels.join(', ');
    return 'Selected: $shown';
  }

  /// Text of the counter of the requests of `category-empty`.
  static String requestsText(int count) => 'Selection requests: $count';

  /// Text counting the cards shown by `category-full`.
  static String cardsText(int count) => 'Cards shown: $count';

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CatalogDemo(
          id: 'category-single',
          label: 'Single selection (ChoiceChip): one category at a time',
          child: _InteractiveDemo(
            id: 'category-single',
            options: singleCategories,
            mode: CbsCategorySelectionMode.single,
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'category-multiple',
          label: 'Multiple selection (FilterChip): add or remove categories',
          child: _InteractiveDemo(
            id: 'category-multiple',
            options: categories,
            mode: CbsCategorySelectionMode.multiple,
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'category-disabled',
          label: 'Disabled categories: visible, inert, selection kept',
          child: _InteractiveDemo(
            id: 'category-disabled',
            options: disabledCategories,
            mode: CbsCategorySelectionMode.multiple,
            initial: {'sport', 'cinema'},
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'category-empty',
          label:
              'Empty selection that the parent does not apply: requests are '
              'counted, nothing gets selected',
          child: _EmptyDemo(),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'category-preselected',
          label: 'Preexisting selection',
          child: _InteractiveDemo(
            id: 'category-preselected',
            options: categories,
            mode: CbsCategorySelectionMode.multiple,
            initial: {'sport', 'theatre'},
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'category-long',
          label: 'Long label: one line, native horizontal scrolling',
          child: _InteractiveDemo(
            id: 'category-long',
            options: longCategories,
            mode: CbsCategorySelectionMode.single,
            initial: {'music'},
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'category-full',
          label:
              'Complete presentation: a section, many categories and the '
              'cards they filter',
          child: _FullDemo(),
        ),
      ],
    );
  }
}

/// Selector owned by a parent that applies every selection it receives.
///
/// The example (the consumer) owns the selection: it stores the set reported
/// by the selector and displays it below the selector.
class _InteractiveDemo extends StatefulWidget {
  const _InteractiveDemo({
    required this.id,
    required this.options,
    required this.mode,
    this.initial = const {},
  });

  final String id;
  final List<CbsCategoryOption<String>> options;
  final CbsCategorySelectionMode mode;
  final Set<String> initial;

  @override
  State<_InteractiveDemo> createState() => _InteractiveDemoState();
}

class _InteractiveDemoState extends State<_InteractiveDemo> {
  late Set<String> selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CbsCategorySelector<String>(
          options: widget.options,
          selectedValues: selected,
          mode: widget.mode,
          onSelectionChanged: (values) => setState(() => selected = values),
        ),
        const SizedBox(height: CbsSpacing.sm),
        Text(
          CategorySelectorSection.readout(widget.options, selected),
          key: CatalogKeys.counter(widget.id),
        ),
      ],
    );
  }
}

/// Selector whose parent counts the selections it receives and never applies
/// them: the selection stays empty, which shows that the selector is
/// controlled.
class _EmptyDemo extends StatefulWidget {
  const _EmptyDemo();

  @override
  State<_EmptyDemo> createState() => _EmptyDemoState();
}

class _EmptyDemoState extends State<_EmptyDemo> {
  int requests = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CbsCategorySelector<String>(
          options: CategorySelectorSection.categories,
          selectedValues: const {},
          mode: CbsCategorySelectionMode.multiple,
          onSelectionChanged: (_) => setState(() => requests++),
        ),
        const SizedBox(height: CbsSpacing.sm),
        Text(
          CategorySelectorSection.requestsText(requests),
          key: CatalogKeys.counter('category-empty'),
        ),
      ],
    );
  }
}

/// Complete presentation: a [CbsContentSection] whose content is a
/// multiple-selection [CbsCategorySelector] above a [CbsAdaptiveCollection]
/// of [CbsContentCard]s.
///
/// The example (the consumer) owns the selection and the filtering: the
/// cards of the selected categories are shown, or every card when nothing is
/// selected.
class _FullDemo extends StatefulWidget {
  const _FullDemo();

  @override
  State<_FullDemo> createState() => _FullDemoState();
}

class _FullDemoState extends State<_FullDemo> {
  Set<String> selected = const {};

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final (title, category) in CategorySelectorSection.fullCards)
        if (selected.isEmpty || selected.contains(category)) title,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CbsContentSection(
          title: CategorySelectorSection.fullTitle,
          subtitle: CategorySelectorSection.fullSubtitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CbsCategorySelector<String>(
                options: CategorySelectorSection.fullCategories,
                selectedValues: selected,
                mode: CbsCategorySelectionMode.multiple,
                onSelectionChanged: (values) =>
                    setState(() => selected = values),
              ),
              const SizedBox(height: CbsSpacing.md),
              CbsAdaptiveCollection(
                layout: CbsCollectionLayout.grid,
                children: [
                  for (final title in cards)
                    CbsContentCard(
                      key: ValueKey('category-card-$title'),
                      content: Text(title),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: CbsSpacing.sm),
        Text(
          CategorySelectorSection.cardsText(cards.length),
          key: CatalogKeys.counter('category-full'),
        ),
      ],
    );
  }
}
