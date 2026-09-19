import 'dart:math' as math;

/// Client-side strength maths.
///
/// Mirrors the server's formulas so an offline workout shows the same
/// estimated 1RM and volume the server will compute once it syncs.
class OneRepMax {
  const OneRepMax._();

  /// Epley estimate, capped at 12 reps where the formula stops being reliable.
  static double? estimate(double? weightKg, int? reps) {
    if (weightKg == null || reps == null || weightKg <= 0 || reps <= 0) {
      return null;
    }
    if (reps == 1) return _round(weightKg);
    final int effectiveReps = math.min(reps, 12);
    return _round(weightKg * (1 + effectiveReps / 30));
  }

  static double volume(double? weightKg, int? reps) {
    if (weightKg == null || reps == null) return 0;
    return _round(weightKg * reps);
  }

  static double _round(double value) => (value * 100).roundToDouble() / 100;
}
