import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_demo.dart';

/// Demonstration of [CbsLoadingIndicator].
///
/// The public API exposes `value` (null for indeterminate, 0.0 to 1.0 for
/// determinate) and an optional `semanticLabel`.
///
/// CURRENT (D03b-C.2): indeterminate and determinate (60 %), in
/// `loading-states`. Added in D03b-C.3: `loading-range`, the two bounds of
/// the determinate range.
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
      ],
    );
  }
}
