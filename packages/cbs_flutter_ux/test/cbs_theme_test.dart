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
  });
}
