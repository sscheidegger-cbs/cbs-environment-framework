import 'package:flutter/material.dart';

/// Severity levels supported by a CBS feedback message.
enum CbsFeedbackType { info, success, warning, error }

/// Reusable feedback message for CBS Flutter applications.
class CbsFeedbackMessage extends StatelessWidget {
  const CbsFeedbackMessage({
    required this.message,
    this.type = CbsFeedbackType.info,
    super.key,
  });

  final String message;
  final CbsFeedbackType type;

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

    return Container(
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
  }
}
