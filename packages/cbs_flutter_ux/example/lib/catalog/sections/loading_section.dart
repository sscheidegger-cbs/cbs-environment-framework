import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

/// CURRENT demonstration of [CbsLoadingIndicator]:
/// indeterminate and determinate (60 %).
class LoadingSection extends StatelessWidget {
  const LoadingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
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
    );
  }
}
