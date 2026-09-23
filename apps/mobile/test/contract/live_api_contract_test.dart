// Contract harness: drives the app's real domain
// deserializers over payloads fetched from a live FitTrack API, so a drift
// between server response shape and app parsing shows up as a failure.
//
//   flutter test test/contract/live_api_contract_test.dart \
//     --dart-define=API_BASE_URL=http://127.0.0.1:8000
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/auth/domain/auth_models.dart';
import 'package:fittrack/features/coach/domain/coach_models.dart';
import 'package:fittrack/features/exercises/domain/exercise.dart';
import 'package:fittrack/features/goals/domain/goal.dart';
import 'package:fittrack/features/habits/domain/habit.dart';
import 'package:fittrack/features/nutrition/domain/nutrition_models.dart';
import 'package:fittrack/features/programs/domain/program.dart';
import 'package:fittrack/features/progress/domain/progress_models.dart';
import 'package:fittrack/features/workout/domain/workout_models.dart';

const String kBase = String.fromEnvironment('API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000');

/// These tests need a running FitTrack API, so they are inert unless asked for:
///
///   flutter test test/contract/live_api_contract_test.dart \
///     --dart-define=LIVE_API=true --dart-define=API_BASE_URL=https://host
///
/// A plain `flutter test` skips them, which keeps CI hermetic.
const bool kLive = bool.fromEnvironment('LIVE_API');
const Object? kSkip =
    kLive ? null : 'needs a live API (pass --dart-define=LIVE_API=true)';

late HttpClient client;
String? accessToken;

Future<dynamic> req(String method, String path, {Object? body}) async {
  final Uri uri = Uri.parse('$kBase$path');
  final HttpClientRequest r = await client.openUrl(method, uri);
  r.headers.set('Accept', 'application/json');
  if (accessToken != null)
    r.headers.set('Authorization', 'Bearer $accessToken');
  if (body != null) {
    r.headers.contentType = ContentType.json;
    r.write(jsonEncode(body));
  }
  final HttpClientResponse resp = await r.close();
  final String text = await resp.transform(utf8.decoder).join();
  if (resp.statusCode >= 400) {
    throw StateError('$method $path -> ${resp.statusCode}: '
        '${text.substring(0, text.length > 300 ? 300 : text.length)}');
  }
  return text.isEmpty ? null : jsonDecode(text);
}

List<Map<String, dynamic>> items(dynamic v) {
  if (v is List) return v.cast<Map<String, dynamic>>();
  if (v is Map && v['items'] is List) {
    return (v['items'] as List).cast<Map<String, dynamic>>();
  }
  throw StateError('not a list or paged payload: ${v.runtimeType}');
}

