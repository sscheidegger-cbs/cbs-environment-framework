# Changelog

All notable changes to the CBS Flutter UX/UI package
are documented in this file.

## Unreleased - D03b-C visual catalog

### Added

- D03b-C.2 infrastructure (example/ only): CatalogScenario and its
  four selection dimensions, CatalogControls, CatalogPreviewFrame
  (simulated viewport with a tight width and a MediaQuery carrying
  the simulated size and text scaler), CatalogEntry and an explicit
  list of sections, CatalogKeys. Controls for Essentials or
  Branded, Light or Dark, widths 320, 600, 840 and 1280 px, and text
  scale x1 or x2: 32 scenarios.
- D03b-C.3 content (example/ only): sections for the six public
  widgets (CbsButton, CbsLoadingIndicator, CbsFeedbackMessage,
  CbsStatePanel, CbsRetryMessage, CbsSectionHeading) with
  representative variants, and a section composing the four
  application states Loading, Empty, Error and Ready from CBS
  widgets. Retry and button demonstrations are interactive and show
  a visible counter.
- D03b-C.2 and C.3 automated tests (example/test): scenario model
  and controls, simulated viewport and MediaQuery / constraints
  consistency, effective theme received by the displayed widgets,
  presence of the six components and of the four states, button and
  retry interactions, and a matrix over the 32 scenarios checking
  for exceptions and overflow, including 320 px with text x2. The
  test of the demonstration that existed before the catalog is
  preserved and adapted to stable keys.

### Documentation

- D03b-C.4: README of the package updated (catalog description,
  commands, qualification limits). The section on current
  limitations no longer states that a visual showcase is missing.
- D03b-C.4: README of example/ rewritten (purpose, architecture,
  components, four states, controls, commands with the CBS Flutter
  3.47.6 toolchain, how to add a section, known limits).
- Limits documented: MediaQuery simulated partially (size and
  textScaler only); absolute text scale (x1 and x2 do not reflect the
  device system setting); headless widget tests; no Android runtime
  proof; no Golden test; no TalkBack or VoiceOver validation; no
  Linux or Web platform; CbsCard deferred until after E09.

### Compatibility

- No change in lib/ and no public symbol added, removed or renamed.
- No pubspec.yaml change and no dependency added.
- The catalog has no dependency on AMH-USR or on any backend service.

### Limitations

- Visual qualification (Golden, TalkBack, VoiceOver, Android runtime,
  multi-device runtime) is not covered by this change. Golden and
  assistive-technology validation on devices are planned for D03c;
  an Android run of the catalog is to be qualified separately.

## Unreleased - D03b-B Lot 2 section heading

### Added

- CbsSectionHeading: presentation-only section title. A single
  Text in the titleMedium style of the active theme with a w700
  weight, wrapped in Semantics(header: true). Title only: no
  style parameter, description, action or built-in spacing.
- Automated tests covering the displayed title, header semantics,
  Essentials and Branded styles, light and dark themes, width 320
  with text scale 2, long titles without overflow, absence of
  external spacing and equivalence with a reproduction of the CURRENT
  AMH-USR Home section headings (Featured, Categories, Nearby, Upcoming).

### Compatibility

- No public symbol removed or renamed.
- No existing behavior changed.
- No dependency added.

### Limitations

- Visual qualification (Golden, TalkBack, VoiceOver, runtime) is
  not covered by this change.
- The 8 pixel gap that follows the heading in Home remains in the
  consumer layout and is not part of CbsSectionHeading.

## Unreleased - D03b-B Lot 1 presentation states

### Added

- CbsFeedbackMessage.expand: optional, defaults to false. When
  true, the message takes the maximum width allowed by its parent.
- CbsStatePanel: presentation-only full-width surface for the
  content of a presentation state (padding 24, radius 16,
  surfaceContainerHighest). Built on DecoratedBox, independent
  from CardTheme.
- CbsRetryMessage: error CbsFeedbackMessage followed by a
  CbsButton, with an 8 pixel vertical gap. All texts are provided
  by the consumer.
- Automated tests for the new widgets, covering Essentials and
  Branded, light and dark themes, widths 320 to 1280, text scales
  1 and 2, semantics and interactions.

### Compatibility

- No public symbol removed or renamed.
- CbsFeedbackMessage behavior is unchanged when expand is omitted.
- No dependency added.

### Limitations

- Visual qualification (Golden, TalkBack, VoiceOver, runtime) is
  not covered by this change.
- A key set on CbsRetryMessage identifies the whole widget, not
  the inner retry button.

## Unreleased - D03b-A graphic foundations

### Added

- CbsThemeConfig typed theme configuration.
- CbsTheme.fromConfig factory.
- CbsFeedbackStyle typed feedback style resolved from
  the Material 3 color scheme.
- CbsElevation tokens (Material 3 levels).
- CbsIconSize tokens.
- CbsMotion tokens (Material 3 durations and easing).
- CbsBreakpoints tokens and CbsWindowSizeClass
  (Material 3 window size classes).
- Automated tests for the new foundations and for
  public API backward compatibility.

### Changed

- CbsTheme.essentials and CbsTheme.branded now delegate
  to CbsTheme.fromConfig. Signatures and resulting
  themes are unchanged.
- CbsFeedbackMessage uses CbsFeedbackStyle, CbsSpacing and
  CbsRadius. Rendered values are unchanged.
- CbsFeedbackType is declared in the foundation layer and
  remains exported from the public entry point.

### Compatibility

- No public symbol removed or renamed.
- No dependency added.

## 0.1.0 - Initial development version

### Added

- Independent reusable Flutter package.
- Public API through cbs_flutter_ux.dart.
- Essentials Material 3 theme.
- Branded Material 3 theme.
- Light and dark theme support.
- Configurable Branded primary color.
- Configurable Branded typography.
- Configurable Branded button corner radius.
- Shared spacing tokens.
- Shared corner-radius tokens.
- CbsButton primitive.
- CbsLoadingIndicator primitive.
- CbsFeedbackMessage primitive.
- Four feedback severity types.
- Optional accessible semantic labels for loading
  and feedback components.
- Automated button accessibility tests.
- Automated component and theme tests.
- Package usage documentation.

### Architecture

- Framework maintained in cbs-environment-framework.
- Independent from application business logic.
- Independent from backend APIs.
- Consumed through a Flutter path dependency.
- Components inherit Material theme configuration.

### Qualification

- Flutter analyze and automated tests.
- Accessibility checks for initial primitives.
- Compatibility checks for Essentials and Branded.
- Manual assistive-technology validation remains pending.

### Limitations

- Package is not published to pub.dev.
- Signature configuration is not implemented.
- Complete component catalog is not available.
- Cross-device visual qualification is not implemented.

## Future versions

Future capabilities will be documented when implemented
and qualified.

No future functionality is considered available
until its implementation and qualification are complete.
