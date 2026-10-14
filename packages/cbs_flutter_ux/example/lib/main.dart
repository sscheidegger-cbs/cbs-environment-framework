import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import 'catalog/catalog_controls.dart';
import 'catalog/catalog_entries.dart';
import 'catalog/catalog_entry.dart';
import 'catalog/catalog_keys.dart';
import 'catalog/catalog_preview_frame.dart';
import 'catalog/catalog_scenario.dart';

void main() {
  runApp(const CbsUxShowcase());
}

/// Visual catalog of the `cbs_flutter_ux` package.
///
/// The active [CatalogScenario] is local state: no state management
/// dependency and no coupling with any consuming application.
class CbsUxShowcase extends StatefulWidget {
  const CbsUxShowcase({
    this.initialScenario = CatalogScenario.initial,
    super.key,
  });

  /// Scenario selected when the catalog starts.
  final CatalogScenario initialScenario;

  @override
  State<CbsUxShowcase> createState() => _CbsUxShowcaseState();
}

class _CbsUxShowcaseState extends State<CbsUxShowcase> {
  late CatalogScenario scenario = widget.initialScenario;

  void _select(CatalogScenario value) {
    setState(() {
      scenario = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CBS Flutter UX/UI Showcase',
      debugShowCheckedModeBanner: false,
      theme: scenario.buildTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('CBS Flutter UX/UI')),
          body: SingleChildScrollView(
            key: CatalogKeys.pageScroll,
            // Horizontal margin kept small: a 320 px simulated surface and
            // its 1 px frame border must fit a 360 dp screen (360 - 2 * 16
            // = 328 >= 322) so the initial scenario does not scroll.
            padding: const EdgeInsets.symmetric(
              horizontal: CbsSpacing.md,
              vertical: CbsSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Design System Showcase',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: CbsSpacing.md),
                const Text('Reusable Flutter components and themes.'),
                const SizedBox(height: CbsSpacing.lg),
                CatalogControls(scenario: scenario, onChanged: _select),
                const SizedBox(height: CbsSpacing.md),
                Text(
                  scenario.summary,
                  key: CatalogKeys.scenarioSummary,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: CbsSpacing.xs),
                // Page level: the real device text scaler, outside the
                // simulated viewport.
                Text(
                  scenario.textScaleReadout(MediaQuery.textScalerOf(context)),
                  key: CatalogKeys.textScaleReadout,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: CbsSpacing.md),
                CatalogPreviewFrame(
                  scenario: scenario,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (index, entry) in catalogEntries.indexed) ...[
                        if (index > 0) const SizedBox(height: CbsSpacing.lg),
                        CatalogSection(entry: entry),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
