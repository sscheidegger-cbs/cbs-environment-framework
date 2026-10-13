/// Material 3 window size classes used for responsive layouts.
enum CbsWindowSizeClass { compact, medium, expanded, large, extraLarge }

/// Shared width breakpoints for CBS Flutter applications.
///
/// Values follow the Material 3 window size classes and are
/// expressed in logical pixels. Each breakpoint is the inclusive
/// lower bound of its size class.
abstract final class CbsBreakpoints {
  static const double medium = 600;
  static const double expanded = 840;
  static const double large = 1200;
  static const double extraLarge = 1600;

  /// Returns the window size class matching [width].
  static CbsWindowSizeClass classify(double width) {
    if (width >= extraLarge) return CbsWindowSizeClass.extraLarge;
    if (width >= large) return CbsWindowSizeClass.large;
    if (width >= expanded) return CbsWindowSizeClass.expanded;
    if (width >= medium) return CbsWindowSizeClass.medium;
    return CbsWindowSizeClass.compact;
  }
}
