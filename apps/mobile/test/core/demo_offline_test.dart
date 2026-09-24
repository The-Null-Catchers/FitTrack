import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fittrack/core/demo/demo_api_adapter.dart';
import 'package:fittrack/core/demo/demo_store.dart';
import 'package:fittrack/features/nutrition/domain/nutrition_models.dart';
import 'package:fittrack/features/progress/domain/progress_models.dart';

/// Redirects `getApplicationDocumentsDirectory()` at a scratch directory.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

/// Covers the promises demo mode makes to the user: that what they log is
/// kept, that the numbers on screen come from what they logged, and that
/// anything the demo cannot actually do says so instead of pretending.
void main() {
  late Directory tmp;
  late DemoStore store;
  late Dio dio;

  String today() => DateTime.now().toIso8601String().split('T').first;

  Dio dioFor(DemoStore s) => Dio(BaseOptions(
        baseUrl: 'http://demo.local',
        // Accept every status so a refusal can be asserted on directly; the
        // real client turns these into ApiException, which is the point.
        validateStatus: (int? code) => code != null,
      ))
        ..httpClientAdapter = DemoApiAdapter(s);

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('fittrack_demo_offline');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);

    final ByteData bytes = await rootBundle.load('assets/demo/seed.json');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
      final String key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'assets/demo/seed.json') return bytes;
      return null;
    });

    store = await DemoStore.open();
    dio = dioFor(store);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<Map<String, dynamic>> getMap(String path,
      [Map<String, dynamic>? q]) async {
    final Response<dynamic> r =
        await dio.get<dynamic>(path, queryParameters: q);
    return Map<String, dynamic>.from(r.data as Map<dynamic, dynamic>);
  }

  /// Log a meal exactly the way the food-search screen does.
  Future<double> logMeal({String? on, int grams = 200}) async {
    final Response<dynamic> foods = await dio.get<dynamic>(
        '/api/v1/nutrition/foods',
        queryParameters: <String, dynamic>{'per_page': 5});
    final Map<String, dynamic> food = Map<String, dynamic>.from(
        ((foods.data as Map<dynamic, dynamic>)['items'] as List<dynamic>).first
            as Map<dynamic, dynamic>);
    await dio.post<dynamic>('/api/v1/nutrition/meals', data: <String, dynamic>{
      'meal_type': 'snack',
      'logged_on': on ?? today(),
      'items': <dynamic>[
        <String, dynamic>{'food_id': food['id'], 'grams': grams},
      ],
    });
    return (food['calories_per_100g'] as num).toDouble() * grams / 100;
  }

  /// Finish a workout the way the active-workout screen does.
  Future<void> finishWorkout({
    required String id,
    required String exerciseId,
    double weight = 100,
    int reps = 5,
  }) async {
    await dio.post<dynamic>(
      '/api/v1/workout-sessions/$id/finish',
      data: <String, dynamic>{
        'name': 'Test session',
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'duration_seconds': 1800,
        'exercises': <dynamic>[
          <String, dynamic>{
            'exercise': <String, dynamic>{
              'id': exerciseId,
              'name': 'Test lift',
              'muscle_group': 'back',
            },
            'sets': <dynamic>[
              <String, dynamic>{
                'weight_kg': weight,
                'reps': reps,
                'is_completed': true,
              },
            ],
          },
        ],
      },
    );
  }

  // --- durability ----------------------------------------------------------

  group('changes survive closing and reopening the app', () {
    test('a logged weight, meal and workout are all still there', () async {
      await dio.post<dynamic>('/api/v1/progress/weights',
          data: <String, dynamic>{'weight_kg': 77.7, 'recorded_on': today()});
      final double kcal = await logMeal();
      await finishWorkout(id: 'restart-1', exerciseId: 'ex-restart');

      // Reopening the store is what the app does on a cold start: same
      // documents directory, brand new object graph.
      final DemoStore reopened = await DemoStore.open();
      dio = dioFor(reopened);

      final List<dynamic> weights =
          (await dio.get<dynamic>('/api/v1/progress/weights')).data
              as List<dynamic>;
      expect(
        weights.any((dynamic w) =>
            (Map<String, dynamic>.from(w as Map<dynamic, dynamic>)['weight_kg']
                as num) ==
            77.7),
        isTrue,
        reason: 'the weight logged before the restart should still be stored',
      );

      final NutritionDay day =
          NutritionDay.fromJson(await getMap('/api/v1/nutrition/day'));
      expect(day.calories.consumed, closeTo(kcal, 0.5));

      final Map<String, dynamic> session =
          await getMap('/api/v1/workout-sessions/restart-1');
      expect(session['id'], 'restart-1');
    });

    test('notification preferences survive a restart', () async {
      await dio.patch<dynamic>('/api/v1/notifications/preferences',
          data: <String, dynamic>{'workout_reminders': false});

      final DemoStore reopened = await DemoStore.open();
      dio = dioFor(reopened);

      final Map<String, dynamic> prefs =
          await getMap('/api/v1/notifications/preferences');
      expect(prefs['workout_reminders'], isFalse);
    });
  });

  // --- derived numbers -----------------------------------------------------

  group('dashboard and charts recalculate from stored data', () {
    test('a logged meal moves the dashboard calorie ring', () async {
      final Map<String, dynamic> before =
          await getMap('/api/v1/progress/dashboard');
      final double beforeKcal =
          ((before['calories'] as Map<dynamic, dynamic>)['consumed'] as num)
              .toDouble();

      final double kcal = await logMeal();

      final Map<String, dynamic> after =
          await getMap('/api/v1/progress/dashboard');
      expect(
        ((after['calories'] as Map<dynamic, dynamic>)['consumed'] as num)
            .toDouble(),
        closeTo(beforeKcal + kcal, 0.5),
      );
    });

    test('finishing a workout moves this week and the volume chart', () async {
      final Map<String, dynamic> before =
          await getMap('/api/v1/progress/dashboard');
      final int doneBefore = (before['weekly_workouts']
          as Map<dynamic, dynamic>)['completed'] as int;

      await finishWorkout(
          id: 'vol-1', exerciseId: 'ex-vol', weight: 100, reps: 5);

      final Map<String, dynamic> after =
          await getMap('/api/v1/progress/dashboard');
      expect(
        (after['weekly_workouts'] as Map<dynamic, dynamic>)['completed'] as int,
        doneBefore + 1,
      );

      final ChartData volume = ChartData.fromJson(await getMap(
          '/api/v1/progress/charts/volume', <String, dynamic>{'range': '7d'}));
      final SeriesPoint todayPoint = volume.series.single.points.lastWhere(
          (SeriesPoint p) => p.x.toIso8601String().startsWith(today()));
      expect(todayPoint.y, greaterThanOrEqualTo(500));
    });

    test('the training overview totals stored sessions, not the capture',
        () async {
      final TrainingOverview before = TrainingOverview.fromJson(await getMap(
          '/api/v1/progress/overview', <String, dynamic>{'range': '30d'}));

      await finishWorkout(
          id: 'ov-1', exerciseId: 'ex-ov', weight: 60, reps: 10);

      final TrainingOverview after = TrainingOverview.fromJson(await getMap(
          '/api/v1/progress/overview', <String, dynamic>{'range': '30d'}));
      expect(after.totalWorkouts, before.totalWorkouts + 1);
      expect(after.totalVolumeKg, greaterThan(before.totalVolumeKg));
      expect(
        after.volumeByMuscleGroup.map((MuscleGroupVolume g) => g.muscleGroup),
        contains('back'),
      );
    });

    test('a new measurement shows up on the measurement chart', () async {
      await dio.post<dynamic>('/api/v1/progress/measurements',
          data: <String, dynamic>{
            'measurement_type': 'waist',
            'value_cm': 70.5,
            'recorded_on': today(),
          });

      final ChartData chart = ChartData.fromJson(await getMap(
          '/api/v1/progress/charts/measurements',
          <String, dynamic>{'range': '30d', 'measurement_type': 'waist'}));
      expect(chart.series.single.points.map((SeriesPoint p) => p.y),
          contains(70.5));
    });

    test('a logged meal shows up on the nutrition chart', () async {
      final double kcal = await logMeal();
      final ChartData chart = ChartData.fromJson(await getMap(
          '/api/v1/progress/charts/nutrition',
          <String, dynamic>{'range': '30d'}));
      final ChartSeries calories =
          chart.series.firstWhere((ChartSeries s) => s.key == 'calories');
      final SeriesPoint point = calories.points.lastWhere(
          (SeriesPoint p) => p.x.toIso8601String().startsWith(today()));
      expect(point.y, closeTo(kcal, 0.5));
    });

    test('deleting a workout takes its volume back off the chart', () async {
      await finishWorkout(
          id: 'del-1', exerciseId: 'ex-del', weight: 100, reps: 10);
      final TrainingOverview withIt = TrainingOverview.fromJson(await getMap(
          '/api/v1/progress/overview', <String, dynamic>{'range': '30d'}));

      await dio.delete<dynamic>('/api/v1/workout-sessions/del-1');

      final TrainingOverview without = TrainingOverview.fromJson(await getMap(
          '/api/v1/progress/overview', <String, dynamic>{'range': '30d'}));
      expect(without.totalWorkouts, withIt.totalWorkouts - 1);
      expect(without.totalVolumeKg, lessThan(withIt.totalVolumeKg));
    });

    test('checking a habit moves the dashboard habit count', () async {
      final List<dynamic> habits =
          (await dio.get<dynamic>('/api/v1/habits')).data as List<dynamic>;
      final String id =
          Map<String, dynamic>.from(habits.first as Map<dynamic, dynamic>)['id']
              as String;

      final Map<String, dynamic> before =
          await getMap('/api/v1/progress/dashboard');
      await dio.post<dynamic>('/api/v1/habits/$id/log',
          data: <String, dynamic>{'logged_on': today()});
      final Map<String, dynamic> after =
          await getMap('/api/v1/progress/dashboard');

      expect(after['habits_completed_today'] as int,
          (before['habits_completed_today'] as int) + 1);
    });

    test('per-exercise progress is derived from the stored sets', () async {
      await finishWorkout(
          id: 'prog-1', exerciseId: 'ex-prog', weight: 80, reps: 5);

      final List<dynamic> trained =
          (await dio.get<dynamic>('/api/v1/progress/exercises')).data
              as List<dynamic>;
      expect(
        trained.map((dynamic e) =>
            Map<String, dynamic>.from(e as Map<dynamic, dynamic>)['id']),
        contains('ex-prog'),
      );

      final ExerciseProgress progress = ExerciseProgress.fromJson(
          await getMap('/api/v1/progress/exercises/ex-prog'));
      expect(progress.points, hasLength(1));
      expect(progress.points.single.totalVolumeKg, 400);
      expect(progress.points.single.bestWeightKg, 80);
    });

    test('an exercise that was never trained is a 404, not an empty chart',
        () async {
      final Response<dynamic> r = await dio
          .get<dynamic>('/api/v1/progress/exercises/never-trained-at-all');
      expect(r.statusCode, 404);
    });

    test('nutrition is kept per day, so yesterday is not today', () async {
      final String yesterday = DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String()
          .split('T')
          .first;
      final double kcal = await logMeal(on: yesterday);

      final NutritionDay todayDay = NutritionDay.fromJson(await getMap(
          '/api/v1/nutrition/day', <String, dynamic>{'on': today()}));
      expect(todayDay.calories.consumed, 0);

      final NutritionDay yesterdayDay = NutritionDay.fromJson(await getMap(
          '/api/v1/nutrition/day', <String, dynamic>{'on': yesterday}));
      expect(yesterdayDay.calories.consumed, closeTo(kcal, 0.5));
    });

    test('water is totalled per day and survives a restart', () async {
      await dio.post<dynamic>('/api/v1/nutrition/water',
          data: <String, dynamic>{'amount_ml': 500, 'logged_on': today()});
      await dio.post<dynamic>('/api/v1/nutrition/water',
          data: <String, dynamic>{'amount_ml': 250, 'logged_on': today()});

      dio = dioFor(await DemoStore.open());
      final NutritionDay day =
          NutritionDay.fromJson(await getMap('/api/v1/nutrition/day'));
      expect(day.waterMl.consumed, 750);
    });

    test('rings carry the profile targets, so they have a denominator',
        () async {
      final NutritionDay day =
          NutritionDay.fromJson(await getMap('/api/v1/nutrition/day'));
      // Taken from the profile in the bundled capture. Without a target the
      // ring has nothing to fill against and renders empty whatever is eaten.
      expect(day.calories.target, 2231);
      expect(day.proteinG.target, 168);
      expect(day.waterMl.target, 2750);

      await logMeal();
      final NutritionDay after =
          NutritionDay.fromJson(await getMap('/api/v1/nutrition/day'));
      expect(after.calories.fraction, greaterThan(0));
      expect(after.calories.remaining, lessThan(2231));
    });
  });

  // --- honesty about what the demo cannot do -------------------------------

  group('nothing claims to have reached a server', () {
    test('sync refuses instead of reporting a successful push', () async {
      final Response<dynamic> r = await dio.post<dynamic>(
        '/api/v1/sync/push',
        data: <String, dynamic>{'operations': <dynamic>[]},
      );
      expect(r.statusCode, 503);
      final Map<String, dynamic> error = Map<String, dynamic>.from(
          (r.data as Map<dynamic, dynamic>)['error'] as Map<dynamic, dynamic>);
      expect(error['code'], 'demo_offline');
      // The old behaviour was a 200 with `applied: 0`, which the sync
      // controller read as "everything went through".
      expect(r.data.toString(), isNot(contains('applied')));
    });

    test('password and account endpoints refuse rather than fake success',
        () async {
      for (final String path in <String>[
        '/api/v1/auth/change-password',
        '/api/v1/auth/forgot-password',
        '/api/v1/auth/reset-password',
        '/api/v1/auth/resend-verification',
      ]) {
        final Response<dynamic> r =
            await dio.post<dynamic>(path, data: <String, dynamic>{});
        expect(r.statusCode, 503, reason: '$path should refuse in demo mode');
        expect(r.data.toString(), isNot(contains('"success":true')));
      }
    });

    test('barcode lookup is a clean 404', () async {
      final Response<dynamic> r =
          await dio.get<dynamic>('/api/v1/nutrition/foods/barcode/123456');
      expect(r.statusCode, 404);
    });
  });

  // --- actions that used to do nothing -------------------------------------

  group('actions actually take effect', () {
    test('favouriting a food sticks, and toggles back', () async {
      final Response<dynamic> foods = await dio.get<dynamic>(
          '/api/v1/nutrition/foods',
          queryParameters: <String, dynamic>{'per_page': 5});
      final Map<String, dynamic> food = Map<String, dynamic>.from(
          ((foods.data as Map<dynamic, dynamic>)['items'] as List<dynamic>)
              .first as Map<dynamic, dynamic>);
      final String id = food['id'] as String;

      final Map<String, dynamic> on = Map<String, dynamic>.from(
          (await dio.post<dynamic>('/api/v1/nutrition/foods/$id/favorite')).data
              as Map<dynamic, dynamic>);
      // The repository reads this field back; a bare {'success': true} left
      // the star switching itself off again.
      expect(on['is_favorite'], isTrue);

      final Map<String, dynamic> off = Map<String, dynamic>.from(
          (await dio.post<dynamic>('/api/v1/nutrition/foods/$id/favorite')).data
              as Map<dynamic, dynamic>);
      expect(off['is_favorite'], isFalse);
    });

    test('acknowledging a record stops it coming back as new', () async {
      final Map<String, dynamic> dash =
          await getMap('/api/v1/progress/dashboard');
      final List<dynamic> recent = dash['recent_records'] as List<dynamic>;
      expect(recent, isNotEmpty);
      final String id =
          Map<String, dynamic>.from(recent.first as Map<dynamic, dynamic>)['id']
              as String;

      await dio.post<dynamic>('/api/v1/personal-records/acknowledge',
          data: <String, dynamic>{
            'ids': <String>[id]
          });

      final Map<String, dynamic> after =
          await getMap('/api/v1/progress/dashboard');
      expect(
        (after['recent_records'] as List<dynamic>).map((dynamic r) =>
            Map<String, dynamic>.from(r as Map<dynamic, dynamic>)['id']),
        isNot(contains(id)),
      );
    });

    test('a notification toggle is saved rather than silently dropped',
        () async {
      final Map<String, dynamic> updated = Map<String, dynamic>.from((await dio
              .patch<dynamic>('/api/v1/notifications/preferences',
                  data: <String, dynamic>{'habit_reminders': false}))
          .data as Map<dynamic, dynamic>);
      expect(updated['habit_reminders'], isFalse);
      // Other preferences must survive a partial update.
      expect(updated['workout_reminders'], isTrue);

      final Map<String, dynamic> read =
          await getMap('/api/v1/notifications/preferences');
      expect(read['habit_reminders'], isFalse);
    });
  });

  // --- export, restore, reset ----------------------------------------------

  group('export, restore and reset', () {
    test('an export restores the data it captured', () async {
      await dio.post<dynamic>('/api/v1/progress/weights',
          data: <String, dynamic>{'weight_kg': 64.2, 'recorded_on': today()});
      final String backup = await store.exportJson();

      // Change things after the backup was taken.
      await dio.post<dynamic>('/api/v1/progress/weights',
          data: <String, dynamic>{'weight_kg': 99.9, 'recorded_on': today()});

      await store.importJson(backup);
      dio = dioFor(await DemoStore.open());

      final List<dynamic> weights =
          (await dio.get<dynamic>('/api/v1/progress/weights')).data
              as List<dynamic>;
      final Iterable<num> values = weights.map((dynamic w) =>
          Map<String, dynamic>.from(w as Map<dynamic, dynamic>)['weight_kg']
              as num);
      expect(values, contains(64.2));
      expect(values, isNot(contains(99.9)),
          reason: 'a restore should replace later changes, not merge them');
    });

    test('restoring a file that is not ours leaves the data alone', () async {
      await dio.post<dynamic>('/api/v1/progress/weights',
          data: <String, dynamic>{'weight_kg': 71.3, 'recorded_on': today()});

      await expectLater(
        store.importJson(jsonEncode(<String, dynamic>{'hello': 'world'})),
        throwsA(isA<FormatException>()),
      );

      // Still intact, both in memory and on disk.
      dio = dioFor(await DemoStore.open());
      final List<dynamic> weights =
          (await dio.get<dynamic>('/api/v1/progress/weights')).data
              as List<dynamic>;
      expect(
        weights.map((dynamic w) =>
            Map<String, dynamic>.from(w as Map<dynamic, dynamic>)['weight_kg']),
        contains(71.3),
      );
    });

    test('reset puts the bundled data back and clears local changes', () async {
      final int seeded = ((await dio.get<dynamic>('/api/v1/progress/weights'))
              .data as List<dynamic>)
          .length;
      await dio.post<dynamic>('/api/v1/progress/weights',
          data: <String, dynamic>{'weight_kg': 55.5, 'recorded_on': today()});
      await logMeal();

      await store.reset();
      dio = dioFor(await DemoStore.open());

      final List<dynamic> weights =
          (await dio.get<dynamic>('/api/v1/progress/weights')).data
              as List<dynamic>;
      expect(weights, hasLength(seeded));
      expect(
        weights.map((dynamic w) =>
            Map<String, dynamic>.from(w as Map<dynamic, dynamic>)['weight_kg']),
        isNot(contains(55.5)),
      );

      final NutritionDay day =
          NutritionDay.fromJson(await getMap('/api/v1/nutrition/day'));
      expect(day.calories.consumed, 0);
    });

    test('a truncated state file falls back to the seed instead of crashing',
        () async {
      await dio.post<dynamic>('/api/v1/progress/weights',
          data: <String, dynamic>{'weight_kg': 60.1, 'recorded_on': today()});

      final File state = File('${tmp.path}/fittrack_demo_state.json');
      expect(state.existsSync(), isTrue);
      await state.writeAsString('{"weights": [truncated');

      final DemoStore reopened = await DemoStore.open();
      dio = dioFor(reopened);
      final List<dynamic> weights =
          (await dio.get<dynamic>('/api/v1/progress/weights')).data
              as List<dynamic>;
      expect(weights, isNotEmpty);
    });
  });
}
