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
import '../../progress/application/progress_providers.dart';
import '../application/workout_controller.dart';
import '../domain/workout_models.dart';

/// Post-workout summary, including any personal records set.
class WorkoutSummaryScreen extends ConsumerWidget {
  const WorkoutSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ActiveWorkoutState state = ref.watch(activeWorkoutProvider);
    final WorkoutSession? session = state.finishedSession;
    final bool imperial = ref.watch(useImperialProvider);

    if (session == null) {
      // Nothing to show — most likely the screen was reopened from history.
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(l10n.t('workoutNoHistory'))),
      );
    }

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: <Widget>[
          Center(
            child: Column(
              children: <Widget>[
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: context.fitColors.success.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 36,
                    color: context.fitColors.success,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l10n.t('workoutSummaryTitle'),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(session.name, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          if (state.wasQueuedOffline)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: FitCard(
                color: context.fitColors.warning.withValues(alpha: 0.12),
                borderColor: context.fitColors.warning,
                child: Row(
                  children: <Widget>[
                    Icon(Icons.cloud_off_rounded,
                        size: 18, color: context.fitColors.warning),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Text(l10n.t('syncOfflineBody'))),
                  ],
                ),
              ),
            ),
          FitCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                StatTile(
                  label: l10n.t('workoutDurationLabel'),
                  value: Units.durationLong(session.durationSeconds),
                ),
                StatTile(
                  label: l10n.t('workoutTotalSets'),
                  value: '${session.totalSets}',
                ),
                StatTile(
                  label: l10n.t('workoutTotalVolume'),
                  value: Units.volume(
                    session.totalVolumeKg > 0
                        ? session.totalVolumeKg
                        : session.localVolumeKg,
                    imperial: imperial,
                  ),
                ),
              ],
            ),
          ),
          if (session.personalRecords.isNotEmpty) ...<Widget>[
            SectionHeader(
              title: session.personalRecords.length == 1
                  ? l10n.t('workoutNewRecord')
                  : l10n.t('workoutNewRecords', <String, Object?>{
                      'count': session.personalRecords.length,
                    }),
              padding: const EdgeInsets.only(
                top: AppSpacing.xxl,
                bottom: AppSpacing.md,
              ),
            ),
            ...session.personalRecords.map(
              (PersonalRecord record) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: FitCard(
                  color: context.fitColors.warning.withValues(alpha: 0.08),
                  borderColor: context.fitColors.warning.withValues(alpha: 0.4),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.emoji_events_rounded,
                          color: context.fitColors.warning),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                                record.exercise.displayName(
                                    Localizations.localeOf(context)
                                        .languageCode),
                                style: theme.textTheme.titleSmall),
                            Text(
                              record.recordType.replaceAll('_', ' '),
                              style: theme.textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            record.unit == 'kg'
                                ? Units.weight(record.value, imperial: imperial)
                                : '${record.value.toStringAsFixed(0)} ${record.unit}',
                            style: theme.textTheme.titleSmall,
                          ),
                          if (record.improvement != null)
                            Text(
                              '+${record.improvement!.toStringAsFixed(1)}',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: context.fitColors.success),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),
          FilledButton(
            onPressed: () {
              ref.read(activeWorkoutProvider.notifier).clearSummary();
              invalidateProgress(ref);
              context.goNamed(Routes.home);
            },
            child: Text(l10n.t('actionDone')),
          ),
        ],
      ),
    );
  }
}
