import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _noop() {}

/// Guards the public contract existing before D03b-A.
///
/// Each reference below fails to compile if the symbol is removed or
/// its signature changes incompatibly.
void main() {
  test('preserves the six historical public resources', () {
    // cbs_button.dart
    const CbsButton(label: 'Action', onPressed: null);

    // cbs_loading_indicator.dart
    const CbsLoadingIndicator(value: 0.5, semanticLabel: 'Loading');

    // cbs_feedback_message.dart
    const CbsFeedbackMessage(
      message: 'Message',
      type: CbsFeedbackType.warning,
      semanticLabel: 'Warning: Message',
    );

    // cbs_radius.dart and cbs_spacing.dart
    expect(CbsRadius.pill, 999);
    expect(CbsSpacing.xxl, 48);

    // cbs_theme.dart
    expect(CbsTheme.essentials().useMaterial3, isTrue);
    expect(
      CbsTheme.branded(
        primaryColor: Colors.green,
        brightness: Brightness.dark,
        textTheme: const TextTheme(),
        buttonRadius: CbsRadius.md,
      ).useMaterial3,
      isTrue,
    );
  });

  test('preserves the package identity', () {
    expect(CbsFlutterUx.packageName, 'cbs_flutter_ux');
  });

  test('preserves the Essentials seed color', () {
    expect(CbsThemeConfig.essentialsSeedColor, Colors.indigo);
  });

  test('exposes the D03b-B Lot 1 additions', () {
    // CbsFeedbackMessage.expand: optional, defaults to false.
    const CbsFeedbackMessage(message: 'Message');
    const CbsFeedbackMessage(message: 'Message', expand: true);
    expect(const CbsFeedbackMessage(message: 'Message').expand, isFalse);

    // CbsStatePanel: child only.
    const CbsStatePanel(child: SizedBox());

    // CbsRetryMessage: message, retryLabel, onRetry; semanticLabel optional.
    const CbsRetryMessage(
      message: 'Message',
      retryLabel: 'Retry',
      onRetry: _noop,
    );
    const CbsRetryMessage(
      message: 'Message',
      retryLabel: 'Retry',
      onRetry: _noop,
      semanticLabel: 'Error: Message',
    );
  });

  test('exposes the D03b-B Lot 2 addition', () {
    // CbsSectionHeading: title only.
    const CbsSectionHeading(title: 'Title');
    const CbsSectionHeading(title: 'Title', key: ValueKey('heading'));
    expect(const CbsSectionHeading(title: 'Title').title, 'Title');
  });

  test('exposes the D05 VP-02 addition', () {
    // CbsMediaFrame: child required; aspectRatio, borderRadius and
    // semanticLabel optional.
    const CbsMediaFrame(child: SizedBox());
    const CbsMediaFrame(
      key: ValueKey('frame'),
      aspectRatio: 1,
      borderRadius: BorderRadius.zero,
      semanticLabel: 'Media',
      child: SizedBox(),
    );
    expect(const CbsMediaFrame(child: SizedBox()).aspectRatio, 16 / 9);
    expect(const CbsMediaFrame(child: SizedBox()).borderRadius, isNull);
    expect(const CbsMediaFrame(child: SizedBox()).semanticLabel, isNull);
  });

  test('exposes the D05 VP-03 addition', () {
    // CbsCollectionLayout: list and grid, in this order.
    expect(CbsCollectionLayout.values, [
      CbsCollectionLayout.list,
      CbsCollectionLayout.grid,
    ]);

    // CbsAdaptiveCollection: children required; layout, spacing,
    // runSpacing and minItemWidth optional.
    const CbsAdaptiveCollection(children: [SizedBox()]);
    const CbsAdaptiveCollection(
      key: ValueKey('collection'),
      layout: CbsCollectionLayout.grid,
      spacing: 8,
      runSpacing: 16,
      minItemWidth: 120,
      children: [SizedBox(), SizedBox()],
    );
    const collection = CbsAdaptiveCollection(children: []);
    expect(collection.layout, CbsCollectionLayout.list);
    expect(collection.spacing, 12);
    expect(collection.runSpacing, 12);
    expect(collection.minItemWidth, 240);
    expect(collection, isA<StatelessWidget>());
  });

  test('exposes the D05 VP-04 addition', () {
    // CbsContentSection: title and child required; subtitle and action
    // optional.
    const CbsContentSection(title: 'Title', child: SizedBox());
    const CbsContentSection(
      key: ValueKey('section'),
      title: 'Title',
      subtitle: 'Subtitle',
      action: SizedBox(),
      child: SizedBox(),
    );
    const section = CbsContentSection(title: 'Title', child: SizedBox());
    expect(section.title, 'Title');
    expect(section.subtitle, isNull);
    expect(section.action, isNull);
    expect(section.child, isA<SizedBox>());
    expect(section, isA<StatelessWidget>());
  });
}
