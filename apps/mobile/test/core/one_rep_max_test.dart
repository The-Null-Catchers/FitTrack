import 'package:fittrack/core/utils/one_rep_max.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('estimated one-rep max', () {
    test('a single is its own maximum', () {
      expect(OneRepMax.estimate(100, 1), 100);
    });

    test('grows with reps', () {
      expect(OneRepMax.estimate(100, 5), closeTo(116.67, 0.01));
      expect(
          OneRepMax.estimate(100, 10)! > OneRepMax.estimate(100, 5)!, isTrue);
    });

    test('plateaus past twelve reps, where the formula stops being useful', () {
      expect(OneRepMax.estimate(60, 20), OneRepMax.estimate(60, 12));
    });

    test('returns null for missing or nonsensical input', () {
      expect(OneRepMax.estimate(null, 5), isNull);
      expect(OneRepMax.estimate(100, null), isNull);
      expect(OneRepMax.estimate(0, 5), isNull);
      expect(OneRepMax.estimate(100, 0), isNull);
    });

    test('matches the server formula so offline numbers do not shift on sync',
        () {
      // Epley: 80 * (1 + 8/30) = 101.33
      expect(OneRepMax.estimate(80, 8), closeTo(101.33, 0.01));
    });
  });

  group('volume', () {
    test('multiplies weight by reps', () {
      expect(OneRepMax.volume(80, 8), 640);
    });

    test('is zero when either side is missing', () {
      expect(OneRepMax.volume(null, 8), 0);
      expect(OneRepMax.volume(80, null), 0);
    });
  });
}
