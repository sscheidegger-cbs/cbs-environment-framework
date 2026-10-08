import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CbsSpacing', () {
    test('exposes the expected spacing scale', () {
      expect(
        [
          CbsSpacing.none,
          CbsSpacing.xs,
          CbsSpacing.sm,
          CbsSpacing.md,
          CbsSpacing.lg,
          CbsSpacing.xl,
          CbsSpacing.xxl,
        ],
        [0, 4, 8, 16, 24, 32, 48],
      );
    });

    test('provides strictly increasing values', () {
      expect(CbsSpacing.none, lessThan(CbsSpacing.xs));
      expect(CbsSpacing.xs, lessThan(CbsSpacing.sm));
      expect(CbsSpacing.sm, lessThan(CbsSpacing.md));
      expect(CbsSpacing.md, lessThan(CbsSpacing.lg));
      expect(CbsSpacing.lg, lessThan(CbsSpacing.xl));
      expect(CbsSpacing.xl, lessThan(CbsSpacing.xxl));
    });
  });

  group('CbsRadius', () {
    test('exposes the expected radius scale', () {
      expect(
        [
          CbsRadius.none,
          CbsRadius.sm,
          CbsRadius.md,
          CbsRadius.lg,
          CbsRadius.xl,
          CbsRadius.pill,
        ],
        [0, 4, 8, 16, 24, 999],
      );
    });

    test('provides strictly increasing values', () {
      expect(CbsRadius.none, lessThan(CbsRadius.sm));
      expect(CbsRadius.sm, lessThan(CbsRadius.md));
      expect(CbsRadius.md, lessThan(CbsRadius.lg));
      expect(CbsRadius.lg, lessThan(CbsRadius.xl));
      expect(CbsRadius.xl, lessThan(CbsRadius.pill));
    });
  });
}
