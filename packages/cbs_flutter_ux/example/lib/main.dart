import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const CbsUxShowcase());
}

class CbsUxShowcase extends StatefulWidget {
  const CbsUxShowcase({super.key});

  @override
  State<CbsUxShowcase> createState() => _CbsUxShowcaseState();
}

class _CbsUxShowcaseState extends State<CbsUxShowcase> {
  bool branded = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CBS Flutter UX/UI Showcase',
      debugShowCheckedModeBanner: false,
      theme: branded
          ? CbsTheme.branded(
              primaryColor: Colors.teal,
              buttonRadius: CbsRadius.lg,
            )
          : CbsTheme.essentials(),
      home: Scaffold(
        appBar: AppBar(title: const Text('CBS Flutter UX/UI')),
        body: ListView(
          padding: const EdgeInsets.all(CbsSpacing.lg),
          children: [
            Text(
              'Design System Showcase',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: CbsSpacing.md),
            const Text('Reusable Flutter components and themes.'),
            const SizedBox(height: CbsSpacing.lg),
            SwitchListTile(
              title: const Text('Branded theme'),
              subtitle: Text(
                branded ? 'Branded / Teal' : 'Essentials / Indigo',
              ),
              value: branded,
              onChanged: (value) {
                setState(() {
                  branded = value;
                });
              },
            ),
            const SizedBox(height: CbsSpacing.lg),
            Text('Buttons', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: CbsSpacing.md),
            CbsButton(label: 'Enabled action', onPressed: () {}),
            const SizedBox(height: CbsSpacing.sm),
            const CbsButton(label: 'Disabled action', onPressed: null),
            const SizedBox(height: CbsSpacing.lg),
            Text(
              'Loading indicators',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: CbsSpacing.md),
            const Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      CbsLoadingIndicator(
                        semanticLabel: 'Indeterminate loading',
                      ),
                      SizedBox(height: CbsSpacing.sm),
                      Text('Indeterminate'),
                    ],
                  ),
                ),
                SizedBox(width: CbsSpacing.md),
                Expanded(
                  child: Column(
                    children: [
                      CbsLoadingIndicator(
                        value: 0.6,
                        semanticLabel: '60 percent complete',
                      ),
                      SizedBox(height: CbsSpacing.sm),
                      Text('Determinate - 60 %'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: CbsSpacing.lg),
            Text(
              'Feedback messages',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: CbsSpacing.md),
            const CbsFeedbackMessage(
              message: 'Information message',
              type: CbsFeedbackType.info,
            ),
            const SizedBox(height: CbsSpacing.sm),
            const CbsFeedbackMessage(
              message: 'Success message',
              type: CbsFeedbackType.success,
            ),
            const SizedBox(height: CbsSpacing.sm),
            const CbsFeedbackMessage(
              message: 'Warning message',
              type: CbsFeedbackType.warning,
            ),
            const SizedBox(height: CbsSpacing.sm),
            const CbsFeedbackMessage(
              message: 'Error message',
              type: CbsFeedbackType.error,
            ),
          ],
        ),
      ),
    );
  }
}
