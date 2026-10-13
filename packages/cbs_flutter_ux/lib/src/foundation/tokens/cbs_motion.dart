import 'package:flutter/material.dart';

/// Shared motion tokens for CBS Flutter applications.
///
/// Durations and easing curves reuse the Material 3 motion system
/// provided by Flutter.
abstract final class CbsMotion {
  /// Short transitions, such as state changes on small elements.
  static const Duration short = Durations.short2;

  /// Medium transitions, such as expanding or collapsing content.
  static const Duration medium = Durations.medium2;

  /// Long transitions, such as large or full-screen changes.
  static const Duration long = Durations.long2;

  /// Default easing for transitions that stay on screen.
  static const Curve standard = Easing.standard;

  /// Easing for elements entering the screen.
  static const Curve enter = Easing.emphasizedDecelerate;

  /// Easing for elements leaving the screen.
  static const Curve exit = Easing.emphasizedAccelerate;
}
