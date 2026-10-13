import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbsThemeConfig', () {
    test('defaults to light brightness without optional values', () {
      const config = CbsThemeConfig(seedColor: Colors.green);

      expect(config.brightness, Brightness.light);
      expect(config.textTheme, isNull);
      expect(config.buttonRadius, isNull);
    });

    test('essentials configuration uses the Essentials seed', () {
      const config = CbsThemeConfig.essentials();

      expect(config.seedColor, CbsThemeConfig.essentialsSeedColor);
      expect(config.brightness, Brightness.light);
      expect(config.textTheme, isNull);
      expect(config.buttonRadius, isNull);
    });

    test('supports value equality', () {
      const a = CbsThemeConfig(seedColor: Colors.green, buttonRadius: 16);
      const b = CbsThemeConfig(seedColor: Colors.green, buttonRadius: 16);
      const c = CbsThemeConfig(seedColor: Colors.orange, buttonRadius: 16);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('copyWith replaces only the given values', () {
      const config = CbsThemeConfig(seedColor: Colors.green, buttonRadius: 8);

      final copy = config.copyWith(brightness: Brightness.dark);

      expect(copy.seedColor, Colors.green);
      expect(copy.buttonRadius, 8);
      expect(copy.brightness, Brightness.dark);
      expect(config.brightness, Brightness.light);
    });
  });

  group('CbsTheme.fromConfig', () {
    test('builds a Material 3 theme from the seed color', () {
      final expected = ColorScheme.fromSeed(seedColor: Colors.teal);

      final theme = CbsTheme.fromConfig(
        const CbsThemeConfig(seedColor: Colors.teal),
      );

      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.primary, expected.primary);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('applies dark brightness', () {
      final theme = CbsTheme.fromConfig(
        const CbsThemeConfig(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      );

      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('applies typography and button radius', () {
      final theme = CbsTheme.fromConfig(
        const CbsThemeConfig(
          seedColor: Colors.teal,
          textTheme: TextTheme(
            headlineLarge: TextStyle(fontFamily: 'CBSBrand', fontSize: 36),
          ),
          buttonRadius: CbsRadius.lg,
        ),
      );

      expect(theme.textTheme.headlineLarge?.fontFamily, 'CBSBrand');

      final shape = theme.filledButtonTheme.style?.shape?.resolve({});
      expect(
        shape,
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CbsRadius.lg),
        ),
      );
    });

    test('preserves Material 3 defaults without optional values', () {
      final theme = CbsTheme.fromConfig(
        const CbsThemeConfig(seedColor: Colors.teal),
      );

      final expected = ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      );

      expect(theme.textTheme, expected.textTheme);
      expect(theme.filledButtonTheme.style, expected.filledButtonTheme.style);
    });
  });

  group('Backward compatibility of CbsTheme factories', () {
    test('essentials matches the legacy Essentials construction', () {
      for (final brightness in Brightness.values) {
        final theme = CbsTheme.essentials(brightness: brightness);

        final legacy = ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: brightness,
          ),
        );

        expect(theme.useMaterial3, legacy.useMaterial3);
        expect(theme.colorScheme, legacy.colorScheme);
        expect(theme.textTheme, legacy.textTheme);
        expect(theme.filledButtonTheme, legacy.filledButtonTheme);
      }
    });

    test('branded matches the equivalent typed configuration', () {
      const textTheme = TextTheme(
        headlineLarge: TextStyle(fontFamily: 'CBSBrand', fontSize: 36),
      );

      final branded = CbsTheme.branded(
        primaryColor: Colors.green,
        brightness: Brightness.dark,
        textTheme: textTheme,
        buttonRadius: CbsRadius.lg,
      );

      final typed = CbsTheme.fromConfig(
        const CbsThemeConfig(
          seedColor: Colors.green,
          brightness: Brightness.dark,
          textTheme: textTheme,
          buttonRadius: CbsRadius.lg,
        ),
      );

      expect(branded.colorScheme, typed.colorScheme);
      expect(branded.textTheme, typed.textTheme);
      expect(branded.filledButtonTheme, typed.filledButtonTheme);
    });
  });
}
