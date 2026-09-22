import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/one_rep_max.dart';
import '../../exercises/domain/exercise.dart';
import '../../programs/domain/program.dart';
import '../data/workout_repository.dart';
import '../domain/workout_models.dart';
import 'rest_timer_controller.dart';

final Provider<WorkoutRepository> workoutRepositoryProvider =
    Provider<WorkoutRepository>((Ref ref) {
  return WorkoutRepository(
    ref.watch(apiClientProvider),
    ref.watch(activeSessionDaoProvider),
    ref.watch(outboxDaoProvider),
    ref.watch(cacheDaoProvider),
  );
});

@immutable
class ActiveWorkoutState {
  const ActiveWorkoutState({
    this.session,
    this.isRestoring = true,
    this.isFinishing = false,
    this.errorMessage,
    this.finishedSession,
    this.wasQueuedOffline = false,
  });

  final WorkoutSession? session;
  final bool isRestoring;
  final bool isFinishing;
  final String? errorMessage;

  /// Set once a workout is finished, so the summary screen has something to
  /// show even after the active session is cleared.
  final WorkoutSession? finishedSession;

  /// True when the finished workout went to the outbox rather than the server.
  final bool wasQueuedOffline;

  bool get hasActiveWorkout => session != null;

  ActiveWorkoutState copyWith({
    WorkoutSession? session,
    bool? isRestoring,
    bool? isFinishing,
    String? errorMessage,
    WorkoutSession? finishedSession,
    bool? wasQueuedOffline,
    bool clearSession = false,
    bool clearError = false,
  }) =>
      ActiveWorkoutState(
        session: clearSession ? null : (session ?? this.session),
        isRestoring: isRestoring ?? this.isRestoring,
        isFinishing: isFinishing ?? this.isFinishing,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        finishedSession: finishedSession ?? this.finishedSession,
        wasQueuedOffline: wasQueuedOffline ?? this.wasQueuedOffline,
      );
}

/// Drives the active workout.
///
/// Every mutation follows the same shape: update the in-memory session, then
/// persist it. Nothing waits on the network, so logging a set is instant and
/// works with the radio off.
class ActiveWorkoutController extends StateNotifier<ActiveWorkoutState> {
  ActiveWorkoutController(this._ref) : super(const ActiveWorkoutState()) {
    unawaited(_restore());
  }

  final Ref _ref;
  final math.Random _random = math.Random();

  WorkoutRepository get _repository => _ref.read(workoutRepositoryProvider);

  bool get _isOnline => _ref.read(isOnlineProvider);

  Future<void> _restore() async {
    final WorkoutSession? stored = await _repository.readActiveLocal();
    state = ActiveWorkoutState(session: stored, isRestoring: false);
  }

  /// A client-generated id, used as the server's idempotency key.
  String _newLocalId([String prefix = 'w']) {
    final String random = List<String>.generate(
      8,
      (_) => _random.nextInt(16).toRadixString(16),
    ).join();
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$random';
  }

  /// Start a workout from a program day, or ad hoc when [day] is null.
  Future<WorkoutSession?> start({
    Program? program,
    ProgramDay? day,
    String? name,
    List<Exercise> exercises = const <Exercise>[],
  }) async {
    if (state.session != null) return state.session;

    final String localId = _newLocalId();
    final List<SessionExercise> sessionExercises = day != null
        ? day.exercises
            .map(
              (DayExercise item) => SessionExercise(
                localId: _newLocalId('se'),
                exercise: item.exercise,
                position: item.position,
                trackingType: item.trackingType,
                restSeconds: item.restSeconds,
                notes: item.notes,
                supersetGroup: item.supersetGroup,
                targetSnapshot: <String, dynamic>{
                  'sets': item.targetSets,
                  'reps_min': item.targetRepsMin,
                  'reps_max': item.targetRepsMax,
                  'weight_kg': item.targetWeightKg,
                  'duration_seconds': item.targetDurationSeconds,
                  'distance_m': item.targetDistanceM,
                  'rpe': item.targetRpe,
                  'rir': item.targetRir,
                },
                sets: _emptySets(item.targetSets, item.trackingType),
              ),
            )
            .toList()
        : exercises
            .asMap()
            .entries
            .map(
              (MapEntry<int, Exercise> entry) => SessionExercise(
                localId: _newLocalId('se'),
                exercise: entry.value,
                position: entry.key,
                trackingType: entry.value.trackingType,
                restSeconds: entry.value.defaultRestSeconds,
                sets: _emptySets(3, entry.value.trackingType),
              ),
            )
            .toList();

    WorkoutSession session = WorkoutSession(
      localId: localId,
      name: name ?? day?.name ?? 'Quick workout',
      status: 'in_progress',
      startedAt: DateTime.now(),
      programId: program?.id,
      dayId: day?.id,
      exercises: sessionExercises,
      isLocalOnly: true,
    );

    await _persist(session);
    state = state.copyWith(session: session, clearError: true);

    // Enrich with server context when we can; failure is not fatal.
    if (_isOnline) {
      try {
        final WorkoutSession remote = await _repository.startRemote(session);
        session = _mergeRemoteContext(session, remote);
        await _persist(session);
        state = state.copyWith(session: session);
      } on ApiException {
        // Offline start is a first-class path, not an error.
      }
    }
    return session;
  }

