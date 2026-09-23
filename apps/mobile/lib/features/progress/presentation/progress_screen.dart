import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/fit_card.dart';
import '../../../core/widgets/fit_line_chart.dart';
import '../../../core/widgets/progress_ring.dart';
import '../../../core/widgets/state_views.dart';
import '../application/progress_providers.dart';
import '../domain/progress_models.dart';

class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  String _rangeLabel(BuildContext context, String range) => switch (range) {
        '7d' => context.l10n.t('progressRange7d'),
        '30d' => context.l10n.t('progressRange30d'),
        '3m' => context.l10n.t('progressRange3m'),
        '6m' => context.l10n.t('progressRange6m'),
        '1y' => context.l10n.t('progressRange1y'),
        _ => context.l10n.t('progressRangeAll'),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final String range = ref.watch(chartRangeProvider);
    final bool imperial = ref.watch(useImperialProvider);

    final AsyncValue<TrainingOverview> overview =
        ref.watch(trainingOverviewProvider);
    final AsyncValue<ChartData> weight = ref.watch(weightChartProvider);
    final AsyncValue<ChartData> volume = ref.watch(volumeChartProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('progressTitle')),
        actions: <Widget>[
          IconButton(
            onPressed: () => context.pushNamed(Routes.records),
            tooltip: l10n.t('progressRecords'),
            icon: const Icon(Icons.emoji_events_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(trainingOverviewProvider);
          ref.invalidate(weightChartProvider);
          ref.invalidate(volumeChartProvider);
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.huge),
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                children: chartRanges
                    .map(
                      (String value) => Padding(
                        padding: const EdgeInsetsDirectional.only(
                            end: AppSpacing.sm),
                        child: ChoiceChip(
                          label: Text(_rangeLabel(context, value)),
                          selected: range == value,
                          onSelected: (_) => ref
                              .read(chartRangeProvider.notifier)
                              .state = value,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            SectionHeader(title: l10n.t('progressOverview')),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
              ),
              child: overview.when(
                loading: () => const FitCard(
                  child: SizedBox(height: 72, child: LoadingView()),
                ),
                error: (Object error, StackTrace _) => FitCard(
                  child: ErrorStateView(
                    message: l10n.t('errorGeneric'),
                    onRetry: () => ref.invalidate(trainingOverviewProvider),
                  ),
                ),
                data: (TrainingOverview data) => FitCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          StatTile(
                            label: l10n.t('navWorkout'),
                            value: '${data.totalWorkouts}',
                          ),
                          StatTile(
                            label: l10n.t('workoutTotalVolume'),
                            value: Units.volume(
                              data.totalVolumeKg,
                              imperial: imperial,
                            ),
                          ),
                          StatTile(
                            label: l10n.t('workoutTotalSets'),
                            value: '${data.totalSets}',
                          ),
                          StatTile(
                            label: l10n.t('progressRecords'),
                            value: '${data.personalRecords}',
                          ),
                        ],
                      ),
                      if (data.summary != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          data.summary!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (data.volumeByMuscleGroup.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.lg),
                        const Divider(height: 1),
                        const SizedBox(height: AppSpacing.lg),
                        ...data.volumeByMuscleGroup.take(5).map(
                              (MuscleGroupVolume group) => Padding(
                                padding: const EdgeInsets.only(
                                    bottom: AppSpacing.md),
                                child: ProgressBarRow(
                                  label: group.muscleGroup
                                      .replaceAll('_', ' ')
                                      .toUpperCase(),
                                  value: group.percent / 100,
                                  trailing:
                                      '${group.percent.toStringAsFixed(0)}%',
                                ),
                              ),
                            ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SectionHeader(
              title: l10n.t('progressWeight'),
              action: TextButton(
                onPressed: () => context.pushNamed(Routes.weightLog),
                child: Text(l10n.t('actionSeeAll')),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
              ),
              child: _ChartCard(
                chart: weight,
                onRetry: () => ref.invalidate(weightChartProvider),
                valueFormatter: (double value) => imperial
                    ? Units.kgToLb(value).toStringAsFixed(0)
                    : value.toStringAsFixed(0),
              ),
            ),
            SectionHeader(title: l10n.t('workoutTotalVolume')),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
              ),
              child: _ChartCard(
                chart: volume,
                onRetry: () => ref.invalidate(volumeChartProvider),
              ),
            ),
            SectionHeader(title: l10n.t('progressTitle')),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
              ),
              child: Column(
                children: <Widget>[
                  _NavRow(
                    icon: Icons.monitor_weight_outlined,
                    label: l10n.t('progressWeight'),
                    onTap: () => context.pushNamed(Routes.weightLog),
                  ),
                  _NavRow(
                    icon: Icons.straighten_rounded,
                    label: l10n.t('progressMeasurements'),
                    onTap: () => context.pushNamed(Routes.measurements),
                  ),
                  _NavRow(
                    icon: Icons.photo_library_outlined,
                    label: l10n.t('progressPhotos'),
                    onTap: () => context.pushNamed(Routes.photos),
                  ),
                  _NavRow(
                    icon: Icons.emoji_events_outlined,
                    label: l10n.t('progressRecords'),
                    onTap: () => context.pushNamed(Routes.records),
                  ),
                  _NavRow(
                    icon: Icons.history_rounded,
                    label: l10n.t('workoutHistory'),
                    onTap: () => context.pushNamed(Routes.workoutHistory),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.chart,
    required this.onRetry,
    this.valueFormatter,
  });

  final AsyncValue<ChartData> chart;
  final VoidCallback onRetry;
  final String Function(double value)? valueFormatter;

  @override
  Widget build(BuildContext context) {
    return FitCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: chart.when(
        loading: () => const SizedBox(height: 200, child: LoadingView()),
        error: (Object error, StackTrace _) => SizedBox(
          height: 200,
          child: ErrorStateView(
            message: context.l10n.t('errorGeneric'),
            onRetry: onRetry,
          ),
        ),
        data: (ChartData data) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FitLineChart(
              series: data.series,
              valueFormatter: valueFormatter,
            ),
            if (data.summary != null)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.md,
                  left: AppSpacing.sm,
                ),
                child: Text(
                  data.summary!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: FitCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: context.fitColors.textMuted),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
