import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/fit_card.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../programs/application/program_providers.dart';
import '../application/coach_controller.dart';
import '../domain/coach_models.dart';

/// Guided plan generation.
///
/// Produces a preview only — saving creates a *new* program, and an existing
/// one is never overwritten.
class PlanGeneratorScreen extends ConsumerStatefulWidget {
  const PlanGeneratorScreen({super.key});

  @override
  ConsumerState<PlanGeneratorScreen> createState() =>
      _PlanGeneratorScreenState();
}

class _PlanGeneratorScreenState extends ConsumerState<PlanGeneratorScreen> {
  static const List<String> _goals = <String>[
    'lose_weight',
    'gain_muscle',
    'improve_strength',
    'improve_endurance',
    'general_fitness',
  ];

  static const List<String> _equipment = <String>[
    'barbell',
    'dumbbell',
    'cable',
    'machine',
    'bodyweight',
    'resistance_band',
    'kettlebell',
  ];

  late final PlanRequest _initial;

  @override
  void initState() {
    super.initState();
    // Seed from the user's own profile — the answers they already gave.
    final FitnessProfile? profile = ref.read(currentProfileProvider);
    _initial = PlanRequest(
      goal: profile?.primaryGoal ?? 'general_fitness',
      experience: profile?.fitnessLevel ?? 'beginner',
      daysPerWeek: profile?.trainingDaysPerWeek ?? 3,
      sessionMinutes: profile?.preferredSessionMinutes ?? 60,
      equipment: profile?.availableEquipment ?? const <String>[],
      location: profile?.workoutLocation ?? 'gym',
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final PlanGeneratorState state = ref.watch(planGeneratorProvider(_initial));
    final PlanGeneratorController controller =
        ref.read(planGeneratorProvider(_initial).notifier);
    final PlanRequest request = state.request;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('coachGeneratePlan'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: <Widget>[
          Text(l10n.t('homeGoals'),
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.md),
          SingleChoiceChips<String>(
            values: _goals,
            selected: request.goal,
            labelBuilder: (String value) => switch (value) {
              'lose_weight' => l10n.t('goalLoseWeight'),
              'gain_muscle' => l10n.t('goalGainMuscle'),
              'improve_strength' => l10n.t('goalImproveStrength'),
              'improve_endurance' => l10n.t('goalImproveEndurance'),
              _ => l10n.t('goalGeneralFitness'),
            },
            onSelected: (String value) =>
                controller.updateRequest(request.copyWith(goal: value)),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            l10n.t('exercisesDifficulty'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          SingleChoiceChips<String>(
            values: const <String>['beginner', 'intermediate', 'advanced'],
            selected: request.experience,
            labelBuilder: (String value) => switch (value) {
              'intermediate' => l10n.t('levelIntermediate'),
              'advanced' => l10n.t('levelAdvanced'),
              _ => l10n.t('levelBeginner'),
            },
            onSelected: (String value) =>
                controller.updateRequest(request.copyWith(experience: value)),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            l10n.t('fieldTrainingDays'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Slider(
            value: request.daysPerWeek.toDouble(),
            min: 1,
            max: 7,
            divisions: 6,
            label: '${request.daysPerWeek}',
            onChanged: (double value) => controller
                .updateRequest(request.copyWith(daysPerWeek: value.round())),
          ),
          Text(
            l10n.t('fieldSessionLength'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Slider(
            value: request.sessionMinutes.toDouble(),
            min: 20,
            max: 120,
            divisions: 10,
            label: '${request.sessionMinutes}',
            onChanged: (double value) => controller
                .updateRequest(request.copyWith(sessionMinutes: value.round())),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.t('onboardingEquipmentTitle'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          MultiChoiceChips<String>(
            values: _equipment,
            selected: request.equipment.toSet(),
            labelBuilder: (String value) => value
                .split('_')
                .map((String part) => part.isEmpty
                    ? part
                    : part[0].toUpperCase() + part.substring(1))
                .join(' '),
            onChanged: (Set<String> next) => controller
                .updateRequest(request.copyWith(equipment: next.toList())),
          ),
          const SizedBox(height: AppSpacing.xxl),
          FilledButton.icon(
            onPressed: state.isGenerating ? null : controller.generate,
            icon: state.isGenerating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(
              state.plan == null
                  ? l10n.t('coachGeneratePlan')
                  : l10n.t('coachRegenerate'),
            ),
          ),
          if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.lg),
              child: Text(
                state.errorMessage!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: context.fitColors.danger),
              ),
            ),
          if (state.plan != null) ...<Widget>[
            SectionHeader(
              title: l10n.t('coachPlanPreview'),
              padding: const EdgeInsets.only(
                top: AppSpacing.xxl,
                bottom: AppSpacing.md,
              ),
            ),
            _PlanPreview(plan: state.plan!),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: state.isSaving
                  ? null
                  : () => _save(controller, activate: false),
              child: Text(l10n.t('coachSavePlan')),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: state.isSaving
                  ? null
                  : () => _save(controller, activate: true),
              child: Text(l10n.t('programsUse')),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save(
    PlanGeneratorController controller, {
    required bool activate,
  }) async {
    final String? programId = await controller.save(activate: activate);
    if (programId == null || !mounted) return;

    invalidatePrograms(ref);
    context.pushReplacementNamed(
      Routes.programDetail,
      pathParameters: <String, String>{'id': programId},
    );
  }
}

class _PlanPreview extends StatelessWidget {
  const _PlanPreview({required this.plan});

  final GeneratedPlan plan;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FitCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(plan.name, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(plan.description, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ...plan.days.map(
          (GeneratedDay day) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: FitCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(day.name, style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  ...day.exercises.map(
                    (GeneratedExercise item) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              item.exerciseName,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            item.prescription.label,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: context.fitColors.textMuted),
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
        if (plan.coachingNotes.isNotEmpty)
          FitCard(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: plan.coachingNotes
                  .map(
                    (String note) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text('• '),
                          Expanded(
                            child: Text(note, style: theme.textTheme.bodySmall),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}
