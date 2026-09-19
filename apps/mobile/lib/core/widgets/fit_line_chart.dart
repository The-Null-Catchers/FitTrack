import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../features/progress/domain/progress_models.dart';
import '../localization/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import 'state_views.dart';

/// A line chart over one or more [ChartSeries].
///
/// Axis labels, gridlines and tooltips all read from the theme, so the chart is
/// legible in dark mode without a second configuration. A trend line, when the
/// series has one, is drawn beneath the raw points rather than replacing them.
class FitLineChart extends StatelessWidget {
  const FitLineChart({
    super.key,
    required this.series,
    this.height = 220,
    this.showTrend = true,
    this.emptyMessage,
    this.valueFormatter,
  });

  final List<ChartSeries> series;
  final double height;
  final bool showTrend;
  final String? emptyMessage;
  final String Function(double value)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    final List<ChartSeries> withData =
        series.where((ChartSeries item) => item.points.length > 1).toList();

    if (withData.isEmpty) {
      return SizedBox(
        height: height,
        child: EmptyStateView(
          icon: Icons.show_chart_rounded,
          title: context.l10n.t('progressNoData'),
          message: emptyMessage ?? context.l10n.t('progressNoDataBody'),
        ),
      );
    }

    final ThemeData theme = Theme.of(context);
    final FitColorsExtension colors = context.fitColors;
    final String locale = Localizations.localeOf(context).languageCode;

    // A shared x-domain keeps multiple series aligned on the same axis.
    final List<DateTime> allDates = withData
        .expand((ChartSeries item) => item.points.map((SeriesPoint p) => p.x))
        .toList()
      ..sort();
    final DateTime minDate = allDates.first;
    final DateTime maxDate = allDates.last;
    final double spanDays =
        maxDate.difference(minDate).inDays.toDouble().clamp(1, double.infinity);

    double toX(DateTime date) =>
        date.difference(minDate).inDays.toDouble();

    final List<double> allValues = withData
        .expand((ChartSeries item) => item.points.map((SeriesPoint p) => p.y))
        .toList();
    final double minY = allValues.reduce((double a, double b) => a < b ? a : b);
    final double maxY = allValues.reduce((double a, double b) => a > b ? a : b);
    // Pad the range so the line never touches the frame.
    final double padding = ((maxY - minY).abs() * 0.12).clamp(1.0, 1e6);

    final List<LineChartBarData> bars = <LineChartBarData>[];
    for (int index = 0; index < withData.length; index++) {
      final ChartSeries item = withData[index];
      final Color color = colors.chartSeries[index % colors.chartSeries.length];

      if (showTrend && item.trend.length > 1) {
        bars.add(
          LineChartBarData(
            spots: item.trend
                .map((SeriesPoint p) => FlSpot(toX(p.x), p.y))
                .toList(),
            isCurved: true,
            curveSmoothness: 0.25,
            color: color.withValues(alpha: 0.35),
            barWidth: 4,
            dotData: const FlDotData(show: false),
          ),
        );
      }

      bars.add(
        LineChartBarData(
          spots:
              item.points.map((SeriesPoint p) => FlSpot(toX(p.x), p.y)).toList(),
          isCurved: item.trend.isEmpty,
          curveSmoothness: 0.2,
          color: color,
          barWidth: 2.4,
          dotData: FlDotData(
            show: item.points.length <= 14,
            getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
              radius: 3,
              color: color,
              strokeWidth: 2,
              strokeColor: theme.colorScheme.surface,
            ),
          ),
          belowBarData: BarAreaData(
            show: withData.length == 1,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                color.withValues(alpha: 0.22),
                color.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: spanDays,
          minY: minY - padding,
          maxY: maxY + padding,
          lineBarsData: bars,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: ((maxY - minY).abs() / 4).clamp(0.5, 1e6),
            getDrawingHorizontalLine: (double value) => FlLine(
              color: colors.border,
              strokeWidth: 1,
              dashArray: const <int>[4, 4],
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: ((maxY - minY).abs() / 4).clamp(0.5, 1e6),
                getTitlesWidget: (double value, TitleMeta meta) => Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: Text(
                    valueFormatter?.call(value) ?? Formatters.number(value),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: colors.textMuted),
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (spanDays / 4).clamp(1, double.infinity),
                getTitlesWidget: (double value, TitleMeta meta) {
                  final DateTime date =
                      minDate.add(Duration(days: value.round()));
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      Formatters.dayMonth(date, locale),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: colors.textMuted),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => colors.surfaceRaised,
              tooltipBorder: BorderSide(color: colors.border),
              getTooltipItems: (List<LineBarSpot> spots) {
                return spots.map((LineBarSpot spot) {
                  final DateTime date =
                      minDate.add(Duration(days: spot.x.round()));
                  return LineTooltipItem(
                    '${valueFormatter?.call(spot.y) ?? Formatters.number(spot.y, decimals: 1)}\n',
                    theme.textTheme.labelMedium ?? const TextStyle(),
                    children: <TextSpan>[
                      TextSpan(
                        text: Formatters.dayMonth(date, locale),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: colors.textMuted),
                      ),
                    ],
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Legend for a multi-series chart.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final FitColorsExtension colors = context.fitColors;
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xs,
      children: List<Widget>.generate(labels.length, (int index) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: colors.chartSeries[index % colors.chartSeries.length],
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(labels[index], style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      }),
    );
  }
}
