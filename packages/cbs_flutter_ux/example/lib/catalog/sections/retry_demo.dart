import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_keys.dart';

/// [CbsRetryMessage] whose retry action is visibly functional.
///
/// The example (the consumer) owns the callback: it only counts the retry
/// requests and displays the count below the message. Nothing is loaded and
/// no CBS state controller exists.
class CatalogRetryDemo extends StatefulWidget {
  const CatalogRetryDemo({
    required this.id,
    required this.message,
    required this.retryLabel,
    this.semanticLabel,
    super.key,
  });

  /// Stable identifier, used to build the [CatalogKeys.retryMessage] and
  /// [CatalogKeys.counter] keys.
  final String id;

  final String message;
  final String retryLabel;
  final String? semanticLabel;

  @override
  State<CatalogRetryDemo> createState() => _CatalogRetryDemoState();
}

class _CatalogRetryDemoState extends State<CatalogRetryDemo> {
  int retries = 0;

  void _retry() {
    setState(() {
      retries++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CbsRetryMessage(
          key: CatalogKeys.retryMessage(widget.id),
          message: widget.message,
          retryLabel: widget.retryLabel,
          semanticLabel: widget.semanticLabel,
          onRetry: _retry,
        ),
        const SizedBox(height: CbsSpacing.sm),
        Text('Retry requests: $retries', key: CatalogKeys.counter(widget.id)),
      ],
    );
  }
}
