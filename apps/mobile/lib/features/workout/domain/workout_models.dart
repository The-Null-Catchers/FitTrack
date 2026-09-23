import '../../exercises/domain/exercise.dart';

/// One logged set.
///
/// [localId] exists because a set can be created offline, before the server
/// has assigned an id. It is stable for the lifetime of the session and is what
/// the UI keys on.
class WorkoutSet {
  const WorkoutSet({
    required this.localId,
    required this.setNumber,
    this.id,
    this.setType = 'normal',
    this.weightKg,
    this.reps,
    this.durationSeconds,
    this.distanceM,
    this.calories,
    this.rpe,
    this.rir,
    this.isCompleted = false,
    this.notes,
    this.estimated1rmKg,
    this.volumeKg = 0,
  });

  final String localId;
  final int setNumber;
  final String? id;
  final String setType;
  final double? weightKg;
  final int? reps;
  final int? durationSeconds;
  final double? distanceM;
  final int? calories;
  final double? rpe;
  final int? rir;
  final bool isCompleted;
  final String? notes;
  final double? estimated1rmKg;
  final double volumeKg;

  bool get isWarmUp => setType == 'warmup';

  bool get hasValue =>
      weightKg != null ||
      reps != null ||
      durationSeconds != null ||
      distanceM != null ||
      calories != null;

  WorkoutSet copyWith({
    int? setNumber,
    String? id,
    String? setType,
    double? weightKg,
    int? reps,
    int? durationSeconds,
    double? distanceM,
    int? calories,
    double? rpe,
    int? rir,
    bool? isCompleted,
    String? notes,
    double? estimated1rmKg,
    double? volumeKg,
    bool clearWeight = false,
    bool clearReps = false,
  }) =>
      WorkoutSet(
        localId: localId,
        setNumber: setNumber ?? this.setNumber,
        id: id ?? this.id,
        setType: setType ?? this.setType,
        weightKg: clearWeight ? null : (weightKg ?? this.weightKg),
        reps: clearReps ? null : (reps ?? this.reps),
        durationSeconds: durationSeconds ?? this.durationSeconds,
        distanceM: distanceM ?? this.distanceM,
        calories: calories ?? this.calories,
        rpe: rpe ?? this.rpe,
        rir: rir ?? this.rir,
        isCompleted: isCompleted ?? this.isCompleted,
        notes: notes ?? this.notes,
        estimated1rmKg: estimated1rmKg ?? this.estimated1rmKg,
        volumeKg: volumeKg ?? this.volumeKg,
      );

  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
        localId: json['local_id'] as String? ??
            json['id'] as String? ??
            'set-${json['set_number']}',
        setNumber: json['set_number'] as int? ?? 1,
        id: json['id'] as String?,
        setType: json['set_type'] as String? ?? 'normal',
        weightKg: (json['weight_kg'] as num?)?.toDouble(),
        reps: json['reps'] as int?,
        durationSeconds: json['duration_seconds'] as int?,
        distanceM: (json['distance_m'] as num?)?.toDouble(),
        calories: json['calories'] as int?,
        rpe: (json['rpe'] as num?)?.toDouble(),
        rir: json['rir'] as int?,
        isCompleted: json['is_completed'] as bool? ?? false,
        notes: json['notes'] as String?,
        estimated1rmKg: (json['estimated_1rm_kg'] as num?)?.toDouble(),
        volumeKg: (json['volume_kg'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'local_id': localId,
        'id': id,
        'set_number': setNumber,
        'set_type': setType,
        'weight_kg': weightKg,
        'reps': reps,
        'duration_seconds': durationSeconds,
        'distance_m': distanceM,
        'calories': calories,
        'rpe': rpe,
        'rir': rir,
        'is_completed': isCompleted,
        'notes': notes,
        'estimated_1rm_kg': estimated1rmKg,
        'volume_kg': volumeKg,
      };

  /// The subset the API accepts when writing a set.
  Map<String, dynamic> toWriteJson() => <String, dynamic>{
        'set_number': setNumber,
        'set_type': setType,
        if (weightKg != null) 'weight_kg': weightKg,
        if (reps != null) 'reps': reps,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        if (distanceM != null) 'distance_m': distanceM,
        if (calories != null) 'calories': calories,
        if (rpe != null) 'rpe': rpe,
        if (rir != null) 'rir': rir,
        'is_completed': isCompleted,
        if (notes != null) 'notes': notes,
      };
}

/// What the user did with this exercise last time.
class PreviousPerformance {
  const PreviousPerformance({
    required this.performedAt,
    required this.sets,
    this.bestSet,
    this.totalVolumeKg = 0,
  });

