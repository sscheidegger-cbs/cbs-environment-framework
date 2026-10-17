import 'package:flutter/material.dart';

import '../../foundation/tokens/cbs_spacing.dart';
import 'cbs_section_heading.dart';

/// Generic section of content: a heading, an optional subtitle and an
/// optional action, followed by the content provided by the consuming
/// application.
///
/// Presentation only: the application builds the [title] and [subtitle] in
/// its current language, and the [action] and the [child] it wants to show.
/// The section knows no business model, holds no state and performs no
/// navigation, network call or loading. It is composed from native Flutter
/// primitives ([Column], [Row], [Expanded], [SizedBox], [Text]) and from
/// [CbsSectionHeading], which draws the [title]; the section does not
/// restyle it.
///
/// Order, from top to bottom (and in the order read by assistive
/// technologies):
/// 1. the [title], a [CbsSectionHeading], exposed as a heading;
/// 2. the [subtitle], when it is not null or empty, under the title;
/// 3. the [child].
///
/// The [action], when provided, is placed on the same row as the title and
/// the subtitle, at the end edge, vertically centered on them. In the
/// reading order it comes after the title and the subtitle and before the
/// [child].
///
/// Spacing (CBS spacing tokens): [CbsSpacing.xs] between the title and the
/// subtitle, [CbsSpacing.md] between the texts and the [action], and
/// [CbsSpacing.sm] between the header (title, subtitle and action) and the
/// [child]. The section adds no external margin and no inner padding; the
/// consumer places it and spaces it from its neighbours.
///
/// Subtitle: `bodyMedium` of the active theme, in the `onSurfaceVariant`
/// color of its color scheme, so it follows Essentials and Branded
/// typography, light and dark appearance, and the text scale of the device.
/// It wraps when the width is bounded.
///
/// Layout: the section takes the maximum width allowed by its parent, which
/// must provide a bounded width, and is as tall as its content. The texts
/// take the width left by the [action], which keeps its own natural width:
/// the [action] should therefore be compact (a button, an icon button),
/// not a wide widget. The section never scrolls by itself; when the content
/// can be taller than the room available, place it in a scroll view. The
/// [child] receives the full width of the section, which is what
/// width-filling widgets such as `CbsContentCard`, `CbsMediaFrame` and
/// `CbsAdaptiveCollection` expect.
///
/// Interaction and accessibility: the section adds no gesture detector, no
/// focus and no semantics of its own. The [action] and the [child] keep
/// their own interactions, focus, semantics and state.
class CbsContentSection extends StatelessWidget {
  const CbsContentSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });

  /// Title of the section, provided by the consuming application and drawn
  /// by a [CbsSectionHeading].
  final String title;

  /// Optional text under the [title], provided by the consuming
  /// application. Nothing is shown when it is null or empty.
  final String? subtitle;

  /// Content of the section, built by the consuming application.
  final Widget child;

  /// Optional action placed at the end of the header, built by the
  /// consuming application.
  final Widget? action;

  /// Gap between the title and the subtitle.
  static const double _subtitleGap = CbsSpacing.xs;

  /// Gap between the texts of the header and the action.
  static const double _actionGap = CbsSpacing.md;

  /// Gap between the header and the [child].
  static const double _contentGap = CbsSpacing.sm;

  @override
  Widget build(BuildContext context) {
    final actionSlot = action;
    final Widget texts = _texts(context);

    final Widget header = actionSlot == null
        ? texts
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: texts),
              const SizedBox(width: _actionGap),
              actionSlot,
            ],
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: _contentGap),
        child,
      ],
    );
  }

  /// Title and optional subtitle, stacked.
  Widget _texts(BuildContext context) {
    final subtitleText = subtitle;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CbsSectionHeading(title: title),
        if (subtitleText != null && subtitleText.isNotEmpty) ...[
          const SizedBox(height: _subtitleGap),
          Text(
            subtitleText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
