import 'package:flutter/material.dart';

import '../../foundation/tokens/cbs_radius.dart';

/// Frame that gives a media provided by the consuming application a fixed
/// aspect ratio and rounded corners.
///
/// Presentation only: the application builds the [child] (an image, a
/// video preview, a placeholder, ...). The frame does not choose how the
/// [child] fits the frame (no `BoxFit`), loads nothing, caches nothing,
/// holds no state and knows no business model. The consumer places and
/// spaces it.
///
/// Layout: the frame is as wide as the width allowed by its parent, which
/// must provide a bounded width (or a bounded height, from which the width
/// is deduced). Its height is the width divided by [aspectRatio]. The
/// [child] receives tight constraints equal to the frame size and owns the
/// way it fills them.
///
/// Shape: the [child] is clipped with [ClipRRect]. Without [borderRadius]
/// the corners use [CbsRadius.md]; pass [BorderRadius.zero] for square
/// corners, for instance when a parent already clips the media.
///
/// Accessibility: the semantics of the [child] are preserved. When
/// [semanticLabel] is provided, it is added to them instead of replacing
/// them; without it the frame adds no semantics of its own.
class CbsMediaFrame extends StatelessWidget {
  const CbsMediaFrame({
    required this.child,
    super.key,
    this.aspectRatio = 16 / 9,
    this.borderRadius,
    this.semanticLabel,
  }) : assert(
         aspectRatio > 0 && aspectRatio < double.infinity,
         'aspectRatio must be positive and finite.',
       );

  /// Media built by the consuming application.
  final Widget child;

  /// Width divided by height of the frame. It must be positive and finite.
  /// Defaults to 16 / 9.
  final double aspectRatio;

  /// Corner radius used to clip the [child]. Defaults to a circular radius
  /// of [CbsRadius.md] when null.
  final BorderRadiusGeometry? borderRadius;

  /// Optional description of the media for assistive technologies. It is
  /// added to the semantics of the [child] and does not hide them.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget frame = AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(CbsRadius.md),
        child: child,
      ),
    );

    final label = semanticLabel;
    return label == null ? frame : Semantics(label: label, child: frame);
  }
}
