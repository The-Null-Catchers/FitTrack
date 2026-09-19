import 'package:fittrack/core/database/active_session_dao.dart';
import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/features/exercises/domain/exercise.dart';
import 'package:fittrack/features/workout/domain/workout_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Covers the "close the app mid-workout and come back" promise.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase database;
  late ActiveSessionDao dao;

  setUp(() async {
    database = await AppDatabase.open(path: inMemoryDatabasePath);
    dao = ActiveSessionDao(database);
  });

  tearDown(() async => database.close());

  WorkoutSession buildSession() {
    const Exercise bench = Exercise(
      id: 'ex-1',
      slug: 'barbell-bench-press',
      name: 'Barbell Bench Press',
      muscleGroup: 'chest',
      equipment: 'barbell',
      difficulty: 'intermediate',
      exerciseType: 'strength',
      trackingType: 'weight_reps',
    );

    return WorkoutSession(
      localId: 'w-1',
      name: 'Push',
      status: 'in_progress',
      startedAt: DateTime(2026, 3, 14, 18, 30),
      exercises: <SessionExercise>[
        SessionExercise(
          localId: 'se-1',
          exercise: bench,
          position: 0,
          trackingType: 'weight_reps',
          restSeconds: 150,
          targetSnapshot: const <String, dynamic>{
            'sets': 4,
            'reps_min': 6,
            'reps_max': 8,
          },
          sets: const <WorkoutSet>[
            WorkoutSet(
              localId: 's-1',
              setNumber: 1,
              weightKg: 80,
              reps: 8,
              isCompleted: true,
              volumeKg: 640,
              estimated1rmKg: 101.33,
            ),
            WorkoutSet(localId: 's-2', setNumber: 2),
          ],
        ),
      ],
    );
  }

  test('an in-progress workout survives being written and read back', () async {
    final WorkoutSession original = buildSession();
    await dao.save(original.localId, original.toJson());

    final Map<String, dynamic>? stored = await dao.read();
    expect(stored, isNotNull);

    final WorkoutSession restored = WorkoutSession.fromJson(stored!);
    expect(restored.localId, 'w-1');
    expect(restored.name, 'Push');
    expect(restored.status, 'in_progress');
    expect(restored.exercises.single.exercise.name, 'Barbell Bench Press');
    expect(restored.exercises.single.sets.length, 2);

    final WorkoutSet first = restored.exercises.single.sets.first;
    expect(first.weightKg, 80);
    expect(first.reps, 8);
    expect(first.isCompleted, isTrue);
    expect(first.volumeKg, 640);

    // The target copied at start time is what the UI shows as "Target".
    expect(restored.exercises.single.targetLabel, '4 × 6-8');
    expect(restored.completedSetCount, 1);
  });

  test('saving again replaces the stored session', () async {
    final WorkoutSession original = buildSession();
    await dao.save(original.localId, original.toJson());
    await dao.save(
      original.localId,
      original.copyWith(name: 'Pull').toJson(),
    );

    expect(WorkoutSession.fromJson((await dao.read())!).name, 'Pull');
  });

  test('clearing removes it, so no phantom workout is offered', () async {
    final WorkoutSession original = buildSession();
    await dao.save(original.localId, original.toJson());
    await dao.clear();

    expect(await dao.read(), isNull);
    expect(await dao.readClientUuid(), isNull);
  });

  test('the client id is the idempotency key the server will see', () async {
    final WorkoutSession original = buildSession();
    await dao.save(original.localId, original.toJson());

    expect(await dao.readClientUuid(), 'w-1');
    expect(original.toSyncPayload()['client_uuid'], 'w-1');
  });
}
