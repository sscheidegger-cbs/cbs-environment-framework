import 'package:flutter/material.dart';

import '../catalog_demo.dart';
import 'feedback_section.dart';
import 'retry_demo.dart';

/// Demonstration of `CbsRetryMessage`.
///
/// The public API exposes `message`, `retryLabel`, `onRetry` and an
/// optional `semanticLabel`. Every text and the callback belong to the
/// example; each demonstration counts its retry requests.
class RetryMessageSection extends StatelessWidget {
  const RetryMessageSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CatalogDemo(
          id: 'retry-short',
          label: 'Short message',
          child: CatalogRetryDemo(
            id: 'retry-short',
            message: 'Content could not be loaded.',
            retryLabel: 'Retry',
            semanticLabel: 'Error: content could not be loaded',
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'retry-long',
          label: 'Long message and long label',
          child: CatalogRetryDemo(
            id: 'retry-long',
            message: FeedbackSection.longMessage,
            retryLabel: 'Try loading the content again',
          ),
        ),
      ],
    );
  }
}
