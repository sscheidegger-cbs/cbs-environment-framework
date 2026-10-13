import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_demo.dart';

/// Demonstration of [CbsStatePanel].
///
/// The public API exposes a single `child`. The panel fills the width given
/// by its parent; padding, radius and color come from CBS tokens and the
/// active theme.
class StatePanelSection extends StatelessWidget {
  const StatePanelSection({super.key});

  /// Width of the narrow parent of `state-panel-constrained`.
  ///
  /// Smaller than the narrowest simulated width (320 px).
  static const double constrainedWidth = 200;

  /// Content of `state-panel-constrained`.
  ///
  /// Deliberately short: it must stay on one line, narrower than
  /// [constrainedWidth] once padded, even at text x2. A panel that fills its
  /// parent is then visibly wider than a panel that hugs its content.
  static const String constrainedText = 'OK';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CatalogDemo(
          id: 'state-panel-content',
          label: 'Representative content, full width',
          child: CbsStatePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CbsSectionHeading(title: 'Panel title'),
                const SizedBox(height: CbsSpacing.sm),
                const Text(
                  'The panel frames content built by the consumer: texts, '
                  'indicators and actions.',
                ),
                const SizedBox(height: CbsSpacing.md),
                CbsButton(label: 'Panel action', onPressed: () {}),
              ],
            ),
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'state-panel-constrained',
          label: 'Parent limited to 200 px',
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: constrainedWidth),
              child: const CbsStatePanel(child: Text(constrainedText)),
            ),
          ),
        ),
      ],
    );
  }
}
