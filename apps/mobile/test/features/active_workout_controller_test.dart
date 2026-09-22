import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/exercises/domain/exercise.dart';
import 'package:fittrack/features/programs/domain/program.dart';
import 'package:fittrack/features/workout/application/workout_controller.dart';
import 'package:fittrack/features/workout/data/workout_repository.dart';
import 'package:fittrack/features/workout/domain/workout_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockWorkoutRepository extends Mock implements WorkoutRepository {}

const Exercise _bench = Exercise(
  id: 'ex-bench',
  slug: 'barbell-bench-press',
  name: 'Barbell Bench Press',
  muscleGroup: 'chest',
  equipment: 'barbell',
  difficulty: 'intermediate',
  exerciseType: 'strength',
  trackingType: 'weight_reps',
);

const Exercise _pushUp = Exercise(
  id: 'ex-pushup',
  slug: 'push-up',
  name: 'Push-Up',
  muscleGroup: 'chest',
  equipment: 'bodyweight',
  difficulty: 'beginner',
  exerciseType: 'strength',
  trackingType: 'reps_only',
);

final Program _program = Program(
  id: 'prog-1',
  name: 'Push / Pull / Legs',
  status: 'active',
  isTemplate: false,
  daysPerWeek: 3,
  days: <ProgramDay>[
    const ProgramDay(
      id: 'day-1',
      name: 'Push',
      position: 0,
      isRestDay: false,
      exercises: <DayExercise>[
        DayExercise(
          id: 'de-1',
          exercise: _bench,
          position: 0,
          targetSets: 3,
          restSeconds: 150,
          trackingType: 'weight_reps',
          targetRepsMin: 6,
          targetRepsMax: 8,
        ),
      ],
    ),
  ],
);

