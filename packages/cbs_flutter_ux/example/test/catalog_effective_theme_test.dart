import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cbs_flutter_ux_example/catalog/catalog_keys.dart';
import 'package:cbs_flutter_ux_example/catalog/catalog_scenario.dart';
import 'package:cbs_flutter_ux_example/main.dart';

import 'catalog_test_helpers.dart';

// D03b-C.2-R1 (M4): `MaterialApp.theme` is only the configured theme. These
// tests assert the theme the previewed CBS components really receive, read
// with `Theme.of(context)` from the context of each component.

/// Public CBS widgets of the CURRENT demonstrations.
final _previewedComponents = <String, Finder>{
  'CbsButton': find.byType(CbsButton),
  'CbsLoadingIndicator': find.byType(CbsLoadingIndicator),
  'CbsFeedbackMessage': find.byType(CbsFeedbackMessage),
};

/// Theme expected for [design] and [brightness], built independently of
/// `CatalogScenario.buildTheme`.
ThemeData _expectedTheme(CatalogDesign design, Brightness brightness) {
  return switch (design) {
    CatalogDesign.essentials => CbsTheme.essentials(brightness: brightness),
    CatalogDesign.branded => CbsTheme.branded(
      primaryColor: Colors.teal,
      buttonRadius: CbsRadius.lg,
      brightness: brightness,
    ),
  };
}

/// Asserts that every previewed component receives [expected].
void _expectEffectiveTheme(WidgetTester tester, ThemeData expected) {
  for (final MapEntry(key: name, value: finder)
      in _previewedComponents.entries) {
    expect(finder, findsWidgets, reason: name);

    final theme = effectiveTheme(tester, finder);
    expect(theme.colorScheme, expected.colorScheme, reason: '$name colors');
    expect(
      theme.colorScheme.brightness,
      expected.colorScheme.brightness,
      reason: '$name brightness',
    );
    expect(theme.brightness, expected.brightness, reason: '$name brightness');
    expect(theme.useMaterial3, expected.useMaterial3, reason: '$name M3');
  }

  // Every component sees the same theme as the preview content itself.
  final previewTheme = Theme.of(
    tester.element(find.byKey(CatalogKeys.previewContent)),
  );
  expect(previewTheme.colorScheme, expected.colorScheme);
}

void main() {
  group('effective theme received by the previewed components', () {
    for (final design in CatalogDesign.values) {
      for (final appearance in CatalogAppearance.values) {
        final label = '${design.label} ${appearance.label}';

        testWidgets('$label, as initial scenario', (tester) async {
          await tester.pumpWidget(
            CbsUxShowcase(
              initialScenario: CatalogScenario(
                design: design,
                appearance: appearance,
              ),
            ),
          );

          _expectEffectiveTheme(
            tester,
            _expectedTheme(design, appearance.brightness),
          );
        });

        testWidgets('$label, selected with the controls', (tester) async {
          await tester.pumpWidget(const CbsUxShowcase());

          await selectOption(tester, CatalogKeys.designOption(design));
          await selectOption(tester, CatalogKeys.appearanceOption(appearance));
          await settleThemeAnimation(tester);

          _expectEffectiveTheme(
            tester,
            _expectedTheme(design, appearance.brightness),
          );
        });
      }
    }

    testWidgets('follow every control change, in sequence', (tester) async {
      await tester.pumpWidget(const CbsUxShowcase());
      _expectEffectiveTheme(
        tester,
        _expectedTheme(CatalogDesign.essentials, Brightness.light),
      );

      final steps = <(Key, CatalogDesign, Brightness)>[
        (
          CatalogKeys.appearanceOption(CatalogAppearance.dark),
          CatalogDesign.essentials,
          Brightness.dark,
        ),
        (
          CatalogKeys.designOption(CatalogDesign.branded),
          CatalogDesign.branded,
          Brightness.dark,
        ),
        (
          CatalogKeys.appearanceOption(CatalogAppearance.light),
          CatalogDesign.branded,
          Brightness.light,
        ),
        (
          CatalogKeys.designOption(CatalogDesign.essentials),
          CatalogDesign.essentials,
          Brightness.light,
        ),
      ];
      for (final (key, design, brightness) in steps) {
        await selectOption(tester, key);
        await settleThemeAnimation(tester);
        _expectEffectiveTheme(tester, _expectedTheme(design, brightness));
      }
    });

    testWidgets('keep the effective theme with other dimensions changed', (
      tester,
    ) async {
      await tester.pumpWidget(const CbsUxShowcase());
      await selectOption(
        tester,
        CatalogKeys.designOption(CatalogDesign.branded),
      );
      await selectOption(
        tester,
        CatalogKeys.appearanceOption(CatalogAppearance.dark),
      );
      await selectOption(tester, CatalogKeys.widthOption(CatalogWidth.w840));
      await selectOption(
        tester,
        CatalogKeys.textScaleOption(CatalogTextScale.x2),
      );
      await settleThemeAnimation(tester);

      _expectEffectiveTheme(
        tester,
        _expectedTheme(CatalogDesign.branded, Brightness.dark),
      );
    });

    for (final platformBrightness in Brightness.values) {
      testWidgets('ignore the device brightness ($platformBrightness)', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue =
            platformBrightness;
        addTearDown(tester.platformDispatcher.clearAllTestValues);

        for (final appearance in CatalogAppearance.values) {
          await tester.pumpWidget(
            CbsUxShowcase(
              // New key: a fresh State reads `initialScenario` again.
              key: ValueKey(appearance),
              initialScenario: CatalogScenario(appearance: appearance),
            ),
          );

          _expectEffectiveTheme(
            tester,
            _expectedTheme(CatalogDesign.essentials, appearance.brightness),
          );
        }
      });
    }
  });
}
