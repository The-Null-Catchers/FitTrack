import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/state_views.dart';
import '../../exercises/domain/exercise.dart';
import '../application/nutrition_providers.dart';
import '../domain/nutrition_models.dart';

/// Search the food catalogue and log a portion.
class FoodSearchScreen extends ConsumerStatefulWidget {
  const FoodSearchScreen({super.key, required this.mealType});

  final String mealType;

  @override
  ConsumerState<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends ConsumerState<FoodSearchScreen> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(foodSearchQueryProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final String query = ref.watch(foodSearchQueryProvider);
    final AsyncValue<PagedResult<Food>> results = ref.watch(foodSearchProvider);
    final AsyncValue<List<Food>> recent = ref.watch(recentFoodsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('nutritionAddFood'))),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: l10n.t('nutritionSearchFood'),
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: query.isEmpty
                ? recent.when(
                    loading: () => const SkeletonList(itemHeight: 60),
                    error: (Object error, StackTrace _) => ErrorStateView(
                      message: l10n.t('errorGeneric'),
                      onRetry: () => ref.invalidate(recentFoodsProvider),
                    ),
                    data: (List<Food> foods) => foods.isEmpty
                        ? EmptyStateView(
                            icon: Icons.search_rounded,
                            title: l10n.t('nutritionSearchFood'),
                          )
                        : _FoodList(
                            foods: foods,
                            header: l10n.t('nutritionRecent'),
                            onTap: _showPortionSheet,
                          ),
                  )
                : results.when(
                    loading: () => const SkeletonList(itemHeight: 60),
                    error: (Object error, StackTrace _) => ErrorStateView(
                      message: l10n.t('errorGeneric'),
                      onRetry: () => ref.invalidate(foodSearchProvider),
                    ),
                    data: (PagedResult<Food> page) => page.items.isEmpty
                        ? EmptyStateView(
                            icon: Icons.search_off_rounded,
                            title: l10n.t('exercisesNoResults'),
                          )
                        : _FoodList(
                            foods: page.items,
                            onTap: _showPortionSheet,
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPortionSheet(Food food) async {
    final double? grams = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _PortionSheet(food: food),
    );
    if (grams == null || !mounted) return;

    final DateTime date = ref.read(nutritionDateProvider);
    try {
      await ref.read(nutritionRepositoryProvider).logMeal(
        loggedOn: date,
        mealType: widget.mealType,
        clientUuid: 'meal-${DateTime.now().microsecondsSinceEpoch}',
        items: <Map<String, dynamic>>[
          <String, dynamic>{'food_id': food.id, 'grams': grams},
        ],
      );
      ref.invalidate(nutritionDayProvider);
      ref.invalidate(recentFoodsProvider);
      if (mounted) context.pop();
    } on Object {
      if (mounted) {
        AppToast.error(context, context.l10n.t('errorSaveFailed'));
      }
    }
  }
}

class _FoodList extends StatelessWidget {
  const _FoodList({required this.foods, required this.onTap, this.header});

  final List<Food> foods;
  final ValueChanged<Food> onTap;
  final String? header;

  @override
  Widget build(BuildContext context) {
    final String languageCode = Localizations.localeOf(context).languageCode;
    return ListView.separated(
      itemCount: foods.length + (header == null ? 0 : 1),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        if (header != null && index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.sm,
              AppSpacing.screenPadding,
              AppSpacing.sm,
            ),
            child:
                Text(header!, style: Theme.of(context).textTheme.labelMedium),
          );
        }
        final Food food = foods[header == null ? index : index - 1];
        return ListTile(
          title: Text(food.displayName(languageCode)),
          subtitle: Text(
            '${food.caloriesPer100g.round()} kcal / 100 g'
            '${food.brand != null ? ' · ${food.brand}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: const Icon(Icons.add_rounded),
          onTap: () => onTap(food),
        );
      },
    );
  }
}

/// Portion picker: a serving preset or a gram amount, with live macros.
class _PortionSheet extends StatefulWidget {
  const _PortionSheet({required this.food});

  final Food food;

  @override
  State<_PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends State<_PortionSheet> {
  late final TextEditingController _grams = TextEditingController(
    text: widget.food.defaultServingGrams.round().toString(),
  );

  double get _value =>
      double.tryParse(_grams.text.trim().replaceAll(',', '.')) ?? 0;

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ThemeData theme = Theme.of(context);
    final double factor = _value / 100;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenPadding,
        right: AppSpacing.screenPadding,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.food
                .displayName(Localizations.localeOf(context).languageCode),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (widget.food.servingOptions.isNotEmpty) ...<Widget>[
            Wrap(
              spacing: AppSpacing.sm,
              children: widget.food.servingOptions
                  .map(
                    (ServingOption option) => ActionChip(
                      label: Text(option.label),
                      onPressed: () => setState(
                        () => _grams.text = option.grams.round().toString(),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          TextField(
            controller: _grams,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.t('nutritionQuantity'),
              suffixText: l10n.t('commonGrams'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '${(widget.food.caloriesPer100g * factor).round()} ${l10n.t('commonKcal')} · '
            'P ${(widget.food.proteinPer100g * factor).round()} · '
            'C ${(widget.food.carbsPer100g * factor).round()} · '
            'F ${(widget.food.fatPer100g * factor).round()}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed:
                  _value <= 0 ? null : () => Navigator.of(context).pop(_value),
              child: Text(l10n.t('actionAdd')),
            ),
          ),
        ],
      ),
    );
  }
}
