import 'package:flutter/widgets.dart';

import 'catalog_scenario.dart';

/// Stable keys of the catalog, shared with widget tests.
abstract final class CatalogKeys {
  /// Vertical scrollable of the whole page.
  static const Key pageScroll = ValueKey('catalog-page-scroll');

  /// Text summarizing the active scenario.
  static const Key scenarioSummary = ValueKey('catalog-scenario-summary');

  /// Text showing how the device and the preview render a reference font
  /// size (D03c-A.2 / F3b).
  static const Key textScaleReadout = ValueKey('catalog-text-scale-readout');

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

  /// Labelled demonstration (a block of a section) identified by [id].
  static Key demo(String id) => ValueKey('catalog-demo-$id');

  /// Text displaying the interaction counter of the demonstration [id].
  static Key counter(String id) => ValueKey('catalog-counter-$id');

  /// `CbsRetryMessage` of the retry demonstration [id].
  static Key retryMessage(String id) => ValueKey('catalog-retry-message-$id');

  /// Dynamic feedback demonstration (D03c-A.2 / C4).
  static const Key dynamicFeedbackShow = ValueKey('catalog-feedback-show');
  static const Key dynamicFeedbackHide = ValueKey('catalog-feedback-hide');
  static const Key dynamicFeedbackMessage = ValueKey(
    'catalog-feedback-message',
  );

  /// Loading indicator without `semanticLabel` (D03c-A.2 / D3).
  static const Key unlabeledLoading = ValueKey('catalog-loading-unlabeled');

  /// Dynamic progress demonstration (D03c-A.2 / D4).
  static const Key progressIndicator = ValueKey('catalog-progress-indicator');
  static const Key progressReadout = ValueKey('catalog-progress-readout');

  /// Button setting the progress to [percent] %.
  static Key progressOption(int percent) =>
      ValueKey('catalog-progress-option-$percent');
}
