import 'package:fittrack/core/utils/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('weight conversion', () {
    test('round-trips between kilograms and pounds', () {
      expect(Units.lbToKg(Units.kgToLb(80)), closeTo(80, 0.001));
    });

    test('formats with the right unit and precision', () {
      expect(Units.weight(82.5, imperial: false), '82.5 kg');
      expect(Units.weight(80, imperial: false), '80 kg');
      expect(Units.weight(null, imperial: false), '—');
      expect(Units.weight(80, imperial: true), endsWith('lb'));
    });

    test('drops the unit when asked', () {
      expect(Units.weight(82.5, imperial: false, withUnit: false), '82.5');
    });
  });

  group('height', () {
    test('reads as feet and inches in imperial', () {
      expect(Units.height(180, imperial: true), "5' 11\"");
      expect(Units.height(180, imperial: false), '180 cm');
    });

    test('rolls 12 inches up to the next foot', () {
      // 183.0 cm is 71.99", which must not render as 5' 12".
      expect(Units.height(182.9, imperial: true), isNot(contains('12"')));
    });
  });

  group('duration', () {
    test('formats minutes and seconds', () {
      expect(Units.duration(90), '01:30');
      expect(Units.duration(59), '00:59');
    });

    test('adds hours past sixty minutes', () {
      expect(Units.duration(3661), '1:01:01');
    });

    test('clamps negatives rather than showing a minus sign', () {
      expect(Units.duration(-5), '00:00');
    });

    test('long form is human, not clock-like', () {
      expect(Units.durationLong(3600), '1h');
      expect(Units.durationLong(4320), '1h 12m');
      expect(Units.durationLong(600), '10m');
      expect(Units.durationLong(0), '—');
    });
  });

  group('distance', () {
    test('switches to kilometres past 1000 m', () {
      expect(Units.distance(500, imperial: false), '500 m');
      expect(Units.distance(5000, imperial: false), '5 km');
    });

    test('uses miles in imperial', () {
      expect(Units.distance(5000, imperial: true), endsWith('mi'));
    });
  });

  test('volume compacts large numbers', () {
    expect(Units.volume(850, imperial: false), '850 kg');
    expect(Units.volume(12500, imperial: false), '12.5k kg');
  });

  test('weight step is smaller in metric', () {
    expect(Units.step(imperial: false), 1.25);
    expect(Units.step(imperial: true), closeTo(1.134, 0.01));
  });
}