  /// Copy previous-performance and progression hints onto the local session.
  WorkoutSession _mergeRemoteContext(
      WorkoutSession local, WorkoutSession remote) {
    final Map<String, SessionExercise> byExerciseId = <String, SessionExercise>{
      for (final SessionExercise item in remote.exercises)
        item.exercise.id: item,
    };

    return local.copyWith(
      id: remote.id,
      isLocalOnly: false,
      exercises: local.exercises.map((SessionExercise item) {
        final SessionExercise? match = byExerciseId[item.exercise.id];
        if (match == null) return item;
        return item.copyWith(
          previous: match.previous,
          progressionHint: match.progressionHint,
        );
      }).toList(),
    );
  }

  List<WorkoutSet> _emptySets(int count, String trackingType) {
    return List<WorkoutSet>.generate(
      math.max(1, count),
      (int index) => WorkoutSet(
        localId: _newLocalId('s'),
        setNumber: index + 1,
      ),
    );
  }

  Future<void> _persist(WorkoutSession session) =>
      _repository.saveActiveLocal(session);

  Future<void> _update(WorkoutSession session) async {
    state = state.copyWith(session: session);
    await _persist(session);
  }

  SessionExercise? _exerciseById(String localId) {
    final WorkoutSession? session = state.session;
    if (session == null) return null;
    for (final SessionExercise item in session.exercises) {
      if (item.localId == localId) return item;
    }
    return null;
  }

  Future<void> _replaceExercise(SessionExercise updated) async {
    final WorkoutSession? session = state.session;
    if (session == null) return;
    await _update(
      session.copyWith(
        exercises: session.exercises
            .map((SessionExercise item) =>
                item.localId == updated.localId ? updated : item)
            .toList(),
      ),
    );
  }

  /// Record a set's values and mark it complete, starting the rest timer.
  Future<void> completeSet(
    String exerciseLocalId,
    String setLocalId, {
    double? weightKg,
    int? reps,
    int? durationSeconds,
    double? distanceM,
    double? rpe,
  }) async {
    final SessionExercise? item = _exerciseById(exerciseLocalId);
    if (item == null) return;

    final List<WorkoutSet> sets = item.sets.map((WorkoutSet set) {
      if (set.localId != setLocalId) return set;
      final double? resolvedWeight = weightKg ?? set.weightKg;
      final int? resolvedReps = reps ?? set.reps;
      return set.copyWith(
        weightKg: resolvedWeight,
        reps: resolvedReps,
        durationSeconds: durationSeconds ?? set.durationSeconds,
        distanceM: distanceM ?? set.distanceM,
        rpe: rpe ?? set.rpe,
        isCompleted: true,
        volumeKg: OneRepMax.volume(resolvedWeight, resolvedReps),
        estimated1rmKg: OneRepMax.estimate(resolvedWeight, resolvedReps),
      );
    }).toList();

    await _replaceExercise(item.copyWith(sets: sets));

    if (!item.isWarmUpSet(setLocalId)) {
      _ref.read(restTimerProvider.notifier).start(
            item.restSeconds,
            exerciseName: item.exercise.name,
          );
    }
  }

