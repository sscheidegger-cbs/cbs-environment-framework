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
- A visual catalog application (see section 11.2),
  located in example/.

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

The visual catalog tests (section 11.2) additionally check,
on the catalog demonstrations, the semantics of the disabled
button (no tap action), the semantics of the retry button
(enabled, with a tap action), the header semantics of the
section headings and the semantic labels of the loading and
feedback demonstrations.

These are headless widget tests. Manual TalkBack and
VoiceOver validation remains a separate qualification
activity and has not been performed.

## 11. Qualification

The current CBS Flutter toolchain is version 3.47.6.

### 11.1 Package

From the package directory (packages/cbs_flutter_ux), run:

    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter analyze

    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter test

### 11.2 Visual catalog

The package ships a visual catalog: a standalone Flutter
application located in packages/cbs_flutter_ux/example/.
It belongs to cbs-environment-framework and has no dependency
on AMH-USR, on authentication or on any backend service.
It depends only on Flutter and on this package
(path dependency ../).

Role: the catalog displays every public CBS widget in the
same place and lets a developer or a reviewer check how it
renders under several configurations, independently of any
consuming application. It is a qualification aid for the
Visual Parts and presentation-state patterns. It is not a
distribution channel: the catalog code is not part of the
public API of cbs_flutter_ux.

Components shown (the six public widgets):

- CbsButton
- CbsLoadingIndicator
- CbsFeedbackMessage
- CbsStatePanel
- CbsRetryMessage
- CbsSectionHeading

CbsTheme, CbsThemeConfig and the tokens are exercised
through the theme applied to these widgets; the catalog has
no dedicated token or palette visualization.

Application states: a seventh section composes the four
presentation states Loading, Empty, Error and Ready from
the widgets above. These compositions are built by the
example, as a consumer would build them: CbsStatePanel,
CbsLoadingIndicator, CbsSectionHeading, CbsRetryMessage and
CbsButton, with plain Flutter widgets for the remaining
text. The package provides no state controller, no state
model and no widget orchestrating these four states.

Scenario controls (located above the preview, outside the
simulated viewport):

- Design: Essentials (indigo) or Branded (teal,
  buttonRadius CbsRadius.lg).
- Appearance: Light or Dark.
- Width: 320, 600, 840 or 1280 logical pixels.
- Text scale: x1 or x2.

The four controls combine into 2 x 2 x 4 x 2 = 32 scenarios.
The catalog starts on Essentials, Light, 320 px, text x1.

Commands, from packages/cbs_flutter_ux/example:

    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter pub get

    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter analyze

    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter test

    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter devices

    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter run -d <device-id> -t lib/main.dart

The example only contains an android/ platform. A running
Android device or emulator is required for flutter run;
none is assumed. Architecture, how to add a section and the
detailed limits are described in example/README.md.

Automated qualification of the catalog (headless widget
tests, no device): the six components and the four states
are present; the 32 scenarios are built without exception
and without overflow, including 320 px with text x2; the
simulated MediaQuery width and the layout constraints agree;
the button and the retry interactions work in every
scenario; the theme received by the displayed widgets is the
selected CBS theme.

Limits of this qualification:

- MediaQuery is simulated partially (M3). Only size
  (width, with the real device height) and textScaler are
  replaced. padding and viewInsets come from the real device
  and are not simulated. orientation is derived by Flutter
  from the simulated size and cannot be set independently.


- The text scale is absolute (M5). x1 and x2 are simulation
  values that replace the text scaler: they do not combine
  with, and do not reflect, the system font size configured
  on the device.
- Tests are headless widget tests: they are not proof of a
  real Android rendering.
- No Golden test exists.
- No TalkBack or VoiceOver validation has been performed.
- Only the Android platform is generated for the example;
  Linux and Web are not generated.
- No Android runtime run of the catalog is recorded by this
  documentation.

## 12. Reuse principles

Independence from AMH-USR was verified by inspection of imports and dependencies; no dedicated automated non-coupling test exists.

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

- A complete set of components: CbsCard is deferred until
  after E09; a media part, semantic iconography, collection
  components and a description or action on CbsSectionHeading
  are deferred.
- Signature-specific configurations.
- Cross-device visual qualification.
- Distribution through pub.dev.

A visual catalog of the six public widgets and of the four
presentation states is available in example/ (section 11.2).

Status of the visual qualification:

- Covered by D03b-C: standalone catalog, six components,
  four application states, 32 scenarios (design, appearance,
  width, text scale), headless widget tests, no dependency
  on AMH-USR services.
- Not covered: Android rendering proof, Golden tests,
  TalkBack and VoiceOver validation, independent simulation
  of padding, viewInsets and orientation, system text scale
  of the device, Linux and Web platforms.
- Deferred to D03c: Golden tests, TalkBack and VoiceOver on
  devices, multi-device runtime. An Android run of the catalog
  is to be qualified separately.
- Deferred until after E09: CbsCard.

These capabilities may be introduced progressively.
No deferred capability is considered available
until its implementation and qualification are complete.
