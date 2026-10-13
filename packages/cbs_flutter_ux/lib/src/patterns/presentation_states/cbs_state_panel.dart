import 'package:flutter/material.dart';

import '../../foundation/tokens/cbs_radius.dart';
import '../../foundation/tokens/cbs_spacing.dart';

/// Full-width surface that frames the content of a presentation state.
///
/// Presentation only: the consuming application chooses the state
/// (loading, empty, ...) and builds the [child], including any localized
/// text. The panel adds no semantics and holds no state.
///
/// The surface uses the `surfaceContainerHighest` color of the active
/// Material 3 color scheme, a [CbsSpacing.lg] padding and a [CbsRadius.lg]
/// corner radius. It does not depend on `CardTheme`.
///
/// The panel takes the maximum width allowed by its parent, which must
/// provide a bounded width.
class CbsStatePanel extends StatelessWidget {
  const CbsStatePanel({required this.child, super.key});

  /// Content displayed inside the panel.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(CbsRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(CbsSpacing.lg),
          child: child,
        ),
      ),
    );
  }
}
