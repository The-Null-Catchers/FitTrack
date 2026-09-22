import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/fit_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../workout/application/workout_controller.dart';
import '../application/program_providers.dart';
import '../data/program_repository.dart';
import '../domain/program.dart';

class ProgramDetailScreen extends ConsumerWidget {
  const ProgramDetailScreen({super.key, required this.programId});

  final String programId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<Program> program =
        ref.watch(programDetailProvider(programId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('programsTitle')),
        actions: <Widget>[
          program.maybeWhen(
            data: (Program plan) => plan.isTemplate
                ? TextButton(
                    onPressed: () => _clone(context, ref, plan),
                    child: Text(l10n.t('programsUse')),
                  )
                : PopupMenuButton<String>(
                    onSelected: (String action) =>
                        _handleAction(context, ref, plan, action),
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'activate',
                        child: Text(l10n.t('programsUse')),
                      ),
                      PopupMenuItem<String>(
                        value: 'duplicate',
                        child: Text(l10n.t('programsDuplicate')),
                      ),
                      PopupMenuItem<String>(
                        value: 'archive',
                        child: Text(l10n.t('programsArchive')),
                      ),
                    ],
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: program.when(
        loading: () => const SkeletonList(itemHeight: 120),
        error: (Object error, StackTrace _) => ErrorStateView(
          message: l10n.t('errorGeneric'),
          onRetry: () => ref.invalidate(programDetailProvider(programId)),
        ),
        data: (Program plan) => ListView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          children: <Widget>[
            Text(plan.name, style: Theme.of(context).textTheme.headlineSmall),
            if (plan.description != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(plan.description!,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: AppSpacing.lg),
            FitCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <Widget>[
                  StatTile(
                    label: l10n.t('fieldTrainingDays'),
                    value: '${plan.daysPerWeek}',
                  ),
                  StatTile(
                    label: l10n.t('exercisesTitle'),
                    value: '${plan.exerciseCount}',
                  ),
                  StatTile(
                    label: l10n.t('fieldSessionLength'),
                    value: plan.estimatedMinutes == null
                        ? '—'
                        : '${plan.estimatedMinutes} min',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            ...plan.days.map(
              (ProgramDay day) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: FitCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              day.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (!day.isRestDay && !plan.isTemplate)
                            TextButton(
                              onPressed: () => _start(context, ref, plan, day),
                              child: Text(l10n.t('workoutStart')),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ...day.exercises.map(
                        (DayExercise item) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  item.exercise.displayName(
                                    Localizations.localeOf(context)
                                        .languageCode,
                                  ),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              Text(
                                item.prescription,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                        color: context.fitColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    Program plan,
    ProgramDay day,
  ) async {
    await ref
        .read(activeWorkoutProvider.notifier)
        .start(program: plan, day: day);
    if (context.mounted) context.pushNamed(Routes.activeWorkout);
  }

  Future<void> _clone(BuildContext context, WidgetRef ref, Program plan) async {
    final Program copy =
        await ref.read(programRepositoryProvider).duplicate(plan.id);
    invalidatePrograms(ref);
    if (context.mounted) {
      context.pushReplacementNamed(
        Routes.programDetail,
        pathParameters: <String, String>{'id': copy.id},
      );
    }
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    Program plan,
    String action,
  ) async {
    final ProgramRepository repository = ref.read(programRepositoryProvider);
    try {
      switch (action) {
        case 'activate':
          await repository.activate(plan.id);
        case 'duplicate':
          await repository.duplicate(plan.id);
        case 'archive':
          await repository.archive(plan.id);
      }
      invalidatePrograms(ref);
      ref.invalidate(programDetailProvider(programId));
    } on Object {
      if (context.mounted) {
        AppToast.error(context, context.l10n.t('errorGeneric'));
      }
    }
  }
}
