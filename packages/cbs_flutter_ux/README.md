# CBS Flutter UX/UI

Reusable Flutter UX/UI foundations for CBS applications.

Package: cbs_flutter_ux
Version: 0.1.0
Status: Initial reusable framework.

## 1. Purpose

CBS Flutter UX/UI provides reusable technical foundations
for Flutter applications.

The package is maintained in cbs-environment-framework.

It is independent from application business logic,
authentication workflows and backend APIs.

## 2. Current scope

The package provides:

- Material 3 themes.
- Essentials and Branded configurations.
- Shared spacing tokens.
- Shared corner-radius tokens.
- Shared elevation, icon size, motion and breakpoint tokens.
- Typed theme configuration.
- Typed feedback style.
- Reusable UI primitives.
- Presentation-state patterns (state panel, retry message).
- Visual parts (section heading).
- Automated Flutter tests.

The package does not provide application-specific
screens, navigation or business workflows.

## 3. Public API

Public entry point:

    import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';

Available foundations:

- CbsFlutterUx
- CbsTheme
- CbsThemeConfig
- CbsSpacing
- CbsRadius
- CbsElevation
- CbsIconSize
- CbsMotion
- CbsBreakpoints
- CbsFeedbackStyle

Available primitives:

- CbsButton
- CbsLoadingIndicator
- CbsFeedbackMessage

Available presentation-state patterns:

- CbsStatePanel
- CbsRetryMessage

Available visual parts:

- CbsSectionHeading

Consumers must use the public entry point
rather than importing internal files from lib/src.

## Installation in a consuming project

The package is currently distributed through a local
Flutter path dependency.

Example repository layout:

    projects/
      amh-usr/
      cbs-environment-framework/
        packages/
          cbs_flutter_ux/

Add the dependency to the consuming application's
pubspec.yaml:

    dependencies:
      flutter:
        sdk: flutter

      cbs_flutter_ux:
        path: ../cbs-environment-framework/packages/cbs_flutter_ux

Run Flutter dependency resolution from the
consuming application's directory:

    flutter pub get

Use the CBS-managed Flutter toolchain when
working in a qualified CBS environment.

The relative path depends on the location
of the consuming application.

The package is not currently published to pub.dev.

## 4. Essentials

Essentials provides standard Material 3 configuration.

Example:

    MaterialApp(
      theme: CbsTheme.essentials(),
      home: const Scaffold(),
    );

Dark mode is available through the brightness parameter.

## 5. Branded

Branded provides configurable visual identity.

Example:

    MaterialApp(
      theme: CbsTheme.branded(
        primaryColor: Colors.green,
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontFamily: 'BrandFont',
            fontSize: 36,
          ),
        ),
        buttonRadius: CbsRadius.lg,
      ),
      home: const Scaffold(),
    );

Configuration parameters:

- primaryColor: required Material 3 color seed.
- brightness: optional light or dark appearance.
- textTheme: optional application typography.
- buttonRadius: optional FilledButton corner radius.

Without optional configuration, Material 3 defaults
are preserved.

Custom fonts must be provided by the consuming application.

## 6. Design tokens

Spacing tokens are available through CbsSpacing.

Example:

    const SizedBox(height: CbsSpacing.md);

Corner-radius tokens are available through CbsRadius.

Example:

    BorderRadius.circular(CbsRadius.md);

Elevation tokens are available through CbsElevation
and follow the Material 3 elevation levels.

Icon size tokens are available through CbsIconSize.

Motion tokens are available through CbsMotion.
Durations and easing curves reuse the Material 3
motion system.

Example:

    AnimatedContainer(
      duration: CbsMotion.medium,
      curve: CbsMotion.standard,
    );

Width breakpoints are available through CbsBreakpoints
and follow the Material 3 window size classes.

Example:

    final sizeClass = CbsBreakpoints.classify(
      MediaQuery.sizeOf(context).width,
    );

### 6.1 Typed theme configuration

CbsThemeConfig describes a theme with typed values.
CbsTheme.fromConfig builds the corresponding Material 3 theme.

Example:

    MaterialApp(
      theme: CbsTheme.fromConfig(
        const CbsThemeConfig(
          seedColor: Colors.green,
          buttonRadius: CbsRadius.lg,
        ),
      ),
      home: const Scaffold(),
    );

CbsTheme.essentials and CbsTheme.branded keep their
signatures and produce the same themes as before.

### 6.2 Feedback style

CbsFeedbackStyle.resolve returns the background color,
foreground color and icon of a CbsFeedbackType
for a given Material 3 color scheme.

Example:

    final style = CbsFeedbackStyle.resolve(
      Theme.of(context).colorScheme,
      CbsFeedbackType.success,
    );

## 7. UI primitives

### 7.1 CbsButton

CbsButton provides a reusable primary action
based on Flutter FilledButton.

Example:

    CbsButton(
      label: 'Continue',
      onPressed: () {},
    );

Parameters:

- label: required visible button text.
- onPressed: required nullable callback.
- key: optional Flutter widget key.

Setting onPressed to null disables the button.

Visual styling is inherited from the active
Material theme.

### 7.2 CbsLoadingIndicator

CbsLoadingIndicator provides a reusable
circular progress indicator.

Indeterminate example:

    const CbsLoadingIndicator(
      semanticLabel: 'Loading content',
    );

