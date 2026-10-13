import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_demo.dart';
import '../catalog_keys.dart';

/// Demonstration of [CbsButton].
///
/// The public API only exposes `label` and a nullable `onPressed`, so the
/// supported variants are: enabled, disabled, long label and a functional
/// interaction. CBS defines no other button style.
///
/// CURRENT (D03b-C.2): enabled and disabled, in `buttons-states`.
/// Added in D03b-C.3: `buttons-long-label` and `buttons-interaction`.
class ButtonsSection extends StatelessWidget {
  const ButtonsSection({super.key});

  /// Label long enough to wrap on the narrowest simulated width.
  static const String longLabel =
      'A deliberately long button label that must wrap on narrow widths';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CatalogDemo(
          id: 'buttons-states',
          label: 'Enabled and disabled',
          child: const _ButtonStatesDemo(),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'buttons-long-label',
          label: 'Long label',
          child: CbsButton(label: longLabel, onPressed: () {}),
        ),
        catalogDemoGap,
        const CatalogDemo(
          id: 'buttons-interaction',
          label: 'Interaction',
          child: _PressCounterDemo(),
        ),
      ],
    );
  }
}

/// Enabled and disabled buttons (CURRENT `buttons-states`).
///
/// The disabled button is wired to a visible counter, so that a test can
/// prove that its callback is never triggered. [_disabledButtonActive] must
/// stay `false`: it only exists so that the callback is reachable if the
/// button were made active by mistake.
class _ButtonStatesDemo extends StatefulWidget {
  const _ButtonStatesDemo();

  @override
  State<_ButtonStatesDemo> createState() => _ButtonStatesDemoState();
}

class _ButtonStatesDemoState extends State<_ButtonStatesDemo> {
  static const bool _disabledButtonActive = false;

  int disabledPresses = 0;

  void _countDisabledPress() {
    setState(() {
      disabledPresses++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CbsButton(label: 'Enabled action', onPressed: () {}),
        const SizedBox(height: CbsSpacing.sm),
        CbsButton(
          label: 'Disabled action',
          onPressed: _disabledButtonActive ? _countDisabledPress : null,
        ),
        const SizedBox(height: CbsSpacing.sm),
        Text(
          'Disabled button presses: $disabledPresses',
          key: CatalogKeys.counter('buttons-disabled'),
        ),
      ],
    );
  }
}

/// Button whose `onPressed` callback is visibly functional.
class _PressCounterDemo extends StatefulWidget {
  const _PressCounterDemo();

  @override
  State<_PressCounterDemo> createState() => _PressCounterDemoState();
}

class _PressCounterDemoState extends State<_PressCounterDemo> {
  int presses = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CbsButton(
          label: 'Increment counter',
          onPressed: () {
            setState(() {
              presses++;
            });
          },
        ),
        const SizedBox(height: CbsSpacing.sm),
        Text(
          'Button presses: $presses',
          key: CatalogKeys.counter('buttons-interaction'),
        ),
      ],
    );
  }
}
