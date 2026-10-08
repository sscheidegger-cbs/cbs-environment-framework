import 'package:flutter/material.dart';

/// Reusable loading indicator for CBS Flutter applications.
///
/// Visual styling is inherited from the application's Material theme.
class CbsLoadingIndicator extends StatelessWidget {
  const CbsLoadingIndicator({super.key, this.value, this.semanticLabel});

  /// Progress between 0.0 and 1.0, or null for indeterminate progress.
  final double? value;

  /// Accessible description of the loading operation.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return CircularProgressIndicator(
      value: value,
      semanticsLabel: semanticLabel,
    );
  }
}
