import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/fit_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../programs/application/program_providers.dart';
import '../../programs/domain/program.dart';
import '../application/workout_controller.dart';
import '../domain/workout_models.dart';

/// The workout tab: today's plan, the rest of the week, and the ways in.
class WorkoutScreen extends ConsumerWidget {
  const WorkoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<Program?> program = ref.watch(activeProgramProvider);
    final WorkoutSession? active = ref.watch(activeWorkoutProvider).session;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('navWorkout')),
        actions: <Widget>[
          IconButton(
            onPressed: () => context.pushNamed(Routes.workoutHistory),
            tooltip: l10n.t('workoutHistory'),
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            onPressed: () => context.pushNamed(Routes.exercises),
            tooltip: l10n.t('exercisesTitle'),
            icon: const Icon(Icons.menu_book_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(activeProgramProvider.future),
        child: program.when(
          loading: () => const SkeletonList(itemHeight: 90),
          error: (Object error, StackTrace _) => ListView(
            children: <Widget>[
              const SizedBox(height: AppSpacing.huge),
              ErrorStateView(
                message: l10n.t('errorGeneric'),
                onRetry: () => ref.invalidate(activeProgramProvider),
              ),
            ],
          ),
          data: (Program? plan) => ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.huge),
            children: <Widget>[
              if (active != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.lg,
                    AppSpacing.screenPadding,
                    0,
                  ),
                  child: FitCard(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderColor: Theme.of(context).colorScheme.primary,
                    onTap: () => context.pushNamed(Routes.activeWorkout),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.timer_outlined),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: Text(l10n.t('homeContinueWorkout'))),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),

              if (plan == null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.huge),
                  child: EmptyStateView(
                    icon: Icons.list_alt_rounded,
                    title: l10n.t('homeNoPlan'),
                    message: l10n.t('homeNoPlanBody'),
                    action: Column(
                      children: <Widget>[
                        FilledButton(
                          onPressed: () => context.pushNamed(Routes.programs),
                          child: Text(l10n.t('programsTemplates')),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        OutlinedButton.icon(
                          onPressed: () => context.pushNamed(Routes.planGenerator),
                          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                          label: Text(l10n.t('coachGeneratePlan')),
                        ),
                      ],
                    ),
                  ),
                )
              else ...<Widget>[
                SectionHeader(
                  title: plan.name,
                  subtitle: l10n.t('programsDayCount', <String, Object?>{
                    'count': plan.dayCount,
                  }),
                  action: TextButton(
                    onPressed: () => context.pushNamed(
                      Routes.programDetail,
                      pathParameters: <String, String>{'id': plan.id},
                    ),
                    child: Text(l10n.t('actionSeeAll')),
                  ),
                ),
                ...plan.days.map(
                  (ProgramDay day) => Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenPadding,
                      0,
                      AppSpacing.screenPadding,
                      AppSpacing.md,
                    ),
                    child: _DayCard(
                      program: plan,
                      day: day,
                      canStart: active == null,
                    ),
                  ),
                ),
              ],

              Padding(
                padding: const EdgeInsets.all(AppSpacing.screenPadding),
                child: OutlinedButton.icon(
                  onPressed: active != null
                      ? null
                      : () => _startEmptyWorkout(context, ref),
                  icon: const Icon(Icons.add_rounded),
                  label: Text('${l10n.t('workoutStart')} · ${l10n.t('commonNone')}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startEmptyWorkout(BuildContext context, WidgetRef ref) async {
    await ref.read(activeWorkoutProvider.notifier).start(
          name: context.l10n.t('navWorkout'),
        );
    if (context.mounted) context.pushNamed(Routes.activeWorkout);
  }
}

class _DayCard extends ConsumerWidget {
  const _DayCard({
    required this.program,
    required this.day,
    required this.canStart,
  });

  final Program program;
  final ProgramDay day;
  final bool canStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);

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
                    Text(day.name, style: theme.textTheme.titleMedium),
                    Text(
                      day.isRestDay
                          ? l10n.t('homeRestDay')
                          : '${day.exercises.length} ${l10n.t('exercisesTitle').toLowerCase()}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (!day.isRestDay)
                FilledButton.tonal(
                  onPressed: canStart ? () => _start(context, ref) : null,
                  child: Text(l10n.t('workoutStart')),
                ),
            ],
          ),
          if (day.exercises.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
            ...day.exercises.take(4).map(
                  (DayExercise item) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            item.exercise.displayName(
                              Localizations.localeOf(context).languageCode,
                            ),
                            style: theme.textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          item.prescription,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: context.fitColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
            if (day.exercises.length > 4)
              Text(
                '+${day.exercises.length - 4}',
                style: theme.textTheme.labelSmall,
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    await ref
        .read(activeWorkoutProvider.notifier)
        .start(program: program, day: day);
    if (context.mounted) context.pushNamed(Routes.activeWorkout);
  }
}
