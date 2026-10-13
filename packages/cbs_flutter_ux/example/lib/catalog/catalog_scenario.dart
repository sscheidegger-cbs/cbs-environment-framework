import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

/// CBS theme family selected in the catalog.
enum CatalogDesign {
  essentials(label: 'Essentials', description: 'Essentials / Indigo'),
  branded(label: 'Branded', description: 'Branded / Teal');

  const CatalogDesign({required this.label, required this.description});

  /// Short label displayed on the selection control.
  final String label;

  /// Description of the resulting theme, displayed below the controls.
  final String description;
}

/// Light or dark appearance selected in the catalog.
enum CatalogAppearance {
  light(label: 'Light', brightness: Brightness.light),
  dark(label: 'Dark', brightness: Brightness.dark);

  const CatalogAppearance({required this.label, required this.brightness});

  final String label;
  final Brightness brightness;
}

/// Simulated preview width, in logical pixels.
enum CatalogWidth {
  w320(320),
  w600(600),
  w840(840),
  w1280(1280);

  const CatalogWidth(this.logicalPixels);

  final double logicalPixels;

  String get label => '${logicalPixels.round()} px';
}

/// Simulated text scale applied to the preview.
enum CatalogTextScale {
  x1(label: 'x1', factor: 1),
  x2(label: 'x2', factor: 2);

  const CatalogTextScale({required this.label, required this.factor});

  final String label;
  final double factor;

  TextScaler get textScaler => TextScaler.linear(factor);
}

/// Local configuration of a catalog scenario.
///
/// Owned by the example application: nothing here belongs to
/// `cbs_flutter_ux`.
@immutable
final class CatalogScenario {
  const CatalogScenario({
    this.design = CatalogDesign.essentials,
    this.appearance = CatalogAppearance.light,
    this.width = CatalogWidth.w320,
    this.textScale = CatalogTextScale.x1,
  });

  /// Scenario displayed when the catalog starts.
  static const CatalogScenario initial = CatalogScenario();

  /// Primary color of the Branded design.
  static const Color brandedPrimaryColor = Colors.teal;

  final CatalogDesign design;
  final CatalogAppearance appearance;
  final CatalogWidth width;
  final CatalogTextScale textScale;

  /// Builds the CBS [ThemeData] matching [design] and [appearance].
  ThemeData buildTheme() {
    final brightness = appearance.brightness;
    return switch (design) {
      CatalogDesign.essentials => CbsTheme.essentials(brightness: brightness),
      CatalogDesign.branded => CbsTheme.branded(
        primaryColor: brandedPrimaryColor,
        buttonRadius: CbsRadius.lg,
        brightness: brightness,
      ),
    };
  }

  /// Human readable summary, e.g. `Essentials · Light · 320 px · Text x1`.
  String get summary =>
      '${design.label} · ${appearance.label} · ${width.label} · '
      'Text ${textScale.label}';

  CatalogScenario copyWith({
    CatalogDesign? design,
    CatalogAppearance? appearance,
    CatalogWidth? width,
    CatalogTextScale? textScale,
  }) {
    return CatalogScenario(
      design: design ?? this.design,
      appearance: appearance ?? this.appearance,
      width: width ?? this.width,
      textScale: textScale ?? this.textScale,
    );
  }

  /// Every combination of design, appearance, width and text scale.
  static Iterable<CatalogScenario> get all sync* {
    for (final design in CatalogDesign.values) {
      for (final appearance in CatalogAppearance.values) {
        for (final width in CatalogWidth.values) {
          for (final textScale in CatalogTextScale.values) {
            yield CatalogScenario(
              design: design,
              appearance: appearance,
              width: width,
              textScale: textScale,
            );
          }
        }
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CatalogScenario &&
      other.design == design &&
      other.appearance == appearance &&
      other.width == width &&
      other.textScale == textScale;

  @override
  int get hashCode => Object.hash(design, appearance, width, textScale);

  @override
  String toString() => 'CatalogScenario($summary)';
}
