import 'package:intl/intl.dart';

/// Date and number formatting that respects the active locale.
///
/// Arabic renders with Western digits deliberately: mixed Arabic-Indic digits
/// next to Latin units ("٨٠ kg") read worse than consistent ones, and every
/// weight input on the screen uses a numeric keyboard.
class Formatters {
  const Formatters._();

  static String dayMonth(DateTime date, String locale) =>
      DateFormat.MMMd(locale).format(date);

  static String fullDate(DateTime date, String locale) =>
      DateFormat.yMMMMd(locale).format(date);

  static String weekday(DateTime date, String locale) =>
      DateFormat.EEEE(locale).format(date);

  static String weekdayShort(DateTime date, String locale) =>
      DateFormat.E(locale).format(date);

  static String time(DateTime date, String locale) =>
      DateFormat.jm(locale).format(date);

  static String dateTime(DateTime date, String locale) =>
      '${DateFormat.MMMd(locale).format(date)} · ${DateFormat.jm(locale).format(date)}';

  static String number(num value, {int decimals = 0}) =>
      NumberFormat.decimalPatternDigits(decimalDigits: decimals).format(value);

  static String compact(num value) => NumberFormat.compact().format(value);

  /// "Today", "Yesterday", or a date — for history headers.
  static String relativeDay(
    DateTime date, {
    required String locale,
    required String today,
    required String yesterday,
  }) {
    final DateTime now = DateTime.now();
    final DateTime justDate = DateTime(date.year, date.month, date.day);
    final DateTime justToday = DateTime(now.year, now.month, now.day);
    final int difference = justToday.difference(justDate).inDays;

    if (difference == 0) return today;
    if (difference == 1) return yesterday;
    if (difference < 7) return DateFormat.EEEE(locale).format(date);
    return DateFormat.MMMd(locale).format(date);
  }

  /// ISO date, the format every API date field uses.
  static String isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
