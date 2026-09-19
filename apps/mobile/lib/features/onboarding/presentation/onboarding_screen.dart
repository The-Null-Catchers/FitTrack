import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/units.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/fit_card.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';

/// The onboarding wizard.
///
/// Five short steps rather than one long form: each screen asks for one kind
/// of thing, and the draft is held in memory until the final submit so a user
/// can move back and forth without losing anything.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const int _stepCount = 5;

  final PageController _pageController = PageController();
  int _step = 0;
  OnboardingDraft _draft = const OnboardingDraft();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _update(OnboardingDraft draft) => setState(() => _draft = draft);

  bool get _canContinue => switch (_step) {
        1 => _draft.heightCm != null && _draft.currentWeightKg != null,
        _ => true,
      };

  Future<void> _next() async {
    if (_step < _stepCount - 1) {
      setState(() => _step++);
      await _pageController.animateToPage(
        _step,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    await _finish();
  }

  Future<void> _back() async {
    if (_step == 0) return;
    setState(() => _step--);
    await _pageController.animateToPage(
      _step,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    final bool success =
        await ref.read(authControllerProvider.notifier).completeOnboarding(_draft);
    if (success && mounted) {
      context.goNamed(Routes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AuthState auth = ref.watch(authControllerProvider);
    final bool imperial = _draft.unitSystem == 'imperial';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('onboardingTitle')),
        leading: _step == 0
            ? null
            : IconButton(
                onPressed: _back,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: l10n.t('actionBack'),
              ),
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              0,
              AppSpacing.screenPadding,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: (_step + 1) / _stepCount,
                    minHeight: 5,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.t('onboardingStep', <String, Object?>{
                    'current': _step + 1,
                    'total': _stepCount,
                  }),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: <Widget>[
                  _GoalStep(draft: _draft, onChanged: _update),
                  _BodyStep(draft: _draft, onChanged: _update, imperial: imperial),
                  _TrainingStep(draft: _draft, onChanged: _update),
                  _EquipmentStep(draft: _draft, onChanged: _update),
                  _ReviewStep(draft: _draft, imperial: imperial),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: Column(
                children: <Widget>[
                  if (auth.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        auth.errorMessage!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: context.fitColors.danger,
                            ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: !_canContinue || auth.isBusy ? null : _next,
                      child: auth.isBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _step == _stepCount - 1
                                  ? l10n.t('onboardingFinish')
                                  : l10n.t('actionContinue'),
                            ),
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
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: context.fitColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.xxl),
          ...children,
        ],
      ),
    );
  }
}

const List<String> _goals = <String>[
  'lose_weight',
  'gain_muscle',
  'improve_strength',
  'improve_endurance',
  'general_fitness',
  'maintain_weight',
];

String _goalLabel(BuildContext context, String goal) => switch (goal) {
      'lose_weight' => context.l10n.t('goalLoseWeight'),
      'gain_muscle' => context.l10n.t('goalGainMuscle'),
      'improve_strength' => context.l10n.t('goalImproveStrength'),
      'improve_endurance' => context.l10n.t('goalImproveEndurance'),
      'maintain_weight' => context.l10n.t('goalMaintainWeight'),
      _ => context.l10n.t('goalGeneralFitness'),
    };

IconData _goalIcon(String goal) => switch (goal) {
      'lose_weight' => Icons.trending_down_rounded,
      'gain_muscle' => Icons.fitness_center_rounded,
      'improve_strength' => Icons.bolt_rounded,
      'improve_endurance' => Icons.directions_run_rounded,
      'maintain_weight' => Icons.balance_rounded,
      _ => Icons.favorite_outline_rounded,
    };

class _GoalStep extends StatelessWidget {
  const _GoalStep({required this.draft, required this.onChanged});

  final OnboardingDraft draft;
  final ValueChanged<OnboardingDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: context.l10n.t('onboardingGoalTitle'),
      subtitle: context.l10n.t('onboardingGoalSubtitle'),
      children: _goals.map((String goal) {
        final bool selected = draft.primaryGoal == goal;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: FitCard(
            onTap: () => onChanged(draft.copyWith(primaryGoal: goal)),
            borderColor: selected ? Theme.of(context).colorScheme.primary : null,
            color: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            semanticLabel: _goalLabel(context, goal),
            child: Row(
              children: <Widget>[
                Icon(
                  _goalIcon(goal),
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : context.fitColors.textMuted,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Text(
                    _goalLabel(context, goal),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _BodyStep extends StatelessWidget {
  const _BodyStep({
    required this.draft,
    required this.onChanged,
    required this.imperial,
  });

  final OnboardingDraft draft;
  final ValueChanged<OnboardingDraft> onChanged;
  final bool imperial;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return _StepScaffold(
      title: l10n.t('onboardingBodyTitle'),
      subtitle: l10n.t('onboardingBodySubtitle'),
      children: <Widget>[
        SegmentedButton<String>(
          segments: <ButtonSegment<String>>[
            ButtonSegment<String>(value: 'metric', label: Text(l10n.t('unitsMetric'))),
            ButtonSegment<String>(
              value: 'imperial',
              label: Text(l10n.t('unitsImperial')),
            ),
          ],
          selected: <String>{draft.unitSystem},
          showSelectedIcon: false,
          onSelectionChanged: (Set<String> next) =>
              onChanged(draft.copyWith(unitSystem: next.first)),
        ),
        const SizedBox(height: AppSpacing.xl),
        _NumberField(
          label: l10n.t('fieldHeight'),
          suffix: imperial ? l10n.t('commonIn') : l10n.t('commonCm'),
          initial: draft.heightCm == null
              ? null
              : (imperial
                  ? Units.cmToInch(draft.heightCm!)
                  : draft.heightCm!),
          onChanged: (double? value) => onChanged(
            draft.copyWith(
              heightCm: value == null
                  ? null
                  : (imperial ? Units.inchToCm(value) : value),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _NumberField(
          label: l10n.t('fieldWeight'),
          suffix: imperial ? l10n.t('commonLb') : l10n.t('commonKg'),
          initial: draft.currentWeightKg == null
              ? null
              : (imperial
                  ? Units.kgToLb(draft.currentWeightKg!)
                  : draft.currentWeightKg!),
          onChanged: (double? value) => onChanged(
            draft.copyWith(
              currentWeightKg:
                  value == null ? null : (imperial ? Units.lbToKg(value) : value),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _NumberField(
          label: l10n.t('fieldTargetWeight'),
          suffix: imperial ? l10n.t('commonLb') : l10n.t('commonKg'),
          initial: draft.targetWeightKg == null
              ? null
              : (imperial
                  ? Units.kgToLb(draft.targetWeightKg!)
                  : draft.targetWeightKg!),
          onChanged: (double? value) => onChanged(
            draft.copyWith(
              targetWeightKg:
                  value == null ? null : (imperial ? Units.lbToKg(value) : value),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(l10n.t('fieldGender'), style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.md),
        SingleChoiceChips<String>(
          values: const <String>['male', 'female', 'other', 'undisclosed'],
          selected: draft.gender,
          labelBuilder: (String value) => switch (value) {
            'male' => l10n.t('genderMale'),
            'female' => l10n.t('genderFemale'),
            'other' => l10n.t('genderOther'),
            _ => l10n.t('genderUndisclosed'),
          },
          onSelected: (String value) => onChanged(draft.copyWith(gender: value)),
        ),
      ],
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.suffix,
    required this.onChanged,
    this.initial,
  });

  final String label;
  final String suffix;
  final ValueChanged<double?> onChanged;
  final double? initial;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial == null
        ? ''
        : widget.initial!.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), ''),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixText: widget.suffix,
      ),
      onChanged: (String value) =>
          widget.onChanged(double.tryParse(value.replaceAll(',', '.'))),
    );
  }
}

class _TrainingStep extends StatelessWidget {
  const _TrainingStep({required this.draft, required this.onChanged});

  final OnboardingDraft draft;
  final ValueChanged<OnboardingDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);

    return _StepScaffold(
      title: l10n.t('onboardingTrainingTitle'),
      subtitle: l10n.t('onboardingTrainingSubtitle'),
      children: <Widget>[
        Text(l10n.t('exercisesDifficulty'), style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.md),
        SingleChoiceChips<String>(
          values: const <String>['beginner', 'intermediate', 'advanced'],
          selected: draft.fitnessLevel,
          labelBuilder: (String value) => switch (value) {
            'intermediate' => l10n.t('levelIntermediate'),
            'advanced' => l10n.t('levelAdvanced'),
            _ => l10n.t('levelBeginner'),
          },
          onSelected: (String value) =>
              onChanged(draft.copyWith(fitnessLevel: value)),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(l10n.t('locationGym'), style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.md),
        SingleChoiceChips<String>(
          values: const <String>['gym', 'home', 'outdoor', 'mixed'],
          selected: draft.workoutLocation,
          labelBuilder: (String value) => switch (value) {
            'home' => l10n.t('locationHome'),
            'outdoor' => l10n.t('locationOutdoor'),
            'mixed' => l10n.t('locationMixed'),
            _ => l10n.t('locationGym'),
          },
          onSelected: (String value) =>
              onChanged(draft.copyWith(workoutLocation: value)),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(l10n.t('fieldTrainingDays'), style: theme.textTheme.titleSmall),
        Slider(
          value: draft.trainingDaysPerWeek.toDouble(),
          min: 1,
          max: 7,
          divisions: 6,
          label: '${draft.trainingDaysPerWeek}',
          onChanged: (double value) =>
              onChanged(draft.copyWith(trainingDaysPerWeek: value.round())),
        ),
        Text(
          l10n.t('daysPerWeek', <String, Object?>{
            'count': draft.trainingDaysPerWeek,
          }),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(l10n.t('fieldSessionLength'), style: theme.textTheme.titleSmall),
        Slider(
          value: draft.preferredSessionMinutes.toDouble(),
          min: 20,
          max: 120,
          divisions: 10,
          label: '${draft.preferredSessionMinutes}',
          onChanged: (double value) =>
              onChanged(draft.copyWith(preferredSessionMinutes: value.round())),
        ),
        Text(
          l10n.t('minutesShort', <String, Object?>{
            'count': draft.preferredSessionMinutes,
          }),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

const List<String> _equipment = <String>[
  'barbell',
  'dumbbell',
  'cable',
  'machine',
  'bodyweight',
  'resistance_band',
  'kettlebell',
  'cardio_machine',
];

class _EquipmentStep extends StatelessWidget {
  const _EquipmentStep({required this.draft, required this.onChanged});

  final OnboardingDraft draft;
  final ValueChanged<OnboardingDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: context.l10n.t('onboardingEquipmentTitle'),
      subtitle: context.l10n.t('onboardingTrainingSubtitle'),
      children: <Widget>[
        MultiChoiceChips<String>(
          values: _equipment,
          selected: draft.availableEquipment.toSet(),
          labelBuilder: (String value) =>
              value.replaceAll('_', ' ').split(' ').map(_capitalise).join(' '),
          onChanged: (Set<String> next) =>
              onChanged(draft.copyWith(availableEquipment: next.toList())),
        ),
      ],
    );
  }

  static String _capitalise(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({required this.draft, required this.imperial});

  final OnboardingDraft draft;
  final bool imperial;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return _StepScaffold(
      title: l10n.t('onboardingReviewTitle'),
      subtitle: l10n.t('onboardingReviewSubtitle'),
      children: <Widget>[
        FitCard(
          child: Column(
            children: <Widget>[
              _ReviewRow(
                label: l10n.t('homeGoals'),
                value: _goalLabel(context, draft.primaryGoal),
              ),
              _ReviewRow(
                label: l10n.t('fieldHeight'),
                value: Units.height(draft.heightCm, imperial: imperial),
              ),
              _ReviewRow(
                label: l10n.t('fieldWeight'),
                value: Units.weight(draft.currentWeightKg, imperial: imperial),
              ),
              if (draft.targetWeightKg != null)
                _ReviewRow(
                  label: l10n.t('fieldTargetWeight'),
                  value: Units.weight(draft.targetWeightKg, imperial: imperial),
                ),
              _ReviewRow(
                label: l10n.t('fieldTrainingDays'),
                value: l10n.t('daysPerWeek', <String, Object?>{
                  'count': draft.trainingDaysPerWeek,
                }),
              ),
              _ReviewRow(
                label: l10n.t('fieldSessionLength'),
                value: l10n.t('minutesShort', <String, Object?>{
                  'count': draft.preferredSessionMinutes,
                }),
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.t('nutritionEstimateNote'),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: context.fitColors.textMuted),
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
