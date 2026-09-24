import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'demo_analytics.dart';
import 'demo_store.dart';

/// Serves the FitTrack API from bundled data, with no network involved.
///
/// This sits under Dio as the transport, so every repository, controller and
/// screen above it runs exactly as it does online — the same requests go out,
/// the same JSON shapes come back. That is deliberate: demo mode should
/// exercise the real app, not a parallel one, and the online stack stays
/// untouched for future work.
///
/// Writes go to [DemoStore], which persists them to the app's documents
/// directory, so changes survive closing and reopening the app.
class DemoApiAdapter implements HttpClientAdapter {
  DemoApiAdapter(this._store, {String Function()? localeCode})
      : _derived = DemoAnalytics(_store),
        _localeCode = localeCode ?? _defaultLocale;

  /// Which language the canned coach replies answer in. Supplied by the app
  /// from the user's chosen locale; defaults to English in tests.
  final String Function() _localeCode;

  static String _defaultLocale() => 'en';

  bool get _isArabic => _localeCode().toLowerCase().startsWith('ar');

  final DemoStore _store;

  /// Every figure the screens show is recomputed from stored data by this.
  final DemoAnalytics _derived;

  static const String kDemoNote =
      'Demo mode — this is a stored sample reply, not a live AI response.';

  static const String kDemoNoteAr =
      'الوضع التجريبي — هذا ردّ محفوظ مسبقًا، وليس ردًّا مباشرًا من الذكاء الاصطناعي.';

  /// The label appended to every canned reply, in the reader's language.
  String get _note => _isArabic ? kDemoNoteAr : kDemoNote;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final String method = options.method.toUpperCase();
    final String path = options.uri.path;
    final Map<String, String> query = options.uri.queryParameters;

    // Photo uploads arrive as multipart, not JSON. Handle them before the
    // stream is consumed, copying the picked file into app storage so it
    // outlives the pick and survives restarts.
    if (options.data is FormData) {
      try {
        // Dio has already finalized the FormData by the time an adapter runs,
        // so the parts have to come from the encoded stream, not the objects.
        return _json(
            await _saveUpload(
              await _collect(requestStream ?? const Stream<Uint8List>.empty()),
              options.contentType ?? '',
            ),
            201);
      } on _DemoError catch (e) {
        return _json(<String, dynamic>{
          'error': <String, dynamic>{
            'code': e.code,
            'message': e.message,
            'details': <String, dynamic>{},
            'request_id': 'demo',
          }
        }, e.status);
      }
    }

    final dynamic body = await _readBody(options, requestStream);

