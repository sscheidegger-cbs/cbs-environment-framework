import 'package:flutter/material.dart';

import '../../components/primitives/cbs_button.dart';
import '../../components/primitives/cbs_feedback_message.dart';
import '../../foundation/tokens/cbs_spacing.dart';

/// Error message followed by a retry action.
///
/// Composes a full-width [CbsFeedbackMessage] of type
/// [CbsFeedbackType.error] and a [CbsButton], separated by a
/// [CbsSpacing.sm] vertical gap and aligned to the start.
///
/// Presentation only: the consuming application provides every text
/// (already localized) and decides what [onRetry] does.
///
/// The widget takes the maximum width allowed by its parent, which must
/// provide a bounded width.
class CbsRetryMessage extends StatelessWidget {
  const CbsRetryMessage({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
    this.semanticLabel,
    super.key,
  });

  /// Visible error message.
  final String message;

  /// Visible label of the retry button.
  final String retryLabel;

  /// Called when the retry button is activated.
  final VoidCallback onRetry;

  /// Accessible description of the error message, forwarded to
  /// [CbsFeedbackMessage.semanticLabel].
  ///
  /// Provided by the consuming application in its current language.
  /// It does not affect the retry button semantics.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CbsFeedbackMessage(
          message: message,
          type: CbsFeedbackType.error,
          semanticLabel: semanticLabel,
          expand: true,
        ),
        const SizedBox(height: CbsSpacing.sm),
        CbsButton(label: retryLabel, onPressed: onRetry),
      ],
    );
  }
}
