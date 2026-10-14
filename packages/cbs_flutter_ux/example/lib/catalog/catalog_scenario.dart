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

/// Text scale applied to the preview.
///
/// `x1` and `x2` are simulated, absolute scales (CURRENT behaviour, kept
/// unchanged). `device` applies no scale of its own: the preview uses the
/// `TextScaler` that `MediaQuery` provides, i.e. the font size chosen in
/// the device settings.
enum CatalogTextScale {
  x1(label: 'x1', factor: 1),
  x2(label: 'x2', factor: 2),
  device(label: 'Device');

  const CatalogTextScale({required this.label, this.factor});

  final String label;

  /// Absolute linear factor, or null when the scale follows the device.
  final double? factor;

  /// Whether the preview uses the `TextScaler` provided by `MediaQuery`.
  bool get followsDevice => factor == null;

  /// The simulated scales (`x1`, `x2`) that make up the 32-scenario matrix.
  static const List<CatalogTextScale> simulated = [x1, x2];

  /// The `TextScaler` the preview must apply.
  ///
  /// [deviceTextScaler] is the scaler provided by `MediaQuery`; it is
  /// returned as is by `device`, never replaced by an absolute value.
  TextScaler resolve(TextScaler deviceTextScaler) {
    final fixed = factor;
    return fixed == null ? deviceTextScaler : TextScaler.linear(fixed);
  }
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

  /// Reference font size, in logical pixels, of [textScaleReadout].
  static const double textScaleReferenceSize = 14;

  /// Text showing how a [textScaleReferenceSize] font is rendered by the
  /// device and by the preview, so that a change of the Android font size
  /// can be observed without measuring pixels.
  String textScaleReadout(TextScaler deviceTextScaler) {
    String render(TextScaler scaler) =>
        '${textScaleReferenceSize.round()} sp → '
        '${scaler.scale(textScaleReferenceSize).toStringAsFixed(1)} sp';

    return 'Device text size: ${render(deviceTextScaler)} · '
        'Preview: ${render(textScale.resolve(deviceTextScaler))}';
  }

  /// The 32-scenario matrix: every combination of design, appearance,
  /// width and simulated text scale (`x1`, `x2`).
  ///
  /// The `device` text scale is deliberately not part of this matrix: its
  /// result depends on the device settings. See [allDeviceTextScale].
  static Iterable<CatalogScenario> get all =>
      _combinations(CatalogTextScale.simulated);

  /// The 16 scenarios using the `device` text scale.
  static Iterable<CatalogScenario> get allDeviceTextScale =>
      _combinations(const [CatalogTextScale.device]);

  static Iterable<CatalogScenario> _combinations(
    List<CatalogTextScale> textScales,
  ) sync* {
    for (final design in CatalogDesign.values) {
      for (final appearance in CatalogAppearance.values) {
        for (final width in CatalogWidth.values) {
          for (final textScale in textScales) {
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
