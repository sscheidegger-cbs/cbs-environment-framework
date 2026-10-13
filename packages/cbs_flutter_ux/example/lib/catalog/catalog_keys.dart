import 'package:flutter/widgets.dart';

import 'catalog_scenario.dart';

/// Stable keys of the catalog, shared with widget tests.
abstract final class CatalogKeys {
  /// Vertical scrollable of the whole page.
  static const Key pageScroll = ValueKey('catalog-page-scroll');

  /// Text summarizing the active scenario.
  static const Key scenarioSummary = ValueKey('catalog-scenario-summary');

  /// Text describing the active design.
  static const Key designDescription = ValueKey('catalog-design-description');

  /// Horizontal scrollable wrapping the simulated viewport.
  static const Key previewScroll = ValueKey('catalog-preview-scroll');

  /// Decorative frame drawn around the simulated viewport.
  static const Key previewFrame = ValueKey('catalog-preview-frame');

  /// Box whose width is the simulated viewport width.
  static const Key previewViewport = ValueKey('catalog-preview-viewport');

  /// Content area under the simulated `MediaQuery`.
  static const Key previewContent = ValueKey('catalog-preview-content');

  /// Selection control groups.
  static const Key designControl = ValueKey('catalog-control-design');
  static const Key appearanceControl = ValueKey('catalog-control-appearance');
  static const Key widthControl = ValueKey('catalog-control-width');
  static const Key textScaleControl = ValueKey('catalog-control-text-scale');

  /// Options of the selection controls.
  static Key designOption(CatalogDesign value) =>
      ValueKey('catalog-design-${value.name}');

  static Key appearanceOption(CatalogAppearance value) =>
      ValueKey('catalog-appearance-${value.name}');

  static Key widthOption(CatalogWidth value) =>
      ValueKey('catalog-width-${value.name}');

  static Key textScaleOption(CatalogTextScale value) =>
      ValueKey('catalog-text-scale-${value.name}');

  /// Section of the catalog identified by [id].
  static Key section(String id) => ValueKey('catalog-section-$id');
}
