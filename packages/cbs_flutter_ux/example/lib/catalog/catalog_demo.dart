import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import 'catalog_keys.dart';

/// Labelled block of a catalog section, identified by a stable [Key].
///
/// A section shows one or several demonstrations; each one is a
/// [CatalogDemo] so that tests and readers can target it without relying
/// on global widget counts.
class CatalogDemo extends StatelessWidget {
  const CatalogDemo({
    required this.id,
    required this.label,
    required this.child,
    super.key,
  });

  /// Stable identifier, used to build the demonstration [Key].
  final String id;

  /// Short caption describing what the demonstration shows.
  final String label;

  /// The demonstrated widgets.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: CatalogKeys.demo(id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: CbsSpacing.sm),
        child,
      ],
    );
  }
}

/// Vertical gap between two demonstrations of a section.
///
/// Spacing belongs to the example (the consumer), not to CBS widgets.
const Widget catalogDemoGap = SizedBox(height: CbsSpacing.md);
