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
- Reusable UI primitives.
- Automated Flutter tests.

The package does not provide application-specific
screens, navigation or business workflows.

## 3. Public API

Public entry point:

    import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';

Available foundations:

- CbsFlutterUx
- CbsTheme
- CbsSpacing
- CbsRadius

Available primitives:

- CbsButton
- CbsLoadingIndicator
- CbsFeedbackMessage

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
- key: optional Flutter widget key.

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

## 8. Accessibility

Automated tests cover initial accessibility contracts,
including semantic labels, disabled button state
and keyboard activation.

Manual TalkBack and VoiceOver validation remains
a separate qualification activity.

## 9. Qualification

The current CBS Flutter toolchain is version 3.47.6.

From the package directory, run:

    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter analyze

    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter test

## 10. Reuse principles

The package must remain independent from AMH-USR
and other consuming applications.

New components should:

1. Reuse Flutter and CBS foundations.
2. Expose a documented public contract.
3. Support theme-driven configuration.
4. Include automated tests.
5. Preserve compatibility.
6. Be qualified before publication.

## 11. Current limitations

Version 0.1.0 does not yet provide:

- A complete component catalog.
- A visual component showcase.
- Signature-specific configurations.
- Automated cross-device visual qualification.
- Distribution through pub.dev.

These capabilities may be introduced progressively.