    try {
      final dynamic result = await _route(method, path, query, body);
      if (result == null) return _json(<String, dynamic>{}, 204);
      return _json(result, method == 'POST' ? 201 : 200);
    } on _DemoError catch (e) {
      return _json(<String, dynamic>{
        'error': <String, dynamic>{
          'code': e.code,
          'message': e.message,
          'details': <String, dynamic>{},
          'request_id': 'demo',
        }
      }, e.status);
    }
  }

  @override
  void close({bool force = false}) {}

  // --- plumbing ------------------------------------------------------------

  Future<dynamic> _readBody(
      RequestOptions options, Stream<Uint8List>? stream) async {
    if (stream == null) {
      final dynamic d = options.data;
      if (d is Map || d is List) return d;
      if (d is String && d.isNotEmpty) {
        try {
          return jsonDecode(d);
        } on FormatException {
          return null;
        }
      }
      return null;
    }
    final List<int> bytes = <int>[];
    await for (final Uint8List chunk in stream) {
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bytes));
    } on Object {
      return null;
    }
  }

  /// Copy an uploaded photo into the app's own storage and record it.
  ///
  /// The picked file lives in a cache the OS may clear, so the bytes are
  /// copied into the documents directory, which survives app restarts, phone
  /// restarts and app updates.
  Future<Map<String, dynamic>> _saveUpload(
    List<int> bytes,
    String contentType,
  ) async {
    final _Multipart parsed = _Multipart.parse(bytes, contentType);
    if (parsed.fileBytes == null) {
      throw _DemoError(400, 'validation_error', 'No file in the upload');
    }
    final Directory dir =
        Directory('${(await getApplicationDocumentsDirectory()).path}/photos');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final String id = _id();
    final String name = parsed.fileName ?? 'photo.jpg';
    final String ext = name.contains('.') ? name.split('.').last : 'jpg';
    final File dest = File('${dir.path}/$id.$ext');
    await dest.writeAsBytes(parsed.fileBytes!, flush: true);

    final Map<String, String> fields = parsed.fields;
    final Map<String, dynamic> photo = <String, dynamic>{
      'id': id,
      'taken_on': fields['taken_on'] ?? _today(),
      'pose': fields['pose'] ?? 'front',
      // A file:// URL: the image widget renders these from disk rather than
      // over the network.
      'url': dest.uri.toString(),
      'thumbnail_url': dest.uri.toString(),
      'weight_kg': double.tryParse(fields['weight_kg'] ?? ''),
      'note': fields['note'],
    };
    await _store.putList(
        'photos', <Map<String, dynamic>>[photo, ..._store.list('photos')]);
    return photo;
  }

  Future<List<int>> _collect(Stream<List<int>> stream) async {
    final List<int> out = <int>[];
    await for (final List<int> chunk in stream) {
      out.addAll(chunk);
    }
    return out;
  }

  ResponseBody _json(dynamic payload, int status) => ResponseBody.fromString(
        jsonEncode(payload),
        status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[
            'application/json; charset=utf-8'
          ],
        },
      );

  Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  int _int(Map<String, String> q, String key, int fallback) =>
      int.tryParse(q[key] ?? '') ?? fallback;

  String _id() => 'demo-${DateTime.now().microsecondsSinceEpoch}';

  String _today() => DateTime.now().toIso8601String().split('T').first;

  String _now() => DateTime.now().toUtc().toIso8601String();

  // --- routing -------------------------------------------------------------

  Future<dynamic> _route(
    String method,
    String path,
    Map<String, String> q,
    dynamic body,
  ) async {
    final List<String> seg =
        path.split('/').where((String s) => s.isNotEmpty).toList();
    // strip /api/v1
    final List<String> p = seg.length >= 2 ? seg.sublist(2) : <String>[];
    final String head = p.isEmpty ? '' : p.first;

    switch (head) {
      case 'auth':
        return _auth(method, p, body);
      case 'profile':
        return _profile(method, p, body);
      case 'exercises':
        return _exercises(method, p, q);
      case 'programs':
        return _programs(method, p, body);
      case 'workout-sessions':
        return _workouts(method, p, q, body);
      case 'personal-records':
        return _personalRecords(method, p, body);
      case 'progress':
        return _progress(method, p, q, body);
      case 'nutrition':
        return _nutrition(method, p, q, body);
      case 'habits':
        return _habits(method, p, body);
      case 'goals':
        return _goals(method, p, body);
      case 'ai':
        return _ai(method, p, body);
      case 'notifications':
        return _notifications(method, p, body);
      case 'sync':
        // There is no server to sync with, and claiming otherwise would tell
        // the user their data left the device when it did not. Refuse loudly:
        // demo changes are already durable in the local store, so there is
        // nothing to push and nothing to lose.
        throw _DemoError(
          503,
          'demo_offline',
          'Sync is unavailable in demo mode. Changes are saved on this device '
              'only.',
        );
      default:
        throw _DemoError(404, 'not_found', 'No demo data for $path');
    }
  }

  // --- auth ----------------------------------------------------------------

  Future<dynamic> _auth(String method, List<String> p, dynamic body) async {
    final String sub = p.length > 1 ? p[1] : '';
    switch (sub) {
      case 'login':
      case 'register':
      case 'refresh':
        return <String, dynamic>{
          'access_token': 'demo-access-token',
          'refresh_token': 'demo-refresh-token',
          'token_type': 'bearer',
          'expires_in': 900,
          'refresh_expires_at': DateTime.now()
              .add(const Duration(days: 60))
              .toUtc()
              .toIso8601String(),
          'user': _store.map('profile'),
        };
      case 'sessions':
        if (method == 'DELETE') return null;
        return <dynamic>[
          <String, dynamic>{
            'id': 'demo-session',
            'device': 'This device',
            'created_at': _now(),
            'last_seen_at': _now(),
            'current': true,
          }
        ];
      case 'logout':
        // Nothing to revoke: the demo never held a real session.
        return <String, dynamic>{'success': true, 'message': 'Signed out.'};
      case 'change-password':
      case 'forgot-password':
      case 'reset-password':
      case 'resend-verification':
        // These need an account server. Reporting success would tell the user
        // their password changed when nothing happened.
        throw _DemoError(
          503,
          'demo_offline',
          'Account and password changes need a server, which demo mode does '
              'not have.',
        );
      case 'delete-account':
        await _store.reset();
        return <String, dynamic>{
          'success': true,
          'message': 'Demo data cleared.'
        };
      default:
        throw _DemoError(404, 'not_found', 'No demo route for auth/$sub');
    }
  }

  // --- profile -------------------------------------------------------------

  Future<dynamic> _profile(String method, List<String> p, dynamic body) async {
    final String sub = p.length > 1 ? p[1] : '';
    if (sub.isEmpty) {
      if (method == 'PATCH') {
        final Map<String, dynamic> profile = Map<String, dynamic>.from(
            _store.map('profile') ?? <String, dynamic>{});
        profile.addAll(_asMap(body));
        await _store.put('profile', profile);
        return profile;
      }
      return _store.map('profile');
    }
    if (sub == 'fitness') {
      final Map<String, dynamic> profile = Map<String, dynamic>.from(
          _store.map('profile') ?? <String, dynamic>{});
      final Map<String, dynamic> fitness =
          Map<String, dynamic>.from(_asMap(profile['fitness_profile']))
            ..addAll(_asMap(body));
      profile['fitness_profile'] = fitness;
      await _store.put('profile', profile);
      return fitness;
    }
    if (sub == 'onboarding') {
      final Map<String, dynamic> profile = Map<String, dynamic>.from(
          _store.map('profile') ?? <String, dynamic>{});
      profile['onboarding_completed'] = true;
      await _store.put('profile', profile);
      return profile;
    }
    if (sub == 'nutrition-targets') {
      final Map<String, dynamic> profile = Map<String, dynamic>.from(
          _store.map('profile') ?? <String, dynamic>{});
      if (p.length > 2 && p[2] == 'estimate') {
        return _asMap(profile['nutrition_targets']);
      }
      final Map<String, dynamic> targets =
          Map<String, dynamic>.from(_asMap(profile['nutrition_targets']))
            ..addAll(_asMap(body));
      profile['nutrition_targets'] = targets;
      await _store.put('profile', profile);
      return targets;
    }
    return _store.map('profile');
  }

  // --- exercises -----------------------------------------------------------

  dynamic _exercises(String method, List<String> p, Map<String, String> q) {
    if (p.length > 1 && p[1] == 'filters')
      return _store.value('exercise_filters');
    if (p.length > 1) {
      final Map<String, dynamic>? detail =
          _asMap(_store.map('exercise_details'))[p[1]] as Map<String, dynamic>?;
      if (detail != null) return detail;
      final Map<String, dynamic> found = _store.list('exercises').firstWhere(
            (Map<String, dynamic> e) => e['id'] == p[1],
            orElse: () => <String, dynamic>{},
          );
      if (found.isEmpty) throw _DemoError(404, 'not_found', 'Unknown exercise');
      return found;
    }

    List<Map<String, dynamic>> items = _store.list('exercises');
    final String search =
        (q['query'] ?? q['search'] ?? '').trim().toLowerCase();
    if (search.isNotEmpty) {
      items = items
          .where((Map<String, dynamic> e) =>
              '${e['name']}'.toLowerCase().contains(search) ||
              '${e['primary_muscle']}'.toLowerCase().contains(search))
          .toList();
    }
    for (final String key in <String>[
      'muscle_group',
      'primary_muscle',
      'equipment',
      'difficulty',
      'category'
    ]) {
      final String? want = q[key];
      if (want == null || want.isEmpty) continue;
      items = items.where((Map<String, dynamic> e) {
        final dynamic v = e[key] ?? e['primary_muscle'];
        if (v is List) return v.map((dynamic x) => '$x').contains(want);
        return '$v' == want;
      }).toList();
    }
    return _store.paged(items,
        page: _int(q, 'page', 1), perPage: _int(q, 'per_page', 20));
  }

  // --- programs ------------------------------------------------------------

  Future<dynamic> _programs(String method, List<String> p, dynamic body) async {
    final String sub = p.length > 1 ? p[1] : '';
    if (sub == 'templates') return _store.value('program_templates');
    if (sub == 'active') return _store.value('active_program');

    if (sub.isEmpty) {
      if (method == 'POST') {
        final Map<String, dynamic> created = <String, dynamic>{
          ..._asMap(body),
          'id': _id(),
          'created_at': _now(),
          'is_active': false,
          'days': _asMap(body)['days'] ?? <dynamic>[],
        };
        final List<Map<String, dynamic>> all = _store.list('programs')
          ..add(created);
        await _store.putList('programs', all);
        return created;
      }
      return _store.value('programs');
    }

    // /programs/{id}[/action]
    final String id = sub;
    final String action = p.length > 2 ? p[2] : '';
    final List<Map<String, dynamic>> all = _store.list('programs');
    final int idx = all.indexWhere((Map<String, dynamic> e) => e['id'] == id);

    if (action == 'activate') {
      for (int i = 0; i < all.length; i++) {
        all[i]['is_active'] = all[i]['id'] == id;
      }
      await _store.putList('programs', all);
      if (idx >= 0) await _store.put('active_program', all[idx]);
      return idx >= 0 ? all[idx] : <String, dynamic>{};
    }
    if (action == 'archive') {
      if (idx >= 0) {
        all[idx]['is_active'] = false;
        all[idx]['archived'] = true;
        await _store.putList('programs', all);
      }
      return idx >= 0 ? all[idx] : <String, dynamic>{};
    }
    if (action == 'duplicate') {
      if (idx < 0) throw _DemoError(404, 'not_found', 'Unknown program');
      final Map<String, dynamic> copy = <String, dynamic>{
        ...all[idx],
        'id': _id(),
        'name': '${all[idx]['name']} (copy)',
        'is_active': false,
      };
      await _store.putList('programs', <Map<String, dynamic>>[...all, copy]);
      return copy;
    }

    if (method == 'DELETE') {
      all.removeWhere((Map<String, dynamic> e) => e['id'] == id);
      await _store.putList('programs', all);
      return null;
    }
    if (method == 'PATCH' && idx >= 0) {
      all[idx] = <String, dynamic>{...all[idx], ..._asMap(body)};
      await _store.putList('programs', all);
      return all[idx];
    }
    if (idx >= 0) return all[idx];

    final Map<String, dynamic>? active = _store.map('active_program');
    if (active != null && active['id'] == id) return active;
    final List<Map<String, dynamic>> templates =
        _store.list('program_templates');
    final Map<String, dynamic> t = templates.firstWhere(
      (Map<String, dynamic> e) => e['id'] == id,
      orElse: () => <String, dynamic>{},
    );
    if (t.isEmpty) throw _DemoError(404, 'not_found', 'Unknown program');
    return t;
  }

  // --- workouts ------------------------------------------------------------

  Future<dynamic> _workouts(
    String method,
    List<String> p,
    Map<String, String> q,
    dynamic body,
  ) async {
    if (p.length >= 4 && p[1] == 'exercises' && p[3] == 'previous') {
      final String exerciseId = p[2];
      for (final Map<String, dynamic> s in _store.list('workout_sessions')) {
        final Map<String, dynamic>? detail =
            _asMap(_store.map('session_details'))[s['id']]
                as Map<String, dynamic>?;
        if (detail == null) continue;
        for (final dynamic e
            in (detail['exercises'] as List<dynamic>? ?? <dynamic>[])) {
          final Map<String, dynamic> ex = _asMap(e);
          if (ex['exercise_id'] == exerciseId ||
              _asMap(ex['exercise'])['id'] == exerciseId) {
            return <String, dynamic>{
              'performed_at': detail['started_at'] ?? detail['completed_at'],
              'sets': ex['sets'] ?? <dynamic>[],
            };
          }
        }
      }
      return null; // 204 — the app treats "no previous performance" as fine
    }

    final String sub = p.length > 1 ? p[1] : '';
    if (sub.isEmpty) {
      if (method == 'POST') {
        final Map<String, dynamic> started = <String, dynamic>{
          ..._asMap(body),
          'id': _asMap(body)['id'] ?? _id(),
          'started_at': _asMap(body)['started_at'] ?? _now(),
          'completed_at': null,
          'exercises': _asMap(body)['exercises'] ?? <dynamic>[],
        };
        return started;
      }
      final List<Map<String, dynamic>> all = _store.list('workout_sessions');
      return _store.paged(all,
          page: _int(q, 'page', 1), perPage: _int(q, 'per_page', 20));
    }

    final String id = sub;
    final String action = p.length > 2 ? p[2] : '';

    if (action == 'finish') {
      final Map<String, dynamic> finished = <String, dynamic>{
        ..._asMap(body),
        'id': id,
        'completed_at': _now(),
      };
      final List<Map<String, dynamic>> all = _store.list('workout_sessions');
      all.removeWhere((Map<String, dynamic> e) => e['id'] == id);
      // Newest first, matching the server's history ordering.
      all.insert(0, _summarise(finished));
      await _store.putList('workout_sessions', all);
      await _store.putInMap('session_details', id, finished);
      return finished;
    }
    if (action == 'discard') {
      return <String, dynamic>{'success': true};
    }
    if (method == 'DELETE') {
      final List<Map<String, dynamic>> all = _store.list('workout_sessions')
        ..removeWhere((Map<String, dynamic> e) => e['id'] == id);
      await _store.putList('workout_sessions', all);
      final Map<String, dynamic> details = Map<String, dynamic>.from(
          _store.map('session_details') ?? <String, dynamic>{})
        ..remove(id);
      await _store.put('session_details', details);
      return null;
    }

    final Map<String, dynamic>? detail =
        _asMap(_store.map('session_details'))[id] as Map<String, dynamic>?;
    if (detail != null) return detail;
    final Map<String, dynamic> found =
        _store.list('workout_sessions').firstWhere(
              (Map<String, dynamic> e) => e['id'] == id,
              orElse: () => <String, dynamic>{},
            );
    if (found.isEmpty) throw _DemoError(404, 'not_found', 'Unknown session');
    return found;
  }

  /// Trim a finished session down to the fields the history list shows.
  Map<String, dynamic> _summarise(Map<String, dynamic> full) {
    final List<dynamic> exercises =
        full['exercises'] as List<dynamic>? ?? <dynamic>[];
    int sets = 0;
    double volume = 0;
    for (final dynamic e in exercises) {
      final List<dynamic> ss =
          _asMap(e)['sets'] as List<dynamic>? ?? <dynamic>[];
      for (final dynamic s in ss) {
        final Map<String, dynamic> set = _asMap(s);
        // The payloads use `is_completed`; checking only `completed` counted
        // sets the user had skipped towards the session's volume.
        if (!DemoAnalytics.setCounts(set)) continue;
        sets += 1;
        volume += DemoAnalytics.setVolume(set);
      }
    }
    return <String, dynamic>{
      'id': full['id'],
      'name': full['name'] ?? 'Workout',
      'started_at': full['started_at'],
      'completed_at': full['completed_at'],
      'duration_seconds': full['duration_seconds'],
      'total_sets': sets,
      'total_volume_kg': volume,
      'exercise_count': exercises.length,
    };
  }

  // --- personal records ----------------------------------------------------

  Future<dynamic> _personalRecords(
      String method, List<String> p, dynamic body) async {
    if (p.length > 1 && p[1] == 'acknowledge') {
      // Without storing this, every record stays "new" and the celebration
      // sheet reappears after each workout.
      final Set<String> ids =
          ((_asMap(body)['ids'] as List<dynamic>?) ?? <dynamic>[])
              .map((dynamic e) => '$e')
              .toSet();
      final List<Map<String, dynamic>> all = _store.list('personal_records');
      for (int i = 0; i < all.length; i++) {
        if (ids.contains('${all[i]['id']}')) {
          all[i] = <String, dynamic>{...all[i], 'acknowledged_at': _now()};
        }
      }
      await _store.putList('personal_records', all);
      return <String, dynamic>{'acknowledged': ids.length};
    }
    return _store.value('personal_records');
  }

  // --- notifications -------------------------------------------------------

  /// Notification preferences, stored locally.
  ///
  /// A PATCH used to be answered with the unchanged defaults, so every toggle
  /// silently reverted on the next read.
  Future<dynamic> _notifications(
      String method, List<String> p, dynamic body) async {
    const Map<String, dynamic> defaults = <String, dynamic>{
      'workout_reminders': true,
      'habit_reminders': true,
      'weekly_summary': true,
      'quiet_hours_start': null,
      'quiet_hours_end': null,
    };
    final Map<String, dynamic> current = <String, dynamic>{
      ...defaults,
      ..._asMap(_store.map('notification_prefs')),
    };
    if (method == 'PATCH' || method == 'PUT' || method == 'POST') {
      final Map<String, dynamic> next = <String, dynamic>{
        ...current,
        ..._asMap(body),
      };
      await _store.put('notification_prefs', next);
      return next;
    }
    return current;
  }

  // --- progress ------------------------------------------------------------

  Future<dynamic> _progress(
    String method,
    List<String> p,
    Map<String, String> q,
    dynamic body,
  ) async {
    final String sub = p.length > 1 ? p[1] : '';
    switch (sub) {
      case 'dashboard':
        // Rebuilt on every request from stored workouts, weights, meals,
        // habits and goals — never read back from the capture.
        return _derived.dashboard();
      case 'overview':
        return _derived.overview(q['range'] ?? '30d');
      case 'charts':
        final String kind = p.length > 2 ? p[2] : 'weight';
        final String range = q['range'] ?? '30d';
        switch (kind) {
          case 'weight':
            return _derived.weightChart(range);
          case 'volume':
            return _derived.volumeChart(range);
          case 'nutrition':
            return _derived.nutritionChart(range);
          case 'measurements':
            return _derived.measurementChart(range, q['measurement_type']);
          default:
            throw _DemoError(404, 'not_found', 'No demo chart for $kind');
        }
      case 'exercises':
        if (p.length > 2) {
          final Map<String, dynamic>? progress =
              _derived.exerciseProgress(p[2], q['range'] ?? '6m');
          if (progress == null) {
            throw _DemoError(404, 'not_found',
                'No stored sessions include that exercise yet');
          }
          return progress;
        }
        return _derived.trainedExercises();
      case 'photos':
        if (p.length > 2 && p[2] == 'compare') {
          final List<Map<String, dynamic>> all = _store.list('photos');
          return <String, dynamic>{
            'before': all.isNotEmpty ? all.last : null,
            'after': all.isNotEmpty ? all.first : null,
          };
        }
        if (method == 'DELETE' && p.length > 2) {
          final List<Map<String, dynamic>> all = _store.list('photos');
          final Map<String, dynamic> gone = all.firstWhere(
            (Map<String, dynamic> e) => e['id'] == p[2],
            orElse: () => <String, dynamic>{},
          );
          // Delete the bytes too: leaving them would quietly grow storage.
          final String? url = gone['url'] as String?;
          if (url != null && url.startsWith('file://')) {
            final File f = File(Uri.parse(url).toFilePath());
            if (f.existsSync()) await f.delete();
          }
          all.removeWhere((Map<String, dynamic> e) => e['id'] == p[2]);
          await _store.putList('photos', all);
          return null;
        }
        final List<Map<String, dynamic>> photos = _store.list('photos');
        final String? pose = q['pose'];
        return pose == null || pose.isEmpty
            ? photos
            : photos
                .where((Map<String, dynamic> e) => e['pose'] == pose)
                .toList();
      case 'weights':
      case 'measurements':
        final String key = sub;
        if (method == 'POST') {
          final Map<String, dynamic> entry = <String, dynamic>{
            ..._asMap(body),
            'id': _id(),
            'recorded_on': _asMap(body)['recorded_on'] ?? _today(),
          };
          final List<Map<String, dynamic>> all = _store.list(key)
            ..insert(0, entry);
          await _store.putList(key, all);
          return entry;
        }
        if (method == 'DELETE' && p.length > 2) {
          final List<Map<String, dynamic>> all = _store.list(key)
            ..removeWhere((Map<String, dynamic> e) => e['id'] == p[2]);
          await _store.putList(key, all);
          return null;
        }
        return _store.value(key);
      default:
        throw _DemoError(404, 'not_found', 'No demo data for progress/$sub');
    }
  }

  // --- nutrition -----------------------------------------------------------

  Future<dynamic> _nutrition(
    String method,
    List<String> p,
    Map<String, String> q,
    dynamic body,
  ) async {
    final String sub = p.length > 1 ? p[1] : '';
    // The app asks for a specific day; answering with one fixed day would
    // show yesterday's food under today's date.
    if (sub == 'day') return _derived.dayFor(q['on'] ?? _today());

    if (sub == 'foods') {
      if (p.length > 2 && p[2] == 'recent') {
        return _store.list('foods').take(10).toList();
      }
      if (p.length > 3 && p[2] == 'barcode') {
        throw _DemoError(
            404, 'not_found', 'Barcode scanning is not available in demo mode');
      }
      if (p.length > 3 && p[3] == 'favorite') {
        // The caller reads `is_favorite` back, so a bare success would make
        // the star spring back to off every time.
        final List<Map<String, dynamic>> all = _store.list('foods');
        final int i =
            all.indexWhere((Map<String, dynamic> f) => f['id'] == p[2]);
        if (i < 0) throw _DemoError(404, 'not_found', 'Unknown food');
        all[i] = <String, dynamic>{
          ...all[i],
          'is_favorite': all[i]['is_favorite'] != true,
        };
        await _store.putList('foods', all);
        return all[i];
      }
      if (method == 'POST') {
        final Map<String, dynamic> created = <String, dynamic>{
          ..._asMap(body),
          'id': _id()
        };
        await _store.putList(
            'foods', <Map<String, dynamic>>[created, ..._store.list('foods')]);
        return created;
      }
      List<Map<String, dynamic>> items = _store.list('foods');
      final String search = (q['query'] ?? '').trim().toLowerCase();
      if (search.isNotEmpty) {
        items = items
            .where((Map<String, dynamic> f) =>
                '${f['name']}'.toLowerCase().contains(search))
            .toList();
      }
      return _store.paged(items,
          page: _int(q, 'page', 1), perPage: _int(q, 'per_page', 20));
    }

    if (sub == 'meals') {
      if (method == 'POST') {
        final String on = '${_asMap(body)['logged_on'] ?? q['on'] ?? _today()}';
        final Map<String, dynamic> meal = DemoAnalytics.withMealTotals(
          <String, dynamic>{
            'name': _asMap(body)['meal_type'] ?? 'Meal',
            ..._asMap(body),
            'id': _id(),
            // Required by the client model.
            'logged_on': on,
            'logged_at': _now(),
            'meal_type': _asMap(body)['meal_type'] ?? 'snack',
            // The app posts {food_id, grams}; the server answers with the
            // food resolved and its macros scaled to the portion.
            'items': _derived.resolveItems(
                _asMap(body)['items'] as List<dynamic>? ?? <dynamic>[]),
          },
        );
        await _editDay(on, (Map<String, dynamic> day) {
          (day['meals'] as List<dynamic>).add(meal);
        });
        return meal;
      }
      if (method == 'DELETE' && p.length > 2) {
        final String on = _dayHolding(p[2]) ?? _today();
        await _editDay(on, (Map<String, dynamic> day) {
          (day['meals'] as List<dynamic>)
              .removeWhere((dynamic m) => _asMap(m)['id'] == p[2]);
        });
        return null;
      }
      return _derived.dayFor(q['on'] ?? _today())['meals'];
    }

    if (sub == 'water') {
      final String on = '${_asMap(body)['logged_on'] ?? q['on'] ?? _today()}';
      final num add = (_asMap(body)['amount_ml'] as num?) ??
          (_asMap(body)['ml'] as num?) ??
          0;
      late Map<String, dynamic> updated;
      await _editDay(on, (Map<String, dynamic> day) {
        day['water_raw_ml'] =
            ((day['water_raw_ml'] as num?) ?? 0).toDouble() + add;
      });
      updated = _derived.dayFor(on);
      return updated;
    }

    throw _DemoError(404, 'not_found', 'No demo data for nutrition/$sub');
  }

  /// Apply [change] to the stored day for [on] and save it.
  ///
  /// Days live in a map keyed by date, so logging lunch today cannot silently
  /// overwrite what was eaten yesterday.
  Future<void> _editDay(
    String on,
    void Function(Map<String, dynamic> day) change,
  ) async {
    final Map<String, dynamic> days = _derived.storedDays();
    final Map<String, dynamic> day = days.containsKey(on)
        ? Map<String, dynamic>.from(_asMap(days[on]))
        : <String, dynamic>{'logged_on': on, 'meals': <dynamic>[]};
    day['meals'] =
        List<dynamic>.from(day['meals'] as List<dynamic>? ?? <dynamic>[]);
    change(day);
    days[on] = day;
    await _store.put('nutrition_days', days);
  }

  /// Which stored day holds the meal with [mealId], if any.
  String? _dayHolding(String mealId) {
    for (final MapEntry<String, dynamic> e in _derived.storedDays().entries) {
      final List<dynamic> meals =
          _asMap(e.value)['meals'] as List<dynamic>? ?? <dynamic>[];
      if (meals.any((dynamic m) => _asMap(m)['id'] == mealId)) return e.key;
    }
    return null;
  }

  // --- habits --------------------------------------------------------------

  Future<dynamic> _habits(String method, List<String> p, dynamic body) async {
    if (p.length == 1) {
      if (method == 'POST') {
        final Map<String, dynamic> habit = <String, dynamic>{
          ..._asMap(body),
          'id': _id(),
          'current_streak': 0,
          'longest_streak': 0,
          'logs': <dynamic>[],
        };
        await _store.putList(
            'habits', <Map<String, dynamic>>[..._store.list('habits'), habit]);
        return habit;
      }
      return _store.value('habits');
    }

    final String id = p[1];
    final List<Map<String, dynamic>> all = _store.list('habits');
    final int idx = all.indexWhere((Map<String, dynamic> e) => e['id'] == id);

    if (p.length > 2 && p[2] == 'log') {
      if (idx < 0) throw _DemoError(404, 'not_found', 'Unknown habit');
      final Map<String, dynamic> habit = Map<String, dynamic>.from(all[idx]);
      final List<dynamic> logs =
          List<dynamic>.from(habit['logs'] as List<dynamic>? ?? <dynamic>[]);
      final String day = _asMap(body)['logged_on']?.toString() ?? _today();
      if (method == 'POST') {
        if (!logs.any((dynamic l) => _asMap(l)['logged_on'] == day)) {
          logs.add(<String, dynamic>{
            'id': _id(),
            'habit_id': id,
            'logged_on': day,
            'completed': true,
          });
        }
      } else {
        logs.removeWhere((dynamic l) => _asMap(l)['logged_on'] == day);
      }
      habit['logs'] = logs;
      habit['current_streak'] = _streak(logs);
      habit['longest_streak'] =
          ((habit['longest_streak'] as num?) ?? 0).toInt() >
                  (habit['current_streak'] as int)
              ? habit['longest_streak']
              : habit['current_streak'];
      all[idx] = habit;
      await _store.putList('habits', all);
      return habit;
    }

    if (method == 'DELETE') {
      all.removeWhere((Map<String, dynamic> e) => e['id'] == id);
      await _store.putList('habits', all);
      return null;
    }
    if (idx >= 0) return all[idx];
    throw _DemoError(404, 'not_found', 'Unknown habit');
  }

  /// Consecutive days ending today (or yesterday, so an unlogged today does
  /// not read as a broken streak).
  int _streak(List<dynamic> logs) {
    final Set<String> days =
        logs.map((dynamic l) => '${_asMap(l)['logged_on']}').toSet();
    DateTime cursor = DateTime.now();
    if (!days.contains(cursor.toIso8601String().split('T').first)) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    int streak = 0;
    while (days.contains(cursor.toIso8601String().split('T').first)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // --- goals ---------------------------------------------------------------

  Future<dynamic> _goals(String method, List<String> p, dynamic body) async {
    if (p.length == 1) {
      if (method == 'POST') {
        final Map<String, dynamic> input = _asMap(body);
        final Map<String, dynamic> goal = <String, dynamic>{
          'goal_type': 'custom',
          'unit': '',
          // Required by the client model; a created goal starts today at zero.
          'start_date': _today(),
          'current_value': 0,
          'progress_percent': 0,
          ...input,
          'id': _id(),
          'created_at': _now(),
          'status': 'active',
        };
        await _store.putList(
            'goals', <Map<String, dynamic>>[..._store.list('goals'), goal]);
        return goal;
      }
      return _store.value('goals');
    }
    final String id = p[1];
    final List<Map<String, dynamic>> all = _store.list('goals');
    final int idx = all.indexWhere((Map<String, dynamic> e) => e['id'] == id);
    if (method == 'DELETE') {
      all.removeWhere((Map<String, dynamic> e) => e['id'] == id);
      await _store.putList('goals', all);
      return null;
    }
    if (method == 'PATCH' && idx >= 0) {
      all[idx] = <String, dynamic>{...all[idx], ..._asMap(body)};
      await _store.putList('goals', all);
      return all[idx];
    }
    if (idx >= 0) return all[idx];
    throw _DemoError(404, 'not_found', 'Unknown goal');
  }

  // --- FitCoach ------------------------------------------------------------

  Future<dynamic> _ai(String method, List<String> p, dynamic body) async {
    final String sub = p.length > 1 ? p[1] : '';

    if (sub == 'chat') {
      final String message = '${_asMap(body)['message'] ?? ''}';
      final String reply =
          _needsMedicalRedirect(message) ? _medicalReply : _coachReply(message);
      final Map<String, dynamic> msg = <String, dynamic>{
        'id': _id(),
        'role': 'assistant',
        'content': reply,
        'created_at': _now(),
      };
      final List<Map<String, dynamic>> convo = _store.list('ai_messages')
        ..add(<String, dynamic>{
          'id': _id(),
          'role': 'user',
          'content': message,
          'created_at': _now(),
        })
        ..add(msg);
      await _store.putList('ai_messages', convo);
      return <String, dynamic>{'message': msg, 'disclaimer': _note};
    }

    if (sub == 'conversations') {
      if (method == 'DELETE') {
        await _store.putList('ai_messages', <Map<String, dynamic>>[]);
        return null;
      }
      final List<Map<String, dynamic>> msgs = _store.list('ai_messages');
      if (p.length > 2) {
        return <String, dynamic>{
          'id': p[2],
          'title': 'Demo conversation',
          'messages': msgs,
          'created_at': _now(),
        };
      }
      if (msgs.isEmpty) return <dynamic>[];
      return <dynamic>[
        <String, dynamic>{
          'id': 'demo-conversation',
          'title': 'Demo conversation',
          'created_at': _now(),
          'message_count': msgs.length,
        }
      ];
    }

    if (sub == 'plans' && p.length > 2 && p[2] == 'generate') {
      final Map<String, dynamic> req = _asMap(body);
      final int days = ((req['days_per_week'] as num?) ?? 4).toInt();
      final List<Map<String, dynamic>> pool = _store.list('exercises');
      final List<Map<String, dynamic>> plannedDays = <Map<String, dynamic>>[];
      for (int d = 0; d < days; d++) {
        final List<Map<String, dynamic>> picks = <Map<String, dynamic>>[];
        for (int j = 0; j < 5 && pool.isNotEmpty; j++) {
          final Map<String, dynamic> e = pool[(d * 5 + j) % pool.length];
          picks.add(<String, dynamic>{
            'exercise_id': e['id'],
            'name': e['name'],
            'sets': 3,
            'target_reps': 8,
            'rest_seconds': 120,
          });
        }
        plannedDays.add(<String, dynamic>{
          'day_index': d,
          'name': 'Day ${d + 1}',
          'exercises': picks,
        });
      }
      return <String, dynamic>{
        'generation_id': _id(),
        'disclaimer': _note,
        'plan': <String, dynamic>{
          'name': 'Demo ${days}-day plan',
          'description': 'Built offline from the bundled exercise library.',
          'goal': req['goal'] ?? 'general_fitness',
          'difficulty': 'intermediate',
          'days_per_week': days,
          'estimated_minutes': 60,
          'equipment_needed': <String>['barbell', 'dumbbell'],
          'days': plannedDays,
          'coaching_notes': <String>[_note],
        },
      };
    }

    if (sub == 'plans' && p.length > 2 && p[2] == 'save') {
      final Map<String, dynamic> saved = <String, dynamic>{
        ..._asMap(body),
        'id': _id(),
        'is_active': false,
      };
      await _store.putList('programs',
          <Map<String, dynamic>>[..._store.list('programs'), saved]);
      return saved;
    }

    if (sub == 'progress-summary') {
      return <String, dynamic>{
        'summary': '$kDemoNote\n\nYour bundled history shows steady training '
            'across the last twelve weeks, with the most volume on lower-body days.',
        'disclaimer': _note,
      };
    }

    if (sub == 'substitutions') {
      final List<Map<String, dynamic>> pool =
          _store.list('exercises').take(5).toList();
      return <String, dynamic>{
        'disclaimer': _note,
        'substitutions': pool
            .map((Map<String, dynamic> e) => <String, dynamic>{
                  'exercise_id': e['id'],
                  'name': e['name'],
                  'reason': 'Bundled suggestion (demo mode).',
                })
            .toList(),
      };
    }

    if (sub == 'usage') {
      return <String, dynamic>{
        'used': 0,
        'limit': 0,
        'unlimited': true,
        'note': _note
      };
    }

    throw _DemoError(404, 'not_found', 'No demo route for ai/$sub');
  }

  /// Mirrors the server's safety layer: injury and medical questions are
  /// redirected to a professional rather than answered. This runs before any
  /// canned reply is chosen, exactly as it does online.
  bool _needsMedicalRedirect(String message) {
    final String m = message.toLowerCase();
    const List<String> patterns = <String>[
      'injur',
      'pain',
      'hurt',
      'tore',
      'torn',
      'sprain',
      'strain',
      'acl',
      'fracture',
      'broken',
      'dislocat',
      'surgery',
      'physio',
      'doctor',
      'diagnos',
      'symptom',
      'dizzy',
      'chest pain',
      'numb',
      'swollen',
    ];
    const List<String> allow = <String>[
      'muscle soreness',
      'doms',
      'sore muscles'
    ];
    if (allow.any(m.contains)) return false;
    return patterns.any(m.contains);
  }

  /// The safety redirect, in the reader's language. This is real logic, not a
  /// canned pleasantry: an injury or medical question never receives training
  /// advice in either language.
  String get _medicalReply => _isArabic
      ? 'لا أستطيع المساعدة في الإصابات أو الألم أو الأعراض الطبية — هذا يحتاج '
          'إلى مختص مؤهل يستطيع فحصك، مثل طبيب أو أخصائي علاج طبيعي.\n\n'
          'إذا كان الألم شديدًا أو ظهر فجأة، أو لديك أعراض مثل ألم الصدر أو '
          'الدوخة أو التنميل، فاطلب رعاية طبية الآن.\n\nبعد حصولك على إذن '
          'بالتمرين، يسعدني مساعدتك في تعديل برنامجك بما يناسبك.'
      : "I'm not able to help with injuries, pain or medical symptoms — that "
          'needs a qualified professional who can actually assess you, such as '
          'a doctor or a physiotherapist.\n\nIf the pain is severe, came on '
          'suddenly, or you have symptoms like chest pain, dizziness or '
          'numbness, please seek medical care now.\n\nOnce you have been '
          'cleared to train, I am glad to help you adjust your programme '
          'around what you can do.';

  String _coachReply(String message) {
    final String m = message.toLowerCase();
    final bool ar = _isArabic;
    String body;
    if (m.contains('protein') ||
        m.contains('eat') ||
        m.contains('diet') ||
        m.contains('nutrition') ||
        m.contains('بروتين') ||
        m.contains('أكل') ||
        m.contains('تغذية')) {
      body = ar
          ? 'استهدف تقريبًا 1.6 إلى 2.2 غرام من البروتين لكل كيلوغرام من وزنك '
              'يوميًا، موزّعة على ثلاث أو أربع وجبات. حافظ على سعراتك قرب هدفك '
              'ودع اتجاه الوزن خلال أسبوعين يحدد ما إذا كنت بحاجة إلى تعديل.'
          : 'Aim for roughly 1.6–2.2 g of protein per kg of bodyweight a day, '
              'spread across three or four meals. Keep total calories near your '
              'target and let the scale trend over a fortnight tell you whether '
              'to adjust.';
    } else if (m.contains('plateau') ||
        m.contains('stuck') ||
        m.contains('progress') ||
        m.contains('ثبات') ||
        m.contains('تقدم')) {
      body = ar
          ? 'الثبات غالبًا مسألة استشفاء لا مجهود. ابقِ الوزن كما هو لأسبوع وزد '
              'التكرارات بدلًا منه، وتأكد من نومك، واحرص أن تكون المجموعة '
              'الأخيرة قريبة فعلًا من الإجهاد.'
          : 'A stall usually means recovery, not effort. Hold the weight for a '
              'week and add reps instead, check you are sleeping enough, and '
              'make sure the last set is genuinely close to failure.';
    } else if (m.contains('week') ||
        m.contains('split') ||
        m.contains('program') ||
        m.contains('plan') ||
        m.contains('أسبوع') ||
        m.contains('برنامج') ||
        m.contains('خطة')) {
      body = ar
          ? 'أبقِ الهيكل بسيطًا: درّب كل مجموعة عضلية مرتين أسبوعيًا تقريبًا، '
              'واجعل معظم المجموعات قريبة من الإجهاد، ودع أرقامك المسجّلة تخبرك '
              'متى تزيد الوزن.'
          : 'Keep the structure simple: train each muscle group about twice a '
              'week, take most working sets close to failure, and let your '
              'logged numbers tell you when to add weight.';
    } else if (m.contains('rest') ||
        m.contains('recover') ||
        m.contains('راحة') ||
        m.contains('استشفاء')) {
      body = ar
          ? 'استرح دقيقتين إلى ثلاث في التمارين المركّبة الثقيلة، وحوالي تسعين '
              'ثانية في التمارين المساعدة. إذا انخفضت مجموعتك التالية بأكثر من '
              'تكرار أو اثنين فقد استرحت أقل من اللازم.'
          : 'Rest two to three minutes on heavy compounds and about ninety '
              'seconds on accessories. If your next set drops by more than a '
              'rep or two, you rested too little.';
    } else {
      body = ar
          ? 'درّب كل مجموعة عضلية مرتين أسبوعيًا تقريبًا، وادفع معظم المجموعات '
              'قريبًا من الإجهاد، ولا تزد الوزن إلا بعد أن تصل إلى أعلى نطاق '
              'التكرارات بأداء سليم.'
          : 'Train each muscle group about twice a week, push most sets close '
              'to failure, and add weight only once you are hitting the top of '
              'your rep range with good form.';
    }
    return '$body\n\n$_note';
  }
}

class _DemoError implements Exception {
  _DemoError(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;
}

/// Just enough multipart parsing to pull one file and the text fields out of
/// an encoded body. Dio finalizes FormData before the adapter sees it, so this
/// works on bytes rather than on the original objects.
class _Multipart {
  _Multipart(this.fields, this.fileBytes, this.fileName);

  final Map<String, String> fields;
  final List<int>? fileBytes;
  final String? fileName;

  static _Multipart parse(List<int> body, String contentType) {
    final RegExpMatch? b =
        RegExp('boundary=(?:"([^"]+)"|([^;]+))').firstMatch(contentType);
    final String? boundary = b?.group(1) ?? b?.group(2);
    if (boundary == null) {
      return _Multipart(<String, String>{}, null, null);
    }

    final List<int> sep = utf8.encode('--$boundary');
    final Map<String, String> fields = <String, String>{};
    List<int>? fileBytes;
    String? fileName;

    int start = _indexOf(body, sep, 0);
    while (start >= 0) {
      final int partStart = start + sep.length;
      final int next = _indexOf(body, sep, partStart);
      if (next < 0) break;
      // Trim the CRLF that precedes the next boundary.
      final List<int> part =
          body.sublist(partStart, next - 2 < partStart ? partStart : next - 2);

      final int headerEnd = _indexOf(part, utf8.encode('\r\n\r\n'), 0);
      if (headerEnd > 0) {
        final String headers =
            utf8.decode(part.sublist(0, headerEnd), allowMalformed: true);
        final List<int> content = part.sublist(headerEnd + 4);
        final String? name =
            RegExp('name="([^"]*)"').firstMatch(headers)?.group(1);
        final String? file =
            RegExp('filename="([^"]*)"').firstMatch(headers)?.group(1);
        if (file != null) {
          fileBytes = content;
          fileName = file;
        } else if (name != null) {
          fields[name] = utf8.decode(content, allowMalformed: true).trim();
        }
      }
      start = next;
    }
    return _Multipart(fields, fileBytes, fileName);
  }

  static int _indexOf(List<int> haystack, List<int> needle, int from) {
    for (int i = from; i <= haystack.length - needle.length; i++) {
      bool hit = true;
      for (int j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          hit = false;
          break;
        }
      }
      if (hit) return i;
    }
    return -1;
  }
}
