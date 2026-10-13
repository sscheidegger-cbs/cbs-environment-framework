import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_demo.dart';

/// Demonstration of [CbsFeedbackMessage].
///
/// The public API exposes `message`, `type` (info, success, warning,
/// error), an optional `semanticLabel` and `expand`.
///
/// CURRENT (D03b-C.2): the four types, in `feedback-types`. Added in
/// D03b-C.3: `feedback-expand`, `feedback-long` and `feedback-semantic`.
class FeedbackSection extends StatelessWidget {
  const FeedbackSection({super.key});

  /// Message long enough to wrap on the narrowest simulated width.
  static const String longMessage =
      'This is a deliberately long feedback message used to check that the '
      'text wraps inside the available width at every simulated width and '
      'text scale instead of overflowing.';

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CatalogDemo(
          id: 'feedback-types',
          label: 'Types',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CbsFeedbackMessage(
                message: 'Information message',
                type: CbsFeedbackType.info,
              ),
              SizedBox(height: CbsSpacing.sm),
              CbsFeedbackMessage(
                message: 'Success message',
                type: CbsFeedbackType.success,
              ),
              SizedBox(height: CbsSpacing.sm),
              CbsFeedbackMessage(
                message: 'Warning message',
                type: CbsFeedbackType.warning,
              ),
              SizedBox(height: CbsSpacing.sm),
              CbsFeedbackMessage(
                message: 'Error message',
                type: CbsFeedbackType.error,
              ),
            ],
          ),
        ),
        catalogDemoGap,
        // `crossAxisAlignment.start` gives the messages loose width
        // constraints: only then does `expand` make a visible difference.
        CatalogDemo(
          id: 'feedback-expand',
          label: 'Expand: false (default) and true',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CbsFeedbackMessage(
                message: 'Compact message',
                type: CbsFeedbackType.info,
              ),
              SizedBox(height: CbsSpacing.sm),
              CbsFeedbackMessage(
                message: 'Expanded message',
                type: CbsFeedbackType.success,
                expand: true,
              ),
            ],
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'feedback-long',
          label: 'Long message',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CbsFeedbackMessage(
                message: longMessage,
                type: CbsFeedbackType.warning,
              ),
              SizedBox(height: CbsSpacing.sm),
              CbsFeedbackMessage(
                message: longMessage,
                type: CbsFeedbackType.error,
                expand: true,
              ),
            ],
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'feedback-semantic',
          label: 'Semantic label',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CbsFeedbackMessage(
                message: 'Upload failed',
                type: CbsFeedbackType.error,
                semanticLabel: 'Error: upload failed',
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
