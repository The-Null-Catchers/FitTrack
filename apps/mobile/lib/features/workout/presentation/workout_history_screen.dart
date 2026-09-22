import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/fit_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../exercises/domain/exercise.dart';
import '../application/workout_controller.dart';
import '../domain/workout_models.dart';

class WorkoutHistoryScreen extends ConsumerWidget {
  const WorkoutHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<PagedResult<WorkoutSession>> history =
        ref.watch(workoutHistoryProvider(1));
    final bool imperial = ref.watch(useImperialProvider);
    final String locale = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('workoutHistory'))),
      body: history.when(
        loading: () => const SkeletonList(itemHeight: 96),
        error: (Object error, StackTrace _) => ErrorStateView(
          message: l10n.t('errorLoadWorkouts'),
          onRetry: () => ref.invalidate(workoutHistoryProvider(1)),
        ),
        data: (PagedResult<WorkoutSession> page) {
          if (page.items.isEmpty) {
            return EmptyStateView(
              icon: Icons.history_rounded,
              title: l10n.t('workoutNoHistory'),
              message: l10n.t('workoutNoHistoryBody'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(workoutHistoryProvider(1).future),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              itemCount: page.items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (BuildContext context, int index) {
                final WorkoutSession session = page.items[index];
                return FitCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  session.name,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                Text(
                                  Formatters.relativeDay(
                                    session.completedAt ?? session.startedAt,
                                    locale: locale,
                                    today: l10n.t('commonToday'),
                                    yesterday: l10n.t('commonYesterday'),
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (session.prCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: context.fitColors.warning
                                    .withValues(alpha: 0.15),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    Icons.emoji_events_rounded,
                                    size: 13,
                                    color: context.fitColors.warning,
                                  ),
                                  const SizedBox(width: AppSpacing.xxs),
                                  Text(
                                    '${session.prCount}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: context.fitColors.warning,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                              session.totalVolumeKg,
                              imperial: imperial,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
