# Changelog

All notable changes to the CBS Flutter UX/UI package
are documented in this file.

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
