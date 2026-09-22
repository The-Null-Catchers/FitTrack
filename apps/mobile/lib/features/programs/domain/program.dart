import '../../exercises/domain/exercise.dart';

/// A prescribed exercise inside a program day.
class DayExercise {
  const DayExercise({
    required this.id,
    required this.exercise,
    required this.position,
    required this.targetSets,
    required this.restSeconds,
    required this.trackingType,
    this.targetRepsMin,
    this.targetRepsMax,
    this.targetWeightKg,
    this.targetDurationSeconds,
    this.targetDistanceM,
    this.targetRpe,
    this.targetRir,
    this.supersetGroup,
    this.notes,
  });

  final String id;
  final Exercise exercise;
  final int position;
  final int targetSets;
  final int restSeconds;
  final String trackingType;
  final int? targetRepsMin;
  final int? targetRepsMax;
  final double? targetWeightKg;
  final int? targetDurationSeconds;
  final double? targetDistanceM;
  final double? targetRpe;
  final int? targetRir;
  final int? supersetGroup;
  final String? notes;

  /// "4 × 6-10", or "3 × 45s" for timed work.
  String get prescription {
    if (trackingType == 'duration' && targetDurationSeconds != null) {
      return '$targetSets × ${targetDurationSeconds}s';
    }
    if (targetRepsMin == null && targetRepsMax == null) {
      return '$targetSets sets';
    }
    if (targetRepsMin != null &&
        targetRepsMax != null &&
        targetRepsMin != targetRepsMax) {
      return '$targetSets × $targetRepsMin-$targetRepsMax';
    }
    return '$targetSets × ${targetRepsMax ?? targetRepsMin}';
  }

  factory DayExercise.fromJson(Map<String, dynamic> json) => DayExercise(
        id: json['id'] as String,
        exercise: Exercise.fromJson(
          Map<String, dynamic>.from(json['exercise'] as Map<dynamic, dynamic>),
        ),
        position: json['position'] as int? ?? 0,
        targetSets: json['target_sets'] as int? ?? 3,
        restSeconds: json['rest_seconds'] as int? ?? 90,
        trackingType: json['tracking_type'] as String? ?? 'weight_reps',
        targetRepsMin: json['target_reps_min'] as int?,
        targetRepsMax: json['target_reps_max'] as int?,
        targetWeightKg: (json['target_weight_kg'] as num?)?.toDouble(),
        targetDurationSeconds: json['target_duration_seconds'] as int?,
        targetDistanceM: (json['target_distance_m'] as num?)?.toDouble(),
        targetRpe: (json['target_rpe'] as num?)?.toDouble(),
        targetRir: json['target_rir'] as int?,
        supersetGroup: json['superset_group'] as int?,
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'exercise': exercise.toJson(),
        'position': position,
        'target_sets': targetSets,
        'rest_seconds': restSeconds,
        'tracking_type': trackingType,
        'target_reps_min': targetRepsMin,
        'target_reps_max': targetRepsMax,
        'target_weight_kg': targetWeightKg,
        'target_duration_seconds': targetDurationSeconds,
        'target_distance_m': targetDistanceM,
        'target_rpe': targetRpe,
        'target_rir': targetRir,
        'superset_group': supersetGroup,
        'notes': notes,
      };
}

class ProgramDay {
  const ProgramDay({
    required this.id,
    required this.name,
    required this.position,
    required this.isRestDay,
    this.weekday,
    this.notes,
    this.exercises = const <DayExercise>[],
  });

  final String id;
  final String name;
  final int position;
  final bool isRestDay;
  final int? weekday;
  final String? notes;
  final List<DayExercise> exercises;

  factory ProgramDay.fromJson(Map<String, dynamic> json) => ProgramDay(
        id: json['id'] as String,
        name: json['name'] as String,
        position: json['position'] as int? ?? 0,
        isRestDay: json['is_rest_day'] as bool? ?? false,
        weekday: json['weekday'] as int?,
        notes: json['notes'] as String?,
        exercises: ((json['exercises'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) => DayExercise.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'position': position,
        'is_rest_day': isRestDay,
        'weekday': weekday,
        'notes': notes,
        'exercises': exercises.map((DayExercise e) => e.toJson()).toList(),
      };
}

class Program {
  const Program({
    required this.id,
    required this.name,
    required this.status,
    required this.isTemplate,
    required this.daysPerWeek,
    this.description,
    this.goal,
    this.difficulty,
    this.location,
    this.estimatedMinutes,
    this.equipmentNeeded = const <String>[],
    this.generatedByAi = false,
    this.isFeatured = false,
    this.dayCount = 0,
    this.exerciseCount = 0,
    this.days = const <ProgramDay>[],
  });

  final String id;
  final String name;
  final String status;
  final bool isTemplate;
  final int daysPerWeek;
  final String? description;
  final String? goal;
  final String? difficulty;
  final String? location;
  final int? estimatedMinutes;
  final List<String> equipmentNeeded;
  final bool generatedByAi;
  final bool isFeatured;
  final int dayCount;
  final int exerciseCount;
  final List<ProgramDay> days;

  bool get isActive => status == 'active';

  List<ProgramDay> get trainingDays =>
      days.where((ProgramDay day) => !day.isRestDay).toList();

  factory Program.fromJson(Map<String, dynamic> json) => Program(
        id: json['id'] as String,
        name: json['name'] as String,
        status: json['status'] as String? ?? 'draft',
        isTemplate: json['is_template'] as bool? ?? false,
        daysPerWeek: json['days_per_week'] as int? ?? 3,
        description: json['description'] as String?,
        goal: json['goal'] as String?,
        difficulty: json['difficulty'] as String?,
        location: json['location'] as String?,
        estimatedMinutes: json['estimated_minutes'] as int?,
        equipmentNeeded:
            ((json['equipment_needed'] as List<dynamic>?) ?? const <dynamic>[])
                .map((dynamic item) => '$item')
                .toList(),
        generatedByAi: json['generated_by_ai'] as bool? ?? false,
        isFeatured: json['is_featured'] as bool? ?? false,
        dayCount: json['day_count'] as int? ?? 0,
        exerciseCount: json['exercise_count'] as int? ?? 0,
        days: ((json['days'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) => ProgramDay.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'status': status,
        'is_template': isTemplate,
        'days_per_week': daysPerWeek,
        'description': description,
        'goal': goal,
        'difficulty': difficulty,
        'location': location,
        'estimated_minutes': estimatedMinutes,
        'equipment_needed': equipmentNeeded,
        'generated_by_ai': generatedByAi,
        'is_featured': isFeatured,
        'day_count': dayCount,
        'exercise_count': exerciseCount,
        'days': days.map((ProgramDay day) => day.toJson()).toList(),
      };
}
