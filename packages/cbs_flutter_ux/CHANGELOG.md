# Changelog

All notable changes to the CBS Flutter UX/UI package
are documented in this file.

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
