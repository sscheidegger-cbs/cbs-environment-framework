import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_demo.dart';

/// Demonstration of [CbsSectionHeading].
///
/// The public API exposes a single `title`. The heading is a title only:
/// no description, action or outer spacing. The gap below it is a
/// `SizedBox` placed by the example, as a consumer would.
class SectionHeadingSection extends StatelessWidget {
  const SectionHeadingSection({super.key});

  /// Short title of `heading-short`.
  static const String shortTitle = 'Short heading';

  /// Title of `heading-hierarchy`.
  static const String hierarchyTitle = 'Heading in the hierarchy';

  /// Title long enough to wrap on the narrowest simulated width.
  static const String longTitle =
      'A deliberately long section title that must wrap inside the '
      'available width';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CatalogDemo(
          id: 'heading-short',
          label: 'Short title',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CbsSectionHeading(title: shortTitle),
              // Spacing is chosen by the consumer, not by the heading.
              SizedBox(height: CbsSpacing.sm),
              Text('Content below the heading, separated by CbsSpacing.sm.'),
            ],
          ),
        ),
        catalogDemoGap,
        const CatalogDemo(
          id: 'heading-long',
          label: 'Long title',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CbsSectionHeading(title: longTitle),
              SizedBox(height: CbsSpacing.sm),
              Text('Content below the long heading.'),
            ],
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'heading-hierarchy',
          label: 'Typographic hierarchy',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Screen title (titleLarge)', style: textTheme.titleLarge),
              const SizedBox(height: CbsSpacing.sm),
              const CbsSectionHeading(title: hierarchyTitle),
              const SizedBox(height: CbsSpacing.xs),
              Text('Body text (bodyMedium)', style: textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
