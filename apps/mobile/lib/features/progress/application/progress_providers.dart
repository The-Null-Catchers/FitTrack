import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../exercises/domain/exercise.dart';
import '../data/progress_repository.dart';
import '../domain/progress_models.dart';

final Provider<ProgressRepository> progressRepositoryProvider =
    Provider<ProgressRepository>((Ref ref) {
  return ProgressRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheDaoProvider),
    ref.watch(outboxDaoProvider),
  );
});

final FutureProvider<DashboardData> dashboardProvider =
    FutureProvider<DashboardData>((Ref ref) {
  return ref.watch(progressRepositoryProvider).dashboard();
});

/// The selected time range, shared by every chart on the progress tab.
final StateProvider<String> chartRangeProvider =
    StateProvider<String>((Ref ref) => '30d');

const List<String> chartRanges = <String>['7d', '30d', '3m', '6m', '1y', 'all'];

final FutureProvider<ChartData> weightChartProvider =
    FutureProvider<ChartData>((Ref ref) {
  return ref
      .watch(progressRepositoryProvider)
      .weightChart(ref.watch(chartRangeProvider));
});

final FutureProvider<ChartData> volumeChartProvider =
    FutureProvider<ChartData>((Ref ref) {
  return ref
      .watch(progressRepositoryProvider)
      .volumeChart(ref.watch(chartRangeProvider));
});

final FutureProvider<ChartData> nutritionChartProvider =
    FutureProvider<ChartData>((Ref ref) {
  return ref
      .watch(progressRepositoryProvider)
      .nutritionChart(ref.watch(chartRangeProvider));
});

final FutureProvider<TrainingOverview> trainingOverviewProvider =
    FutureProvider<TrainingOverview>((Ref ref) {
  return ref
      .watch(progressRepositoryProvider)
      .overview(ref.watch(chartRangeProvider));
});

final FutureProvider<List<BodyWeightEntry>> bodyWeightsProvider =
    FutureProvider<List<BodyWeightEntry>>((Ref ref) {
  return ref.watch(progressRepositoryProvider).weights();
});

final FutureProviderFamily<List<MeasurementEntry>, String?>
    measurementsProvider =
    FutureProvider.family<List<MeasurementEntry>, String?>((Ref ref, String? type) {
  return ref.watch(progressRepositoryProvider).measurements(type: type);
});

final FutureProviderFamily<List<ProgressPhoto>, String?> progressPhotosProvider =
    FutureProvider.family<List<ProgressPhoto>, String?>((Ref ref, String? pose) {
  return ref.watch(progressRepositoryProvider).photos(pose: pose);
});

final FutureProvider<List<Exercise>> trainedExercisesProvider =
    FutureProvider<List<Exercise>>((Ref ref) {
  return ref.watch(progressRepositoryProvider).trainedExercises();
});

final FutureProviderFamily<ExerciseProgress, String> exerciseProgressProvider =
    FutureProvider.family<ExerciseProgress, String>((Ref ref, String exerciseId) {
  return ref
      .watch(progressRepositoryProvider)
      .exerciseProgress(exerciseId, ref.watch(chartRangeProvider));
});

/// Refresh everything the progress tab and dashboard show.
///
/// Takes a [WidgetRef] because it is called from screens after a mutation.
void invalidateProgress(WidgetRef ref) {
  ref.invalidate(dashboardProvider);
  ref.invalidate(bodyWeightsProvider);
  ref.invalidate(weightChartProvider);
  ref.invalidate(volumeChartProvider);
  ref.invalidate(trainingOverviewProvider);
}
