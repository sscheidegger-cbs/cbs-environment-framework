import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import 'catalog_keys.dart';
import 'catalog_scenario.dart';

/// Interactive controls selecting the active [CatalogScenario].
///
/// Rendered outside the simulated viewport: controls keep the real
/// device width and text scale so they stay usable in every scenario.
class CatalogControls extends StatelessWidget {
  const CatalogControls({
    required this.scenario,
    required this.onChanged,
    super.key,
  });

  final CatalogScenario scenario;
  final ValueChanged<CatalogScenario> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ControlGroup<CatalogDesign>(
          groupKey: CatalogKeys.designControl,
          title: 'Design',
          values: CatalogDesign.values,
          selected: scenario.design,
          labelOf: (value) => value.label,
          optionKey: CatalogKeys.designOption,
          onSelected: (value) => onChanged(scenario.copyWith(design: value)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: CbsSpacing.xs),
          child: Text(
            scenario.design.description,
            key: CatalogKeys.designDescription,
          ),
        ),
        const SizedBox(height: CbsSpacing.md),
        _ControlGroup<CatalogAppearance>(
          groupKey: CatalogKeys.appearanceControl,
          title: 'Appearance',
          values: CatalogAppearance.values,
          selected: scenario.appearance,
          labelOf: (value) => value.label,
          optionKey: CatalogKeys.appearanceOption,
          onSelected: (value) =>
              onChanged(scenario.copyWith(appearance: value)),
        ),
        const SizedBox(height: CbsSpacing.md),
        _ControlGroup<CatalogWidth>(
          groupKey: CatalogKeys.widthControl,
          title: 'Width',
          values: CatalogWidth.values,
          selected: scenario.width,
          labelOf: (value) => value.label,
          optionKey: CatalogKeys.widthOption,
          onSelected: (value) => onChanged(scenario.copyWith(width: value)),
        ),
        const SizedBox(height: CbsSpacing.md),
        _ControlGroup<CatalogTextScale>(
          groupKey: CatalogKeys.textScaleControl,
          title: 'Text scale',
          values: CatalogTextScale.values,
          selected: scenario.textScale,
          labelOf: (value) => value.label,
          optionKey: CatalogKeys.textScaleOption,
          onSelected: (value) => onChanged(scenario.copyWith(textScale: value)),
        ),
      ],
    );
  }
}

/// Single-choice group rendered as wrapping [ChoiceChip]s.
///
/// `Wrap` keeps the group free of overflow on narrow devices and with
/// large system text.
class _ControlGroup<T> extends StatelessWidget {
  const _ControlGroup({
    required this.groupKey,
    required this.title,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.optionKey,
    required this.onSelected,
  });

  final Key groupKey;
  final String title;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final Key Function(T value) optionKey;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: groupKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: CbsSpacing.sm),
        Wrap(
          spacing: CbsSpacing.sm,
          runSpacing: CbsSpacing.sm,
          children: [
            for (final value in values)
              ChoiceChip(
                key: optionKey(value),
                label: Text(labelOf(value)),
                selected: value == selected,
                onSelected: (_) => onSelected(value),
              ),
          ],
        ),
      ],
    );
  }
}
