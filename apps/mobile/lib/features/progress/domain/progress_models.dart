import '../../exercises/domain/exercise.dart';
import '../../goals/domain/goal.dart';
import '../../workout/domain/workout_models.dart';

class BodyWeightEntry {
  const BodyWeightEntry({
    required this.recordedOn,
    required this.weightKg,
    this.id,
    this.bodyFatPercent,
    this.muscleMassKg,
    this.note,
  });

  final DateTime recordedOn;
  final double weightKg;
  final String? id;
  final double? bodyFatPercent;
  final double? muscleMassKg;
  final String? note;

  factory BodyWeightEntry.fromJson(Map<String, dynamic> json) =>
      BodyWeightEntry(
        recordedOn: DateTime.parse(json['recorded_on'] as String),
        weightKg: (json['weight_kg'] as num).toDouble(),
        id: json['id'] as String?,
        bodyFatPercent: (json['body_fat_percent'] as num?)?.toDouble(),
        muscleMassKg: (json['muscle_mass_kg'] as num?)?.toDouble(),
        note: json['note'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'recorded_on': recordedOn.toIso8601String().split('T').first,
        'weight_kg': weightKg,
        'body_fat_percent': bodyFatPercent,
        'muscle_mass_kg': muscleMassKg,
        'note': note,
      };
}

class MeasurementEntry {
  const MeasurementEntry({
    required this.recordedOn,
    required this.measurementType,
    required this.valueCm,
    this.id,
    this.customLabel,
    this.note,
  });

  final DateTime recordedOn;
  final String measurementType;
  final double valueCm;
  final String? id;
  final String? customLabel;
  final String? note;

  String get label => customLabel ?? measurementType;

  factory MeasurementEntry.fromJson(Map<String, dynamic> json) =>
      MeasurementEntry(
        recordedOn: DateTime.parse(json['recorded_on'] as String),
        measurementType: json['measurement_type'] as String,
        valueCm: (json['value_cm'] as num).toDouble(),
        id: json['id'] as String?,
        customLabel: json['custom_label'] as String?,
        note: json['note'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'recorded_on': recordedOn.toIso8601String().split('T').first,
        'measurement_type': measurementType,
        'value_cm': valueCm,
        'custom_label': customLabel,
        'note': note,
      };
}

class ProgressPhoto {
  const ProgressPhoto({
    required this.id,
    required this.takenOn,
    required this.pose,
    this.url,
    this.thumbnailUrl,
    this.weightKg,
    this.note,
  });

  final String id;
  final DateTime takenOn;
  final String pose;

  /// Short-lived signed URL. Never cached to disk beyond the image cache.
  final String? url;
  final String? thumbnailUrl;
  final double? weightKg;
  final String? note;

  factory ProgressPhoto.fromJson(Map<String, dynamic> json) => ProgressPhoto(
        id: json['id'] as String,
        takenOn: DateTime.parse(json['taken_on'] as String),
        pose: json['pose'] as String? ?? 'front',
        url: json['url'] as String?,
        thumbnailUrl: json['thumbnail_url'] as String?,
        weightKg: (json['weight_kg'] as num?)?.toDouble(),
        note: json['note'] as String?,
      );
}

/// A single point on a chart.
class SeriesPoint {
  const SeriesPoint({required this.x, required this.y});

  final DateTime x;
  final double y;