  /// Edit a set without changing its completion state.
  Future<void> updateSet(
    String exerciseLocalId,
    String setLocalId, {
    double? weightKg,
    int? reps,
    int? durationSeconds,
    double? distanceM,
    double? rpe,
    int? rir,
    String? setType,
    bool? isCompleted,
    String? notes,
  }) async {
    final SessionExercise? item = _exerciseById(exerciseLocalId);
    if (item == null) return;

    final List<WorkoutSet> sets = item.sets.map((WorkoutSet set) {
      if (set.localId != setLocalId) return set;
      final double? resolvedWeight = weightKg ?? set.weightKg;
      final int? resolvedReps = reps ?? set.reps;
      return set.copyWith(
        weightKg: resolvedWeight,
        reps: resolvedReps,
        durationSeconds: durationSeconds ?? set.durationSeconds,
        distanceM: distanceM ?? set.distanceM,
        rpe: rpe ?? set.rpe,
        rir: rir ?? set.rir,
        setType: setType ?? set.setType,
        isCompleted: isCompleted ?? set.isCompleted,
        notes: notes ?? set.notes,
        volumeKg: OneRepMax.volume(resolvedWeight, resolvedReps),
        estimated1rmKg: OneRepMax.estimate(resolvedWeight, resolvedReps),
      );
    }).toList();

    await _replaceExercise(item.copyWith(sets: sets));
  }

  Future<void> addSet(String exerciseLocalId,
      {String setType = 'normal'}) async {
    final SessionExercise? item = _exerciseById(exerciseLocalId);
    if (item == null) return;

    // A new set inherits the last one's load — what the user would type anyway.
    final WorkoutSet? last = item.sets.isEmpty ? null : item.sets.last;
    final List<WorkoutSet> sets = <WorkoutSet>[
      ...item.sets,
      WorkoutSet(
        localId: _newLocalId('s'),
        setNumber: item.sets.length + 1,
        setType: setType,
        weightKg: setType == 'warmup' ? null : last?.weightKg,
      ),
    ];
    await _replaceExercise(item.copyWith(sets: sets));
  }

  Future<void> removeSet(String exerciseLocalId, String setLocalId) async {
    final SessionExercise? item = _exerciseById(exerciseLocalId);
    if (item == null || item.sets.length <= 1) return;

    final List<WorkoutSet> remaining =
        item.sets.where((WorkoutSet set) => set.localId != setLocalId).toList();
    // Renumber so the displayed set numbers stay 1..n.
    final List<WorkoutSet> renumbered = <WorkoutSet>[
      for (int index = 0; index < remaining.length; index++)
        remaining[index].copyWith(setNumber: index + 1),
    ];
    await _replaceExercise(item.copyWith(sets: renumbered));
  }

  Future<void> setExerciseNotes(String exerciseLocalId, String notes) async {
    final SessionExercise? item = _exerciseById(exerciseLocalId);
    if (item == null) return;
    await _replaceExercise(item.copyWith(notes: notes));
  }

  Future<void> addExercise(Exercise exercise) async {
    final WorkoutSession? session = state.session;
    if (session == null) return;

    await _update(
      session.copyWith(
        exercises: <SessionExercise>[
          ...session.exercises,
          SessionExercise(
            localId: _newLocalId('se'),
            exercise: exercise,
            position: session.exercises.length,
            trackingType: exercise.trackingType,
            restSeconds: exercise.defaultRestSeconds,
            sets: _emptySets(3, exercise.trackingType),
          ),
        ],
      ),
    );
  }

  /// Swap the movement while keeping position, rest and logged sets.
  Future<void> replaceExercise(
      String exerciseLocalId, Exercise replacement) async {
    final SessionExercise? item = _exerciseById(exerciseLocalId);
    if (item == null) return;
    await _replaceExercise(
      item.copyWith(
        exercise: replacement,
        trackingType: replacement.trackingType,
        previous: null,
        progressionHint: null,
      ),
    );
  }

