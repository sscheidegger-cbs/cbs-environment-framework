import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_demo.dart';
import 'retry_demo.dart';

/// The four presentation states, composed from existing CBS widgets.
///
/// Presentation only, as a consumer would build it: there is no CBS state
/// controller, model or orchestrator. Each state is a plain composition of
/// `CbsStatePanel`, `CbsLoadingIndicator`, `CbsSectionHeading`,
/// `CbsRetryMessage` and `CbsButton`; the texts and the retry callback
/// belong to the example.
class ApplicationStatesSection extends StatelessWidget {
  const ApplicationStatesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Each state below is composed by the consumer from CBS widgets.'),
        SizedBox(height: CbsSpacing.md),
        CatalogDemo(
          id: 'state-loading',
          label: 'Loading',
          child: CbsStatePanel(
            child: Column(
              children: [
                CbsLoadingIndicator(semanticLabel: 'Loading content'),
                SizedBox(height: CbsSpacing.sm),
                Text('Loading content...', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'state-empty',
          label: 'Empty',
          child: CbsStatePanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CbsSectionHeading(title: 'Nothing to show yet'),
                SizedBox(height: CbsSpacing.xs),
                Text('There is no content to display.'),
              ],
            ),
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'state-error',
          label: 'Error',
          child: CatalogRetryDemo(
            id: 'state-error',
            message: 'Content could not be loaded.',
            retryLabel: 'Try again',
          ),
        ),
        catalogDemoGap,
        CatalogDemo(id: 'state-ready', label: 'Ready', child: _ReadyContent()),
      ],
    );
  }
}

/// Ready state: consumer content under a section heading.
class _ReadyContent extends StatelessWidget {
  const _ReadyContent();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CbsSectionHeading(title: 'Sample content'),
        const SizedBox(height: CbsSpacing.sm),
        const Text('First sample item'),
        const SizedBox(height: CbsSpacing.xs),
        const Text('Second sample item'),
        const SizedBox(height: CbsSpacing.xs),
        const Text('Third sample item'),
        const SizedBox(height: CbsSpacing.md),
        CbsButton(label: 'Open item', onPressed: () {}),
      ],
    );
  }
}
