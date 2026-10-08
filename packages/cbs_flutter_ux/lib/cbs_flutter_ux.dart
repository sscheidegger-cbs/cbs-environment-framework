/// Reusable Flutter UX/UI foundations for CBS applications.
///
/// Independent from application business logic and backend APIs.
library;

export 'src/components/primitives/cbs_button.dart';
export 'src/components/primitives/cbs_loading_indicator.dart';
export 'src/foundation/tokens/cbs_radius.dart';
export 'src/foundation/tokens/cbs_spacing.dart';
export 'src/foundation/theme/cbs_theme.dart';

/// Public identity of the CBS Flutter UX/UI framework.
///
/// This initial contract proves that consuming applications can
/// reference the framework without importing internal implementation.
abstract final class CbsFlutterUx {
  static const String packageName = 'cbs_flutter_ux';
}
