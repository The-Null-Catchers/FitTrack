import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../exercises/domain/exercise.dart';
import '../data/nutrition_repository.dart';
import '../domain/nutrition_models.dart';

final Provider<NutritionRepository> nutritionRepositoryProvider =
    Provider<NutritionRepository>((Ref ref) {
  return NutritionRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheDaoProvider),
    ref.watch(outboxDaoProvider),
  );
});

/// The day the nutrition tab is showing. Defaults to today.
final StateProvider<DateTime> nutritionDateProvider = StateProvider<DateTime>(
  (Ref ref) {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  },
);

final FutureProvider<NutritionDay> nutritionDayProvider =
    FutureProvider<NutritionDay>((Ref ref) {
  return ref
      .watch(nutritionRepositoryProvider)
      .day(ref.watch(nutritionDateProvider));
});

final StateProvider<String> foodSearchQueryProvider =
    StateProvider<String>((Ref ref) => '');

final FutureProvider<PagedResult<Food>> foodSearchProvider =
    FutureProvider<PagedResult<Food>>((Ref ref) {
  return ref
      .watch(nutritionRepositoryProvider)
      .searchFoods(ref.watch(foodSearchQueryProvider));
});

final FutureProvider<List<Food>> recentFoodsProvider =
    FutureProvider<List<Food>>((Ref ref) {
  return ref.watch(nutritionRepositoryProvider).recentFoods();
});

final FutureProvider<PagedResult<Food>> favouriteFoodsProvider =
    FutureProvider<PagedResult<Food>>((Ref ref) {
  return ref
      .watch(nutritionRepositoryProvider)
      .searchFoods('', favouritesOnly: true);
});
