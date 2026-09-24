import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:fittrack/core/demo/demo_api_adapter.dart';
import 'package:fittrack/core/demo/demo_store.dart';
import 'package:fittrack/features/exercises/domain/exercise.dart';
import 'package:fittrack/features/goals/domain/goal.dart';
import 'package:fittrack/features/habits/domain/habit.dart';
import 'package:fittrack/features/nutrition/domain/nutrition_models.dart';
import 'package:fittrack/features/programs/domain/program.dart';
import 'package:fittrack/features/progress/domain/progress_models.dart';
import 'package:fittrack/features/workout/domain/workout_models.dart';

/// Redirects `getApplicationDocumentsDirectory()` to a scratch directory so
/// the demo store writes somewhere disposable during tests.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  late Directory tmp;
  late DemoStore store;
  late Dio dio;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmp = await Directory.systemTemp.createTemp('fittrack_demo_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);

    // Serve the real bundled asset, so these tests exercise the shipped data.
    final ByteData bytes = await rootBundle.load('assets/demo/seed.json');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (ByteData? message) async {
      final String key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'assets/demo/seed.json') return bytes;
      return null;
    });

    store = await DemoStore.open();
    dio = Dio(BaseOptions(
      baseUrl: 'http://demo.local',
      validateStatus: (int? s) => s != null && s < 500,
    ))
      ..httpClientAdapter = DemoApiAdapter(store);
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

  /// Total across all pages, not just the first one.
  Future<int> total(String path) async {
    final Response<dynamic> r = await dio.get<dynamic>(path);
    final dynamic d = r.data;
    if (d is Map && d['meta'] is Map) {
      return (d['meta'] as Map<dynamic, dynamic>)['total'] as int;
    }
    return (d as List<dynamic>).length;
  }

  Future<List<Map<String, dynamic>>> getList(String path,
      [Map<String, dynamic>? q]) async {
    final Response<dynamic> r =
        await dio.get<dynamic>(path, queryParameters: q);
    final dynamic d = r.data;
    final dynamic items = d is Map && d.containsKey('items') ? d['items'] : d;
    return (items as List<dynamic>)
        .map((dynamic e) =>
            Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
        .toList();
  }

  test('signing in needs no network and no real password', () async {
    final Response<dynamic> r = await dio.post<dynamic>(
      '/api/v1/auth/login',
      data: <String, dynamic>{'email': 'anything@example.com', 'password': 'x'},
    );
    expect(r.statusCode, anyOf(200, 201));
    final Map<String, dynamic> body =
        Map<String, dynamic>.from(r.data as Map<dynamic, dynamic>);
    expect(body['access_token'], isNotEmpty);
    expect(body['user'], isNotNull);
  });

  test('exercise library parses and pages', () async {
    final Map<String, dynamic> page1 = await getMap(
        '/api/v1/exercises', <String, dynamic>{'page': 1, 'per_page': 20});
    final Map<String, dynamic> meta =
        Map<String, dynamic>.from(page1['meta'] as Map<dynamic, dynamic>);
    expect(meta['total'], greaterThan(50));
    expect(meta['has_next'], isTrue);

    final List<Exercise> parsed = (page1['items'] as List<dynamic>)
        .map((dynamic e) => Exercise.fromJson(
            Map<String, dynamic>.from(e as Map<dynamic, dynamic>)))
        .toList();
    expect(parsed, hasLength(20));
    expect(parsed.first.name, isNotEmpty);

    final Map<String, dynamic> page2 = await getMap(
        '/api/v1/exercises', <String, dynamic>{'page': 2, 'per_page': 20});
    expect((page2['items'] as List<dynamic>).first,
        isNot(equals(page1['items'] as List<dynamic>)));
  });

  test('exercise search narrows the list', () async {
    final List<Map<String, dynamic>> all =
        await getList('/api/v1/exercises', <String, dynamic>{'per_page': 200});
    final List<Map<String, dynamic>> hits = await getList('/api/v1/exercises',
        <String, dynamic>{'query': 'press', 'per_page': 200});
    expect(hits.length, lessThan(all.length));
    expect(hits, isNotEmpty);
    for (final Map<String, dynamic> e in hits) {
      expect('${e['name']}${e['primary_muscle']}'.toLowerCase(),
          contains('press'));
    }
  });

  test('programs and templates parse', () async {
    final List<Map<String, dynamic>> templates =
        await getList('/api/v1/programs/templates');
    expect(templates, isNotEmpty);
    for (final Map<String, dynamic> t in templates) {
      Program.fromJson(t);
    }
    final Map<String, dynamic> active = await getMap('/api/v1/programs/active');
    expect(Program.fromJson(active).name, isNotEmpty);
  });

  test('workout history and detail parse, with nested sets', () async {
    final List<Map<String, dynamic>> sessions =
        await getList('/api/v1/workout-sessions');
    expect(sessions, isNotEmpty);
    final WorkoutSession first = WorkoutSession.fromJson(sessions.first);
    final Map<String, dynamic> detail =
        await getMap('/api/v1/workout-sessions/${first.id}');
    final WorkoutSession full = WorkoutSession.fromJson(detail);
    expect(full.exercises, isNotEmpty);
  });

  test('a finished workout is saved and survives reopening the store',
      () async {
    final int before = await total('/api/v1/workout-sessions');

    final Response<dynamic> started = await dio.post<dynamic>(
      '/api/v1/workout-sessions',
      data: <String, dynamic>{'name': 'Test session', 'exercises': <dynamic>[]},
    );
    final String id =
        Map<String, dynamic>.from(started.data as Map<dynamic, dynamic>)['id']
            as String;

    await dio.post<dynamic>(
      '/api/v1/workout-sessions/$id/finish',
      data: <String, dynamic>{
        'id': id,
        'name': 'Test session',
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'duration_seconds': 1800,
        'exercises': <dynamic>[
          <String, dynamic>{
            'exercise_id': 'x',
            'sets': <dynamic>[
              <String, dynamic>{'reps': 5, 'weight_kg': 100, 'completed': true},
              <String, dynamic>{'reps': 5, 'weight_kg': 100, 'completed': true},
            ],
          }
        ],
      },
    );

    expect(await total('/api/v1/workout-sessions'), before + 1);
    final List<Map<String, dynamic>> after =
        await getList('/api/v1/workout-sessions');
    expect(after.first['id'], id,
        reason: 'newest workout should lead the history');
    expect(after.first['total_sets'], 2);
    expect(after.first['total_volume_kg'], 1000);

    // Reopen from disk: this is what "survives closing the app" means.
    final DemoStore reopened = await DemoStore.open();
    final Dio dio2 = Dio(BaseOptions(baseUrl: 'http://demo.local'))
      ..httpClientAdapter = DemoApiAdapter(reopened);
    final Response<dynamic> r =
        await dio2.get<dynamic>('/api/v1/workout-sessions');
    final List<dynamic> items =
        Map<String, dynamic>.from(r.data as Map<dynamic, dynamic>)['items']
            as List<dynamic>;
    expect(
        Map<String, dynamic>.from(items.first as Map<dynamic, dynamic>)['id'],
        id);
  });

  test('resetting puts the bundled data back', () async {
    final int before = await total('/api/v1/workout-sessions');
    final Response<dynamic> started = await dio.post<dynamic>(
      '/api/v1/workout-sessions',
      data: <String, dynamic>{'name': 'Throwaway', 'exercises': <dynamic>[]},
    );
    final String id =
        Map<String, dynamic>.from(started.data as Map<dynamic, dynamic>)['id']
            as String;
    await dio.post<dynamic>('/api/v1/workout-sessions/$id/finish',
        data: <String, dynamic>{'id': id, 'exercises': <dynamic>[]});
    expect(await total('/api/v1/workout-sessions'), before + 1);

    await store.reset();
    final DemoStore fresh = await DemoStore.open();
    final Dio dio2 = Dio(BaseOptions(baseUrl: 'http://demo.local'))
      ..httpClientAdapter = DemoApiAdapter(fresh);
    final Response<dynamic> r =
        await dio2.get<dynamic>('/api/v1/workout-sessions');
    final Map<String, dynamic> meta = Map<String, dynamic>.from(
        Map<String, dynamic>.from(r.data as Map<dynamic, dynamic>)['meta']
            as Map<dynamic, dynamic>);
    expect(meta['total'], before);
  });

  test('progress dashboard and charts parse', () async {
    await getMap('/api/v1/progress/dashboard');
    for (final String c in <String>['weight', 'volume', 'nutrition']) {
      ChartData.fromJson(await getMap('/api/v1/progress/charts/$c'));
    }
    final List<Map<String, dynamic>> weights =
        await getList('/api/v1/progress/weights');
    expect(weights, isNotEmpty);
    for (final Map<String, dynamic> w in weights) {
      BodyWeightEntry.fromJson(w);
    }
  });

  test('logging a body weight persists it', () async {
    final int before = (await getList('/api/v1/progress/weights')).length;
    await dio.post<dynamic>('/api/v1/progress/weights', data: <String, dynamic>{
      'weight_kg': 81.5,
      'recorded_on': '2026-09-24'
    });
    final List<Map<String, dynamic>> after =
        await getList('/api/v1/progress/weights');
    expect(after.length, before + 1);
    expect(after.first['weight_kg'], 81.5);
  });

  test('nutrition day parses and a logged meal moves the totals', () async {
    final Map<String, dynamic> day = await getMap('/api/v1/nutrition/day');
    NutritionDay.fromJson(day);
    final num before =
        (day['totals'] as Map<dynamic, dynamic>?)?['calories'] as num? ?? 0;

    await dio.post<dynamic>('/api/v1/nutrition/meals', data: <String, dynamic>{
      'meal_type': 'snack',
      'items': <dynamic>[
        <String, dynamic>{
          'name': 'Test food',
          'calories': 250,
          'protein_g': 20,
          'carbs_g': 30,
          'fat_g': 5
        },
      ],
    });

    final Map<String, dynamic> after = await getMap('/api/v1/nutrition/day');
    final num now =
        (after['totals'] as Map<dynamic, dynamic>)['calories'] as num;
    expect(now, before + 250);
  });

  test('food search parses', () async {
    final List<Map<String, dynamic>> foods = await getList(
        '/api/v1/nutrition/foods', <String, dynamic>{'per_page': 200});
    expect(foods.length, greaterThan(20));
    for (final Map<String, dynamic> f in foods) {
      Food.fromJson(f);
    }
  });

  test('habits parse and checking one advances the streak', () async {
    final List<Map<String, dynamic>> habits = await getList('/api/v1/habits');
    expect(habits, isNotEmpty);
    for (final Map<String, dynamic> h in habits) {
      Habit.fromJson(h);
    }
    final String id = habits.first['id'] as String;
    final Response<dynamic> r = await dio
        .post<dynamic>('/api/v1/habits/$id/log', data: <String, dynamic>{
      'logged_on': DateTime.now().toIso8601String().split('T').first
    });
    final Habit updated = Habit.fromJson(
        Map<String, dynamic>.from(r.data as Map<dynamic, dynamic>));
    expect(updated.currentStreak, greaterThanOrEqualTo(1));
  });

  test('goals parse and can be created', () async {
    final List<Map<String, dynamic>> goals = await getList('/api/v1/goals');
    for (final Map<String, dynamic> g in goals) {
      Goal.fromJson(g);
    }
    final Response<dynamic> r = await dio.post<dynamic>('/api/v1/goals',
        data: <String, dynamic>{'title': 'Demo goal', 'target_value': 100});
    expect(
        Goal.fromJson(
                Map<String, dynamic>.from(r.data as Map<dynamic, dynamic>))
            .id,
        isNotEmpty);
    expect((await getList('/api/v1/goals')).length, goals.length + 1);
  });

  test('FitCoach replies are labelled as demo responses', () async {
    final Response<dynamic> r = await dio.post<dynamic>('/api/v1/ai/chat',
        data: <String, dynamic>{'message': 'How should I structure my week?'});
    final Map<String, dynamic> body =
        Map<String, dynamic>.from(r.data as Map<dynamic, dynamic>);
    final String content = Map<String, dynamic>.from(
        body['message'] as Map<dynamic, dynamic>)['content'] as String;
    expect(content, contains('Demo mode'));
  });

  test('FitCoach still redirects injury questions to a professional', () async {
    for (final String q in <String>[
      'I think I tore my ACL, what should I do?',
      'my shoulder has sharp pain when pressing',
    ]) {
      final Response<dynamic> r = await dio.post<dynamic>('/api/v1/ai/chat',
          data: <String, dynamic>{'message': q});
      final Map<String, dynamic> body =
          Map<String, dynamic>.from(r.data as Map<dynamic, dynamic>);
      final String content = Map<String, dynamic>.from(
          body['message'] as Map<dynamic, dynamic>)['content'] as String;
      expect(content.toLowerCase(),
          anyOf(contains('professional'), contains('doctor')),
          reason: 'injury question must not get training advice: $q');
    }
  });

  test('ordinary soreness is not treated as an injury', () async {
    final Response<dynamic> r = await dio.post<dynamic>('/api/v1/ai/chat',
        data: <String, dynamic>{
          'message': 'muscle soreness after leg day, normal?'
        });
    final String content = Map<String, dynamic>.from(
        Map<String, dynamic>.from(r.data as Map<dynamic, dynamic>)['message']
            as Map<dynamic, dynamic>)['content'] as String;
    expect(content.toLowerCase(), isNot(contains('not able to help')));
  });

  test('generated plans are built from the bundled library', () async {
    final Response<dynamic> r = await dio.post<dynamic>(
        '/api/v1/ai/plans/generate',
        data: <String, dynamic>{'days_per_week': 4, 'goal': 'gain_muscle'});
    final Map<String, dynamic> body =
        Map<String, dynamic>.from(r.data as Map<dynamic, dynamic>);
    final Map<String, dynamic> plan =
        Map<String, dynamic>.from(body['plan'] as Map<dynamic, dynamic>);
    expect(plan['days'], hasLength(4));
    expect(body['disclaimer'], contains('Demo mode'));
  });

  test('a photo upload is stored on disk and listed back', () async {
    final FormData form = FormData.fromMap(<String, dynamic>{
      'file': MultipartFile.fromBytes(
        <int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4],
        filename: 'front.jpg',
      ),
      'taken_on': '2026-09-24',
      'pose': 'front',
    });
    final Response<dynamic> r =
        await dio.post<dynamic>('/api/v1/progress/photos', data: form);
    final Map<String, dynamic> photo =
        Map<String, dynamic>.from(r.data as Map<dynamic, dynamic>);
    final ProgressPhoto parsed = ProgressPhoto.fromJson(photo);
    expect(parsed.url, startsWith('file://'));
    expect(File(Uri.parse(parsed.url!).toFilePath()).existsSync(), isTrue,
        reason: 'the bytes must outlive the picked file');

    final List<Map<String, dynamic>> listed =
        await getList('/api/v1/progress/photos');
    expect(
        listed.map((Map<String, dynamic> e) => e['id']), contains(parsed.id));

    // Deleting removes the bytes too, not just the record.
    await dio.delete<dynamic>('/api/v1/progress/photos/${parsed.id}');
    expect(File(Uri.parse(parsed.url!).toFilePath()).existsSync(), isFalse);
    expect(await getList('/api/v1/progress/photos'), isEmpty);
  });

  test('the weight chart reflects a newly logged weight', () async {
    final String today = DateTime.now().toIso8601String().split('T').first;
    await dio.post<dynamic>('/api/v1/progress/weights',
        data: <String, dynamic>{'weight_kg': 77.7, 'recorded_on': today});
    final ChartData chart =
        ChartData.fromJson(await getMap('/api/v1/progress/charts/weight'));
    expect(chart.series, isNotEmpty);
    final List<SeriesPoint> pts = chart.series.first.points;
    expect(pts.last.y, 77.7,
        reason: 'the chart must show data saved on this device');
  });

  test('the volume chart reflects a finished workout', () async {
    final Response<dynamic> started = await dio
        .post<dynamic>('/api/v1/workout-sessions', data: <String, dynamic>{
      'name': 'Volume test',
      'exercises': <dynamic>[]
    });
    final String id =
        Map<String, dynamic>.from(started.data as Map<dynamic, dynamic>)['id']
            as String;
    await dio.post<dynamic>('/api/v1/workout-sessions/\$id/finish',
        data: <String, dynamic>{
          'id': id,
          'started_at': DateTime.now().toUtc().toIso8601String(),
          'exercises': <dynamic>[
            <String, dynamic>{
              'exercise_id': 'x',
              'sets': <dynamic>[
                <String, dynamic>{
                  'reps': 10,
                  'weight_kg': 60,
                  'completed': true
                },
              ],
            }
          ],
        });
    final ChartData chart =
        ChartData.fromJson(await getMap('/api/v1/progress/charts/volume'));
    expect(chart.series.first.points, isNotEmpty);
    expect(chart.series.first.points.last.y, greaterThanOrEqualTo(600));
  });

  test('export then restore brings local changes back', () async {
    await dio.post<dynamic>('/api/v1/goals', data: <String, dynamic>{
      'title': 'Survives a restore',
      'target_value': 5
    });
    final String backup = await store.exportJson();
    expect(backup, contains('fittrack-demo-export'));

    await store.reset();
    final DemoStore wiped = await DemoStore.open();
    final Dio dioWiped = Dio(BaseOptions(baseUrl: 'http://demo.local'))
      ..httpClientAdapter = DemoApiAdapter(wiped);
    final List<dynamic> afterReset =
        (await dioWiped.get<dynamic>('/api/v1/goals')).data as List<dynamic>;
    expect(
      afterReset.where((dynamic g) =>
          Map<String, dynamic>.from(g as Map<dynamic, dynamic>)['title'] ==
          'Survives a restore'),
      isEmpty,
    );

    await wiped.importJson(backup);
    final DemoStore restored = await DemoStore.open();
    final Dio dioRestored = Dio(BaseOptions(baseUrl: 'http://demo.local'))
      ..httpClientAdapter = DemoApiAdapter(restored);
    final List<dynamic> back =
        (await dioRestored.get<dynamic>('/api/v1/goals')).data as List<dynamic>;
    expect(
      back.where((dynamic g) =>
          Map<String, dynamic>.from(g as Map<dynamic, dynamic>)['title'] ==
          'Survives a restore'),
      isNotEmpty,
    );
  });

  test('restoring a foreign file is refused without destroying data', () async {
    await expectLater(
      store.importJson('{"format":"something-else","overlay":{}}'),
      throwsA(isA<FormatException>()),
    );
    expect(await getList('/api/v1/goals'), isNotEmpty);
  });

  test('unimplemented endpoints fail cleanly rather than crashing', () async {
    final Response<dynamic> r =
        await dio.get<dynamic>('/api/v1/nutrition/foods/barcode/12345');
    expect(r.statusCode, 404);
    final Map<String, dynamic> body =
        Map<String, dynamic>.from(r.data as Map<dynamic, dynamic>);
    expect(body['error'], isNotNull);
  });
}
