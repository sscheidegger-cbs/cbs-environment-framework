import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_demo.dart';

/// Demonstration of [CbsMediaFrame].
///
/// The public API exposes a `child`, an `aspectRatio`, a `borderRadius`
/// and a `semanticLabel`. The frame fixes the ratio and clips the corners;
/// it loads no image and chooses no `BoxFit`. Every media drawn here (a
/// ratio caption, a custom composition, a placeholder) is built by the
/// example from the active theme, as a consumer would: it is CBS
/// demonstration data and comes from no application.
class MediaFrameSection extends StatelessWidget {
  const MediaFrameSection({super.key});

  /// Caption drawn inside `media-16-9`.
  static const String ratioWideCaption = '16:9';

  /// Caption drawn inside `media-1-1`.
  static const String ratioSquareCaption = '1:1';

  /// Caption drawn inside the custom media of `media-custom`.
  static const String customCaption = 'Custom media';

  /// Semantic label of the custom media of `media-custom`.
  static const String customSemanticLabel = 'Custom media, decorative sample';

  /// Semantic label of the placeholder of `media-placeholder`.
  static const String placeholderSemanticLabel = 'Media placeholder';

  /// Aspect ratio of the custom media of `media-custom`.
  static const double customAspectRatio = 4 / 3;

  /// Widest width given to the frames that are not full width, so that a
  /// square stays small on wide simulated viewports.
  static const double compactMaxWidth = 240;

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CatalogDemo(
          id: 'media-16-9',
          label: 'Aspect ratio 16:9 (default)',
          child: CbsMediaFrame(child: _RatioCaption(caption: ratioWideCaption)),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'media-1-1',
          label: 'Aspect ratio 1:1',
          child: _Compact(
            child: CbsMediaFrame(
              aspectRatio: 1,
              child: _RatioCaption(caption: ratioSquareCaption),
            ),
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'media-custom',
          label: 'Custom media with its own ratio, radius and label',
          child: _Compact(
            child: CbsMediaFrame(
              aspectRatio: customAspectRatio,
              borderRadius: BorderRadius.all(Radius.circular(CbsRadius.xl)),
              semanticLabel: customSemanticLabel,
              child: _CustomMedia(),
            ),
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'media-placeholder',
          label: 'Placeholder',
          child: CbsMediaFrame(
            semanticLabel: placeholderSemanticLabel,
            child: _Placeholder(),
          ),
        ),
      ],
    );
  }
}

/// Keeps a demonstrated frame at most [MediaFrameSection.compactMaxWidth]
/// wide, aligned to the start edge. The limit belongs to the example (the
/// consumer), not to the frame.
class _Compact extends StatelessWidget {
  const _Compact({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: MediaFrameSection.compactMaxWidth,
        ),
        child: child,
      ),
    );
  }
}

/// Plain surface naming the ratio of its frame; no image is loaded.
class _RatioCaption extends StatelessWidget {
  const _RatioCaption({required this.caption});

  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ColoredBox(
      color: scheme.secondaryContainer,
      child: Center(
        child: Text(
          caption,
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

/// Media composed by the example: an icon at the top and a caption at the
/// bottom, drawn from the active theme.
class _CustomMedia extends StatelessWidget {
  const _CustomMedia();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ColoredBox(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(CbsSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.photo_camera_outlined,
              size: CbsIconSize.lg,
              color: scheme.onPrimaryContainer,
            ),
            Text(
              MediaFrameSection.customCaption,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Neutral placeholder drawn from the active theme; no image is loaded.
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: CbsIconSize.xl,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
