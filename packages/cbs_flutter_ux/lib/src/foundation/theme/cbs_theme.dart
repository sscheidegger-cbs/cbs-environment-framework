import 'package:flutter/material.dart';

import 'cbs_theme_config.dart';

/// Builds reusable Flutter themes for CBS applications.
abstract final class CbsTheme {
  /// Essentials theme with standard Material 3 defaults.
  static ThemeData essentials({Brightness brightness = Brightness.light}) {
    return fromConfig(CbsThemeConfig.essentials(brightness: brightness));
  }

  /// Branded theme using an application-provided primary color.
  static ThemeData branded({
    required Color primaryColor,
    Brightness brightness = Brightness.light,
    TextTheme? textTheme,
    double? buttonRadius,
  }) {
    return fromConfig(
      CbsThemeConfig(
        seedColor: primaryColor,
        brightness: brightness,
        textTheme: textTheme,
        buttonRadius: buttonRadius,
      ),
    );
  }

  /// Builds a Material 3 theme from a typed [config].
  static ThemeData fromConfig(CbsThemeConfig config) {
    final buttonRadius = config.buttonRadius;

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: config.seedColor,
        brightness: config.brightness,
      ),
      textTheme: config.textTheme,
      filledButtonTheme: buttonRadius == null
          ? null
          : FilledButtonThemeData(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(buttonRadius),
                ),
              ),
            ),
    );
  }
}
