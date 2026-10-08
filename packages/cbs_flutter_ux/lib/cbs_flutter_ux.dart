/// Reusable Flutter UX/UI foundations for CBS applications.
///
/// Independent from application business logic and backend APIs.
library;

/// Public identity of the CBS Flutter UX/UI framework.
///
/// This initial contract proves that consuming applications can
/// reference the framework without importing internal implementation.
abstract final class CbsFlutterUx {
  static const String packageName = 'cbs_flutter_ux';
}
