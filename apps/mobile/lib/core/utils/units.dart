import 'dart:math' as math;

/// Unit conversion and display formatting.
///
/// Everything is stored in metric; the imperial preference is purely a
/// presentation concern, converted at the edge.
class Units {
  const Units._();

  static const double kgPerLb = 0.45359237;
  static const double cmPerInch = 2.54;

  static double kgToLb(double kg) => kg / kgPerLb;

  static double lbToKg(double lb) => lb * kgPerLb;

  static double cmToInch(double cm) => cm / cmPerInch;

  static double inchToCm(double inches) => inches * cmPerInch;

  /// Weight for display, rounded to a precision that matches the unit.
  static String weight(double? kg, {required bool imperial, bool withUnit = true}) {
    if (kg == null) return '—';
    final double value = imperial ? kgToLb(kg) : kg;
    final String number = _trim(value, imperial ? 1 : 1);
    return withUnit ? '$number ${imperial ? 'lb' : 'kg'}' : number;
  }

  static String length(double? cm, {required bool imperial, bool withUnit = true}) {
    if (cm == null) return '—';
    final double value = imperial ? cmToInch(cm) : cm;
    final String number = _trim(value, 1);
    return withUnit ? '$number ${imperial ? 'in' : 'cm'}' : number;
  }

  /// Height reads as feet and inches in imperial, where "70 in" would not.
  static String height(double? cm, {required bool imperial}) {
    if (cm == null) return '—';
    if (!imperial) return '${_trim(cm, 0)} cm';
    final double totalInches = cmToInch(cm);
    final int feet = totalInches ~/ 12;
    final int inches = (totalInches - feet * 12).round();
    return inches == 12 ? '${feet + 1}\' 0"' : '$feet\' $inches"';
  }

  static String distance(double? metres, {required bool imperial}) {
    if (metres == null) return '—';
    if (imperial) {
      final double miles = metres / 1609.344;
      return miles >= 0.1 ? '${_trim(miles, 2)} mi' : '${_trim(metres * 3.28084, 0)} ft';
    }
    return metres >= 1000 ? '${_trim(metres / 1000, 2)} km' : '${_trim(metres, 0)} m';
  }

  /// `mm:ss`, or `h:mm:ss` once a session passes an hour.
  static String duration(int? seconds) {
    if (seconds == null) return '—';
    final int safe = math.max(0, seconds);
    final int hours = safe ~/ 3600;
    final int minutes = (safe % 3600) ~/ 60;
    final int remaining = safe % 60;
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = remaining.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  /// Long-form duration for summaries: "1h 12m".
  static String durationLong(int? seconds) {
    if (seconds == null || seconds <= 0) return '—';
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    if (hours == 0) return '${minutes}m';
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  static String volume(double? kg, {required bool imperial}) {
    if (kg == null) return '—';
    final double value = imperial ? kgToLb(kg) : kg;
    if (value >= 1000) {
      return '${_trim(value / 1000, 1)}k ${imperial ? 'lb' : 'kg'}';
    }
    return '${_trim(value, 0)} ${imperial ? 'lb' : 'kg'}';
  }

  /// The smallest weight step the increment buttons should use.
  static double step({required bool imperial}) => imperial ? lbToKg(2.5) : 1.25;

  static String _trim(double value, int decimals) {
    final String text = value.toStringAsFixed(decimals);
    if (!text.contains('.')) return text;
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
