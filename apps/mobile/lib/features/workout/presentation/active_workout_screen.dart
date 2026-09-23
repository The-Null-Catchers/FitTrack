import 'dart:async';

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
import '../../../core/widgets/state_views.dart';
import '../../exercises/domain/exercise.dart';
import '../application/workout_controller.dart';
import '../domain/workout_models.dart';
import 'widgets/rest_timer_bar.dart';
import 'widgets/set_row.dart';

/// The workout logging screen.
///
/// Everything here writes straight to local storage, so the session survives
/// the app being closed and works with no connection at all. The bar at the
/// bottom of the shell lets it be minimised without ending it.
class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  const ActiveWorkoutScreen({super.key});

  @override
  ConsumerState<ActiveWorkoutScreen> createState() =>
      _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> {
  Timer? _elapsedTicker;

  @override
  void initState() {
    super.initState();
    // Repaint the header clock once a second; the value itself is derived from
    // the session's start time, not counted.
    _elapsedTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _elapsedTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ActiveWorkoutState state = ref.watch(activeWorkoutProvider);
    final WorkoutSession? session = state.session;
    final bool imperial = ref.watch(useImperialProvider);

    if (state.isRestoring) {
      return Scaffold(
        appBar: AppBar(),
        body: LoadingView(message: l10n.t('commonLoading')),
      );
    }

    if (session == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyStateView(
          icon: Icons.fitness_center_rounded,
          title: l10n.t('workoutNoExercises'),
          message: l10n.t('workoutNoExercisesBody'),
          action: FilledButton(
            onPressed: () => context.goNamed(Routes.workout),
            child: Text(l10n.t('workoutStart')),
          ),
        ),
      );
    }

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => context.pop(),
            tooltip: l10n.t('actionClose'),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(session.name,
                  style: Theme.of(context).textTheme.titleMedium),
              Text(
                Units.duration(session.elapsed.inSeconds),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          actions: <Widget>[
            IconButton(
              onPressed: () => _confirmDiscard(context),
              tooltip: l10n.t('workoutDiscard'),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
            TextButton(
              onPressed: state.isFinishing ? null : () => _finish(context),
              child: Text(l10n.t('workoutFinish')),
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            const RestTimerBar(),
            Expanded(
              child: session.exercises.isEmpty
                  ? EmptyStateView(
                      icon: Icons.add_circle_outline_rounded,
                      title: l10n.t('workoutNoExercises'),
                      message: l10n.t('workoutNoExercisesBody'),
                      action: FilledButton.icon(
                        onPressed: () => _pickExercise(context),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(l10n.t('workoutAddExercise')),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: AppSpacing.huge),
                      children: <Widget>[
                        _SessionSummaryStrip(
                            session: session, imperial: imperial),
                        ...session.exercises.map(
                          (SessionExercise item) => _ExerciseCard(
                            key: ValueKey<String>(item.localId),
                            sessionExercise: item,
                            imperial: imperial,
                          ),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.all(AppSpacing.screenPadding),
                          child: OutlinedButton.icon(
                            onPressed: () => _pickExercise(context),
                            icon: const Icon(Icons.add_rounded),
                            label: Text(l10n.t('workoutAddExercise')),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickExercise(BuildContext context) async {
    final Object? picked = await context
        .pushNamed<Object?>(Routes.exercises, queryParameters: <String, String>{
      'picker': 'true',
    });
    if (picked is Exercise) {
      await ref.read(activeWorkoutProvider.notifier).addExercise(picked);
    }
  }

  Future<void> _confirmDiscard(BuildContext context) async {
    final AppLocalizations l10n = context.l10n;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(l10n.t('workoutDiscard')),
        content: Text(l10n.t('workoutDiscardConfirm')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('actionCancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.fitColors.danger,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.t('actionDelete')),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(activeWorkoutProvider.notifier).discard();
      if (context.mounted) context.goNamed(Routes.home);
    }
  }

  Future<void> _finish(BuildContext context) async {
    final WorkoutSession? finished =
        await ref.read(activeWorkoutProvider.notifier).finish();
    if (finished != null && context.mounted) {
      context.pushReplacementNamed(Routes.workoutSummary);
    }
  }
}

class _SessionSummaryStrip extends StatelessWidget {
  const _SessionSummaryStrip({required this.session, required this.imperial});

  final WorkoutSession session;
  final bool imperial;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.lg,
        AppSpacing.screenPadding,
        0,
      ),
      child: FitCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            StatTile(
              label: l10n.t('workoutTotalSets'),
              value: '${session.completedSetCount}/${session.plannedSetCount}',
            ),
            StatTile(
              label: l10n.t('workoutTotalVolume'),
              value: Units.volume(session.localVolumeKg, imperial: imperial),
            ),
            StatTile(
              label: l10n.t('workoutDurationLabel'),
              value: Units.durationLong(session.elapsed.inSeconds),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({
    super.key,
    required this.sessionExercise,
    required this.imperial,
  });

  final SessionExercise sessionExercise;
  final bool imperial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final ActiveWorkoutController controller =
        ref.read(activeWorkoutProvider.notifier);
    final String languageCode = Localizations.localeOf(context).languageCode;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.lg,
        AppSpacing.screenPadding,
        0,
      ),
      child: FitCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          sessionExercise.exercise.displayName(languageCode),
                          style: theme.textTheme.titleMedium,
                        ),
                        if (sessionExercise.targetLabel != null)
                          Text(
                            '${l10n.t('workoutTarget')}: ${sessionExercise.targetLabel}',
                            style: theme.textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showExerciseMenu(context, ref),
                    tooltip: l10n.t('actionEdit'),
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
                ],
              ),
            ),

            if (sessionExercise.progressionHint != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.fitColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.trending_up_rounded,
                      size: 16,
                      color: context.fitColors.info,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        sessionExercise.progressionHint!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: context.fitColors.info),
                      ),
                    ),
                  ],
                ),
              ),

            // Column headers, so the numbers below need no labels.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 34),
                  SizedBox(
                    width: 62,
                    child: Text(
                      l10n.t('workoutPrevious'),
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        sessionExercise.trackingType == 'duration'
                            ? l10n.t('workoutDuration')
                            : l10n.t('workoutWeight'),
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ),
                  if (sessionExercise.trackingType != 'duration' &&
                      sessionExercise.trackingType != 'distance') ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Center(
                        child: Text(
                          l10n.t('workoutReps'),
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(
                      width: AppSpacing.minTouchTarget + AppSpacing.sm),
                ],
              ),
            ),

            ...sessionExercise.sets.asMap().entries.map(
              (MapEntry<int, WorkoutSet> entry) {
                final List<WorkoutSet> previousSets =
                    sessionExercise.previous?.sets ?? const <WorkoutSet>[];
                return SetRow(
                  key: ValueKey<String>(entry.value.localId),
                  set: entry.value,
                  trackingType: sessionExercise.trackingType,
                  imperial: imperial,
                  previousSet: entry.key < previousSets.length
                      ? previousSets[entry.key]
                      : null,
                  onComplete: (
                          {double? weightKg,
                          int? reps,
                          int? durationSeconds}) =>
                      controller.completeSet(
                    sessionExercise.localId,
                    entry.value.localId,
                    weightKg: weightKg,
                    reps: reps,
                    durationSeconds: durationSeconds,
                  ),
                  onChanged: (
                          {double? weightKg,
                          int? reps,
                          int? durationSeconds}) =>
                      controller.updateSet(
                    sessionExercise.localId,
                    entry.value.localId,
                    weightKg: weightKg,
                    reps: reps,
                    durationSeconds: durationSeconds,
                  ),
                  onRemove: () => controller.removeSet(
                    sessionExercise.localId,
                    entry.value.localId,
                  ),
                  onTypeChanged: (String type) => controller.updateSet(
                    sessionExercise.localId,
                    entry.value.localId,
                    setType: type,
                  ),
                );
              },
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () =>
                          controller.addSet(sessionExercise.localId),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(l10n.t('workoutAddSet')),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => controller.addSet(
                        sessionExercise.localId,
                        setType: 'warmup',
                      ),
                      icon: const Icon(Icons.local_fire_department_outlined,
                          size: 18),
                      label: Text(l10n.t('workoutWarmUp')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showExerciseMenu(BuildContext context, WidgetRef ref) async {
    final AppLocalizations l10n = context.l10n;
    final ActiveWorkoutController controller =
        ref.read(activeWorkoutProvider.notifier);

    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: Text(l10n.t('workoutReplaceExercise')),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final Object? picked = await context.pushNamed<Object?>(
                  Routes.exercises,
                  queryParameters: <String, String>{'picker': 'true'},
                );
                if (picked is Exercise) {
                  await controller.replaceExercise(
                      sessionExercise.localId, picked);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(l10n.t('exercisesInstructions')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.pushNamed(
                  Routes.exerciseDetail,
                  pathParameters: <String, String>{
                    'id': sessionExercise.exercise.id,
                  },
                );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: context.fitColors.danger,
              ),
              title: Text(
                l10n.t('actionDelete'),
                style: TextStyle(color: context.fitColors.danger),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.removeExercise(sessionExercise.localId);
              },
            ),
          ],
        ),
      ),
    );
  }
}
