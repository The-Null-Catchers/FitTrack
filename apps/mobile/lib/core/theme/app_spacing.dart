/// Spacing, radius and elevation scale.
///
/// A 4pt base grid. Using the named steps instead of raw numbers is what keeps
/// rhythm consistent across screens built at different times.
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  /// Horizontal padding for full-width screen content.
  static const double screenPadding = lg;

  /// Minimum interactive size, per WCAG 2.5.5 and the platform guidelines.
  static const double minTouchTarget = 48;
}

class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;
}

class AppDuration {
  const AppDuration._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
}
