class HabitLog {
  const HabitLog({
    required this.id,
    required this.habitId,
    required this.loggedOn,
    required this.count,
    required this.isCompleted,
    this.value,
  });

  final String id;
  final String habitId;
  final DateTime loggedOn;
  final int count;
  final bool isCompleted;
  final double? value;

  factory HabitLog.fromJson(Map<String, dynamic> json) => HabitLog(
        id: json['id'] as String,
        habitId: json['habit_id'] as String,
        loggedOn: DateTime.parse(json['logged_on'] as String),
        count: json['count'] as int? ?? 0,
        isCompleted: json['is_completed'] as bool? ?? false,
        value: (json['value'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'habit_id': habitId,
        'logged_on': loggedOn.toIso8601String().split('T').first,
        'count': count,
        'is_completed': isCompleted,
        'value': value,
      };
}

class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.icon,
    required this.frequency,
    required this.targetCount,
    required this.currentStreak,
    required this.longestStreak,
    this.color,
    this.targetValue,
    this.unit,
    this.activeWeekdays = const <int>[],
    this.reminderTime,
    this.isArchived = false,
    this.position = 0,
    this.today,
    this.completionRate30d = 0,
  });

  final String id;
  final String name;
  final String icon;
  final String frequency;
  final int targetCount;
  final int currentStreak;
  final int longestStreak;
  final String? color;
  final double? targetValue;
  final String? unit;
  final List<int> activeWeekdays;
  final String? reminderTime;
  final bool isArchived;
  final int position;
  final HabitLog? today;
  final double completionRate30d;

  bool get isDoneToday => today?.isCompleted ?? false;

  int get todayCount => today?.count ?? 0;

  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
        id: json['id'] as String,
        name: json['name'] as String,
        icon: json['icon'] as String? ?? 'check_circle',
        frequency: json['frequency'] as String? ?? 'daily',
        targetCount: json['target_count'] as int? ?? 1,
        currentStreak: json['current_streak'] as int? ?? 0,
        longestStreak: json['longest_streak'] as int? ?? 0,
        color: json['color'] as String?,
        targetValue: (json['target_value'] as num?)?.toDouble(),
        unit: json['unit'] as String?,
        activeWeekdays: ((json['active_weekdays'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) => item as int)
            .toList(),
        reminderTime: json['reminder_time'] as String?,
        isArchived: json['is_archived'] as bool? ?? false,
        position: json['position'] as int? ?? 0,
        today: json['today'] == null
            ? null
            : HabitLog.fromJson(
                Map<String, dynamic>.from(json['today'] as Map<dynamic, dynamic>),
              ),
        completionRate30d: (json['completion_rate_30d'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'icon': icon,
        'frequency': frequency,
        'target_count': targetCount,
        'current_streak': currentStreak,
        'longest_streak': longestStreak,
        'color': color,
        'target_value': targetValue,
        'unit': unit,
        'active_weekdays': activeWeekdays,
        'reminder_time': reminderTime,
        'is_archived': isArchived,
        'position': position,
        'today': today?.toJson(),
        'completion_rate_30d': completionRate30d,
      };
}
