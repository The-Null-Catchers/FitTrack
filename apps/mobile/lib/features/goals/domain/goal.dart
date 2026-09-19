class Goal {
  const Goal({
    required this.id,
    required this.goalType,
    required this.title,
    required this.targetValue,
    required this.unit,
    required this.isDecreasing,
    required this.startDate,
    required this.status,
    required this.progressPercent,
    this.description,
    this.exerciseId,
    this.exerciseName,
    this.measurementType,
    this.startValue,
    this.currentValue,
    this.targetDate,
    this.achievedAt,
    this.daysRemaining,
  });

  final String id;
  final String goalType;
  final String title;
  final double targetValue;
  final String unit;
  final bool isDecreasing;
  final DateTime startDate;
  final String status;
  final double progressPercent;
  final String? description;
  final String? exerciseId;
  final String? exerciseName;
  final String? measurementType;
  final double? startValue;
  final double? currentValue;
  final DateTime? targetDate;
  final DateTime? achievedAt;
  final int? daysRemaining;

  bool get isAchieved => status == 'achieved';

  bool get isActive => status == 'active';

  double get fraction => (progressPercent / 100).clamp(0.0, 1.0);

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: json['id'] as String,
        goalType: json['goal_type'] as String? ?? 'custom',
        title: json['title'] as String,
        targetValue: (json['target_value'] as num).toDouble(),
        unit: json['unit'] as String? ?? '',
        isDecreasing: json['is_decreasing'] as bool? ?? false,
        startDate: DateTime.parse(json['start_date'] as String),
        status: json['status'] as String? ?? 'active',
        progressPercent: (json['progress_percent'] as num?)?.toDouble() ?? 0,
        description: json['description'] as String?,
        exerciseId: json['exercise_id'] as String?,
        exerciseName: json['exercise_name'] as String?,
        measurementType: json['measurement_type'] as String?,
        startValue: (json['start_value'] as num?)?.toDouble(),
        currentValue: (json['current_value'] as num?)?.toDouble(),
        targetDate: json['target_date'] == null
            ? null
            : DateTime.tryParse(json['target_date'] as String),
        achievedAt: json['achieved_at'] == null
            ? null
            : DateTime.tryParse('${json['achieved_at']}'),
        daysRemaining: json['days_remaining'] as int?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'goal_type': goalType,
        'title': title,
        'target_value': targetValue,
        'unit': unit,
        'is_decreasing': isDecreasing,
        'start_date': startDate.toIso8601String().split('T').first,
        'status': status,
        'progress_percent': progressPercent,
        'description': description,
        'exercise_id': exerciseId,
        'exercise_name': exerciseName,
        'measurement_type': measurementType,
        'start_value': startValue,
        'current_value': currentValue,
        'target_date': targetDate?.toIso8601String().split('T').first,
        'achieved_at': achievedAt?.toIso8601String(),
        'days_remaining': daysRemaining,
      };
}
