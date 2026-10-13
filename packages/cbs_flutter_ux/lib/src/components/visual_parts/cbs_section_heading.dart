import 'package:flutter/material.dart';

/// Title of a content section, exposed to assistive technologies as a
/// heading.
///
/// Presentation only: the consuming application provides the [title] in
/// its current language. The heading holds no state, shows no description
/// or action and adds no spacing around itself; the consumer places it and
/// separates it from the content that follows.
///
/// The text uses the `titleMedium` style of the active theme with a
/// [FontWeight.w700] weight, so it follows Essentials and Branded
/// typography, light and dark appearance, and the text scale of the
/// device. The text is as wide as its content and wraps when the parent
/// width is bounded.
class CbsSectionHeading extends StatelessWidget {
  const CbsSectionHeading({required this.title, super.key});

  /// Visible title, provided by the consuming application.
  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