Determinate example:

    const CbsLoadingIndicator(
      value: 0.5,
      semanticLabel: 'Loading content',
    );

Parameters:

- value: optional progress value between 0.0 and 1.0.
- semanticLabel: optional accessible description.
- key: optional Flutter widget key.

A null value produces indeterminate progress.

Visual styling is inherited from the active
Material theme.

### 7.3 CbsFeedbackMessage

CbsFeedbackMessage displays a message using
semantic colors from the active Material theme.

Example:

    const CbsFeedbackMessage(
      message: 'Changes saved',
      type: CbsFeedbackType.success,
      semanticLabel: 'Success: Changes saved',
    );

Parameters:

- message: required visible message.
- type: optional severity, defaulting to info.
- semanticLabel: optional accessible description.
- expand: optional, defaulting to false.
- key: optional Flutter widget key.

By default the message is as wide as its content.
With expand set to true it takes the maximum width
allowed by its parent, which must provide a bounded width:

    const CbsFeedbackMessage(
      message: 'Unable to load',
      type: CbsFeedbackType.error,
      expand: true,
    );

Supported feedback types:

- CbsFeedbackType.info
- CbsFeedbackType.success
- CbsFeedbackType.warning
- CbsFeedbackType.error

Each type selects an icon and corresponding
Material color scheme values.

When semanticLabel is provided, it replaces
the semantics of the visual child content.

The consuming application is responsible
for providing localized message text
and accessible descriptions.

## 8. Presentation-state patterns

These patterns are presentation only. The consuming
application keeps its controller, its state model,
its data loading, the meaning of its actions and every
localized text. They add no state management and no
orchestration of loading, empty, error or ready states.

Both widgets take the maximum width allowed by their
parent, which must provide a bounded width.

### 8.1 CbsStatePanel

CbsStatePanel is a full-width surface that frames the
content of a presentation state.

Example:

    CbsStatePanel(
      child: Text(
        'Nothing to show yet.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );

Parameters:

- child: required content.
- key: optional Flutter widget key.

Rendering: full width, 24 logical pixels of padding
(CbsSpacing.lg), 16 logical pixels of corner radius
(CbsRadius.lg) and the surfaceContainerHighest color of the
active Material 3 color scheme. It adds no semantics.

The surface is a DecoratedBox rather than Card.filled:
Card.filled adds a 4 pixel margin, a 12 pixel radius, a
Material layer and a semantic container, and reads
its color, elevation, clipping and margin from the
application's CardTheme. CbsStatePanel is independent
from CardTheme.

### 8.2 CbsRetryMessage

CbsRetryMessage shows an error message followed by a retry
button, aligned to the start and separated by 8 logical
pixels (CbsSpacing.sm). It composes CbsFeedbackMessage
(type error, expand true) and CbsButton.

Example:

    CbsRetryMessage(
      message: 'Unable to load the content.',
      retryLabel: 'Retry',
      onRetry: controller.load,
    );

Parameters:

- message: required visible error message.
- retryLabel: required visible button label.
- onRetry: required callback of the retry button.
- semanticLabel: optional accessible description of the
  error message. It does not change the button semantics.
- key: optional Flutter widget key.

The framework contains no text: message, retryLabel and
semanticLabel are provided by the consuming application in
its current language. A key set on CbsRetryMessage identifies
the whole widget, not the inner button.

## 9. Visual parts

### 9.1 CbsSectionHeading

CbsSectionHeading displays the title of a content section
and exposes it to assistive technologies as a heading
(Semantics with header set to true).

Example:

    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CbsSectionHeading(title: sectionTitle),
        const SizedBox(height: CbsSpacing.sm),
        content,
      ],
    );

Parameters:

- title: required visible title.
- key: optional Flutter widget key.

Rendering: a single Text using the titleMedium style of the
active theme with a w700 weight. It follows Essentials and
Branded typography, light and dark appearance, and the text
scale of the device. Under a loose width constraint the text is as
wide as its content; under a tight constraint (for example
CrossAxisAlignment.stretch) it takes the constrained width.
It wraps when the parent width is bounded.

The heading has no other parameter: no style override, no
description and no action. It adds no spacing of its own:
the consuming application places it and separates it from the
content that follows, for example with CbsSpacing.sm as above.

The framework contains no text: title is provided by the
consuming application in its current language.

## 10. Accessibility

Automated tests cover initial accessibility contracts,
including semantic labels, disabled button state
and keyboard activation, and the semantics of
CbsStatePanel, CbsRetryMessage and the header semantics
of CbsSectionHeading.

Manual TalkBack and VoiceOver validation remains
a separate qualification activity.

## 11. Qualification

The current CBS Flutter toolchain is version 3.47.6.

From the package directory, run:

    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter analyze

    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter test

## 12. Reuse principles

The package must remain independent from AMH-USR
and other consuming applications.

New components should:

1. Reuse Flutter and CBS foundations.
2. Expose a documented public contract.
3. Support theme-driven configuration.
4. Include automated tests.
5. Preserve compatibility.
6. Be qualified before publication.

## 13. Current limitations

Version 0.1.0 does not yet provide:

- A complete component catalog.
- A visual component showcase.
- Signature-specific configurations.
- Automated cross-device visual qualification.
- Distribution through pub.dev.

These capabilities may be introduced progressively.
