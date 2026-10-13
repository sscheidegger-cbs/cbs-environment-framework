import 'package:flutter/material.dart';

import '../../foundation/theme/cbs_feedback_style.dart';
import '../../foundation/tokens/cbs_radius.dart';
import '../../foundation/tokens/cbs_spacing.dart';

export '../../foundation/theme/cbs_feedback_style.dart' show CbsFeedbackType;

/// Reusable feedback message for CBS Flutter applications.
class CbsFeedbackMessage extends StatelessWidget {
  const CbsFeedbackMessage({
    required this.message,
    this.type = CbsFeedbackType.info,
    this.semanticLabel,
    super.key,
  });

  final String message;
  final CbsFeedbackType type;

  /// Accessible description, including the message severity when relevant.
  ///
  /// Provided by the consuming application in its current language.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final style = CbsFeedbackStyle.resolve(Theme.of(context).colorScheme, type);

    final content = Container(
      padding: const EdgeInsets.all(CbsSpacing.md),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(CbsRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, color: style.foreground),
          const SizedBox(width: CbsSpacing.sm),
          Flexible(
            child: Text(message, style: TextStyle(color: style.foreground)),
          ),
        ],
      ),
    );

    if (semanticLabel == null) {
      return content;
    }

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: content,
    );
  }
}
