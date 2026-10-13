import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

/// CURRENT demonstration of [CbsButton]: enabled and disabled.
class ButtonsSection extends StatelessWidget {
  const ButtonsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CbsButton(label: 'Enabled action', onPressed: () {}),
        const SizedBox(height: CbsSpacing.sm),
        const CbsButton(label: 'Disabled action', onPressed: null),
      ],
    );
  }
}