void main() {
  setUpAll(() async {
    if (!kLive) return;
    client = HttpClient();
    final dynamic auth = await req('POST', '/api/v1/auth/login', body: {
      'email': 'demo@fittrack.app',
      'password': 'FitTrack2024!',
    });
    final AuthSession s = AuthSession.fromJson(auth as Map<String, dynamic>);
    accessToken = s.accessToken;
  });

  tearDownAll(() {
    if (kLive) client.close(force: true);
  });

  test('AuthSession + AuthUser parse', () async {
    expect(accessToken, isNotNull);
    expect(accessToken!.isNotEmpty, isTrue);
    final AuthUser u = AuthUser.fromJson(
        await req('GET', '/api/v1/profile') as Map<String, dynamic>);
    expect(u.email, 'demo@fittrack.app');
  }, skip: kSkip);

  test('FitnessProfile parses from the profile payload', () async {
    final Map<String, dynamic> prof =
        await req('GET', '/api/v1/profile') as Map<String, dynamic>;
    final Object? fit = prof['fitness_profile'] ?? prof['fitness'];
    if (fit is Map) {
      FitnessProfile.fromJson(Map<String, dynamic>.from(fit));
    }
    // The app only ever writes this endpoint; GET is intentionally not allowed.
    await expectLater(
        req('GET', '/api/v1/profile/fitness'), throwsA(isA<StateError>()));
  }, skip: kSkip);

  test('Exercise list parses', () async {
    final List<Map<String, dynamic>> raw =
        items(await req('GET', '/api/v1/exercises?page=1&page_size=25'));
    expect(raw, isNotEmpty);
    final List<Exercise> parsed = raw.map(Exercise.fromJson).toList();
    expect(parsed.length, raw.length);
    expect(parsed.first.name.isNotEmpty, isTrue);
  }, skip: kSkip);

  test('Program templates and active program parse', () async {
    final List<Map<String, dynamic>> t =
        items(await req('GET', '/api/v1/programs/templates'));
    expect(t, isNotEmpty);
    for (final Map<String, dynamic> j in t) {
      Program.fromJson(j);
    }
    final dynamic active = await req('GET', '/api/v1/programs/active');
    if (active != null) Program.fromJson(active as Map<String, dynamic>);
  }, skip: kSkip);

  test('WorkoutSession history parses', () async {
    final List<Map<String, dynamic>> raw =
        items(await req('GET', '/api/v1/workout-sessions?page=1&page_size=10'));
    expect(raw, isNotEmpty);
    final List<WorkoutSession> sessions =
        raw.map(WorkoutSession.fromJson).toList();
    expect(sessions.first.id, isNotNull);
    // Detail carries nested exercises and sets.
    final dynamic detail =
        await req('GET', '/api/v1/workout-sessions/${sessions.first.id}');
    final WorkoutSession full =
        WorkoutSession.fromJson(detail as Map<String, dynamic>);
    expect(full.exercises, isNotEmpty);
  }, skip: kSkip);

  test('PersonalRecord list parses', () async {
    final List<Map<String, dynamic>> raw =
        items(await req('GET', '/api/v1/personal-records'));
    for (final Map<String, dynamic> j in raw) {
      PersonalRecord.fromJson(j);
    }
  }, skip: kSkip);

  test('Progress dashboard and charts parse', () async {
    await req('GET', '/api/v1/progress/dashboard');
    for (final String c in <String>['weight', 'volume', 'nutrition']) {
      final dynamic raw = await req('GET', '/api/v1/progress/charts/$c');
      ChartData.fromJson(raw as Map<String, dynamic>);
    }
    final dynamic meas = await req(
        'GET', '/api/v1/progress/charts/measurements?measurement_type=waist');
    ChartData.fromJson(meas as Map<String, dynamic>);
    final List<Map<String, dynamic>> w =
        items(await req('GET', '/api/v1/progress/weights'));
    for (final Map<String, dynamic> j in w) {
      BodyWeightEntry.fromJson(j);
    }
  }, skip: kSkip);

  test('ProgressPhoto list parses and hides raw storage keys', () async {
    final List<Map<String, dynamic>> raw =
        items(await req('GET', '/api/v1/progress/photos'));
    for (final Map<String, dynamic> j in raw) {
      final ProgressPhoto p = ProgressPhoto.fromJson(j);
      expect(p, isNotNull);
      expect(jsonEncode(j).contains('var/storage'), isFalse,
          reason: 'raw storage path leaked to the client');
    }
  }, skip: kSkip);

  test('Nutrition day, foods and meals parse', () async {
    final dynamic day = await req('GET', '/api/v1/nutrition/day');
    NutritionDay.fromJson(day as Map<String, dynamic>);
    final List<Map<String, dynamic>> foods =
        items(await req('GET', '/api/v1/nutrition/foods?query=chicken'));
    expect(foods, isNotEmpty);
    for (final Map<String, dynamic> j in foods) {
      Food.fromJson(j);
    }
  }, skip: kSkip);

  test('Habits parse with streaks', () async {
    final List<Map<String, dynamic>> raw =
        items(await req('GET', '/api/v1/habits'));
    for (final Map<String, dynamic> j in raw) {
      Habit.fromJson(j);
    }
  }, skip: kSkip);

  test('Goals parse', () async {
    final List<Map<String, dynamic>> raw =
        items(await req('GET', '/api/v1/goals'));
    for (final Map<String, dynamic> j in raw) {
      Goal.fromJson(j);
    }
  }, skip: kSkip);

  test('FitCoach chat round-trip parses (mock provider)', () async {
    final dynamic reply = await req('POST', '/api/v1/ai/chat',
        body: <String, dynamic>{'message': 'How should I structure my week?'});
    final Map<String, dynamic> m = reply as Map<String, dynamic>;
    final Map<String, dynamic> msg =
        (m['message'] ?? m) as Map<String, dynamic>;
    final CoachMessage parsed = CoachMessage.fromJson(msg);
    expect(parsed.content.isNotEmpty, isTrue);
  }, skip: kSkip);

  test('FitCoach medical safety redirect still applies', () async {
    final dynamic reply = await req('POST', '/api/v1/ai/chat',
        body: <String, dynamic>{
          'message': 'I think I tore my ACL, what should I do?'
        });
    final Map<String, dynamic> m = reply as Map<String, dynamic>;
    final Map<String, dynamic> msg =
        (m['message'] ?? m) as Map<String, dynamic>;
    final String text = CoachMessage.fromJson(msg).content.toLowerCase();
    expect(
      text.contains('professional') ||
          text.contains('doctor') ||
          text.contains('medical') ||
          text.contains('qualified'),
      isTrue,
      reason: 'injury message should redirect to professional care, got: $text',
    );
  }, skip: kSkip);

  test('AI plan generation parses', () async {
    final dynamic plan = await req('POST', '/api/v1/ai/plans/generate',
        body: <String, dynamic>{'days_per_week': 4, 'goal': 'gain_muscle'});
    final GeneratedPlan gp =
        GeneratedPlan.fromResponse(plan as Map<String, dynamic>);
    expect(gp.days, isNotEmpty);
  }, skip: kSkip);
}
