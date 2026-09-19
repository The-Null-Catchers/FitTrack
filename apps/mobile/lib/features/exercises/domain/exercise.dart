/// Paging envelope, re-exported so callers that work with exercise lists
/// need only one import.
export '../../../core/models/paged_result.dart';

/// An entry in the exercise library.
class Exercise {
  const Exercise({
    required this.id,
    required this.slug,
    required this.name,
    required this.muscleGroup,
    required this.equipment,
    required this.difficulty,
    required this.exerciseType,
    required this.trackingType,
    this.nameAr,
    this.imageUrl,
    this.isPublic = true,
    this.description,
    this.instructions = const <String>[],
    this.secondaryMuscles = const <String>[],
    this.defaultRestSeconds = 90,
    this.videoUrl,
  });

  final String id;
  final String slug;
  final String name;
  final String muscleGroup;
  final String equipment;
  final String difficulty;
  final String exerciseType;
  final String trackingType;
  final String? nameAr;
  final String? imageUrl;
  final bool isPublic;
  final String? description;
  final List<String> instructions;
  final List<String> secondaryMuscles;
  final int defaultRestSeconds;
  final String? videoUrl;

  /// Prefer the Arabic name when the UI is in Arabic and one exists.
  String displayName(String languageCode) =>
      languageCode == 'ar' && (nameAr?.isNotEmpty ?? false) ? nameAr! : name;

  bool get tracksWeight =>
      trackingType == 'weight_reps' || trackingType == 'assisted_weight';

  bool get tracksReps =>
      trackingType == 'weight_reps' ||
      trackingType == 'reps_only' ||
      trackingType == 'assisted_weight';

  bool get tracksDuration => trackingType == 'duration';

  bool get tracksDistance => trackingType == 'distance';

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
        id: json['id'] as String,
        slug: json['slug'] as String? ?? '',
        name: json['name'] as String,
        muscleGroup: json['muscle_group'] as String? ?? 'full_body',
        equipment: json['equipment'] as String? ?? 'bodyweight',
        difficulty: json['difficulty'] as String? ?? 'beginner',
        exerciseType: json['exercise_type'] as String? ?? 'strength',
        trackingType: json['default_tracking_type'] as String? ?? 'weight_reps',
        nameAr: json['name_ar'] as String?,
        imageUrl: json['image_url'] as String?,
        isPublic: json['is_public'] as bool? ?? true,
        description: json['description'] as String?,
        instructions: ((json['instructions'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) => '$item')
            .toList(),
        secondaryMuscles:
            ((json['secondary_muscles'] as List<dynamic>?) ?? const <dynamic>[])
                .map((dynamic item) => '$item')
                .toList(),
        defaultRestSeconds: json['default_rest_seconds'] as int? ?? 90,
        videoUrl: json['video_url'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'slug': slug,
        'name': name,
        'name_ar': nameAr,
        'muscle_group': muscleGroup,
        'equipment': equipment,
        'difficulty': difficulty,
        'exercise_type': exerciseType,
        'default_tracking_type': trackingType,
        'image_url': imageUrl,
        'is_public': isPublic,
        'description': description,
        'instructions': instructions,
        'secondary_muscles': secondaryMuscles,
        'default_rest_seconds': defaultRestSeconds,
        'video_url': videoUrl,
      };
}

/// Filters applied to an exercise search.
class ExerciseFilters {
  const ExerciseFilters({
    this.query = '',
    this.muscleGroup,
    this.equipment,
    this.difficulty,
  });

  final String query;
  final String? muscleGroup;
  final String? equipment;
  final String? difficulty;

  bool get isEmpty =>
      query.isEmpty &&
      muscleGroup == null &&
      equipment == null &&
      difficulty == null;

  int get activeCount => <Object?>[muscleGroup, equipment, difficulty]
      .where((Object? value) => value != null)
      .length;

  ExerciseFilters copyWith({
    String? query,
    String? muscleGroup,
    String? equipment,
    String? difficulty,
    bool clearMuscleGroup = false,
    bool clearEquipment = false,
    bool clearDifficulty = false,
  }) =>
      ExerciseFilters(
        query: query ?? this.query,
        muscleGroup: clearMuscleGroup ? null : (muscleGroup ?? this.muscleGroup),
        equipment: clearEquipment ? null : (equipment ?? this.equipment),
        difficulty: clearDifficulty ? null : (difficulty ?? this.difficulty),
      );

  /// A stable cache key, so the same search always hits the same entry.
  String get cacheKey =>
      '${query.toLowerCase()}|${muscleGroup ?? ''}|${equipment ?? ''}|${difficulty ?? ''}';

  Map<String, dynamic> toQuery({required int page, int perPage = 30}) =>
      <String, dynamic>{
        'page': page,
        'per_page': perPage,
        if (query.isNotEmpty) 'q': query,
        if (muscleGroup != null) 'muscle_group': muscleGroup,
        if (equipment != null) 'equipment': equipment,
        if (difficulty != null) 'difficulty': difficulty,
      };
}
