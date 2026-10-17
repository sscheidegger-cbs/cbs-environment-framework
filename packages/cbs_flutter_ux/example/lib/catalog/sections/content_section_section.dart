import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_demo.dart';
import '../catalog_keys.dart';

/// Demonstration of [CbsContentSection].
///
/// The public API exposes a `title`, a `child`, an optional `subtitle` and
/// an optional `action`. The section draws the title with
/// [CbsSectionHeading], shows the subtitle and the action when they are
/// given, and places the child under them. Every text, card, media
/// placeholder and callback drawn here belongs to the example and is CBS
/// demonstration data: it does not come from any application.
class ContentSectionSection extends StatelessWidget {
  const ContentSectionSection({super.key});

  /// Title of every demonstration section.
  static const String sectionTitle = 'Section title';

  /// Subtitle of the demonstration sections that show one.
  static const String sectionSubtitle = 'Short description of the section';

  /// Label of the action of the demonstration sections that show one.
  static const String actionLabel = 'See all';

  /// Content of the plain demonstrations.
  static const String bodyText = 'Content provided by the example.';

  /// Title of every demonstration card.
  static const String cardTitle = 'Sample card';

  /// Subtitle of every demonstration card.
  static const String cardSubtitle =
      'Demonstration data provided by the example';

  /// Action label of the card of `section-card`.
  static const String cardActionLabel = 'Open';

  /// Semantic label of the media of `section-media`.
  static const String mediaSemanticLabel = 'Media sample';

  /// Number of tiles of `section-collection`.
  static const int tileCount = 6;

  /// Number of cards of `section-full`.
  static const int fullCardCount = 4;

  /// Text of the tile number [index] (1-based) of `section-collection`.
  static String tileText(int index) => 'Tile $index';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CatalogDemo(
          id: 'section-title-content',
          label: 'Title and content',
          child: CbsContentSection(title: sectionTitle, child: Text(bodyText)),
        ),
        catalogDemoGap,
        const CatalogDemo(
          id: 'section-subtitle',
          label: 'Title, subtitle and content',
          child: CbsContentSection(
            title: sectionTitle,
            subtitle: sectionSubtitle,
            child: Text(bodyText),
          ),
        ),
        catalogDemoGap,
        const CatalogDemo(
          id: 'section-action',
          label: 'Title, subtitle and action',
          child: _ActionDemo(),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'section-card',
          label: 'Section with a CbsContentCard',
          child: CbsContentSection(
            title: sectionTitle,
            child: CbsContentCard(
              media: const _DemoMedia(aspectRatio: 16 / 9),
              content: const _DemoContent(),
              action: TextButton(
                onPressed: () {},
                child: const Text(cardActionLabel),
              ),
            ),
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'section-collection',
          label: 'Section with a CbsAdaptiveCollection',
          child: CbsContentSection(
            title: sectionTitle,
            subtitle: sectionSubtitle,
            child: CbsAdaptiveCollection(
              layout: CbsCollectionLayout.grid,
              children: [
                for (var i = 1; i <= tileCount; i++) _DemoTile(index: i),
              ],
            ),
          ),
        ),
        catalogDemoGap,
        const CatalogDemo(
          id: 'section-media',
          label: 'Section with a CbsMediaFrame',
          child: CbsContentSection(
            title: sectionTitle,
            child: CbsMediaFrame(
              semanticLabel: mediaSemanticLabel,
              child: _DemoMediaFill(),
            ),
          ),
        ),
        catalogDemoGap,
        const CatalogDemo(
          id: 'section-full',
          label:
              'Complete section: title, subtitle, action and a collection '
              'of cards with media',
          child: _FullDemo(),
        ),
      ],
    );
  }
}

/// Section whose action is visibly functional.
///
/// The example (the consumer) owns the callback: it only counts the action
/// presses and displays the count below the section.
class _ActionDemo extends StatefulWidget {
  const _ActionDemo();

  @override
  State<_ActionDemo> createState() => _ActionDemoState();
}

class _ActionDemoState extends State<_ActionDemo> {
  int presses = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CbsContentSection(
          title: ContentSectionSection.sectionTitle,
          subtitle: ContentSectionSection.sectionSubtitle,
          action: TextButton(
            onPressed: () => setState(() => presses++),
            child: const Text(ContentSectionSection.actionLabel),
          ),
          child: const Text(ContentSectionSection.bodyText),
        ),
        const SizedBox(height: CbsSpacing.sm),
        Text(
          'Section action presses: $presses',
          key: CatalogKeys.counter('section-action'),
        ),
      ],
    );
  }
}

/// Complete section: a header with a subtitle and an action over a grid of
/// activatable cards with media.
///
/// The example (the consumer) owns the callbacks: it only counts the action
/// presses and the card taps, and displays the counts below the section.
class _FullDemo extends StatefulWidget {
  const _FullDemo();

  @override
  State<_FullDemo> createState() => _FullDemoState();
}

class _FullDemoState extends State<_FullDemo> {
  int actions = 0;
  int taps = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CbsContentSection(
          title: ContentSectionSection.sectionTitle,
          subtitle: ContentSectionSection.sectionSubtitle,
          action: TextButton(
            onPressed: () => setState(() => actions++),
            child: const Text(ContentSectionSection.actionLabel),
          ),
          child: CbsAdaptiveCollection(
            layout: CbsCollectionLayout.grid,
            children: [
              for (var i = 0; i < ContentSectionSection.fullCardCount; i++)
                CbsContentCard(
                  media: const _DemoMedia(aspectRatio: 16 / 9),
                  content: const _DemoContent(),
                  onTap: () => setState(() => taps++),
                ),
            ],
          ),
        ),
        const SizedBox(height: CbsSpacing.sm),
        Text(
          'Full section action presses: $actions',
          key: CatalogKeys.counter('section-full-action'),
        ),
        Text(
          'Full section card taps: $taps',
          key: CatalogKeys.counter('section-full-card'),
        ),
      ],
    );
  }
}

/// Plain tile composed by the example, as a consumer would: a text on a
/// surface of the active theme.
class _DemoTile extends StatelessWidget {
  const _DemoTile({required this.index});

  final int index;

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
          ContentSectionSection.tileText(index),
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
        Text(ContentSectionSection.cardTitle, style: textTheme.titleMedium),
        const SizedBox(height: CbsSpacing.xs),
        Text(ContentSectionSection.cardSubtitle, style: textTheme.bodyMedium),
      ],
    );
  }
}

/// Media placeholder drawn from the active theme and sized by its own
/// aspect ratio, for the media slot of a `CbsContentCard`; no image is
/// loaded.
class _DemoMedia extends StatelessWidget {
  const _DemoMedia({required this.aspectRatio});

  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(aspectRatio: aspectRatio, child: const _DemoMediaFill());
  }
}

/// Media placeholder drawn from the active theme. It fills the frame it is
/// given; no image is loaded.
class _DemoMediaFill extends StatelessWidget {
  const _DemoMediaFill();

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
