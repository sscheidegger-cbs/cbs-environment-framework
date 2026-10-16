import 'package:flutter/material.dart';

/// Generic, application-agnostic content surface.
///
/// The caller supplies presentation widgets and owns all business data,
/// navigation and actions. The card inherits the active Material theme.
enum CbsContentCardLayout { vertical, horizontal }

class CbsContentCard extends StatelessWidget {
  const CbsContentCard({
    required this.content,
    this.media,
    this.action,
    this.layout = CbsContentCardLayout.vertical,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final Widget content;
  final Widget? media;
  final Widget? action;
  final CbsContentCardLayout layout;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final body = layout == CbsContentCardLayout.vertical
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (media != null) media!,
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    content,
                    if (action != null) ...[
                      const SizedBox(height: 8),
                      action!,
                    ],
                  ],
                ),
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              if (media != null) Flexible(child: media!),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      content,
                      if (action != null) ...[
                        const SizedBox(height: 8),
                        action!,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );

    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? body
          : InkWell(onTap: onTap, child: body),
    );

    return semanticLabel == null
        ? card
        : Semantics(label: semanticLabel, child: card);
  }
}
