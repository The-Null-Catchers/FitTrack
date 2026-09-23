import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../goals/data/goal_repository.dart';
import '../../goals/domain/goal.dart';
import '../data/habit_repository.dart';
import '../domain/habit.dart';

final Provider<HabitRepository> habitRepositoryProvider =
    Provider<HabitRepository>((Ref ref) {
  return HabitRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheDaoProvider),
    ref.watch(outboxDaoProvider),
  );
});

final FutureProvider<List<Habit>> habitsProvider =
    FutureProvider<List<Habit>>((Ref ref) {
  return ref.watch(habitRepositoryProvider).list();
});

final Provider<GoalRepository> goalRepositoryProvider =
    Provider<GoalRepository>((Ref ref) {
  return GoalRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheDaoProvider),
  );
});

final FutureProviderFamily<List<Goal>, String?> goalsProvider =
    FutureProvider.family<List<Goal>, String?>((Ref ref, String? status) {
  return ref.watch(goalRepositoryProvider).list(status: status);
});
