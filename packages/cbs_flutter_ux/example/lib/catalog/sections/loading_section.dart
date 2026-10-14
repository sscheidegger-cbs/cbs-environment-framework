import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_demo.dart';
import '../catalog_keys.dart';
import 'dynamic_progress_demo.dart';

/// Demonstration of [CbsLoadingIndicator].
///
/// The public API exposes `value` (null for indeterminate, 0.0 to 1.0 for
/// determinate) and an optional `semanticLabel`.
///
/// CURRENT (D03b-C.2): indeterminate and determinate (60 %), in
/// `loading-states`. Added in D03b-C.3: `loading-range`, the two bounds of
/// the determinate range. Added in D03c-A.2: `loading-no-label` (D3, an
/// indicator without `semanticLabel`) and `loading-progress` (D4, a
/// determinate indicator whose progress changes on user action).
class LoadingSection extends StatelessWidget {
  const LoadingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CatalogDemo(
          id: 'loading-states',
          label: 'Indeterminate and determinate',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    CbsLoadingIndicator(semanticLabel: 'Indeterminate loading'),
                    SizedBox(height: CbsSpacing.sm),
                    Text('Indeterminate'),
                  ],
                ),
              ),
              SizedBox(width: CbsSpacing.md),
              Expanded(
                child: Column(
                  children: [
                    CbsLoadingIndicator(
                      value: 0.6,
                      semanticLabel: '60 percent complete',
                    ),
                    SizedBox(height: CbsSpacing.sm),
                    Text('Determinate - 60 %'),
                  ],
                ),
              ),
            ],
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'loading-range',
          label: 'Determinate bounds',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    CbsLoadingIndicator(
                      value: 0,
                      semanticLabel: '0 percent complete',
                    ),
                    SizedBox(height: CbsSpacing.sm),
                    Text('Determinate - 0 %'),
                  ],
                ),
              ),
              SizedBox(width: CbsSpacing.md),
              Expanded(
                child: Column(
                  children: [
                    CbsLoadingIndicator(
                      value: 1,
                      semanticLabel: '100 percent complete',
                    ),
                    SizedBox(height: CbsSpacing.sm),
                    Text('Determinate - 100 %'),
                  ],
                ),
              ),
            ],
          ),
        ),
        catalogDemoGap,
        // D03c-A.2 / D3: deliberately no `semanticLabel` and no replacement
        // label (no wrapping `Semantics`): the demonstration exists to
        // observe what a screen reader does without a label.
        CatalogDemo(
          id: 'loading-no-label',
          label: 'Indeterminate without semanticLabel',
          child: Column(
            children: [
              CbsLoadingIndicator(key: CatalogKeys.unlabeledLoading),
              SizedBox(height: CbsSpacing.sm),
              Text(
                'No semanticLabel is provided to this indicator.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'loading-progress',
          label: 'Determinate with changing progress',
          child: CatalogDynamicProgressDemo(),
        ),
      ],
    );
  }
}