  final DateTime performedAt;
  final List<WorkoutSet> sets;
  final WorkoutSet? bestSet;
  final double totalVolumeKg;

  factory PreviousPerformance.fromJson(Map<String, dynamic> json) =>
      PreviousPerformance(
        performedAt:
            DateTime.tryParse('${json['performed_at']}') ?? DateTime.now(),
        sets: ((json['sets'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) => WorkoutSet.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
        bestSet: json['best_set'] == null
            ? null
            : WorkoutSet.fromJson(
                Map<String, dynamic>.from(
                    json['best_set'] as Map<dynamic, dynamic>),
              ),
        totalVolumeKg: (json['total_volume_kg'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'performed_at': performedAt.toIso8601String(),
        'sets': sets.map((WorkoutSet set) => set.toJson()).toList(),
        'best_set': bestSet?.toJson(),
        'total_volume_kg': totalVolumeKg,
      };
}

class SessionExercise {
  const SessionExercise({
    required this.localId,
    required this.exercise,
    required this.position,
    required this.trackingType,
    required this.restSeconds,
    this.id,
    this.notes,
    this.supersetGroup,
    this.targetSnapshot = const <String, dynamic>{},
    this.sets = const <WorkoutSet>[],
    this.previous,
    this.progressionHint,
  });

  final String localId;
  final Exercise exercise;
  final int position;
  final String trackingType;
  final int restSeconds;
  final String? id;
  final String? notes;
  final int? supersetGroup;
  final Map<String, dynamic> targetSnapshot;
  final List<WorkoutSet> sets;
  final PreviousPerformance? previous;
  final String? progressionHint;

  int get completedSets =>
      sets.where((WorkoutSet set) => set.isCompleted).length;

  int get targetSets => (targetSnapshot['sets'] as int?) ?? sets.length;

  bool get isComplete => sets.isNotEmpty && completedSets >= sets.length;

  /// "4 × 6-8" from the prescription copied at session start.
  String? get targetLabel {
    final int? setCount = targetSnapshot['sets'] as int?;
    if (setCount == null) return null;
    final int? min = targetSnapshot['reps_min'] as int?;
    final int? max = targetSnapshot['reps_max'] as int?;
    final int? seconds = targetSnapshot['duration_seconds'] as int?;
    if (seconds != null) return '$setCount × ${seconds}s';
    if (min == null && max == null) return '$setCount sets';
    if (min != null && max != null && min != max)
      return '$setCount × $min-$max';
    return '$setCount × ${max ?? min}';
  }

  SessionExercise copyWith({
    List<WorkoutSet>? sets,
    String? notes,
    int? position,
    String? id,
    Exercise? exercise,
    String? trackingType,
    int? restSeconds,
    PreviousPerformance? previous,
    String? progressionHint,
  }) =>
      SessionExercise(
        localId: localId,
        exercise: exercise ?? this.exercise,
        position: position ?? this.position,
        trackingType: trackingType ?? this.trackingType,
        restSeconds: restSeconds ?? this.restSeconds,
        id: id ?? this.id,
        notes: notes ?? this.notes,
        supersetGroup: supersetGroup,
        targetSnapshot: targetSnapshot,
        sets: sets ?? this.sets,
        previous: previous ?? this.previous,
        progressionHint: progressionHint ?? this.progressionHint,
      );

  factory SessionExercise.fromJson(Map<String, dynamic> json) =>
      SessionExercise(
        localId: json['local_id'] as String? ?? json['id'] as String? ?? '',
        exercise: Exercise.fromJson(
          Map<String, dynamic>.from(json['exercise'] as Map<dynamic, dynamic>),
        ),
        position: json['position'] as int? ?? 0,
        trackingType: json['tracking_type'] as String? ?? 'weight_reps',
        restSeconds: json['rest_seconds'] as int? ?? 90,
        id: json['id'] as String?,
        notes: json['notes'] as String?,
        supersetGroup: json['superset_group'] as int?,
        targetSnapshot: Map<String, dynamic>.from(
          (json['target_snapshot'] as Map<dynamic, dynamic>?) ??
              <dynamic, dynamic>{},
        ),
        sets: ((json['sets'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) => WorkoutSet.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
        previous: json['previous'] == null
            ? null
            : PreviousPerformance.fromJson(
                Map<String, dynamic>.from(
                    json['previous'] as Map<dynamic, dynamic>),
              ),
        progressionHint: json['progression_hint'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'local_id': localId,
        'id': id,
        'exercise': exercise.toJson(),
        'position': position,
        'tracking_type': trackingType,
        'rest_seconds': restSeconds,
        'notes': notes,
        'superset_group': supersetGroup,
        'target_snapshot': targetSnapshot,
        'sets': sets.map((WorkoutSet set) => set.toJson()).toList(),
        'previous': previous?.toJson(),
        'progression_hint': progressionHint,
      };

  /// The shape the sync endpoint expects for a finished session.
  Map<String, dynamic> toSyncJson() => <String, dynamic>{
        'exercise_id': exercise.id,
        'position': position,
        'tracking_type': trackingType,
        'rest_seconds': restSeconds,
        if (notes != null) 'notes': notes,
        if (supersetGroup != null) 'superset_group': supersetGroup,
        'target_snapshot': targetSnapshot,
        'sets': sets
            .where((WorkoutSet set) => set.hasValue)
            .map((WorkoutSet set) => set.toWriteJson())
            .toList(),
      };
}

class PersonalRecord {
  const PersonalRecord({
    required this.id,
    required this.recordType,
    required this.value,
    required this.unit,
    required this.achievedAt,
    required this.exercise,
    this.reps,
    this.weightKg,
    this.previousValue,
    this.acknowledgedAt,
  });

  final String id;
  final String recordType;
  final double value;
  final String unit;
  final DateTime achievedAt;
  final Exercise exercise;
  final int? reps;
  final double? weightKg;
  final double? previousValue;
  final DateTime? acknowledgedAt;

  double? get improvement =>
      previousValue == null ? null : value - previousValue!;

  factory PersonalRecord.fromJson(Map<String, dynamic> json) => PersonalRecord(
        id: json['id'] as String,
        recordType: json['record_type'] as String,
        value: (json['value'] as num).toDouble(),
        unit: json['unit'] as String? ?? '',
        achievedAt:
            DateTime.tryParse('${json['achieved_at']}') ?? DateTime.now(),
        exercise: Exercise.fromJson(
          Map<String, dynamic>.from(json['exercise'] as Map<dynamic, dynamic>),
        ),
        reps: json['reps'] as int?,
        weightKg: (json['weight_kg'] as num?)?.toDouble(),
        previousValue: (json['previous_value'] as num?)?.toDouble(),
        acknowledgedAt: json['acknowledged_at'] == null
            ? null
            : DateTime.tryParse('${json['acknowledged_at']}'),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'record_type': recordType,
        'value': value,
        'unit': unit,
        'achieved_at': achievedAt.toIso8601String(),
        'exercise': exercise.toJson(),
        'reps': reps,
        'weight_kg': weightKg,
        'previous_value': previousValue,
        'acknowledged_at': acknowledgedAt?.toIso8601String(),
      };
}

class WorkoutSession {
  const WorkoutSession({
    required this.localId,
    required this.name,
    required this.status,
    required this.startedAt,
    this.id,
    this.programId,
    this.dayId,
    this.completedAt,
    this.durationSeconds,
    this.notes,
    this.perceivedEffort,
    this.bodyweightKg,
    this.totalVolumeKg = 0,
    this.totalSets = 0,
    this.totalReps = 0,
    this.estimatedCalories,
    this.exerciseCount = 0,
    this.prCount = 0,
    this.exercises = const <SessionExercise>[],
    this.personalRecords = const <PersonalRecord>[],
    this.isLocalOnly = false,
  });

  /// Client-generated id; doubles as the server's idempotency key.
  final String localId;
  final String name;
  final String status;
  final DateTime startedAt;
  final String? id;
  final String? programId;
  final String? dayId;
  final DateTime? completedAt;
  final int? durationSeconds;
  final String? notes;
  final int? perceivedEffort;
  final double? bodyweightKg;
  final double totalVolumeKg;
  final int totalSets;
  final int totalReps;
  final int? estimatedCalories;
  final int exerciseCount;
  final int prCount;
  final List<SessionExercise> exercises;
  final List<PersonalRecord> personalRecords;

  /// True while the session exists only on this device.
  final bool isLocalOnly;

  bool get isInProgress => status == 'in_progress';

  bool get isCompleted => status == 'completed';

  int get completedSetCount => exercises.fold<int>(
        0,
        (int sum, SessionExercise item) => sum + item.completedSets,
      );

  int get plannedSetCount => exercises.fold<int>(
      0, (int sum, SessionExercise item) => sum + item.sets.length);

  /// Volume computed locally, so the summary is right even offline.
  double get localVolumeKg => exercises.fold<double>(
        0,
        (double sum, SessionExercise item) =>
            sum +
            item.sets.where((WorkoutSet set) => set.isCompleted).fold<double>(
                0, (double s, WorkoutSet set) => s + set.volumeKg),
      );

  Duration get elapsed => DateTime.now().difference(startedAt);

  WorkoutSession copyWith({
    String? id,
    String? name,
    String? status,
    DateTime? completedAt,
    int? durationSeconds,
    String? notes,
    int? perceivedEffort,
    double? bodyweightKg,
    List<SessionExercise>? exercises,
    List<PersonalRecord>? personalRecords,
    bool? isLocalOnly,
    double? totalVolumeKg,
    int? totalSets,
    int? totalReps,
    int? estimatedCalories,
  }) =>
      WorkoutSession(
        localId: localId,
        name: name ?? this.name,
        status: status ?? this.status,
        startedAt: startedAt,
        id: id ?? this.id,
        programId: programId,
        dayId: dayId,
        completedAt: completedAt ?? this.completedAt,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        notes: notes ?? this.notes,
        perceivedEffort: perceivedEffort ?? this.perceivedEffort,
        bodyweightKg: bodyweightKg ?? this.bodyweightKg,
        totalVolumeKg: totalVolumeKg ?? this.totalVolumeKg,
        totalSets: totalSets ?? this.totalSets,
        totalReps: totalReps ?? this.totalReps,
        estimatedCalories: estimatedCalories ?? this.estimatedCalories,
        exerciseCount: exercises?.length ?? exerciseCount,
        prCount: personalRecords?.length ?? prCount,
        exercises: exercises ?? this.exercises,
        personalRecords: personalRecords ?? this.personalRecords,
        isLocalOnly: isLocalOnly ?? this.isLocalOnly,
      );

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
        localId: json['local_id'] as String? ??
            json['client_uuid'] as String? ??
            json['id'] as String? ??
            '',
        name: json['name'] as String? ?? 'Workout',
        status: json['status'] as String? ?? 'in_progress',
        startedAt: DateTime.tryParse('${json['started_at']}')?.toLocal() ??
            DateTime.now(),
        id: json['id'] as String?,
        programId: json['program_id'] as String?,
        dayId: json['day_id'] as String?,
        completedAt: json['completed_at'] == null
            ? null
            : DateTime.tryParse('${json['completed_at']}')?.toLocal(),
        durationSeconds: json['duration_seconds'] as int?,
        notes: json['notes'] as String?,
        perceivedEffort: json['perceived_effort'] as int?,
        bodyweightKg: (json['bodyweight_kg'] as num?)?.toDouble(),
        totalVolumeKg: (json['total_volume_kg'] as num?)?.toDouble() ?? 0,
        totalSets: json['total_sets'] as int? ?? 0,
        totalReps: json['total_reps'] as int? ?? 0,
        estimatedCalories: json['estimated_calories'] as int?,
        exerciseCount: json['exercise_count'] as int? ?? 0,
        prCount: json['pr_count'] as int? ?? 0,
        exercises: ((json['exercises'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) => SessionExercise.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
        personalRecords:
            ((json['personal_records'] as List<dynamic>?) ?? const <dynamic>[])
                .map((dynamic item) => PersonalRecord.fromJson(
                    Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
                .toList(),
        isLocalOnly: json['is_local_only'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'local_id': localId,
        'id': id,
        'client_uuid': localId,
        'name': name,
        'status': status,
        'started_at': startedAt.toUtc().toIso8601String(),
        'program_id': programId,
        'day_id': dayId,
        'completed_at': completedAt?.toUtc().toIso8601String(),
        'duration_seconds': durationSeconds,
        'notes': notes,
        'perceived_effort': perceivedEffort,
        'bodyweight_kg': bodyweightKg,
        'total_volume_kg': totalVolumeKg,
        'total_sets': totalSets,
        'total_reps': totalReps,
        'estimated_calories': estimatedCalories,
        'exercise_count': exerciseCount,
        'pr_count': prCount,
        'exercises':
            exercises.map((SessionExercise item) => item.toJson()).toList(),
        'personal_records': personalRecords
            .map((PersonalRecord record) => record.toJson())
            .toList(),
        'is_local_only': isLocalOnly,
      };

  /// Payload for `/sync/push` when a workout was finished offline.
  Map<String, dynamic> toSyncPayload() => <String, dynamic>{
        'client_uuid': localId,
        if (programId != null) 'program_id': programId,
        if (dayId != null) 'day_id': dayId,
        'name': name,
        'started_at': startedAt.toUtc().toIso8601String(),
        'finished': true,
        if (completedAt != null)
          'completed_at': completedAt!.toUtc().toIso8601String(),
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        if (notes != null) 'notes': notes,
        if (perceivedEffort != null) 'perceived_effort': perceivedEffort,
        'exercises':
            exercises.map((SessionExercise item) => item.toSyncJson()).toList(),
      };
}
