import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

/// CURRENT demonstration of [CbsFeedbackMessage]: the four types.
class FeedbackSection extends StatelessWidget {
  const FeedbackSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
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
    );
  }
}
