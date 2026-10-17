import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_demo.dart';
import '../catalog_keys.dart';

/// Demonstration of [CbsContentCard].
///
/// The public API exposes the `content`, `media` and `action` slots, a
/// `layout`, an optional `onTap` and an optional `semanticLabel`. Every
/// text, the media placeholder and the callbacks belong to the example and
/// are CBS demonstration data: they do not come from any application.
class ContentCardSection extends StatelessWidget {
  const ContentCardSection({super.key});

  /// Title of every demonstration card.
  static const String title = 'Sample card title';

  /// Subtitle of every demonstration card.
  static const String subtitle = 'Demonstration data provided by the example';

  /// Title long enough to wrap on the narrowest simulated width.
  static const String longTitle =
      'A deliberately long card title that must wrap inside the available '
      'width without any overflow';

  /// Action label of the demonstration cards.
  static const String actionLabel = 'Open';

  /// Semantic label of `card-interactive`.
  static const String interactiveSemanticLabel = 'Sample card, opens details';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CatalogDemo(
          id: 'card-vertical',
          label: 'Vertical layout: media, content and action',
          child: CbsContentCard(
            media: const _DemoMedia(aspectRatio: 16 / 9),
            content: const _DemoContent(),
            action: TextButton(
              onPressed: () {},
              child: const Text(actionLabel),
            ),
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'card-horizontal',
          label: 'Horizontal layout: media, content and action',
          child: CbsContentCard(
            layout: CbsContentCardLayout.horizontal,
            media: const _DemoMedia(aspectRatio: 1),
            content: const _DemoContent(),
            action: TextButton(
              onPressed: () {},
              child: const Text(actionLabel),
            ),
          ),
        ),
        catalogDemoGap,
        const CatalogDemo(
          id: 'card-content-only',
          label: 'Content only: no media, no action',
          child: CbsContentCard(content: _DemoContent()),
        ),
        catalogDemoGap,
        const CatalogDemo(
          id: 'card-long',
          label: 'Long title, horizontal layout',
          child: CbsContentCard(
            layout: CbsContentCardLayout.horizontal,
            media: _DemoMedia(aspectRatio: 1),
            content: _DemoContent(titleText: longTitle),
          ),
        ),
        catalogDemoGap,
        const CatalogDemo(
          id: 'card-interactive',
          label: 'Interactive card with an independent action',
          child: _InteractiveCardDemo(),
        ),
      ],
    );
  }
}

/// Title and subtitle composed by the example, as a consumer would.
class _DemoContent extends StatelessWidget {
  const _DemoContent({this.titleText = ContentCardSection.title});

  final String titleText;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titleText, style: textTheme.titleMedium),
        const SizedBox(height: CbsSpacing.xs),
        Text(ContentCardSection.subtitle, style: textTheme.bodyMedium),
      ],
    );
  }
}

/// Media placeholder drawn from the active theme; no image is loaded.
class _DemoMedia extends StatelessWidget {
  const _DemoMedia({required this.aspectRatio});

  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ColoredBox(
        color: scheme.primaryContainer,
        child: Center(
          child: Icon(
            Icons.image_outlined,
            size: CbsIconSize.lg,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

/// [CbsContentCard] whose activation and action are visibly functional.
///
/// The example (the consumer) owns the callbacks: it only counts the card
/// taps and the action presses, and displays the counts below the card.
class _InteractiveCardDemo extends StatefulWidget {
  const _InteractiveCardDemo();

  @override
  State<_InteractiveCardDemo> createState() => _InteractiveCardDemoState();
}

class _InteractiveCardDemoState extends State<_InteractiveCardDemo> {
  int taps = 0;
  int actions = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CbsContentCard(
          media: const _DemoMedia(aspectRatio: 16 / 9),
          content: const _DemoContent(),
          semanticLabel: ContentCardSection.interactiveSemanticLabel,
          onTap: () => setState(() => taps++),
          action: TextButton(
            onPressed: () => setState(() => actions++),
            child: const Text(ContentCardSection.actionLabel),
          ),
        ),
        const SizedBox(height: CbsSpacing.sm),
        Text('Card taps: $taps', key: CatalogKeys.counter('card-interactive')),
        Text(
          'Action presses: $actions',
          key: CatalogKeys.counter('card-action'),
        ),
      ],
    );
  }
}
