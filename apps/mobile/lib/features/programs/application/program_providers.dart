import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/program_repository.dart';
import '../domain/program.dart';

final Provider<ProgramRepository> programRepositoryProvider =
    Provider<ProgramRepository>((Ref ref) {
  return ProgramRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheDaoProvider),
  );
});

final FutureProvider<Program?> activeProgramProvider =
    FutureProvider<Program?>((Ref ref) {
  return ref.watch(programRepositoryProvider).active();
});

final FutureProvider<List<Program>> myProgramsProvider =
    FutureProvider<List<Program>>((Ref ref) async {
  final ProgramRepository repository = ref.watch(programRepositoryProvider);
  return (await repository.mine()).items;
});

final FutureProvider<List<Program>> programTemplatesProvider =
    FutureProvider<List<Program>>((Ref ref) {
  return ref.watch(programRepositoryProvider).templates();
});

final FutureProviderFamily<Program, String> programDetailProvider =
    FutureProvider.family<Program, String>((Ref ref, String id) {
  return ref.watch(programRepositoryProvider).byId(id);
});

/// Invalidate everything that depends on the program set after a mutation.
void invalidatePrograms(WidgetRef ref) {
  ref.invalidate(activeProgramProvider);
  ref.invalidate(myProgramsProvider);
  ref.invalidate(programTemplatesProvider);
}
