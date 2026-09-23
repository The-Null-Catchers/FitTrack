import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/fit_card.dart';
import '../../../core/widgets/progress_ring.dart';
import '../../../core/widgets/state_views.dart';
import '../application/nutrition_providers.dart';
import '../domain/nutrition_models.dart';

/// The nutrition tab: one day at a time, macros up top, meals below.
class NutritionScreen extends ConsumerWidget {
  const NutritionScreen({super.key});

  static const List<String> _mealTypes = <String>[
    'breakfast',
    'lunch',
    'dinner',
    'snack',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final DateTime date = ref.watch(nutritionDateProvider);
    final AsyncValue<NutritionDay> day = ref.watch(nutritionDayProvider);
    final String locale = Localizations.localeOf(context).languageCode;

    final bool isToday = DateUtils.isSameDay(date, DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('navNutrition')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  onPressed: () => ref
                      .read(nutritionDateProvider.notifier)
                      .state = date.subtract(const Duration(days: 1)),
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: 'Previous day',
                ),
                Text(
                  isToday
                      ? l10n.t('commonToday')
                      : Formatters.fullDate(date, locale),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                IconButton(
                  onPressed: isToday
                      ? null
                      : () => ref.read(nutritionDateProvider.notifier).state =
                          date.add(const Duration(days: 1)),
                  icon: const Icon(Icons.chevron_right_rounded),
                  tooltip: 'Next day',
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(nutritionDayProvider.future),
        child: day.when(
          loading: () => const SkeletonList(itemHeight: 110),
          error: (Object error, StackTrace _) => ListView(
            children: <Widget>[
              const SizedBox(height: AppSpacing.huge),
              ErrorStateView(
                message: l10n.t('errorGeneric'),
                onRetry: () => ref.invalidate(nutritionDayProvider),
              ),
            ],
          ),
          data: (NutritionDay data) => ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.huge),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.lg,
                  AppSpacing.screenPadding,
                  0,
                ),
                child: FitCard(
                  child: Column(
                    children: <Widget>[
                      ProgressRing(
                        value: data.calories.fraction,
                        label: l10n.t('nutritionCalories'),
                        centerText: '${data.calories.consumed.round()}',
                        subtitle: data.calories.target == null
                            ? null
                            : '/ ${data.calories.target!.round()}',
                        size: 116,
                        strokeWidth: 11,
                        isOver: data.calories.isOver,
                      ),
                      if (data.calories.remaining != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          data.calories.isOver
                              ? l10n.t('nutritionOver', <String, Object?>{
                                  'amount':
                                      '${data.calories.remaining!.abs().round()} kcal',
                                })
                              : l10n.t('nutritionRemaining', <String, Object?>{
                                  'amount':
                                      '${data.calories.remaining!.round()} kcal',
                                }),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      ProgressBarRow(
                        label: l10n.t('nutritionProtein'),
                        value: data.proteinG.fraction,
                        trailing:
                            '${data.proteinG.consumed.round()} / ${data.proteinG.target?.round() ?? '—'} g',
                        color: context.fitColors.info,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ProgressBarRow(
                        label: l10n.t('nutritionCarbs'),
                        value: data.carbsG.fraction,
                        trailing:
                            '${data.carbsG.consumed.round()} / ${data.carbsG.target?.round() ?? '—'} g',
                        color: context.fitColors.warning,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ProgressBarRow(
                        label: l10n.t('nutritionFat'),
                        value: data.fatG.fraction,
                        trailing:
                            '${data.fatG.consumed.round()} / ${data.fatG.target?.round() ?? '—'} g',
                        color: context.fitColors.success,
                      ),
                    ],
                  ),
                ),
              ),
              SectionHeader(title: l10n.t('nutritionWater')),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                child: FitCard(
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: ProgressBarRow(
                          label: l10n.t('nutritionWater'),
                          value: data.waterMl.fraction,
                          trailing:
                              '${(data.waterMl.consumed / 1000).toStringAsFixed(1)} / '
                              '${((data.waterMl.target ?? 0) / 1000).toStringAsFixed(1)} L',
                          color: context.fitColors.info,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      FilledButton.tonal(
                        onPressed: () => _addWater(context, ref, date, 250),
                        child: const Text('+250'),
                      ),
                    ],
                  ),
                ),
              ),
              for (final String mealType in _mealTypes)
                _MealSection(
                  mealType: mealType,
                  meals: data.mealsOfType(mealType),
                  totalCalories: data.caloriesOfType(mealType),
                ),
              if (data.meals.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: EmptyStateView(
                    icon: Icons.restaurant_outlined,
                    title: l10n.t('nutritionNoMeals'),
                    message: l10n.t('nutritionNoMealsBody'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addWater(
    BuildContext context,
    WidgetRef ref,
    DateTime date,
    int amountMl,
  ) async {
    try {
      await ref.read(nutritionRepositoryProvider).logWater(
            loggedOn: date,
            amountMl: amountMl,
            clientUuid: 'water-${DateTime.now().microsecondsSinceEpoch}',
          );
      ref.invalidate(nutritionDayProvider);
    } on Object {
      if (context.mounted) {
        AppToast.error(context, context.l10n.t('errorSaveFailed'));
      }
    }
  }
}

class _MealSection extends ConsumerWidget {
  const _MealSection({
    required this.mealType,
    required this.meals,
    required this.totalCalories,
  });

  final String mealType;
  final List<Meal> meals;
  final double totalCalories;

  String _title(BuildContext context) => switch (mealType) {
        'breakfast' => context.l10n.t('nutritionBreakfast'),
        'lunch' => context.l10n.t('nutritionLunch'),
        'dinner' => context.l10n.t('nutritionDinner'),
        _ => context.l10n.t('nutritionSnack'),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: _title(context),
          subtitle: totalCalories > 0
              ? '${totalCalories.round()} ${context.l10n.t('commonKcal')}'
              : null,
          action: IconButton(
            onPressed: () => context.pushNamed(
              Routes.foodSearch,
              queryParameters: <String, String>{'meal': mealType},
            ),
            tooltip: context.l10n.t('nutritionAddFood'),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ),
        if (meals.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding),
            child: FitCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                children: meals
                    .expand((Meal meal) => meal.items)
                    .map(
                      (MealItem item) => ListTile(
                        dense: true,
                        title: Text(item.foodName),
                        subtitle: Text(
                          '${item.grams.round()} g · '
                          'P ${item.proteinG.round()} · '
                          'C ${item.carbsG.round()} · '
                          'F ${item.fatG.round()}',
                          style: theme.textTheme.labelSmall,
                        ),
                        trailing: Text(
                          '${item.calories.round()}',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }
}
