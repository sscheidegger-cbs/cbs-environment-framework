import 'package:flutter/material.dart';

/// Typed configuration of a CBS Material 3 theme.
///
/// Optional values left to null preserve Material 3 defaults.
@immutable
final class CbsThemeConfig {
  const CbsThemeConfig({
    required this.seedColor,
    this.brightness = Brightness.light,
    this.textTheme,
    this.buttonRadius,
  });

  /// Configuration used by the Essentials theme.
  const CbsThemeConfig.essentials({this.brightness = Brightness.light})
    : seedColor = essentialsSeedColor,
      textTheme = null,
      buttonRadius = null;

  /// Seed color of the Essentials theme.
  static const Color essentialsSeedColor = Colors.indigo;

  /// Material 3 color seed.
  final Color seedColor;

  /// Light or dark appearance.
  final Brightness brightness;

  /// Application typography, provided by the consuming application.
  final TextTheme? textTheme;

  /// Corner radius of FilledButton, in logical pixels.
  final double? buttonRadius;

  /// Returns a copy with the given values replaced.
  CbsThemeConfig copyWith({
    Color? seedColor,
    Brightness? brightness,
    TextTheme? textTheme,
    double? buttonRadius,
  }) {
    return CbsThemeConfig(
      seedColor: seedColor ?? this.seedColor,
      brightness: brightness ?? this.brightness,
      textTheme: textTheme ?? this.textTheme,
      buttonRadius: buttonRadius ?? this.buttonRadius,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CbsThemeConfig &&
      other.seedColor == seedColor &&
      other.brightness == brightness &&
      other.textTheme == textTheme &&
      other.buttonRadius == buttonRadius;

  @override
  int get hashCode =>
      Object.hash(seedColor, brightness, textTheme, buttonRadius);
}
