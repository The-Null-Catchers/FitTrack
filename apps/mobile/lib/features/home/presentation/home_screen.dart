import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/fit_card.dart';
import '../../../core/widgets/fit_line_chart.dart';
import '../../../core/widgets/progress_ring.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../goals/domain/goal.dart';
import '../../programs/application/program_providers.dart';
import '../../programs/domain/program.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/domain/progress_models.dart';
import '../../workout/application/workout_controller.dart';
import '../../workout/domain/workout_models.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<DashboardData> dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.refresh(dashboardProvider.future),
          child: dashboard.when(
            loading: () => const SkeletonList(itemCount: 5, itemHeight: 110),
            error: (Object error, StackTrace _) => ListView(
              children: <Widget>[
                const SizedBox(height: AppSpacing.huge),
                ErrorStateView(
                  message: l10n.t('errorLoadDashboard'),
                  onRetry: () => ref.invalidate(dashboardProvider),
                ),
              ],
            ),
            data: (DashboardData data) => _DashboardBody(data: data),
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.data});

  final DashboardData data;

  String _greeting(BuildContext context) {
    final int hour = DateTime.now().hour;
    final Map<String, Object?> name = <String, Object?>{'name': data.greetingName};
    if (hour < 12) return context.l10n.t('homeGreetingMorning', name);
    if (hour < 18) return context.l10n.t('homeGreetingAfternoon', name);
    return context.l10n.t('homeGreetingEvening', name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final bool imperial = ref.watch(useImperialProvider);
    final String locale = Localizations.localeOf(context).languageCode;

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.huge),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.lg,
            AppSpacing.screenPadding,
            0,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(_greeting(context), style: theme.textTheme.headlineSmall),
                    Text(
                      Formatters.fullDate(data.date, locale),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (data.currentStreakDays > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: context.fitColors.warning.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.local_fire_department_rounded,
                        size: 16,
                        color: context.fitColors.warning,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '${data.currentStreakDays}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: context.fitColors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // Today's workout, or a prompt to resume one in progress.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.xl,
            AppSpacing.screenPadding,
            0,
          ),
          child: _TodayCard(data: data),
        ),

        SectionHeader(title: l10n.t('nutritionCalories')),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: FitCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                ProgressRing(
                  value: data.calories.fraction,
                  label: l10n.t('nutritionCalories'),
                  centerText: '${data.calories.consumed.round()}',
                  subtitle: data.calories.target == null
                      ? null
                      : '/ ${data.calories.target!.round()}',
                  isOver: (data.calories.remaining ?? 0) < 0,
                ),
                ProgressRing(
                  value: data.proteinG.fraction,
                  label: l10n.t('nutritionProtein'),
                  centerText: '${data.proteinG.consumed.round()}g',
                  subtitle: data.proteinG.target == null
                      ? null
                      : '/ ${data.proteinG.target!.round()}',
                  color: context.fitColors.info,
                ),
                ProgressRing(
                  value: data.waterMl.fraction,
                  label: l10n.t('nutritionWater'),
                  centerText: '${(data.waterMl.consumed / 1000).toStringAsFixed(1)}L',
                  color: context.fitColors.info,
                ),
              ],
            ),
          ),
        ),

        SectionHeader(title: l10n.t('homeWeeklyProgress')),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: FitCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.t('homeWorkoutsCompleted', <String, Object?>{
                    'completed': data.weeklyWorkouts.completed,
                    'target': data.weeklyWorkouts.target,
                  }),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List<Widget>.generate(7, (int index) {
                    final bool trained = index < data.weeklyWorkouts.days.length &&
                        data.weeklyWorkouts.days[index];
                    final DateTime day = DateTime.now()
                        .subtract(Duration(days: DateTime.now().weekday - 1))
                        .add(Duration(days: index));
                    return Column(
                      children: <Widget>[
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: trained
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: trained
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: theme.colorScheme.onPrimary,
                                )
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          Formatters.weekdayShort(day, locale),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        ),

        if (data.weightTrend != null && data.weightTrend!.points.length > 1) ...<Widget>[
          SectionHeader(
            title: l10n.t('homeWeightTrend'),
            subtitle: data.weightChange30dKg == null
                ? null
                : '${data.weightChange30dKg! > 0 ? '+' : ''}'
                    '${Units.weight(data.weightChange30dKg!.abs(), imperial: imperial)}',
            action: TextButton(
              onPressed: () => context.pushNamed(Routes.weightLog),
              child: Text(l10n.t('actionSeeAll')),
            ),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
            child: FitCard(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: FitLineChart(
                series: <ChartSeries>[data.weightTrend!],
                height: 170,
                valueFormatter: (double value) => imperial
                    ? Units.kgToLb(value).toStringAsFixed(0)
                    : value.toStringAsFixed(0),
              ),
            ),
          ),
        ],

        SectionHeader(title: l10n.t('homeQuickActions')),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: <Widget>[
              _QuickAction(
                icon: Icons.monitor_weight_outlined,
                label: l10n.t('homeLogWeight'),
                onTap: () => context.pushNamed(Routes.weightLog),
              ),
              _QuickAction(
                icon: Icons.restaurant_outlined,
                label: l10n.t('homeAddMeal'),
                onTap: () => context.goNamed(Routes.nutrition),
              ),
              _QuickAction(
                icon: Icons.straighten_rounded,
                label: l10n.t('homeAddMeasurement'),
                onTap: () => context.pushNamed(Routes.measurements),
              ),
              _QuickAction(
                icon: Icons.photo_camera_outlined,
                label: l10n.t('homeProgressPhoto'),
                onTap: () => context.pushNamed(Routes.photos),
              ),
              _QuickAction(
                icon: Icons.list_alt_rounded,
                label: l10n.t('homeViewPlan'),
                onTap: () => context.pushNamed(Routes.programs),
              ),
              _QuickAction(
                icon: Icons.auto_awesome_rounded,
                label: l10n.t('coachTitle'),
                onTap: () => context.pushNamed(Routes.coach),
              ),
            ],
          ),
        ),

        if (data.recentRecords.isNotEmpty) ...<Widget>[
          SectionHeader(
            title: l10n.t('homeRecentRecords'),
            action: TextButton(
              onPressed: () => context.pushNamed(Routes.records),
              child: Text(l10n.t('actionSeeAll')),
            ),
          ),
          ...data.recentRecords.take(3).map(
                (PersonalRecord record) => Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    0,
                    AppSpacing.screenPadding,
                    AppSpacing.md,
                  ),
                  child: _RecordRow(record: record, imperial: imperial),
                ),
              ),
        ],

        if (data.activeGoals.isNotEmpty) ...<Widget>[
          SectionHeader(title: l10n.t('homeGoals')),
          ...data.activeGoals.take(3).map(
                (Goal goal) => Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    0,
                    AppSpacing.screenPadding,
                    AppSpacing.md,
                  ),
                  child: FitCard(
                    child: ProgressBarRow(
                      label: goal.title,
                      value: goal.fraction,
                      trailing:
                          '${goal.currentValue?.toStringAsFixed(1) ?? '—'} / '
                          '${goal.targetValue.toStringAsFixed(1)} ${goal.unit}',
                    ),
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final WorkoutSession? active = ref.watch(activeWorkoutProvider).session;

    if (active != null) {
      return FitCard(
        color: theme.colorScheme.primaryContainer,
        borderColor: theme.colorScheme.primary,
        onTap: () => context.pushNamed(Routes.activeWorkout),
        child: Row(
          children: <Widget>[
            Icon(Icons.timer_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.t('homeContinueWorkout'),
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(active.name, style: theme.textTheme.titleMedium),
                ],
              ),
            ),
            FilledButton(
              onPressed: () => context.pushNamed(Routes.activeWorkout),
              child: Text(l10n.t('homeResumeWorkout')),
            ),
          ],
        ),
      );
    }

    final TodayWorkout? today = data.todayWorkout;
    if (today == null) {
      return FitCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.t('homeNoPlan'), style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(l10n.t('homeNoPlanBody'), style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: <Widget>[
                FilledButton(
                  onPressed: () => context.pushNamed(Routes.programs),
                  child: Text(l10n.t('programsTemplates')),
                ),
                const SizedBox(width: AppSpacing.md),
                OutlinedButton(
                  onPressed: () => context.pushNamed(Routes.planGenerator),
                  child: Text(l10n.t('coachGeneratePlan')),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (today.isRestDay) {
      return FitCard(
        child: Row(
          children: <Widget>[
            Icon(Icons.self_improvement_rounded, color: context.fitColors.info),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(l10n.t('homeRestDay'), style: theme.textTheme.titleMedium),
                  Text(l10n.t('homeRestDayBody'),
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return FitCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.t('homeTodaysWorkout'), style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          Text(today.dayName, style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${today.programName} · ${today.exerciseCount} '
            '${l10n.t('exercisesTitle').toLowerCase()}'
            '${today.estimatedMinutes != null ? ' · ~${today.estimatedMinutes} min' : ''}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _startWorkout(context, ref, today),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(l10n.t('homeStartWorkout')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startWorkout(
    BuildContext context,
    WidgetRef ref,
    TodayWorkout today,
  ) async {
    final Program program =
        await ref.read(programRepositoryProvider).byId(today.programId);
    ProgramDay? day;
    for (final ProgramDay candidate in program.days) {
      if (candidate.id == today.dayId) day = candidate;
    }
    if (day == null) return;

    await ref
        .read(activeWorkoutProvider.notifier)
        .start(program: program, day: day);
    if (context.mounted) {
      context.pushNamed(Routes.activeWorkout);
    }
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double width =
        (MediaQuery.sizeOf(context).width - AppSpacing.screenPadding * 2 - AppSpacing.md * 2) / 3;

    return SizedBox(
      width: width,
      child: FitCard(
        onTap: onTap,
        semanticLabel: label,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
          children: <Widget>[
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: theme.textTheme.labelSmall,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, required this.imperial});

  final PersonalRecord record;
  final bool imperial;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String value = record.unit == 'kg'
        ? Units.weight(record.value, imperial: imperial)
        : '${record.value.toStringAsFixed(0)} ${record.unit}';

    return FitCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.emoji_events_rounded,
            size: 20,
            color: context.fitColors.warning,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(record.exercise.name, style: theme.textTheme.titleSmall),
                Text(
                  record.recordType.replaceAll('_', ' '),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Text(value, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}
