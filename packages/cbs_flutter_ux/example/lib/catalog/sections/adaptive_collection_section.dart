import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_demo.dart';
import '../catalog_keys.dart';

/// Demonstration of [CbsAdaptiveCollection].
///
/// The public API exposes the `children`, a `layout` ([CbsCollectionLayout]
/// `list` or `grid`), a `spacing` between columns, a `runSpacing` between
/// rows and a `minItemWidth`. The collection arranges the widgets it is
/// given and nothing else: every tile, card, media placeholder and callback
/// drawn here belongs to the example and is CBS demonstration data. It does
/// not come from any application.
class AdaptiveCollectionSection extends StatelessWidget {
  const AdaptiveCollectionSection({super.key});

  /// Number of tiles of `collection-list`.
  static const int listCount = 3;

  /// Number of tiles of `collection-grid`.
  static const int gridCount = 6;

  /// Number of cards of `collection-cards`.
  static const int cardCount = 4;

  /// Number of cards of `collection-media`.
  static const int mediaCount = 4;

  /// Number of cards of `collection-narrow`.
  static const int narrowCount = 3;

  /// Width of the parent of `collection-narrow`, narrower than the default
  /// `minItemWidth` of 240.
  static const double narrowWidth = 200;

  /// Title of every demonstration card.
  static const String cardTitle = 'Collection card';

  /// Subtitle of every demonstration card.
  static const String cardSubtitle =
      'Demonstration data provided by the '
      'example';

  /// Action label of the cards of `collection-cards`.
  static const String actionLabel = 'Select';

  /// Text of the tile number [index] (1-based) of a demonstration whose
  /// tiles are named [prefix].
  static String tileText(String prefix, int index) => '$prefix $index';

  /// Prefix of the tiles of `collection-list`.
  static const String listPrefix = 'List item';

  /// Prefix of the tiles of `collection-grid`.
  static const String gridPrefix = 'Grid item';

  /// Semantic label of the media of the card number [index] (1-based) of
  /// `collection-media`.
  static String mediaLabel(int index) => 'Media sample $index';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CatalogDemo(
          id: 'collection-list',
          label: 'List layout: one child per row',
          child: CbsAdaptiveCollection(
            children: [
              for (var i = 1; i <= listCount; i++)
                _DemoTile(text: tileText(listPrefix, i)),
            ],
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'collection-grid',
          label: 'Grid layout: columns follow the width (minItemWidth 240)',
          child: CbsAdaptiveCollection(
            layout: CbsCollectionLayout.grid,
            children: [
              for (var i = 1; i <= gridCount; i++)
                _DemoTile(text: tileText(gridPrefix, i)),
            ],
          ),
        ),
        catalogDemoGap,
        const CatalogDemo(
          id: 'collection-cards',
          label: 'Grid of CbsContentCard with a tap and an action',
          child: _CardsDemo(),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'collection-media',
          label: 'Grid of CbsContentCard composed with CbsMediaFrame',
          child: CbsAdaptiveCollection(
            layout: CbsCollectionLayout.grid,
            children: [
              for (var i = 1; i <= mediaCount; i++)
                CbsContentCard(
                  media: CbsMediaFrame(
                    borderRadius: BorderRadius.zero,
                    semanticLabel: mediaLabel(i),
                    child: const _DemoMedia(),
                  ),
                  content: const _DemoContent(),
                ),
            ],
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'collection-narrow',
          label:
              'Narrow screen: a ${narrowWidth.round()} px parent, '
              'narrower than minItemWidth',
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: narrowWidth,
              child: CbsAdaptiveCollection(
                layout: CbsCollectionLayout.grid,
                children: [
                  for (var i = 1; i <= narrowCount; i++)
                    CbsContentCard(
                      media: CbsMediaFrame(
                        borderRadius: BorderRadius.zero,
                        child: const _DemoMedia(),
                      ),
                      content: const _DemoContent(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Plain tile composed by the example, as a consumer would: a text on a
/// surface of the active theme.
class _DemoTile extends StatelessWidget {
  const _DemoTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(CbsRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CbsSpacing.md),
        child: Text(
          text,
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

/// Title and subtitle composed by the example, as a consumer would.
class _DemoContent extends StatelessWidget {
  const _DemoContent();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AdaptiveCollectionSection.cardTitle, style: textTheme.titleMedium),
        const SizedBox(height: CbsSpacing.xs),
        Text(
          AdaptiveCollectionSection.cardSubtitle,
          style: textTheme.bodyMedium,
        ),
      ],
    );
  }
}

/// Media placeholder drawn from the active theme; no image is loaded. It
/// fills the frame it is given.
class _DemoMedia extends StatelessWidget {
  const _DemoMedia();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.primaryContainer,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: CbsIconSize.lg,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// Collection of [CbsContentCard] whose activation and action are visibly
/// functional.
///
/// The example (the consumer) owns the callbacks: it only counts the card
/// taps and the action presses, and displays the counts below the grid.
class _CardsDemo extends StatefulWidget {
  const _CardsDemo();

  @override
  State<_CardsDemo> createState() => _CardsDemoState();
}

class _CardsDemoState extends State<_CardsDemo> {
  int taps = 0;
  int actions = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CbsAdaptiveCollection(
          layout: CbsCollectionLayout.grid,
          children: [
            for (var i = 0; i < AdaptiveCollectionSection.cardCount; i++)
              CbsContentCard(
                content: const _DemoContent(),
                onTap: () => setState(() => taps++),
                action: TextButton(
                  onPressed: () => setState(() => actions++),
                  child: const Text(AdaptiveCollectionSection.actionLabel),
                ),
              ),
          ],
        ),
        const SizedBox(height: CbsSpacing.sm),
        Text(
          'Collection card taps: $taps',
          key: CatalogKeys.counter('collection-cards'),
        ),
        Text(
          'Collection action presses: $actions',
          key: CatalogKeys.counter('collection-action'),
        ),
      ],
    );
  }
}