void main() {
  setUpAll(() {
    registerFallbackValue(
      WorkoutSession(
        localId: 'fallback',
        name: 'x',
        status: 'in_progress',
        startedAt: DateTime(2026),
      ),
    );
  });

  late _MockWorkoutRepository repository;
  late ProviderContainer container;

  ProviderContainer build() => ProviderContainer(
        overrides: <Override>[
          workoutRepositoryProvider.overrideWithValue(repository),
          // Force the offline path: nothing should need the network.
          isOnlineProvider.overrideWithValue(false),
        ],
      );

  setUp(() {
    repository = _MockWorkoutRepository();
    when(() => repository.readActiveLocal()).thenAnswer((_) async => null);
    when(() => repository.saveActiveLocal(any())).thenAnswer((_) async {});
    when(() => repository.clearActiveLocal()).thenAnswer((_) async {});
    when(() => repository.enqueueFinished(any())).thenAnswer((_) async {});
    container = build();
  });

  tearDown(() => container.dispose());

  Future<ActiveWorkoutController> controller() async {
    final ActiveWorkoutController notifier =
        container.read(activeWorkoutProvider.notifier);
    // Let the restore future settle before the test drives it.
    await Future<void>.delayed(Duration.zero);
    return notifier;
  }

  group('starting a workout', () {
    test('builds the session from the program day, offline', () async {
      final ActiveWorkoutController notifier = await controller();
      final WorkoutSession? session = await notifier.start(
        program: _program,
        day: _program.days.first,
      );

      expect(session, isNotNull);
      expect(session!.name, 'Push');
      expect(session.status, 'in_progress');
      expect(session.exercises.length, 1);
      // Three empty sets, matching the prescription.
      expect(session.exercises.single.sets.length, 3);
      expect(session.exercises.single.targetLabel, '3 × 6-8');
      // Never touched the network.
      verifyNever(() => repository.startRemote(any()));
      // Persisted locally straight away.
      verify(() => repository.saveActiveLocal(any())).called(greaterThan(0));
    });

    test('will not start a second workout while one is in progress', () async {
      final ActiveWorkoutController notifier = await controller();
      final WorkoutSession? first =
          await notifier.start(program: _program, day: _program.days.first);
      final WorkoutSession? second =
          await notifier.start(program: _program, day: _program.days.first);

      expect(second!.localId, first!.localId);
    });

    test('an ad-hoc workout starts from a list of exercises', () async {
      final ActiveWorkoutController notifier = await controller();
      final WorkoutSession? session = await notifier.start(
        name: 'Quick session',
        exercises: <Exercise>[_pushUp],
      );

      expect(session!.name, 'Quick session');
      expect(session.exercises.single.exercise.id, 'ex-pushup');
      expect(session.exercises.single.trackingType, 'reps_only');
    });
  });

  group('logging sets', () {
    test('completing a set records volume and estimated 1RM', () async {
      final ActiveWorkoutController notifier = await controller();
      await notifier.start(program: _program, day: _program.days.first);

      final SessionExercise exercise =
          container.read(activeWorkoutProvider).session!.exercises.single;
      await notifier.completeSet(
        exercise.localId,
        exercise.sets.first.localId,
        weightKg: 80,
        reps: 8,
      );

      final WorkoutSet logged = container
          .read(activeWorkoutProvider)
          .session!
          .exercises
          .single
          .sets
          .first;
      expect(logged.isCompleted, isTrue);
      expect(logged.weightKg, 80);
      expect(logged.volumeKg, 640);
      expect(logged.estimated1rmKg, closeTo(101.33, 0.01));
    });

    test('adding a set carries the previous load forward', () async {
      final ActiveWorkoutController notifier = await controller();
      await notifier.start(program: _program, day: _program.days.first);

      SessionExercise exercise =
          container.read(activeWorkoutProvider).session!.exercises.single;
      await notifier.completeSet(
        exercise.localId,
        exercise.sets.last.localId,
        weightKg: 82.5,
        reps: 6,
      );
      await notifier.addSet(exercise.localId);

      exercise =
          container.read(activeWorkoutProvider).session!.exercises.single;
      expect(exercise.sets.length, 4);
      expect(exercise.sets.last.weightKg, 82.5);
      expect(exercise.sets.last.setNumber, 4);
    });

    test('a warm-up set starts empty rather than inheriting the load',
        () async {
      final ActiveWorkoutController notifier = await controller();
      await notifier.start(program: _program, day: _program.days.first);

      SessionExercise exercise =
          container.read(activeWorkoutProvider).session!.exercises.single;
      await notifier.completeSet(
        exercise.localId,
        exercise.sets.first.localId,
        weightKg: 80,
        reps: 8,
      );
      await notifier.addSet(exercise.localId, setType: 'warmup');

      exercise =
          container.read(activeWorkoutProvider).session!.exercises.single;
      expect(exercise.sets.last.setType, 'warmup');
      expect(exercise.sets.last.weightKg, isNull);
    });

    test('removing a set renumbers the rest', () async {
      final ActiveWorkoutController notifier = await controller();
      await notifier.start(program: _program, day: _program.days.first);

      SessionExercise exercise =
          container.read(activeWorkoutProvider).session!.exercises.single;
      await notifier.removeSet(exercise.localId, exercise.sets.first.localId);

      exercise =
          container.read(activeWorkoutProvider).session!.exercises.single;
      expect(exercise.sets.length, 2);
      expect(
        exercise.sets.map((WorkoutSet set) => set.setNumber).toList(),
        <int>[1, 2],
      );
    });

    test('the last set cannot be removed, so a card is never empty', () async {
      final ActiveWorkoutController notifier = await controller();
      await notifier.start(program: _program, day: _program.days.first);

      SessionExercise exercise =
          container.read(activeWorkoutProvider).session!.exercises.single;
      for (int index = 0; index < 5; index++) {
        exercise =
            container.read(activeWorkoutProvider).session!.exercises.single;
        await notifier.removeSet(exercise.localId, exercise.sets.first.localId);
      }

      expect(
        container
            .read(activeWorkoutProvider)
            .session!
            .exercises
            .single
            .sets
            .length,
        1,
      );
    });
  });

  group('editing the session', () {
    test('replacing an exercise keeps the slot and its logged sets', () async {
      final ActiveWorkoutController notifier = await controller();
      await notifier.start(program: _program, day: _program.days.first);

      final SessionExercise before =
          container.read(activeWorkoutProvider).session!.exercises.single;
      await notifier.replaceExercise(before.localId, _pushUp);

      final SessionExercise after =
          container.read(activeWorkoutProvider).session!.exercises.single;
      expect(after.localId, before.localId);
      expect(after.exercise.id, 'ex-pushup');
      expect(after.trackingType, 'reps_only');
      expect(after.sets.length, before.sets.length);
    });

    test('adding and removing exercises keeps positions contiguous', () async {
      final ActiveWorkoutController notifier = await controller();
      await notifier.start(program: _program, day: _program.days.first);
      await notifier.addExercise(_pushUp);

      WorkoutSession session = container.read(activeWorkoutProvider).session!;
      expect(session.exercises.length, 2);

      await notifier.removeExercise(session.exercises.first.localId);
      session = container.read(activeWorkoutProvider).session!;

      expect(session.exercises.length, 1);
      expect(session.exercises.single.position, 0);
    });

    test('reordering moves an exercise and renumbers positions', () async {
      final ActiveWorkoutController notifier = await controller();
      await notifier.start(program: _program, day: _program.days.first);
      await notifier.addExercise(_pushUp);

      await notifier.reorderExercises(1, 0);

      final WorkoutSession session =
          container.read(activeWorkoutProvider).session!;
      expect(session.exercises.first.exercise.id, 'ex-pushup');
      expect(session.exercises.first.position, 0);
      expect(session.exercises.last.position, 1);
    });
  });

  group('finishing offline', () {
    test('queues the workout and clears the active session', () async {
      final ActiveWorkoutController notifier = await controller();
      await notifier.start(program: _program, day: _program.days.first);

      final SessionExercise exercise =
          container.read(activeWorkoutProvider).session!.exercises.single;
      await notifier.completeSet(
        exercise.localId,
        exercise.sets.first.localId,
        weightKg: 80,
        reps: 8,
      );

      final WorkoutSession? finished = await notifier.finish();

      expect(finished, isNotNull);
      expect(finished!.status, 'completed');
      expect(finished.totalSets, 1);
      expect(finished.totalVolumeKg, 640);
      expect(finished.durationSeconds, isNotNull);

      verify(() => repository.enqueueFinished(any())).called(1);
      verify(() => repository.clearActiveLocal()).called(1);
      verifyNever(() => repository.finishRemote(any()));

      final ActiveWorkoutState state = container.read(activeWorkoutProvider);
      expect(state.session, isNull);
      expect(state.wasQueuedOffline, isTrue);
      expect(state.finishedSession, isNotNull);
    });

    test('discarding removes the workout everywhere', () async {
      final ActiveWorkoutController notifier = await controller();
      await notifier.start(program: _program, day: _program.days.first);
      when(() => repository.discard(any())).thenAnswer((_) async {});

      await notifier.discard();

      verify(() => repository.discard(any())).called(1);
      expect(container.read(activeWorkoutProvider).session, isNull);
    });
  });

  group('resuming', () {
    test('restores a workout stored on the device', () async {
      final WorkoutSession stored = WorkoutSession(
        localId: 'w-stored',
        name: 'Pull',
        status: 'in_progress',
        startedAt: DateTime.now().subtract(const Duration(minutes: 20)),
        exercises: <SessionExercise>[
          SessionExercise(
            localId: 'se-1',
            exercise: _bench,
            position: 0,
            trackingType: 'weight_reps',
            restSeconds: 120,
            sets: const <WorkoutSet>[
              WorkoutSet(
                localId: 's-1',
                setNumber: 1,
                weightKg: 75,
                reps: 10,
                isCompleted: true,
                volumeKg: 750,
              ),
            ],
          ),
        ],
      );

      repository = _MockWorkoutRepository();
      when(() => repository.readActiveLocal()).thenAnswer((_) async => stored);
      when(() => repository.saveActiveLocal(any())).thenAnswer((_) async {});
      container.dispose();
      container = build();

      await controller();

      final ActiveWorkoutState state = container.read(activeWorkoutProvider);
      expect(state.isRestoring, isFalse);
      expect(state.session, isNotNull);
      expect(state.session!.name, 'Pull');
      expect(state.session!.completedSetCount, 1);
    });
  });
}
