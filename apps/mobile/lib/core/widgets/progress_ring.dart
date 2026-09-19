import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// A macro ring: consumed against a target, with the overshoot shown in the
/// warning colour rather than silently clamped.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.label,
    required this.centerText,
    this.subtitle,
    this.size = 92,
    this.strokeWidth = 9,
    this.color,
    this.isOver = false,
  });

  final double value;
  final String label;
  final String centerText;
  final String? subtitle;
  final double size;
  final double strokeWidth;
  final Color? color;
  final bool isOver;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final FitColorsExtension colors = context.fitColors;
    final Color ringColor =
        isOver ? colors.warning : (color ?? theme.colorScheme.primary);

    return Semantics(
      label: '$label: $centerText',
      value: '${(value * 100).round()}%',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                CustomPaint(
                  size: Size.square(size),
                  painter: _RingPainter(
                    value: value.clamp(0.0, 1.0),
                    color: ringColor,
                    trackColor: theme.colorScheme.surfaceContainerHighest,
                    strokeWidth: strokeWidth,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      centerText,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    if (subtitle != null)
                      Text(subtitle!, style: theme.textTheme.labelSmall),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double value;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = Offset(size.width / 2, size.height / 2);
    final double radius = (size.width - strokeWidth) / 2;

    final Paint track = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(centre, radius, track);

    if (value <= 0) return;

    final Paint progress = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}

/// A labelled horizontal bar, used where a ring would be too heavy.
class ProgressBarRow extends StatelessWidget {
  const ProgressBarRow({
    super.key,
    required this.label,
    required this.value,
    required this.trailing,
    this.color,
  });

  final String label;
  final double value;
  final String trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      label: '$label: $trailing',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(label, style: theme.textTheme.bodySmall),
              Text(
                trailing,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 6,
              color: color ?? theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}
