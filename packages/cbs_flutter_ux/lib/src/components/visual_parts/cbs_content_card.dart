import 'package:flutter/material.dart';

import '../../foundation/tokens/cbs_spacing.dart';

/// Arrangement of the slots of a [CbsContentCard].
enum CbsContentCardLayout {
  /// The media is stacked above the content and the action.
  vertical,

  /// The media is placed beside the content and the action.
  horizontal,
}

/// Generic card that frames content provided by the consuming application.
///
/// Presentation only: the application builds the [content] (title,
/// subtitle, metadata, ...) in its current language, and optionally the
/// [media] and the [action]. The card knows no business model, holds no
/// state and performs no navigation or network call.
///
/// Slots:
/// * [media] (optional): placed at the top edge of the card in the
///   [CbsContentCardLayout.vertical] layout, at its start edge in the
///   [CbsContentCardLayout.horizontal] layout, and clipped by the card
///   shape. In the vertical layout it is as wide as the card and owns its
///   height. In the horizontal layout it takes one third of the card width
///   and owns its height (for instance with an [AspectRatio]).
/// * [content] (required): padded with [CbsSpacing.md]; it takes the
///   remaining width.
/// * [action] (optional): placed under the content, aligned to the end, and
///   independently activatable from the card.
///
/// Surface: the card is a Material [Card] and follows the `cardTheme`, the
/// color scheme and the shape of the active theme (Essentials or Branded,
/// light or dark). It adds no external margin; the consumer places it and
/// spaces it.
///
/// Interaction: without [onTap] the card is not interactive. With [onTap]
/// the whole card is an [InkWell]: it shows the native ripple, hover and
/// focus feedback, can be focused by keyboard and exposes a tap action to
/// assistive technologies.
///
/// Accessibility: the visible texts of the slots stay available to
/// assistive technologies. When [semanticLabel] is provided, it is added
/// to them instead of replacing them. The text follows the text scale of
/// the device.
///
/// The card takes the maximum width allowed by its parent, which must
/// provide a bounded width.
class CbsContentCard extends StatelessWidget {
  const CbsContentCard({
    required this.content,
    super.key,
    this.media,
    this.action,
    this.layout = CbsContentCardLayout.vertical,
    this.onTap,
    this.semanticLabel,
  });

  /// Main content of the card, built by the consuming application.
  final Widget content;

  /// Optional media, built by the consuming application.
  final Widget? media;

  /// Optional action, built by the consuming application.
  final Widget? action;

  /// Arrangement of the slots. Defaults to
  /// [CbsContentCardLayout.vertical].
  final CbsContentCardLayout layout;

  /// Called when the card is activated. The card is not interactive when it
  /// is null.
  final VoidCallback? onTap;

  /// Optional description added to the texts of the slots for assistive
  /// technologies. It does not hide them.
  final String? semanticLabel;

  /// Share of the width of the horizontal layout given to the media.
  static const int _mediaFlex = 1;

  /// Share of the width of the horizontal layout given to the content and
  /// the action.
  static const int _bodyFlex = 2;

  @override
  Widget build(BuildContext context) {
    final mediaSlot = media;
    final Widget arrangement = switch (layout) {
      CbsContentCardLayout.vertical => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [?mediaSlot, _body()],
      ),
      CbsContentCardLayout.horizontal => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (mediaSlot != null) Expanded(flex: _mediaFlex, child: mediaSlot),
          Expanded(flex: _bodyFlex, child: _body()),
        ],
      ),
    };

    final label = semanticLabel;
    final Widget described = label == null
        ? arrangement
        : Semantics(label: label, child: arrangement);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? described
          : InkWell(onTap: onTap, child: described),
    );
  }

  Widget _body() {
    final actionSlot = action;
    return Padding(
      padding: const EdgeInsets.all(CbsSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          if (actionSlot != null) ...[
            const SizedBox(height: CbsSpacing.sm),
            Align(alignment: AlignmentDirectional.centerEnd, child: actionSlot),
          ],
        ],
      ),
    );
  }
}
