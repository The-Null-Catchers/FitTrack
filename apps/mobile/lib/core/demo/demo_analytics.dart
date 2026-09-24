import 'dart:math' as math;

import 'demo_store.dart';

/// Derives every dashboard tile, chart and summary from what is actually
/// stored on the device.
///
/// The bundled capture seeds the starting state, but nothing here reads a
/// pre-computed figure out of it: each number is recomputed from the stored
/// workouts, weights, measurements, meals, habits and goals every time it is
/// asked for. That is what makes a logged workout move the volume chart and a
/// logged meal move the calorie ring, instead of the screens continuing to
/// show whatever the capture happened to contain.
class DemoAnalytics {
  const DemoAnalytics(this._store);

  final DemoStore _store;

  // --- shared helpers ------------------------------------------------------

  static String isoDay(DateTime d) => d.toIso8601String().split('T').first;

  static String today() => isoDay(DateTime.now());

  static Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static int rangeDays(String range) => switch (range) {
        '7d' => 7,
        '30d' => 30,
        '90d' => 90,
        '6m' => 180,
        '180d' => 180,
        '1y' => 365,
        'all' => 3650,
        _ => 30,
      };

  /// Sets carry `is_completed` in the captured payloads. A set that was
  /// skipped must not count towards volume, so treat a missing flag as done
  /// (the seed's historical sets omit it) but an explicit false as skipped.
  static bool setCounts(Map<String, dynamic> set) =>
      set['is_completed'] != false && set['completed'] != false;

  static double setVolume(Map<String, dynamic> set) {
    final num? explicit = set['volume_kg'] as num?;
    if (explicit != null) return explicit.toDouble();
    final num reps = (set['reps'] as num?) ?? 0;
    final num weight =
        (set['weight_kg'] as num?) ?? (set['weight'] as num?) ?? 0;
    return (reps * weight).toDouble();
  }

  /// Epley, matching what the server reports for a captured set.
  static double? _estimated1rm(Map<String, dynamic> set) {
    final num? explicit = set['estimated_1rm_kg'] as num?;
    if (explicit != null) return explicit.toDouble();
    final num? weight = set['weight_kg'] as num?;
    final num? reps = set['reps'] as num?;
    if (weight == null || reps == null || reps <= 0) return null;
    return weight.toDouble() * (1 + reps.toDouble() / 30.0);
  }

  DateTime? _sessionDate(Map<String, dynamic> session) =>
      DateTime.tryParse('${session['completed_at'] ?? session['started_at']}');

  /// Finished sessions inside [range], newest first.
  List<Map<String, dynamic>> sessionsInRange(String range) {
    final DateTime from =
        DateTime.now().subtract(Duration(days: rangeDays(range)));
    return _store.list('workout_sessions').where((Map<String, dynamic> s) {
      final DateTime? on = _sessionDate(s);
      return on != null && !on.isBefore(from);
    }).toList();
  }

  /// The stored detail for a session, or an empty map when only the summary
  /// was kept (true of most of the captured history).
  Map<String, dynamic> detailFor(String id) =>
      _asMap(_asMap(_store.map('session_details'))[id]);

  Map<String, dynamic> _chart(
    String range,
    List<Map<String, dynamic>> series, {
    String? summary,
  }) {
    double? changeAbs;
    double? changePct;
    final List<dynamic> first = series.isEmpty
        ? <dynamic>[]
        : (series.first['points'] as List<dynamic>);
    if (first.length >= 2) {
      final double a = ((_asMap(first.first)['y'] as num?) ?? 0).toDouble();
      final double b = ((_asMap(first.last)['y'] as num?) ?? 0).toDouble();
      changeAbs = b - a;
      if (a != 0) changePct = (changeAbs / a) * 100;
    }
    return <String, dynamic>{
      'range': range,
      'series': series,
      'summary': summary,
      'change_absolute': changeAbs,
      'change_percent': changePct,
    };
  }

