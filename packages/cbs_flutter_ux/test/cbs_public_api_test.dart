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
}
