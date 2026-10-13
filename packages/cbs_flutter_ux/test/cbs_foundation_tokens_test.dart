import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbsElevation', () {
    test('exposes the Material 3 elevation levels', () {
      expect(
        [
          CbsElevation.level0,
          CbsElevation.level1,
          CbsElevation.level2,
          CbsElevation.level3,
          CbsElevation.level4,
          CbsElevation.level5,
        ],
        [0, 1, 3, 6, 8, 12],
      );
    });
  });

  group('CbsIconSize', () {
    test('exposes the expected icon size scale', () {
      expect(
        [CbsIconSize.sm, CbsIconSize.md, CbsIconSize.lg, CbsIconSize.xl],
        [16, 24, 32, 48],
      );
    });

    test('provides strictly increasing values', () {
      expect(CbsIconSize.sm, lessThan(CbsIconSize.md));
      expect(CbsIconSize.md, lessThan(CbsIconSize.lg));
      expect(CbsIconSize.lg, lessThan(CbsIconSize.xl));
    });
  });

  group('CbsMotion', () {
    test('reuses the Material 3 durations', () {
      expect(CbsMotion.short, Durations.short2);
      expect(CbsMotion.medium, Durations.medium2);
      expect(CbsMotion.long, Durations.long2);
    });

    test('provides strictly increasing durations', () {
      expect(CbsMotion.short, lessThan(CbsMotion.medium));
      expect(CbsMotion.medium, lessThan(CbsMotion.long));
    });

    test('reuses the Material 3 easing curves', () {
      expect(CbsMotion.standard, Easing.standard);
      expect(CbsMotion.enter, Easing.emphasizedDecelerate);
      expect(CbsMotion.exit, Easing.emphasizedAccelerate);
    });
  });

  group('CbsBreakpoints', () {
    test('exposes the Material 3 width breakpoints', () {
      expect(
        [
          CbsBreakpoints.medium,
          CbsBreakpoints.expanded,
          CbsBreakpoints.large,
          CbsBreakpoints.extraLarge,
        ],
        [600, 840, 1200, 1600],
      );
    });

    test('classifies widths with inclusive lower bounds', () {
      expect(CbsBreakpoints.classify(0), CbsWindowSizeClass.compact);
      expect(CbsBreakpoints.classify(599.9), CbsWindowSizeClass.compact);
      expect(CbsBreakpoints.classify(600), CbsWindowSizeClass.medium);
      expect(CbsBreakpoints.classify(839.9), CbsWindowSizeClass.medium);
      expect(CbsBreakpoints.classify(840), CbsWindowSizeClass.expanded);
      expect(CbsBreakpoints.classify(1199.9), CbsWindowSizeClass.expanded);
      expect(CbsBreakpoints.classify(1200), CbsWindowSizeClass.large);
      expect(CbsBreakpoints.classify(1599.9), CbsWindowSizeClass.large);
      expect(CbsBreakpoints.classify(1600), CbsWindowSizeClass.extraLarge);
    });
  });
}
