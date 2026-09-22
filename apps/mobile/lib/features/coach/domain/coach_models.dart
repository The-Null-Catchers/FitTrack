class CoachMessage {
  const CoachMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.safetyRedirect = false,
    this.payload = const <String, dynamic>{},
    this.isPending = false,
  });

  final String id;
  final String role;
  final String content;
  final DateTime createdAt;

  /// True when the safety layer answered instead of the model.
  final bool safetyRedirect;
  final Map<String, dynamic> payload;

  /// Optimistic local message, not yet confirmed by the server.
  final bool isPending;

  bool get isUser => role == 'user';

  factory CoachMessage.fromJson(Map<String, dynamic> json) => CoachMessage(
        id: json['id'] as String,
        role: json['role'] as String,
        content: json['content'] as String,
        createdAt: DateTime.tryParse('${json['created_at']}')?.toLocal() ??
            DateTime.now(),
        safetyRedirect: json['safety_redirect'] as bool? ?? false,
        payload: Map<String, dynamic>.from(
          (json['payload'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{},
        ),
      );
}

class CoachConversation {
  const CoachConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    this.lastMessageAt,
    this.messageCount = 0,
    this.messages = const <CoachMessage>[],
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime? lastMessageAt;
  final int messageCount;
  final List<CoachMessage> messages;

  factory CoachConversation.fromJson(Map<String, dynamic> json) =>
      CoachConversation(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Conversation',
        createdAt: DateTime.tryParse('${json['created_at']}')?.toLocal() ??
            DateTime.now(),
        lastMessageAt: json['last_message_at'] == null
            ? null
            : DateTime.tryParse('${json['last_message_at']}')?.toLocal(),
        messageCount: json['message_count'] as int? ?? 0,
        messages: ((json['messages'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) => CoachMessage.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
      );
}

class GeneratedPrescription {
  const GeneratedPrescription({
    required this.sets,
    required this.restSeconds,
    this.repsMin,
    this.repsMax,
    this.durationSeconds,
    this.rpe,
    this.notes,
  });

  final int sets;
  final int restSeconds;
  final int? repsMin;
  final int? repsMax;
  final int? durationSeconds;
  final double? rpe;
  final String? notes;

  String get label {
    if (durationSeconds != null) return '$sets × ${durationSeconds}s';
    if (repsMin != null && repsMax != null && repsMin != repsMax) {
      return '$sets × $repsMin-$repsMax';
    }
    return '$sets × ${repsMax ?? repsMin ?? '—'}';
  }

  factory GeneratedPrescription.fromJson(Map<String, dynamic> json) =>
      GeneratedPrescription(
        sets: json['sets'] as int? ?? 3,
        restSeconds: json['rest_seconds'] as int? ?? 90,
        repsMin: json['reps_min'] as int?,
        repsMax: json['reps_max'] as int?,
        durationSeconds: json['duration_seconds'] as int?,
        rpe: (json['rpe'] as num?)?.toDouble(),
        notes: json['notes'] as String?,
      );
}

class GeneratedExercise {
  const GeneratedExercise({
    required this.exerciseName,
    required this.prescription,
    this.exerciseId,
  });

  final String exerciseName;
  final GeneratedPrescription prescription;
  final String? exerciseId;

  factory GeneratedExercise.fromJson(Map<String, dynamic> json) =>
      GeneratedExercise(
        exerciseName: json['exercise_name'] as String,
        prescription: GeneratedPrescription.fromJson(
          Map<String, dynamic>.from(
              json['prescription'] as Map<dynamic, dynamic>),
        ),
        exerciseId: json['exercise_id'] as String?,
      );
}

class GeneratedDay {
  const GeneratedDay({
    required this.name,
    this.weekday,
    this.focus,
    this.exercises = const <GeneratedExercise>[],
  });

  final String name;
  final int? weekday;
  final String? focus;
  final List<GeneratedExercise> exercises;

  factory GeneratedDay.fromJson(Map<String, dynamic> json) => GeneratedDay(
        name: json['name'] as String,
        weekday: json['weekday'] as int?,
        focus: json['focus'] as String?,
        exercises: ((json['exercises'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) => GeneratedExercise.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
      );
}

/// A plan preview. Nothing is written until the user chooses to save it.
class GeneratedPlan {
  const GeneratedPlan({
    required this.generationId,
    required this.name,
    required this.description,
    required this.goal,
    required this.difficulty,
    required this.daysPerWeek,
    required this.estimatedMinutes,
    this.equipmentNeeded = const <String>[],
    this.days = const <GeneratedDay>[],
    this.coachingNotes = const <String>[],
    this.disclaimer = '',
  });

  final String generationId;
  final String name;
  final String description;
  final String goal;
  final String difficulty;
  final int daysPerWeek;
  final int estimatedMinutes;
  final List<String> equipmentNeeded;
  final List<GeneratedDay> days;
  final List<String> coachingNotes;
  final String disclaimer;

  factory GeneratedPlan.fromResponse(Map<String, dynamic> json) {
    final Map<String, dynamic> plan =
        Map<String, dynamic>.from(json['plan'] as Map<dynamic, dynamic>);
    return GeneratedPlan(
      generationId: json['generation_id'] as String,
      name: plan['name'] as String,
      description: plan['description'] as String? ?? '',
      goal: plan['goal'] as String? ?? 'general_fitness',
      difficulty: plan['difficulty'] as String? ?? 'beginner',
      daysPerWeek: plan['days_per_week'] as int? ?? 3,
      estimatedMinutes: plan['estimated_minutes'] as int? ?? 60,
      equipmentNeeded:
          ((plan['equipment_needed'] as List<dynamic>?) ?? const <dynamic>[])
              .map((dynamic item) => '$item')
              .toList(),
      days: ((plan['days'] as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic item) => GeneratedDay.fromJson(
              Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
          .toList(),
      coachingNotes:
          ((plan['coaching_notes'] as List<dynamic>?) ?? const <dynamic>[])
              .map((dynamic item) => '$item')
              .toList(),
      disclaimer: json['disclaimer'] as String? ?? '',
    );
  }
}

/// Inputs for the guided plan generator.
class PlanRequest {
  const PlanRequest({
    required this.goal,
    required this.experience,
    required this.daysPerWeek,
    required this.sessionMinutes,
    required this.equipment,
    required this.location,
    this.excludedExerciseIds = const <String>[],
    this.preferredExerciseIds = const <String>[],
    this.notes,
  });

  final String goal;
  final String experience;
  final int daysPerWeek;
  final int sessionMinutes;
  final List<String> equipment;
  final String location;
  final List<String> excludedExerciseIds;
  final List<String> preferredExerciseIds;
  final String? notes;

  PlanRequest copyWith({
    String? goal,
    String? experience,
    int? daysPerWeek,
    int? sessionMinutes,
    List<String>? equipment,
    String? location,
    List<String>? excludedExerciseIds,
    List<String>? preferredExerciseIds,
    String? notes,
  }) =>
      PlanRequest(
        goal: goal ?? this.goal,
        experience: experience ?? this.experience,
        daysPerWeek: daysPerWeek ?? this.daysPerWeek,
        sessionMinutes: sessionMinutes ?? this.sessionMinutes,
        equipment: equipment ?? this.equipment,
        location: location ?? this.location,
        excludedExerciseIds: excludedExerciseIds ?? this.excludedExerciseIds,
        preferredExerciseIds: preferredExerciseIds ?? this.preferredExerciseIds,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'goal': goal,
        'experience': experience,
        'days_per_week': daysPerWeek,
        'session_minutes': sessionMinutes,
        'equipment': equipment,
        'location': location,
        'excluded_exercise_ids': excludedExerciseIds,
        'preferred_exercise_ids': preferredExerciseIds,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}