  static Map<String, dynamic> series(
    String key,
    String label,
    String unit,
    List<Map<String, dynamic>> points,
  ) =>
      <String, dynamic>{
        'key': key,
        'label': label,
        'unit': unit,
        'points': points,
        'trend': <dynamic>[],
      };

  static Map<String, dynamic> _point(String x, double y) =>
      <String, dynamic>{'x': x, 'y': y};

  // --- charts --------------------------------------------------------------

  /// Body weight, straight from the stored entries.
  Map<String, dynamic> weightChart(String range) {
    final DateTime from =
        DateTime.now().subtract(Duration(days: rangeDays(range)));
    final List<Map<String, dynamic>> points = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> e in _store.list('weights')) {
      final DateTime? on = DateTime.tryParse('${e['recorded_on']}');
      final num? kg = e['weight_kg'] as num?;
      if (on == null || kg == null || on.isBefore(from)) continue;
      points.add(_point(isoDay(on), kg.toDouble()));
    }
    points.sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
        '${a['x']}'.compareTo('${b['x']}'));
    return _chart(range, <Map<String, dynamic>>[
      series('body_weight', 'Body weight', 'kg', points)
    ]);
  }

  /// Training volume totalled per day from stored sessions.
  Map<String, dynamic> volumeChart(String range) {
    final Map<String, double> byDay = <String, double>{};
    for (final Map<String, dynamic> s in sessionsInRange(range)) {
      final DateTime? on = _sessionDate(s);
      if (on == null) continue;
      byDay[isoDay(on)] =
          (byDay[isoDay(on)] ?? 0) + _sessionVolume(s).toDouble();
    }
    final List<String> days = byDay.keys.toList()..sort();
    return _chart(range, <Map<String, dynamic>>[
      series('volume', 'Training volume', 'kg',
          days.map((String d) => _point(d, byDay[d]!)).toList())
    ]);
  }

  /// A session's volume: the stored summary when the server gave one,
  /// otherwise totalled from the sets the user actually completed.
  double _sessionVolume(Map<String, dynamic> session) {
    final num? summary = session['total_volume_kg'] as num?;
    if (summary != null) return summary.toDouble();
    double total = 0;
    for (final dynamic e
        in (detailFor('${session['id']}')['exercises'] as List<dynamic>? ??
            <dynamic>[])) {
      for (final dynamic s
          in (_asMap(e)['sets'] as List<dynamic>? ?? <dynamic>[])) {
        final Map<String, dynamic> set = _asMap(s);
        if (!setCounts(set)) continue;
        total += setVolume(set);
      }
    }
    return total;
  }

  int _sessionSets(Map<String, dynamic> session) {
    final num? summary = session['total_sets'] as num?;
    if (summary != null) return summary.toInt();
    int sets = 0;
    for (final dynamic e
        in (detailFor('${session['id']}')['exercises'] as List<dynamic>? ??
            <dynamic>[])) {
      for (final dynamic s
          in (_asMap(e)['sets'] as List<dynamic>? ?? <dynamic>[])) {
        if (setCounts(_asMap(s))) sets += 1;
      }
    }
    return sets;
  }

  /// Nutrition, per day, from the meals stored for each day.
  ///
  /// Days the user has logged are computed from those meals. Days they have
  /// not touched keep the captured history, so the chart still has a past to
  /// show without inventing one.
  Map<String, dynamic> nutritionChart(String range) {
    final DateTime from =
        DateTime.now().subtract(Duration(days: rangeDays(range)));
    final Map<String, Map<String, double>> byDay =
        <String, Map<String, double>>{};

    // Captured history first, so a locally logged day can replace it.
    final Map<String, dynamic> seeded =
        _asMap(_store.seedValue('chart_nutrition'));
    for (final dynamic s
        in (seeded['series'] as List<dynamic>? ?? <dynamic>[])) {
      final Map<String, dynamic> ser = _asMap(s);
      final String key = '${ser['key']}';
      for (final dynamic p
          in (ser['points'] as List<dynamic>? ?? <dynamic>[])) {
        final Map<String, dynamic> point = _asMap(p);
        final DateTime? on = DateTime.tryParse('${point['x']}');
        if (on == null || on.isBefore(from)) continue;
        byDay.putIfAbsent(isoDay(on), () => <String, double>{})[key] =
            ((point['y'] as num?) ?? 0).toDouble();
      }
    }

    for (final MapEntry<String, dynamic> entry in storedDays().entries) {
      final DateTime? on = DateTime.tryParse(entry.key);
      if (on == null || on.isBefore(from)) continue;
      final Map<String, double> totals = dayTotals(_asMap(entry.value));
      byDay[entry.key] = <String, double>{
        'calories': totals['calories']!,
        'protein': totals['protein_g']!,
        'carbs': totals['carbs_g']!,
        'fat': totals['fat_g']!,
      };
    }

    final List<String> days = byDay.keys.toList()..sort();
    List<Map<String, dynamic>> pointsFor(String key) => days
        .where((String d) => byDay[d]!.containsKey(key))
        .map((String d) => _point(d, byDay[d]![key]!))
        .toList();

    return _chart(range, <Map<String, dynamic>>[
      series('calories', 'Calories', 'kcal', pointsFor('calories')),
      series('protein', 'Protein', 'g', pointsFor('protein')),
      series('carbs', 'Carbs', 'g', pointsFor('carbs')),
      series('fat', 'Fat', 'g', pointsFor('fat')),
    ]);
  }

  /// Body measurements, grouped by type, from the stored entries.
  Map<String, dynamic> measurementChart(String range, String? type) {
    final DateTime from =
        DateTime.now().subtract(Duration(days: rangeDays(range)));
    final Map<String, List<Map<String, dynamic>>> byType =
        <String, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> e in _store.list('measurements')) {
      final DateTime? on = DateTime.tryParse('${e['recorded_on']}');
      final num? cm = e['value_cm'] as num?;
      final String kind = '${e['measurement_type']}';
      if (on == null || cm == null || on.isBefore(from)) continue;
      if (type != null && type.isNotEmpty && kind != type) continue;
      byType
          .putIfAbsent(kind, () => <Map<String, dynamic>>[])
          .add(_point(isoDay(on), cm.toDouble()));
    }
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final String kind in byType.keys.toList()..sort()) {
      final List<Map<String, dynamic>> points = byType[kind]!
        ..sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
            '${a['x']}'.compareTo('${b['x']}'));
      out.add(series(kind, _titleCase(kind), 'cm', points));
    }
    return _chart(range, out);
  }

  static String _titleCase(String s) => s.isEmpty
      ? s
      : s
          .split('_')
          .map((String w) =>
              w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');

  // --- nutrition days ------------------------------------------------------

  /// Every day the user has logged something on, keyed by ISO date.
  Map<String, dynamic> storedDays() => Map<String, dynamic>.from(
      _store.map('nutrition_days') ?? <String, dynamic>{});

  /// The stored day for [iso], or a fresh empty day against the user's
  /// current targets.
  Map<String, dynamic> dayFor(String iso) {
    final Map<String, dynamic> stored = storedDays();
    if (stored.containsKey(iso)) return recalcDay(_asMap(stored[iso]));
    return recalcDay(<String, dynamic>{'logged_on': iso, 'meals': <dynamic>[]});
  }

  static const List<String> macroKeys = <String>[
    'calories',
    'protein_g',
    'carbs_g',
    'fat_g',
    'fiber_g',
  ];

  /// Turn the app's `{food_id, grams}` item into the full item the server
  /// would have returned.
  ///
  /// The food-search screen posts only an id and a portion — the server looks
  /// the food up and scales its per-100g macros. Storing the item as posted
  /// leaves it with no `food_name`, which the client model requires, so the
  /// nutrition screen throws the moment a meal is logged.
  List<Map<String, dynamic>> resolveItems(List<dynamic> raw) {
    final List<Map<String, dynamic>> foods = _store.list('foods');
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (int i = 0; i < raw.length; i++) {
      final Map<String, dynamic> item = _asMap(raw[i]);
      final String? foodId = item['food_id'] as String?;
      final Map<String, dynamic> food = foodId == null
          ? <String, dynamic>{}
          : foods.firstWhere((Map<String, dynamic> f) => f['id'] == foodId,
              orElse: () => <String, dynamic>{});
      final double grams = ((item['grams'] as num?) ??
              (food['default_serving_grams'] as num?) ??
              100)
          .toDouble();
      double scaled(String per100) =>
          _round1(((food[per100] as num?)?.toDouble() ?? 0) * grams / 100);

      out.add(<String, dynamic>{
        ...item,
        'id':
            '${item['id'] ?? 'demo-item-$i-${DateTime.now().microsecondsSinceEpoch}'}',
        'food_id': foodId,
        'food_name': '${item['food_name'] ?? food['name'] ?? 'Food'}',
        'grams': grams,
        // An item that already carries its own macros keeps them; otherwise
        // they come from the food, scaled to the portion.
        'calories': (item['calories'] as num?)?.toDouble() ??
            scaled('calories_per_100g'),
        'protein_g': (item['protein_g'] as num?)?.toDouble() ??
            scaled('protein_per_100g'),
        'carbs_g':
            (item['carbs_g'] as num?)?.toDouble() ?? scaled('carbs_per_100g'),
        'fat_g': (item['fat_g'] as num?)?.toDouble() ?? scaled('fat_per_100g'),
        'fiber_g':
            (item['fiber_g'] as num?)?.toDouble() ?? scaled('fiber_per_100g'),
        'serving_label': item['serving_label'],
        'quantity': (item['quantity'] as num?)?.toDouble() ?? 1,
        'position': (item['position'] as num?)?.toInt() ?? i,
      });
    }
    return out;
  }

  /// What one meal contributes, under the `total_*` names the app reads.
  ///
  /// An itemised meal is summed from its items; one logged as a single figure
  /// uses that. Either way the meal carries its own totals afterwards, so the
  /// meal list and the day's rings cannot disagree.
  static Map<String, double> mealTotals(Map<String, dynamic> meal) {
    final List<dynamic> items = meal['items'] as List<dynamic>? ?? <dynamic>[];
    final Map<String, double> out = <String, double>{
      for (final String k in macroKeys) k: 0.0,
    };
    if (items.isEmpty) {
      for (final String k in macroKeys) {
        out[k] = (meal['total_$k'] as num?)?.toDouble() ??
            (meal[k] as num?)?.toDouble() ??
            0;
      }
      return out;
    }
    for (final dynamic i in items) {
      final Map<String, dynamic> item = _asMap(i);
      for (final String k in macroKeys) {
        out[k] = out[k]! + ((item[k] as num?)?.toDouble() ?? 0);
      }
    }
    return out;
  }

  /// Stamp a meal with the `total_*` fields the client model reads.
  static Map<String, dynamic> withMealTotals(Map<String, dynamic> meal) {
    final Map<String, double> totals = mealTotals(meal);
    return <String, dynamic>{
      ...meal,
      for (final String k in macroKeys) 'total_$k': totals[k],
    };
  }

  /// Sum the macros a day's meals actually contain.
  static Map<String, double> dayTotals(Map<String, dynamic> day) {
    final Map<String, double> out = <String, double>{
      for (final String k in macroKeys) k: 0.0,
    };
    for (final dynamic m in (day['meals'] as List<dynamic>? ?? <dynamic>[])) {
      final Map<String, double> totals = mealTotals(_asMap(m));
      for (final String k in macroKeys) {
        out[k] = out[k]! + totals[k]!;
      }
    }
    return out;
  }

  /// Rebuild a day's rings from its meals and the user's current targets.
  Map<String, dynamic> recalcDay(Map<String, dynamic> day) {
    final Map<String, double> totals = dayTotals(day);
    final Map<String, dynamic> targets = _targets();
    final Map<String, dynamic> out = Map<String, dynamic>.from(day);
    for (final String key in <String>[
      'calories',
      'protein_g',
      'carbs_g',
      'fat_g',
      'fiber_g'
    ]) {
      out[key] = ring(totals[key]!, (targets[key] as num?)?.toDouble());
    }
    final num water = (_asMap(day['water_ml'])['consumed'] as num?) ??
        (day['water_raw_ml'] as num?) ??
        0;
    out['water_ml'] =
        ring(water.toDouble(), (targets['water_ml'] as num?)?.toDouble());
    out['water_raw_ml'] = water;
    out['logged_on'] = day['logged_on'] ?? today();
    out['meals'] = day['meals'] ?? <dynamic>[];
    return out;
  }

  Map<String, dynamic> _targets() {
    final Map<String, dynamic> profile = _asMap(_store.map('profile'));
    final Map<String, dynamic> fitness = _asMap(profile['profile']).isNotEmpty
        ? _asMap(profile['profile'])
        : _asMap(profile['fitness_profile']);
    final Map<String, dynamic> explicit = _asMap(profile['nutrition_targets']);
    num? pick(String a, String b) =>
        (explicit[a] as num?) ?? (fitness[b] as num?);
    return <String, dynamic>{
      'calories': pick('calories', 'daily_calorie_target'),
      'protein_g': pick('protein_g', 'daily_protein_target_g'),
      'carbs_g': pick('carbs_g', 'daily_carbs_target_g'),
      'fat_g': pick('fat_g', 'daily_fat_target_g'),
      'fiber_g': pick('fiber_g', 'daily_fiber_target_g'),
      'water_ml': pick('water_ml', 'daily_water_target_ml'),
    };
  }

  static Map<String, dynamic> ring(double consumed, double? target) {
    final double rounded = double.parse(consumed.toStringAsFixed(1));
    return <String, dynamic>{
      'consumed': rounded,
      'target': target,
      'remaining': target == null ? null : target - rounded,
      'percent': target == null || target == 0 ? 0.0 : (rounded / target) * 100,
    };
  }

  // --- dashboard -----------------------------------------------------------

  /// The home dashboard, rebuilt from stored data on every request.
  Map<String, dynamic> dashboard() {
    final Map<String, dynamic> day = dayFor(today());
    final List<Map<String, dynamic>> weights = _sortedWeights();
    final Map<String, dynamic> weekly = _weeklyWorkouts();
    final Map<String, dynamic> profile = _asMap(_store.map('profile'));

    final List<Map<String, dynamic>> habits = _store.list('habits');
    final String todayIso = today();
    int habitsDone = 0;
    for (final Map<String, dynamic> h in habits) {
      final List<dynamic> logs = h['logs'] as List<dynamic>? ?? <dynamic>[];
      if (logs.any((dynamic l) => '${_asMap(l)['logged_on']}' == todayIso)) {
        habitsDone += 1;
      }
    }

    final List<Map<String, dynamic>> records = _store.list('personal_records')
      ..sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
          '${b['achieved_at']}'.compareTo('${a['achieved_at']}'));

    return <String, dynamic>{
      'greeting_name': _greetingName(profile),
      'date': todayIso,
      'calories': day['calories'],
      'protein_g': day['protein_g'],
      'water_ml': day['water_ml'],
      'current_streak_days': _workoutStreak(),
      'longest_streak_days': _longestWorkoutStreak(),
      'weekly_workouts': weekly,
      'today_workout': _todayWorkout(),
      'active_session': null,
      'weight_trend': (weightChart('90d')['series'] as List<dynamic>).first,
      'latest_weight_kg': weights.isEmpty
          ? null
          : (weights.last['weight_kg'] as num).toDouble(),
      'weight_change_30d_kg': _weightChange(30),
      'recent_records': records
          .where((Map<String, dynamic> r) => r['acknowledged_at'] == null)
          .take(5)
          .toList(),
      'active_goals': _store
          .list('goals')
          .where((Map<String, dynamic> g) => g['status'] == 'active')
          .toList(),
      'habits_completed_today': habitsDone,
      'habits_total_today': habits
          .where((Map<String, dynamic> h) => h['is_archived'] != true)
          .length,
      'unread_notifications': 0,
    };
  }

  String _greetingName(Map<String, dynamic> profile) {
    final String full = '${profile['full_name'] ?? ''}'.trim();
    if (full.isEmpty) return '';
    return full.split(RegExp(r'\s+')).first;
  }

  Map<String, dynamic>? _todayWorkout() {
    final Map<String, dynamic> active = _asMap(_store.map('active_program'));
    if (active.isEmpty) return null;
    final List<dynamic> days = active['days'] as List<dynamic>? ?? <dynamic>[];
    if (days.isEmpty) return null;
    // Rotate through the program's days by how many workouts are already done,
    // so finishing one advances the card instead of pinning it to the capture.
    final int done = _store.list('workout_sessions').length;
    final Map<String, dynamic> pick = _asMap(days[done % days.length]);
    final List<dynamic> exercises =
        pick['exercises'] as List<dynamic>? ?? <dynamic>[];
    return <String, dynamic>{
      'program_id': active['id'],
      'program_name': active['name'],
      'day_id': pick['id'],
      'day_name': pick['name'],
      'exercise_count': exercises.length,
      'estimated_minutes': pick['estimated_minutes'] ?? 60,
      'is_rest_day': pick['is_rest_day'] ?? false,
    };
  }

  List<Map<String, dynamic>> _sortedWeights() {
    final List<Map<String, dynamic>> all = _store
        .list('weights')
        .where((Map<String, dynamic> e) => e['weight_kg'] is num)
        .toList()
      ..sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
          '${a['recorded_on']}'.compareTo('${b['recorded_on']}'));
    return all;
  }

  double? _weightChange(int days) {
    final List<Map<String, dynamic>> all = _sortedWeights();
    if (all.length < 2) return null;
    final DateTime from = DateTime.now().subtract(Duration(days: days));
    final Iterable<Map<String, dynamic>> window = all.where(
        (Map<String, dynamic> e) =>
            !(DateTime.tryParse('${e['recorded_on']}') ?? DateTime(1970))
                .isBefore(from));
    if (window.length < 2) return null;
    final double first = (window.first['weight_kg'] as num).toDouble();
    final double last = (window.last['weight_kg'] as num).toDouble();
    return double.parse((last - first).toStringAsFixed(2));
  }

  /// Monday-first flags for the current week, plus the count and target.
  Map<String, dynamic> _weeklyWorkouts() {
    final DateTime now = DateTime.now();
    final DateTime monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final Set<String> trained = <String>{};
    for (final Map<String, dynamic> s in _store.list('workout_sessions')) {
      final DateTime? on = _sessionDate(s);
      if (on == null) continue;
      if (on.isBefore(monday)) continue;
      trained.add(isoDay(on));
    }
    final List<bool> days = <bool>[];
    for (int i = 0; i < 7; i++) {
      days.add(trained.contains(isoDay(monday.add(Duration(days: i)))));
    }
    final int completed = days.where((bool d) => d).length;
    final int target = ((_asMap(_asMap(_store.map('profile'))['profile'])[
                'training_days_per_week'] as num?) ??
            3)
        .toInt();
    return <String, dynamic>{
      'completed': completed,
      'target': target,
      'percent': target == 0 ? 0.0 : (completed / target) * 100,
      'days': days,
    };
  }

  Set<String> _trainingDays() {
    final Set<String> days = <String>{};
    for (final Map<String, dynamic> s in _store.list('workout_sessions')) {
      final DateTime? on = _sessionDate(s);
      if (on != null) days.add(isoDay(on));
    }
    return days;
  }

  /// Consecutive weeks with at least one workout, reported in days the way
  /// the dashboard shows it: a run of days ending today or yesterday.
  int _workoutStreak() {
    final Set<String> days = _trainingDays();
    if (days.isEmpty) return 0;
    DateTime cursor = DateTime.now();
    if (!days.contains(isoDay(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    int streak = 0;
    while (days.contains(isoDay(cursor))) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int _longestWorkoutStreak() {
    final List<String> days = _trainingDays().toList()..sort();
    if (days.isEmpty) return 0;
    int best = 1;
    int run = 1;
    for (int i = 1; i < days.length; i++) {
      final DateTime? prev = DateTime.tryParse(days[i - 1]);
      final DateTime? cur = DateTime.tryParse(days[i]);
      if (prev == null || cur == null) continue;
      if (cur.difference(prev).inDays == 1) {
        run += 1;
        best = math.max(best, run);
      } else {
        run = 1;
      }
    }
    return best;
  }

  // --- training overview ---------------------------------------------------

  /// The progress screen's training summary, totalled from stored sessions.
  Map<String, dynamic> overview(String range) {
    final List<Map<String, dynamic>> sessions = sessionsInRange(range);
    double volume = 0;
    int sets = 0;
    int seconds = 0;
    final Map<String, List<double>> byGroup = <String, List<double>>{};

    for (final Map<String, dynamic> s in sessions) {
      volume += _sessionVolume(s);
      sets += _sessionSets(s);
      seconds += ((s['duration_seconds'] as num?) ?? 0).toInt();

      for (final dynamic e
          in (detailFor('${s['id']}')['exercises'] as List<dynamic>? ??
              <dynamic>[])) {
        final Map<String, dynamic> ex = _asMap(e);
        final String group =
            '${_asMap(ex['exercise'])['muscle_group'] ?? ex['muscle_group'] ?? 'other'}';
        double gv = 0;
        int gs = 0;
        for (final dynamic st
            in (ex['sets'] as List<dynamic>? ?? <dynamic>[])) {
          final Map<String, dynamic> set = _asMap(st);
          if (!setCounts(set)) continue;
          gv += setVolume(set);
          gs += 1;
        }
        final List<double> acc =
            byGroup.putIfAbsent(group, () => <double>[0, 0]);
        acc[0] += gv;
        acc[1] += gs;
      }
    }

    final double groupTotal =
        byGroup.values.fold<double>(0, (double a, List<double> v) => a + v[0]);
    final List<Map<String, dynamic>> groups = byGroup.entries
        .map((MapEntry<String, List<double>> e) => <String, dynamic>{
              'muscle_group': e.key,
              'volume_kg': _round1(e.value[0]),
              'set_count': e.value[1].toInt(),
              'percent': groupTotal == 0
                  ? 0.0
                  : _round1(e.value[0] / groupTotal * 100),
            })
        .toList()
      ..sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
          (b['volume_kg'] as double).compareTo(a['volume_kg'] as double));

    final int days = rangeDays(range);
    final int minutes = (seconds / 60).round();
    final int records =
        _store.list('personal_records').where((Map<String, dynamic> r) {
      final DateTime? on = DateTime.tryParse('${r['achieved_at']}');
      return on != null &&
          !on.isBefore(DateTime.now().subtract(Duration(days: days)));
    }).length;

    return <String, dynamic>{
      'range': range,
      'total_workouts': sessions.length,
      'total_duration_minutes': minutes,
      'total_volume_kg': _round1(volume),
      'total_sets': sets,
      'average_session_minutes':
          sessions.isEmpty ? 0.0 : _round1(minutes / sessions.length),
      'workouts_per_week':
          days == 0 ? 0.0 : _round1(sessions.length / (days / 7)),
      'volume_by_muscle_group': groups,
      'personal_records': records,
      'summary': sessions.isEmpty
          ? 'No workouts logged in this period.'
          : '${sessions.length} workouts, ${_round1(volume).toStringAsFixed(0)} kg lifted '
              'and $records personal records in this period.',
    };
  }

  static double _round1(double v) => double.parse(v.toStringAsFixed(1));

  // --- per-exercise progress ----------------------------------------------

  /// Every exercise the stored sessions actually contain, newest first.
  List<Map<String, dynamic>> trainedExercises() {
    final Map<String, Map<String, dynamic>> found =
        <String, Map<String, dynamic>>{};
    for (final Map<String, dynamic> s in _store.list('workout_sessions')) {
      for (final dynamic e
          in (detailFor('${s['id']}')['exercises'] as List<dynamic>? ??
              <dynamic>[])) {
        final Map<String, dynamic> ex = _asMap(e);
        final Map<String, dynamic> exercise = _asMap(ex['exercise']);
        final String? id = (exercise['id'] ?? ex['exercise_id'])?.toString();
        if (id == null || found.containsKey(id)) continue;
        if (exercise.isNotEmpty) {
          found[id] = exercise;
        } else {
          final Map<String, dynamic> lookup =
              _store.list('exercises').firstWhere(
                    (Map<String, dynamic> x) => x['id'] == id,
                    orElse: () => <String, dynamic>{},
                  );
          if (lookup.isNotEmpty) found[id] = lookup;
        }
      }
    }
    return found.values.toList();
  }

  /// One exercise's history, derived from the sets stored for it.
  ///
  /// Returns null when the stored sessions contain no work for [exerciseId],
  /// so the caller can answer 404 rather than invent a flat line.
  Map<String, dynamic>? exerciseProgress(String exerciseId, String range) {
    final DateTime from =
        DateTime.now().subtract(Duration(days: rangeDays(range)));
    final List<Map<String, dynamic>> points = <Map<String, dynamic>>[];
    String name = '';

    for (final Map<String, dynamic> s in _store.list('workout_sessions')) {
      final DateTime? on = _sessionDate(s);
      if (on == null || on.isBefore(from)) continue;
      for (final dynamic e
          in (detailFor('${s['id']}')['exercises'] as List<dynamic>? ??
              <dynamic>[])) {
        final Map<String, dynamic> ex = _asMap(e);
        final Map<String, dynamic> exercise = _asMap(ex['exercise']);
        final String id = '${exercise['id'] ?? ex['exercise_id']}';
        if (id != exerciseId) continue;
        if (name.isEmpty) name = '${exercise['name'] ?? ''}';

        double volume = 0;
        int sets = 0;
        double? bestWeight;
        int? bestReps;
        double? best1rm;
        for (final dynamic st
            in (ex['sets'] as List<dynamic>? ?? <dynamic>[])) {
          final Map<String, dynamic> set = _asMap(st);
          if (!setCounts(set)) continue;
          sets += 1;
          volume += setVolume(set);
          final num? w = set['weight_kg'] as num?;
          if (w != null && (bestWeight == null || w > bestWeight)) {
            bestWeight = w.toDouble();
            bestReps = (set['reps'] as num?)?.toInt();
          }
          final double? orm = _estimated1rm(set);
          if (orm != null && (best1rm == null || orm > best1rm)) best1rm = orm;
        }
        if (sets == 0) continue;
        points.add(<String, dynamic>{
          'performed_on': isoDay(on),
          'total_volume_kg': _round1(volume),
          'total_sets': sets,
          'best_weight_kg': bestWeight,
          'best_reps': bestReps,
          'estimated_1rm_kg': best1rm == null ? null : _round1(best1rm),
        });
      }
    }

    if (points.isEmpty) return null;
    points.sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
        '${a['performed_on']}'.compareTo('${b['performed_on']}'));

    if (name.isEmpty) {
      name = '${_store.list('exercises').firstWhere(
            (Map<String, dynamic> x) => x['id'] == exerciseId,
            orElse: () => <String, dynamic>{'name': 'Exercise'},
          )['name']}';
    }

    double? best1rm;
    for (final Map<String, dynamic> p in points) {
      final num? v = p['estimated_1rm_kg'] as num?;
      if (v != null && (best1rm == null || v > best1rm)) best1rm = v.toDouble();
    }
    double? changePct;
    if (points.length >= 2) {
      final double a = (points.first['total_volume_kg'] as num).toDouble();
      final double b = (points.last['total_volume_kg'] as num).toDouble();
      if (a != 0) changePct = _round1((b - a) / a * 100);
    }

    return <String, dynamic>{
      'exercise_id': exerciseId,
      'exercise_name': name,
      'range': range,
      'points': points,
      'best_1rm_kg': best1rm,
      'change_percent': changePct,
      'summary': '${points.length} sessions in this period.',
    };
  }
}