  Future<void> removeExercise(String exerciseLocalId) async {
    final WorkoutSession? session = state.session;
    if (session == null) return;

    final List<SessionExercise> remaining = session.exercises
        .where((SessionExercise item) => item.localId != exerciseLocalId)
        .toList();
    await _update(
      session.copyWith(
        exercises: <SessionExercise>[
          for (int index = 0; index < remaining.length; index++)
            remaining[index].copyWith(position: index),
        ],
      ),
    );
  }

  Future<void> reorderExercises(int oldIndex, int newIndex) async {
    final WorkoutSession? session = state.session;
    if (session == null) return;

    final List<SessionExercise> ordered =
        List<SessionExercise>.of(session.exercises);
    final int target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final SessionExercise moved = ordered.removeAt(oldIndex);
    ordered.insert(target, moved);

    await _update(
      session.copyWith(
        exercises: <SessionExercise>[
          for (int index = 0; index < ordered.length; index++)
            ordered[index].copyWith(position: index),
        ],
      ),
    );
  }

  /// Finish the workout: online it goes straight to the API and returns any
  /// personal records; offline it is queued and syncs later.
  Future<WorkoutSession?> finish({String? notes, int? perceivedEffort}) async {
    final WorkoutSession? session = state.session;
    if (session == null) return null;

    state = state.copyWith(isFinishing: true, clearError: true);

    final DateTime completedAt = DateTime.now();
    final WorkoutSession finished = session.copyWith(
      status: 'completed',
      completedAt: completedAt,
      durationSeconds: completedAt.difference(session.startedAt).inSeconds,
      notes: notes,
      perceivedEffort: perceivedEffort,
      totalVolumeKg: session.localVolumeKg,
      totalSets: session.completedSetCount,
    );

    _ref.read(restTimerProvider.notifier).skip();

    if (_isOnline) {
      try {
        final WorkoutSession saved = await _repository.finishRemote(finished);
        await _repository.clearActiveLocal();
        state = ActiveWorkoutState(
          isRestoring: false,
          finishedSession: saved,
          wasQueuedOffline: false,
        );
        return saved;
      } on ApiException catch (error) {
        if (!error.isConnectivity) {
          state =
              state.copyWith(isFinishing: false, errorMessage: error.message);
          return null;
        }
        // Connectivity dropped between the check and the call — fall through.
      }
    }

    await _repository.enqueueFinished(finished);
    await _repository.clearActiveLocal();
    state = ActiveWorkoutState(
      isRestoring: false,
      finishedSession: finished,
      wasQueuedOffline: true,
    );
    return finished;
  }

  Future<void> discard() async {
    final WorkoutSession? session = state.session;
    if (session == null) return;
    _ref.read(restTimerProvider.notifier).skip();
    await _repository.discard(session);
    state = const ActiveWorkoutState(isRestoring: false);
  }

  void clearSummary() =>
      state = state.copyWith(finishedSession: null, wasQueuedOffline: false);
}

/// Convenience predicate used by [ActiveWorkoutController].
extension on SessionExercise {
  bool isWarmUpSet(String setLocalId) {
    for (final WorkoutSet set in sets) {
      if (set.localId == setLocalId) return set.isWarmUp;
    }
    return false;
  }
}

final StateNotifierProvider<ActiveWorkoutController, ActiveWorkoutState>
    activeWorkoutProvider =
    StateNotifierProvider<ActiveWorkoutController, ActiveWorkoutState>(
  (Ref ref) => ActiveWorkoutController(ref),
);

/// Workout history, paged.
final FutureProviderFamily<PagedResult<WorkoutSession>, int>
    workoutHistoryProvider =
    FutureProvider.family<PagedResult<WorkoutSession>, int>(
        (Ref ref, int page) {
  return ref.watch(workoutRepositoryProvider).history(page: page);
});

final FutureProviderFamily<WorkoutSession, String> workoutDetailProvider =
    FutureProvider.family<WorkoutSession, String>((Ref ref, String id) {
  return ref.watch(workoutRepositoryProvider).sessionDetail(id);
});

final FutureProvider<List<PersonalRecord>> personalRecordsProvider =
    FutureProvider<List<PersonalRecord>>((Ref ref) {
  return ref.watch(workoutRepositoryProvider).personalRecords();
});
