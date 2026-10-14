import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import 'catalog_keys.dart';
import 'catalog_scenario.dart';

/// Simulated viewport of a [CatalogScenario].
///
/// The child is laid out with a tight width equal to the scenario width
/// and sees a matching `MediaQuery` (size and `TextScaler`), so widgets
/// that read either one react as on a real device of that width. With the
/// `device` text scale, the `TextScaler` is the one provided by the
/// enclosing `MediaQuery`, unchanged.
///
/// The simulated surface carries no padding: the width given to the child
/// is exactly the width declared in its `MediaQuery`.
///
/// The decorative frame (surface color, border and rounded corners) is
/// drawn around the simulated surface and never inside it. The border is
/// laid out outside the simulated width, so the frame is `border * 2`
/// wider than the scenario; nothing is clipped.
///
/// When the frame is wider than the available width, it scrolls
/// horizontally instead of overflowing the page.
class CatalogPreviewFrame extends StatelessWidget {
  const CatalogPreviewFrame({
    required this.scenario,
    required this.child,
    super.key,
  });

  final CatalogScenario scenario;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = scenario.width.logicalPixels;
    final media = MediaQuery.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      key: CatalogKeys.previewScroll,
      scrollDirection: Axis.horizontal,
      child: Container(
        key: CatalogKeys.previewFrame,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(CbsRadius.md),
        ),
        child: SizedBox(
          key: CatalogKeys.previewViewport,
          width: width,
          child: MediaQuery(
            data: media.copyWith(
              size: Size(width, media.size.height),
              // `device` keeps the scaler provided by `MediaQuery`.
              textScaler: scenario.textScale.resolve(media.textScaler),
            ),
            child: KeyedSubtree(key: CatalogKeys.previewContent, child: child),
          ),
        ),
      ),
    );
  }
}
