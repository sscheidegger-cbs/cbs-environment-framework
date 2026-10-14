import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_keys.dart';

/// [CbsFeedbackMessage] displayed, hidden and displayed again on user action.
///
/// D03c-A.2 / C4: manual qualification aid. The example (the consumer)
/// owns the state: the message is inserted into, and removed from, the
/// widget tree. Nothing is announced on purpose: the CURRENT behaviour of
/// `CbsFeedbackMessage` is observed, not corrected, so no `liveRegion` and
/// no `semanticLabel` is added here.
class CatalogDynamicFeedbackDemo extends StatefulWidget {
  const CatalogDynamicFeedbackDemo({required this.id, super.key});

  /// Stable identifier, used to build the [CatalogKeys.counter] key.
  final String id;

  /// Message displayed on user action.
  static const String message = 'Dynamic feedback message';

  @override
  State<CatalogDynamicFeedbackDemo> createState() =>
      _CatalogDynamicFeedbackDemoState();
}

class _CatalogDynamicFeedbackDemoState
    extends State<CatalogDynamicFeedbackDemo> {
  bool visible = false;
  int displays = 0;

  void _show() {
    if (visible) {
      return;
    }
    setState(() {
      visible = true;
      displays++;
    });
  }

  void _hide() {
    setState(() {
      visible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: CbsSpacing.sm,
          runSpacing: CbsSpacing.sm,
          children: [
            CbsButton(
              key: CatalogKeys.dynamicFeedbackShow,
              label: 'Show feedback',
              onPressed: _show,
            ),
            CbsButton(
              key: CatalogKeys.dynamicFeedbackHide,
              label: 'Hide feedback',
              onPressed: _hide,
            ),
          ],
        ),
        if (visible) ...[
          const SizedBox(height: CbsSpacing.sm),
          const CbsFeedbackMessage(
            key: CatalogKeys.dynamicFeedbackMessage,
            message: CatalogDynamicFeedbackDemo.message,
            type: CbsFeedbackType.info,
            expand: true,
          ),
        ],
        const SizedBox(height: CbsSpacing.sm),
        Text(
          'Feedback displays: $displays',
          key: CatalogKeys.counter(widget.id),
        ),
      ],
    );
  }
}
