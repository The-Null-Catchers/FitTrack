import 'package:flutter/material.dart';

/// Semantic colour tokens.
///
/// Nothing in the app hard-codes a colour: widgets read from
/// `Theme.of(context)` or from [FitColorsExtension], so light and dark mode
/// stay consistent and a palette change is a single-file edit.
class AppColors {
  const AppColors._();

  // Brand
  static const Color indigo500 = Color(0xFF4F46E5);
  static const Color indigo400 = Color(0xFF818CF8);
  static const Color indigo50 = Color(0xFFEEF2FF);

  // Light surfaces
  static const Color lightBackground = Color(0xFFF7F8FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF1F3F9);
  static const Color lightBorder = Color(0xFFE4E7EE);
  static const Color lightText = Color(0xFF14192B);
  static const Color lightTextMuted = Color(0xFF6B7280);

  // Dark surfaces
  static const Color darkBackground = Color(0xFF0F1117);
  static const Color darkSurface = Color(0xFF171A23);
  static const Color darkSurfaceVariant = Color(0xFF1F2330);
  static const Color darkBorder = Color(0xFF2B303D);
  static const Color darkText = Color(0xFFF2F4F8);
  static const Color darkTextMuted = Color(0xFF9AA2B1);

  // Status
  static const Color success = Color(0xFF16A34A);
  static const Color successDark = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFD97706);
  static const Color warningDark = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerDark = Color(0xFFF87171);
  static const Color info = Color(0xFF2563EB);
  static const Color infoDark = Color(0xFF60A5FA);

  /// Chart series colours, ordered so adjacent series stay distinguishable —
  /// including for the most common forms of colour vision deficiency.
  static const List<Color> chartLight = <Color>[
    Color(0xFF4F46E5),
    Color(0xFF0EA5E9),
    Color(0xFF16A34A),
    Color(0xFFD97706),
    Color(0xFFDB2777),
    Color(0xFF7C3AED),
  ];

  static const List<Color> chartDark = <Color>[
    Color(0xFF818CF8),
    Color(0xFF38BDF8),
    Color(0xFF4ADE80),
    Color(0xFFFBBF24),
    Color(0xFFF472B6),
    Color(0xFFA78BFA),
  ];
}

/// Tokens Material's [ColorScheme] has no slot for.
@immutable
class FitColorsExtension extends ThemeExtension<FitColorsExtension> {
  const FitColorsExtension({
    required this.textMuted,
    required this.border,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.chartSeries,
    required this.surfaceRaised,
  });

  final Color textMuted;
  final Color border;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final List<Color> chartSeries;
  final Color surfaceRaised;

  static const FitColorsExtension light = FitColorsExtension(
    textMuted: AppColors.lightTextMuted,
    border: AppColors.lightBorder,
    success: AppColors.success,
    warning: AppColors.warning,
    danger: AppColors.danger,
    info: AppColors.info,
    chartSeries: AppColors.chartLight,
    surfaceRaised: AppColors.lightSurface,
  );

  static const FitColorsExtension dark = FitColorsExtension(
    textMuted: AppColors.darkTextMuted,
    border: AppColors.darkBorder,
    success: AppColors.successDark,
    warning: AppColors.warningDark,
    danger: AppColors.dangerDark,
    info: AppColors.infoDark,
    chartSeries: AppColors.chartDark,
    surfaceRaised: AppColors.darkSurfaceVariant,
  );

  @override
  FitColorsExtension copyWith({
    Color? textMuted,
    Color? border,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    List<Color>? chartSeries,
    Color? surfaceRaised,
  }) {
    return FitColorsExtension(
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      chartSeries: chartSeries ?? this.chartSeries,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    );
  }

  @override
  FitColorsExtension lerp(ThemeExtension<FitColorsExtension>? other, double t) {
    if (other is! FitColorsExtension) {
      return this;
    }
    return FitColorsExtension(
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      chartSeries: t < 0.5 ? chartSeries : other.chartSeries,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
    );
  }
}

/// `context.fitColors` instead of the full `Theme.of(context).extension<…>()!`.
extension FitColorsContext on BuildContext {
  FitColorsExtension get fitColors =>
      Theme.of(this).extension<FitColorsExtension>() ??
      FitColorsExtension.light;
}
