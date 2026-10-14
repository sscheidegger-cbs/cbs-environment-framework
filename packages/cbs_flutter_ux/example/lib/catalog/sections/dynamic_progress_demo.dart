import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_keys.dart';

/// Determinate [CbsLoadingIndicator] whose progress changes on user action.
///
/// D03c-A.2 / D4: manual qualification aid. The progress takes one of five
/// simple values (0, 25, 50, 75, 100 %). The example owns the state; no
/// `liveRegion` is added, so that a reader can tell what is read when the
/// indicator receives the screen reader focus from what, if anything, is
/// announced spontaneously after a change.
class CatalogDynamicProgressDemo extends StatefulWidget {
  const CatalogDynamicProgressDemo({super.key});

  /// Progress values offered by the demonstration, in percent.
  static const List<int> steps = [0, 25, 50, 75, 100];

  /// Semantic label of the indicator. Constant: only the progress value
  /// changes between two steps.
  static const String semanticLabel = 'Progress';

  @override
  State<CatalogDynamicProgressDemo> createState() =>
      _CatalogDynamicProgressDemoState();
}

class _CatalogDynamicProgressDemoState
    extends State<CatalogDynamicProgressDemo> {
  int percent = CatalogDynamicProgressDemo.steps.first;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: CbsLoadingIndicator(
            key: CatalogKeys.progressIndicator,
            value: percent / 100,
            semanticLabel: CatalogDynamicProgressDemo.semanticLabel,
          ),
        ),
        const SizedBox(height: CbsSpacing.sm),
        Text(
          'Progress: $percent %',
          key: CatalogKeys.progressReadout,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: CbsSpacing.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: CbsSpacing.sm,
          runSpacing: CbsSpacing.sm,
          children: [
            for (final step in CatalogDynamicProgressDemo.steps)
              CbsButton(
                key: CatalogKeys.progressOption(step),
                label: 'Set $step %',
                onPressed: () {
                  setState(() {
                    percent = step;
                  });
                },
              ),
          ],
        ),
      ],
    );
  }
}
