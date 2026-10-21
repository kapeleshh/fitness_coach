import 'package:coach_engine/src/stats.dart';
import 'package:test/test.dart';

void main() {
  test('mean and sampleSd follow the readiness engine', () {
    expect(mean([1, 2, 3, 4]), 2.5);
    expect(() => mean([]), throwsStateError);
    expect(meanOrNull([]), isNull);
    expect(sampleSd([5]), 0.0);
    expect(sampleSd([2, 4, 4, 4, 5, 5, 7, 9]), closeTo(2.138089935299395, 1e-15));
  });

  group('pearson', () {
    test('is 1 for a perfect positive relationship', () {
      expect(pearson([1, 2, 3, 4], [2, 4, 6, 8]), closeTo(1.0, 1e-12));
    });

    test('skips positions where either side is missing', () {
      expect(pearson([1, null, 2, 3, 4], [2, 9, 4, 6, null]), closeTo(1.0, 1e-12));
    });

    test("is null when it can't tell: under 3 pairs or a constant side", () {
      expect(pearson([1, 2], [3, 4]), isNull);
      expect(pearson([5, 5, 5, 5], [1, 2, 3, 4]), isNull);
    });
  });

  test('categorizeStrength uses strict thresholds', () {
    expect(categorizeStrength(0.61), 'strong');
    expect(categorizeStrength(-0.6), 'moderate');
    expect(categorizeStrength(0.4), 'weak');
    expect(categorizeStrength(0.2), 'minimal');
  });
}
