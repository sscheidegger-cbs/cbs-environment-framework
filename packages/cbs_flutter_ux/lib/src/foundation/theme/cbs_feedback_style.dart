import 'package:flutter/material.dart';

/// Severity levels supported by CBS feedback elements.
enum CbsFeedbackType { info, success, warning, error }

/// Resolved visual style of a feedback severity.
///
/// Colors come from the Material 3 color scheme, so the style
/// follows the active theme, including light and dark modes.
@immutable
final class CbsFeedbackStyle {
  const CbsFeedbackStyle({
    required this.background,
    required this.foreground,
    required this.icon,
  });

  /// Resolves the style of [type] from [colorScheme].
  factory CbsFeedbackStyle.resolve(
    ColorScheme colorScheme,
    CbsFeedbackType type,
  ) {
    return switch (type) {
      CbsFeedbackType.info => CbsFeedbackStyle(
        background: colorScheme.primaryContainer,
        foreground: colorScheme.onPrimaryContainer,
        icon: Icons.info_outline,
      ),
      CbsFeedbackType.success => CbsFeedbackStyle(
        background: colorScheme.secondaryContainer,
        foreground: colorScheme.onSecondaryContainer,
        icon: Icons.check_circle_outline,
      ),
      CbsFeedbackType.warning => CbsFeedbackStyle(
        background: colorScheme.tertiaryContainer,
        foreground: colorScheme.onTertiaryContainer,
        icon: Icons.warning_amber_outlined,
      ),
      CbsFeedbackType.error => CbsFeedbackStyle(
        background: colorScheme.errorContainer,
        foreground: colorScheme.onErrorContainer,
        icon: Icons.error_outline,
      ),
    };
  }

  final Color background;
  final Color foreground;
  final IconData icon;

  @override
  bool operator ==(Object other) =>
      other is CbsFeedbackStyle &&
      other.background == background &&
      other.foreground == foreground &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(background, foreground, icon);
}
