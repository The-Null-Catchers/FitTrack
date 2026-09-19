import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/exercise_repository.dart';
import '../domain/exercise.dart';

final Provider<ExerciseRepository> exerciseRepositoryProvider =
    Provider<ExerciseRepository>((Ref ref) {
  return ExerciseRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheDaoProvider),
  );
});

/// Current filter state for the library browser.
final StateProvider<ExerciseFilters> exerciseFiltersProvider =
    StateProvider<ExerciseFilters>((Ref ref) => const ExerciseFilters());

/// Paged, filter-aware exercise list.
class ExerciseListState {
  const ExerciseListState({
    this.items = const <Exercise>[],
    this.page = 1,
    this.totalPages = 1,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<Exercise> items;
  final int page;
  final int totalPages;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  bool get hasMore => page < totalPages;

  bool get isEmpty => items.isEmpty && !isLoading && error == null;

  ExerciseListState copyWith({
    List<Exercise>? items,
    int? page,
    int? totalPages,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
  }) =>
      ExerciseListState(
        items: items ?? this.items,
        page: page ?? this.page,
        totalPages: totalPages ?? this.totalPages,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        error: clearError ? null : (error ?? this.error),
      );
}

class ExerciseListController extends StateNotifier<ExerciseListState> {
  ExerciseListController(this._ref) : super(const ExerciseListState()) {
    // Re-run the search whenever the filters change, debounced so typing in
    // the search field doesn't fire a request per keystroke.
    _ref.listen<ExerciseFilters>(exerciseFiltersProvider, (
      ExerciseFilters? previous,
      ExerciseFilters next,
    ) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        unawaited(refresh());
      });
    });
    unawaited(refresh());
  }

  final Ref _ref;
  Timer? _debounce;

  ExerciseRepository get _repository => _ref.read(exerciseRepositoryProvider);

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final PagedResult<Exercise> result = await _repository.search(
        _ref.read(exerciseFiltersProvider),
      );
      state = ExerciseListState(
        items: result.items,
        page: result.page,
        totalPages: result.totalPages,
      );
    } on Object catch (error) {
      state = state.copyWith(isLoading: false, error: _message(error));
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.isLoading) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final PagedResult<Exercise> result = await _repository.search(
        _ref.read(exerciseFiltersProvider),
        page: state.page + 1,
      );
      state = state.copyWith(
        items: <Exercise>[...state.items, ...result.items],
        page: result.page,
        totalPages: result.totalPages,
        isLoadingMore: false,
      );
    } on Object {
      // Losing a "load more" is recoverable by scrolling again; don't replace
      // the list the user is already reading with an error screen.
      state = state.copyWith(isLoadingMore: false);
    }
  }

  static String _message(Object error) => error.toString();

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final StateNotifierProvider<ExerciseListController, ExerciseListState>
    exerciseListProvider =
    StateNotifierProvider<ExerciseListController, ExerciseListState>(
  (Ref ref) => ExerciseListController(ref),
);

final FutureProviderFamily<Exercise?, String> exerciseDetailProvider =
    FutureProvider.family<Exercise?, String>((Ref ref, String id) {
  return ref.watch(exerciseRepositoryProvider).byIdCached(id);
});

final FutureProvider<Map<String, List<String>>> exerciseFilterOptionsProvider =
    FutureProvider<Map<String, List<String>>>((Ref ref) {
  return ref.watch(exerciseRepositoryProvider).filterOptions();
});