  factory SeriesPoint.fromJson(Map<String, dynamic> json) => SeriesPoint(
        x: DateTime.parse(json['x'] as String),
        y: (json['y'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'x': x.toIso8601String().split('T').first,
        'y': y,
      };
}

class ChartSeries {
  const ChartSeries({
    required this.key,
    required this.label,
    this.unit,
    this.points = const <SeriesPoint>[],
    this.trend = const <SeriesPoint>[],
  });

  final String key;
  final String label;
  final String? unit;
  final List<SeriesPoint> points;

  /// Optional smoothed line drawn behind noisy daily values.
  final List<SeriesPoint> trend;

  bool get isEmpty => points.isEmpty;

  factory ChartSeries.fromJson(Map<String, dynamic> json) => ChartSeries(
        key: json['key'] as String,
        label: json['label'] as String,
        unit: json['unit'] as String?,
        points: ((json['points'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) => SeriesPoint.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
        trend: ((json['trend'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) => SeriesPoint.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'label': label,
        'unit': unit,
        'points': points.map((SeriesPoint p) => p.toJson()).toList(),
        'trend': trend.map((SeriesPoint p) => p.toJson()).toList(),
      };
}

class ChartData {
  const ChartData({
    required this.range,
    this.series = const <ChartSeries>[],
    this.summary,
    this.changePercent,
    this.changeAbsolute,
  });

  final String range;
  final List<ChartSeries> series;
  final String? summary;
  final double? changePercent;
  final double? changeAbsolute;

  bool get isEmpty =>
      series.isEmpty || series.every((ChartSeries item) => item.isEmpty);

  factory ChartData.fromJson(Map<String, dynamic> json) => ChartData(
        range: json['range'] as String? ?? '30d',
        series: ((json['series'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) => ChartSeries.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
        summary: json['summary'] as String?,
        changePercent: (json['change_percent'] as num?)?.toDouble(),
        changeAbsolute: (json['change_absolute'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'range': range,
        'series': series.map((ChartSeries item) => item.toJson()).toList(),
        'summary': summary,
        'change_percent': changePercent,
        'change_absolute': changeAbsolute,
      };
}

class ExerciseProgressPoint {
  const ExerciseProgressPoint({
    required this.performedOn,
    required this.totalVolumeKg,
    required this.totalSets,
    this.bestWeightKg,
    this.bestReps,
    this.estimated1rmKg,
  });

  final DateTime performedOn;
  final double totalVolumeKg;
  final int totalSets;
  final double? bestWeightKg;
  final int? bestReps;
  final double? estimated1rmKg;

  factory ExerciseProgressPoint.fromJson(Map<String, dynamic> json) =>
      ExerciseProgressPoint(
        performedOn: DateTime.parse(json['performed_on'] as String),
        totalVolumeKg: (json['total_volume_kg'] as num?)?.toDouble() ?? 0,
        totalSets: json['total_sets'] as int? ?? 0,
        bestWeightKg: (json['best_weight_kg'] as num?)?.toDouble(),
        bestReps: json['best_reps'] as int?,
        estimated1rmKg: (json['estimated_1rm_kg'] as num?)?.toDouble(),
      );
}

class ExerciseProgress {
  const ExerciseProgress({
    required this.exerciseId,
    required this.exerciseName,
    required this.range,
    this.points = const <ExerciseProgressPoint>[],
    this.best1rmKg,
    this.changePercent,
    this.summary,
  });

  final String exerciseId;
  final String exerciseName;
  final String range;
  final List<ExerciseProgressPoint> points;
  final double? best1rmKg;
  final double? changePercent;
  final String? summary;

  factory ExerciseProgress.fromJson(Map<String, dynamic> json) =>
      ExerciseProgress(
        exerciseId: json['exercise_id'] as String,
        exerciseName: json['exercise_name'] as String,
        range: json['range'] as String? ?? '6m',
        points: ((json['points'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) => ExerciseProgressPoint.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
        best1rmKg: (json['best_1rm_kg'] as num?)?.toDouble(),
        changePercent: (json['change_percent'] as num?)?.toDouble(),
        summary: json['summary'] as String?,
      );
}

class MuscleGroupVolume {
  const MuscleGroupVolume({
    required this.muscleGroup,
    required this.volumeKg,
    required this.setCount,
    required this.percent,
  });

  final String muscleGroup;
  final double volumeKg;
  final int setCount;
  final double percent;

  factory MuscleGroupVolume.fromJson(Map<String, dynamic> json) =>
      MuscleGroupVolume(
        muscleGroup: json['muscle_group'] as String,
        volumeKg: (json['volume_kg'] as num?)?.toDouble() ?? 0,
        setCount: json['set_count'] as int? ?? 0,
        percent: (json['percent'] as num?)?.toDouble() ?? 0,
      );
}

class TrainingOverview {
  const TrainingOverview({
    required this.range,
    required this.totalWorkouts,
    required this.totalDurationMinutes,
    required this.totalVolumeKg,
    required this.totalSets,
    required this.averageSessionMinutes,
    required this.workoutsPerWeek,
    this.volumeByMuscleGroup = const <MuscleGroupVolume>[],
    this.personalRecords = 0,
    this.summary,
  });

  final String range;
  final int totalWorkouts;
  final int totalDurationMinutes;
  final double totalVolumeKg;
  final int totalSets;
  final double averageSessionMinutes;
  final double workoutsPerWeek;
  final List<MuscleGroupVolume> volumeByMuscleGroup;
  final int personalRecords;
  final String? summary;

  factory TrainingOverview.fromJson(Map<String, dynamic> json) =>
      TrainingOverview(
        range: json['range'] as String? ?? '30d',
        totalWorkouts: json['total_workouts'] as int? ?? 0,
        totalDurationMinutes: json['total_duration_minutes'] as int? ?? 0,
        totalVolumeKg: (json['total_volume_kg'] as num?)?.toDouble() ?? 0,
        totalSets: json['total_sets'] as int? ?? 0,
        averageSessionMinutes:
            (json['average_session_minutes'] as num?)?.toDouble() ?? 0,
        workoutsPerWeek: (json['workouts_per_week'] as num?)?.toDouble() ?? 0,
        volumeByMuscleGroup:
            ((json['volume_by_muscle_group'] as List<dynamic>?) ??
                    const <dynamic>[])
                .map((dynamic item) => MuscleGroupVolume.fromJson(
                    Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
                .toList(),
        personalRecords: json['personal_records'] as int? ?? 0,
        summary: json['summary'] as String?,
      );
}

// --- dashboard -------------------------------------------------------------

class MacroRing {
  const MacroRing({required this.consumed, this.target, this.percent});

  final double consumed;
  final double? target;
  final double? percent;

  double get fraction =>
      target == null || target == 0 ? 0 : (consumed / target!).clamp(0.0, 1.0);

  double? get remaining => target == null ? null : target! - consumed;

  factory MacroRing.fromJson(Map<String, dynamic> json) => MacroRing(
        consumed: (json['consumed'] as num?)?.toDouble() ?? 0,
        target: (json['target'] as num?)?.toDouble(),
        percent: (json['percent'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'consumed': consumed,
        'target': target,
        'percent': percent,
      };
}

class TodayWorkout {
  const TodayWorkout({
    required this.programId,
    required this.programName,
    required this.dayId,
    required this.dayName,
    required this.exerciseCount,
    this.estimatedMinutes,
    this.isRestDay = false,
  });

  final String programId;
  final String programName;
  final String dayId;
  final String dayName;
  final int exerciseCount;
  final int? estimatedMinutes;
  final bool isRestDay;

  factory TodayWorkout.fromJson(Map<String, dynamic> json) => TodayWorkout(
        programId: json['program_id'] as String,
        programName: json['program_name'] as String,
        dayId: json['day_id'] as String,
        dayName: json['day_name'] as String,
        exerciseCount: json['exercise_count'] as int? ?? 0,
        estimatedMinutes: json['estimated_minutes'] as int?,
        isRestDay: json['is_rest_day'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'program_id': programId,
        'program_name': programName,
        'day_id': dayId,
        'day_name': dayName,
        'exercise_count': exerciseCount,
        'estimated_minutes': estimatedMinutes,
        'is_rest_day': isRestDay,
      };
}

class ActiveSessionRef {
  const ActiveSessionRef({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.completedSetCount,
    required this.totalSetCount,
  });

  final String id;
  final String name;
  final DateTime startedAt;
  final int completedSetCount;
  final int totalSetCount;

  factory ActiveSessionRef.fromJson(Map<String, dynamic> json) =>
      ActiveSessionRef(
        id: json['id'] as String,
        name: json['name'] as String,
        startedAt: DateTime.parse(json['started_at'] as String).toLocal(),
        completedSetCount: json['completed_set_count'] as int? ?? 0,
        totalSetCount: json['total_set_count'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'started_at': startedAt.toUtc().toIso8601String(),
        'completed_set_count': completedSetCount,
        'total_set_count': totalSetCount,
      };
}

class WeeklyProgress {
  const WeeklyProgress({
    required this.completed,
    required this.target,
    required this.percent,
    this.days = const <bool>[],
  });

  final int completed;
  final int target;
  final double percent;

  /// Monday-first flags for the current week.
  final List<bool> days;

  factory WeeklyProgress.fromJson(Map<String, dynamic> json) => WeeklyProgress(
        completed: json['completed'] as int? ?? 0,
        target: json['target'] as int? ?? 3,
        percent: (json['percent'] as num?)?.toDouble() ?? 0,
        days: ((json['days'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) => item == true)
            .toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'completed': completed,
        'target': target,
        'percent': percent,
        'days': days,
      };
}

class DashboardData {
  const DashboardData({
    required this.greetingName,
    required this.date,
    required this.calories,
    required this.proteinG,
    required this.waterMl,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.weeklyWorkouts,
    this.todayWorkout,
    this.activeSession,
    this.weightTrend,
    this.latestWeightKg,
    this.weightChange30dKg,
    this.recentRecords = const <PersonalRecord>[],
    this.activeGoals = const <Goal>[],
    this.habitsCompletedToday = 0,
    this.habitsTotalToday = 0,
    this.unreadNotifications = 0,
  });

  final String greetingName;
  final DateTime date;
  final MacroRing calories;
  final MacroRing proteinG;
  final MacroRing waterMl;
  final int currentStreakDays;
  final int longestStreakDays;
  final WeeklyProgress weeklyWorkouts;
  final TodayWorkout? todayWorkout;
  final ActiveSessionRef? activeSession;
  final ChartSeries? weightTrend;
  final double? latestWeightKg;
  final double? weightChange30dKg;
  final List<PersonalRecord> recentRecords;
  final List<Goal> activeGoals;
  final int habitsCompletedToday;
  final int habitsTotalToday;
  final int unreadNotifications;

  factory DashboardData.fromJson(Map<String, dynamic> json) => DashboardData(
        greetingName: json['greeting_name'] as String? ?? '',
        date: DateTime.tryParse('${json['date']}') ?? DateTime.now(),
        calories: MacroRing.fromJson(
          Map<String, dynamic>.from(json['calories'] as Map<dynamic, dynamic>),
        ),
        proteinG: MacroRing.fromJson(
          Map<String, dynamic>.from(json['protein_g'] as Map<dynamic, dynamic>),
        ),
        waterMl: MacroRing.fromJson(
          Map<String, dynamic>.from(json['water_ml'] as Map<dynamic, dynamic>),
        ),
        currentStreakDays: json['current_streak_days'] as int? ?? 0,
        longestStreakDays: json['longest_streak_days'] as int? ?? 0,
        weeklyWorkouts: WeeklyProgress.fromJson(
          Map<String, dynamic>.from(
            json['weekly_workouts'] as Map<dynamic, dynamic>,
          ),
        ),
        todayWorkout: json['today_workout'] == null
            ? null
            : TodayWorkout.fromJson(
                Map<String, dynamic>.from(
                  json['today_workout'] as Map<dynamic, dynamic>,
                ),
              ),
        activeSession: json['active_session'] == null
            ? null
            : ActiveSessionRef.fromJson(
                Map<String, dynamic>.from(
                  json['active_session'] as Map<dynamic, dynamic>,
                ),
              ),
        weightTrend: json['weight_trend'] == null
            ? null
            : ChartSeries.fromJson(
                Map<String, dynamic>.from(
                  json['weight_trend'] as Map<dynamic, dynamic>,
                ),
              ),
        latestWeightKg: (json['latest_weight_kg'] as num?)?.toDouble(),
        weightChange30dKg: (json['weight_change_30d_kg'] as num?)?.toDouble(),
        recentRecords:
            ((json['recent_records'] as List<dynamic>?) ?? const <dynamic>[])
                .map((dynamic item) => PersonalRecord.fromJson(
                    Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
                .toList(),
        activeGoals:
            ((json['active_goals'] as List<dynamic>?) ?? const <dynamic>[])
                .map((dynamic item) => Goal.fromJson(
                    Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
                .toList(),
        habitsCompletedToday: json['habits_completed_today'] as int? ?? 0,
        habitsTotalToday: json['habits_total_today'] as int? ?? 0,
        unreadNotifications: json['unread_notifications'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'greeting_name': greetingName,
        'date': date.toIso8601String().split('T').first,
        'calories': calories.toJson(),
        'protein_g': proteinG.toJson(),
        'water_ml': waterMl.toJson(),
        'current_streak_days': currentStreakDays,
        'longest_streak_days': longestStreakDays,
        'weekly_workouts': weeklyWorkouts.toJson(),
        'today_workout': todayWorkout?.toJson(),
        'active_session': activeSession?.toJson(),
        'weight_trend': weightTrend?.toJson(),
        'latest_weight_kg': latestWeightKg,
        'weight_change_30d_kg': weightChange30dKg,
        'recent_records': recentRecords
            .map((PersonalRecord record) => record.toJson())
            .toList(),
        'active_goals': activeGoals.map((Goal goal) => goal.toJson()).toList(),
        'habits_completed_today': habitsCompletedToday,
        'habits_total_today': habitsTotalToday,
        'unread_notifications': unreadNotifications,
      };
}

/// Convenience alias so progress screens can reference the shared type.
typedef TrainedExercise = Exercise;
