import 'package:fittrack/features/exercises/domain/exercise.dart';
import 'package:fittrack/features/workout/domain/workout_models.dart';
import 'package:flutter_test/flutter_test.dart';

const Exercise _bench = Exercise(
  id: 'ex-1',
  slug: 'barbell-bench-press',
  name: 'Barbell Bench Press',
  nameAr: 'ضغط البار المسطح',
  muscleGroup: 'chest',
  equipment: 'barbell',
  difficulty: 'intermediate',
  exerciseType: 'strength',
  trackingType: 'weight_reps',
);

SessionExercise _exercise({
  List<WorkoutSet> sets = const <WorkoutSet>[],
  Map<String, dynamic> target = const <String, dynamic>{},
}) =>
    SessionExercise(
      localId: 'se-1',
      exercise: _bench,
      position: 0,
      trackingType: 'weight_reps',
      restSeconds: 150,
      targetSnapshot: target,
      sets: sets,
    );

void main() {
  group('exercise', () {
    test('uses the Arabic name when the interface is in Arabic', () {
      expect(_bench.displayName('ar'), 'ضغط البار المسطح');
      expect(_bench.displayName('en'), 'Barbell Bench Press');
    });

    test('falls back to the English name when no translation exists', () {
      const Exercise untranslated = Exercise(
        id: 'ex-2',
        slug: 'landmine-press',
        name: 'Landmine Press',
        muscleGroup: 'shoulders',
        equipment: 'barbell',
        difficulty: 'intermediate',
        exerciseType: 'strength',
        trackingType: 'weight_reps',
      );
      expect(untranslated.displayName('ar'), 'Landmine Press');
    });

    test('exposes what a set for it should capture', () {
      expect(_bench.tracksWeight, isTrue);
      expect(_bench.tracksReps, isTrue);
      expect(_bench.tracksDuration, isFalse);
    });
  });

  group('target label', () {
    test('renders a rep range', () {
      expect(
        _exercise(target: const <String, dynamic>{
          'sets': 4,
          'reps_min': 6,
          'reps_max': 8,
        }).targetLabel,
        '4 × 6-8',
      );
    });

    test('collapses a fixed rep count', () {
      expect(
        _exercise(target: const <String, dynamic>{
          'sets': 3,
          'reps_min': 10,
          'reps_max': 10,
        }).targetLabel,
        '3 × 10',
      );
    });

    test('renders seconds for timed work', () {
      expect(
        _exercise(target: const <String, dynamic>{
          'sets': 3,
          'duration_seconds': 45,
        }).targetLabel,
        '3 × 45s',
      );
    });

    test('is absent when the workout was started ad hoc', () {
      expect(_exercise().targetLabel, isNull);
    });
  });

  group('session totals', () {
    test('counts only completed sets', () {
      final WorkoutSession session = WorkoutSession(
        localId: 'w-1',
        name: 'Push',
        status: 'in_progress',
        startedAt: DateTime(2026, 3, 14),
        exercises: <SessionExercise>[
          _exercise(
            sets: const <WorkoutSet>[
              WorkoutSet(
                localId: 's-1',
                setNumber: 1,
                weightKg: 80,
                reps: 8,
                isCompleted: true,
                volumeKg: 640,
              ),
              WorkoutSet(
                localId: 's-2',
                setNumber: 2,
                weightKg: 80,
                reps: 7,
                volumeKg: 560,
              ),
            ],
          ),
        ],
      );

      expect(session.completedSetCount, 1);
      expect(session.plannedSetCount, 2);
      expect(session.localVolumeKg, 640);
    });
  });

  group('sync payload', () {
    test('carries the client id and only sets with values', () {
      final WorkoutSession session = WorkoutSession(
        localId: 'w-offline-1',
        name: 'Push',
        status: 'completed',
        startedAt: DateTime.utc(2026, 3, 14, 18),
        completedAt: DateTime.utc(2026, 3, 14, 19),
        durationSeconds: 3600,
        exercises: <SessionExercise>[
          _exercise(
            sets: const <WorkoutSet>[
              WorkoutSet(
                localId: 's-1',
                setNumber: 1,
                weightKg: 80,
                reps: 8,
                isCompleted: true,
              ),
              // Never touched — must not be sent.
              WorkoutSet(localId: 's-2', setNumber: 2),
            ],
          ),
        ],
      );

      final Map<String, dynamic> payload = session.toSyncPayload();
      expect(payload['client_uuid'], 'w-offline-1');
      expect(payload['finished'], isTrue);
      expect(payload['duration_seconds'], 3600);

      final List<dynamic> exercises = payload['exercises'] as List<dynamic>;
      final Map<String, dynamic> first =
          exercises.single as Map<String, dynamic>;
      expect(first['exercise_id'], 'ex-1');
      expect((first['sets'] as List<dynamic>).length, 1);
    });
  });

  group('round-tripping through local storage', () {
    test('keeps set state intact', () {
      const WorkoutSet original = WorkoutSet(
        localId: 's-1',
        setNumber: 2,
        setType: 'warmup',
        weightKg: 60,
        reps: 10,
        rpe: 7.5,
        isCompleted: true,
        volumeKg: 600,
        estimated1rmKg: 80,
      );

      final WorkoutSet restored = WorkoutSet.fromJson(original.toJson());
      expect(restored.localId, original.localId);
      expect(restored.setType, 'warmup');
      expect(restored.isWarmUp, isTrue);
      expect(restored.weightKg, 60);
      expect(restored.rpe, 7.5);
      expect(restored.volumeKg, 600);
    });
  });
}
