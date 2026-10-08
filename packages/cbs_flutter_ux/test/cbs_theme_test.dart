import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbsTheme Essentials', () {
    test('uses Material 3', () {
      final theme = CbsTheme.essentials();

      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('supports dark mode', () {
      final theme = CbsTheme.essentials(brightness: Brightness.dark);

      expect(theme.colorScheme.brightness, Brightness.dark);
    });
  });

  group('CbsTheme Branded', () {
    test('uses the supplied brand color as seed', () {
      final expectedScheme = ColorScheme.fromSeed(seedColor: Colors.green);

      final theme = CbsTheme.branded(primaryColor: Colors.green);

      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.primary, expectedScheme.primary);
    });

    test('supports distinct brand configurations', () {
      final green = CbsTheme.branded(primaryColor: Colors.green);

      final orange = CbsTheme.branded(primaryColor: Colors.orange);

      expect(green.colorScheme.primary, isNot(orange.colorScheme.primary));
    });

    test('supports dark mode', () {
      final theme = CbsTheme.branded(
        primaryColor: Colors.green,
        brightness: Brightness.dark,
      );

      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('preserves default typography without customization', () {
      final theme = CbsTheme.branded(primaryColor: Colors.green);

      final expected = ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      );

      expect(theme.textTheme, expected.textTheme);
    });

    test('preserves default button shape without customization', () {
      final theme = CbsTheme.branded(primaryColor: Colors.green);

      final expected = ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      );

      expect(theme.filledButtonTheme.style, expected.filledButtonTheme.style);
    });

    test('supports custom branded typography', () {
      const customTextTheme = TextTheme(
        headlineLarge: TextStyle(
          fontFamily: 'CBSBrand',
          fontSize: 36,
          fontWeight: FontWeight.w700,
        ),
      );

      final theme = CbsTheme.branded(
        primaryColor: Colors.green,
        textTheme: customTextTheme,
      );

      expect(theme.textTheme.headlineLarge?.fontFamily, 'CBSBrand');
      expect(theme.textTheme.headlineLarge?.fontSize, 36);
      expect(theme.textTheme.headlineLarge?.fontWeight, FontWeight.w700);
    });
  });
}
