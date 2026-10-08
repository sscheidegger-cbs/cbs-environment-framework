# CBS Flutter UX/UI — Showcase

## Purpose

Independent visual qualification application for the reusable
`cbs_flutter_ux` package.

The showcase belongs to `cbs-environment-framework`, not AMH-USR.

## Architecture

- Framework: `packages/cbs_flutter_ux/`
- Showcase: `packages/cbs_flutter_ux/example/`
- Dependency: `cbs_flutter_ux` via `path: ../`
- Application: `lib/main.dart`
- Widget tests: `test/showcase_test.dart`

## Demonstrated features

**Themes**
- Essentials: indigo Material 3.
- Branded: teal Material 3 with customized button radius.
- Interactive theme switching.

**Components**
- Active and disabled buttons.
- Indeterminate loading indicator.
- Determinate loading indicator at 60%.
- Information, success, warning and error feedback messages.

Loading indicators provide accessibility labels and visible captions.

## Requirements

Flutter 3.47.6 and a supported Flutter device.

## Run

From the `example/` directory:

    flutter pub get
    flutter devices
    flutter run -d emulator-5554 -t lib/main.dart

Replace the device identifier if necessary.

## Qualification

From the `example/` directory:

    flutter analyze
    flutter test

## Scope boundaries

- No AMH-USR business functionality.
- No IAM or backend integration.
- No modification of the AMH-USR application.
- No proof of independent-repository portability.

Portability to another consuming repository is qualified in E07b-F.

## Evolution

Extend this showcase alongside reusable CBS UX/UI components.
Keep business-specific workflows in consuming applications.
