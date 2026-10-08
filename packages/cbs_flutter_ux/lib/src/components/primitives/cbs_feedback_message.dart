import 'package:flutter/material.dart';

/// Severity levels supported by a CBS feedback message.
enum CbsFeedbackType { info, success, warning, error }

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
    final colorScheme = Theme.of(context).colorScheme;

    final (Color background, Color foreground, IconData icon) = switch (type) {
      CbsFeedbackType.info => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
        Icons.info_outline,
      ),
      CbsFeedbackType.success => (
        colorScheme.secondaryContainer,
        colorScheme.onSecondaryContainer,
        Icons.check_circle_outline,
      ),
      CbsFeedbackType.warning => (
        colorScheme.tertiaryContainer,
        colorScheme.onTertiaryContainer,
        Icons.warning_amber_outlined,
      ),
      CbsFeedbackType.error => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
        Icons.error_outline,
      ),
    };

    final content = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 8),
          Flexible(
            child: Text(message, style: TextStyle(color: foreground)),
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
