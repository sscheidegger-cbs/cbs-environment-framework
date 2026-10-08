import 'package:flutter/material.dart';

/// Builds reusable Flutter themes for CBS applications.
abstract final class CbsTheme {
  /// Essentials theme with standard Material 3 defaults.
  static ThemeData essentials({Brightness brightness = Brightness.light}) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: brightness,
      ),
    );
  }

  /// Branded theme using an application-provided primary color.
  static ThemeData branded({
    required Color primaryColor,
    Brightness brightness = Brightness.light,
    TextTheme? textTheme,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: brightness,
      ),
      textTheme: textTheme,
    );
  }
}
