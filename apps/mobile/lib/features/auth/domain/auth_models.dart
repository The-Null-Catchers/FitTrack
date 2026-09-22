/// Account and fitness-profile models.
///
/// Written by hand rather than generated: the app has no code-generation step,
/// and an explicit `fromJson` is the one place a server contract change shows
/// up as a compile error rather than a runtime null.
library;

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.locale,
    required this.emailVerified,
    required this.onboardingCompleted,
    this.avatarUrl,
    this.timezone = 'UTC',
    this.theme = 'system',
    this.subscriptionTier = 'free',
    this.profile,
  });

  final String id;
  final String email;
  final String fullName;
  final String role;
  final String locale;
  final bool emailVerified;
  final bool onboardingCompleted;
  final String? avatarUrl;
  final String timezone;
  final String theme;
  final String subscriptionTier;
  final FitnessProfile? profile;

  bool get isAdmin => role == 'admin';

  /// First name only, for greetings.
  String get givenName => fullName.trim().split(RegExp(r'\s+')).first;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        role: json['role'] as String? ?? 'user',
        locale: json['locale'] as String? ?? 'en',
        emailVerified: json['email_verified'] as bool? ?? false,
        onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
        avatarUrl: json['avatar_url'] as String?,
        timezone: json['timezone'] as String? ?? 'UTC',
        theme: json['theme'] as String? ?? 'system',
        subscriptionTier: json['subscription_tier'] as String? ?? 'free',
        profile: json['profile'] == null
            ? null
            : FitnessProfile.fromJson(
                Map<String, dynamic>.from(
                    json['profile'] as Map<dynamic, dynamic>),
              ),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'email': email,
        'full_name': fullName,
        'role': role,
        'locale': locale,
        'email_verified': emailVerified,
        'onboarding_completed': onboardingCompleted,
        'avatar_url': avatarUrl,
        'timezone': timezone,
        'theme': theme,
        'subscription_tier': subscriptionTier,
        'profile': profile?.toJson(),
      };

  AuthUser copyWith({
    String? fullName,
    String? locale,
    String? theme,
    String? avatarUrl,
    bool? onboardingCompleted,
    FitnessProfile? profile,
  }) =>
      AuthUser(
        id: id,
        email: email,
        fullName: fullName ?? this.fullName,
        role: role,
        locale: locale ?? this.locale,
        emailVerified: emailVerified,
        onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        timezone: timezone,
        theme: theme ?? this.theme,
        subscriptionTier: subscriptionTier,
        profile: profile ?? this.profile,
      );
}

class FitnessProfile {
  const FitnessProfile({
    required this.unitSystem,
    required this.primaryGoal,
    required this.fitnessLevel,
    required this.activityLevel,
    required this.workoutLocation,
    required this.trainingDaysPerWeek,
    required this.preferredSessionMinutes,
    required this.defaultRestSeconds,
    required this.dailyWaterTargetMl,
    required this.targetsAreManual,
    required this.aiContextOptIn,
    this.dateOfBirth,
    this.gender = 'undisclosed',
    this.heightCm,
    this.currentWeightKg,
    this.targetWeightKg,
    this.availableEquipment = const <String>[],
    this.dailyCalorieTarget,
    this.dailyProteinTargetG,
    this.dailyCarbsTargetG,
    this.dailyFatTargetG,
    this.dailyFiberTargetG,
  });

  final String unitSystem;
  final String primaryGoal;
  final String fitnessLevel;
  final String activityLevel;
  final String workoutLocation;
  final int trainingDaysPerWeek;
  final int preferredSessionMinutes;
  final int defaultRestSeconds;
  final int dailyWaterTargetMl;
  final bool targetsAreManual;
  final bool aiContextOptIn;
  final DateTime? dateOfBirth;
  final String gender;
  final double? heightCm;
  final double? currentWeightKg;
  final double? targetWeightKg;
  final List<String> availableEquipment;
  final int? dailyCalorieTarget;
  final int? dailyProteinTargetG;
  final int? dailyCarbsTargetG;
  final int? dailyFatTargetG;
  final int? dailyFiberTargetG;

  bool get useImperial => unitSystem == 'imperial';

  factory FitnessProfile.fromJson(Map<String, dynamic> json) => FitnessProfile(
        unitSystem: json['unit_system'] as String? ?? 'metric',
        primaryGoal: json['primary_goal'] as String? ?? 'general_fitness',
        fitnessLevel: json['fitness_level'] as String? ?? 'beginner',
        activityLevel: json['activity_level'] as String? ?? 'moderate',
        workoutLocation: json['workout_location'] as String? ?? 'gym',
        trainingDaysPerWeek: json['training_days_per_week'] as int? ?? 3,
        preferredSessionMinutes:
            json['preferred_session_minutes'] as int? ?? 60,
        defaultRestSeconds: json['default_rest_seconds'] as int? ?? 90,
        dailyWaterTargetMl: json['daily_water_target_ml'] as int? ?? 2000,
        targetsAreManual: json['targets_are_manual'] as bool? ?? false,
        aiContextOptIn: json['ai_context_opt_in'] as bool? ?? true,
        dateOfBirth: json['date_of_birth'] == null
            ? null
            : DateTime.tryParse(json['date_of_birth'] as String),
        gender: json['gender'] as String? ?? 'undisclosed',
        heightCm: (json['height_cm'] as num?)?.toDouble(),
        currentWeightKg: (json['current_weight_kg'] as num?)?.toDouble(),
        targetWeightKg: (json['target_weight_kg'] as num?)?.toDouble(),
        availableEquipment: ((json['available_equipment'] as List<dynamic>?) ??
                const <dynamic>[])
            .map((dynamic item) => '$item')
            .toList(),
        dailyCalorieTarget: json['daily_calorie_target'] as int?,
        dailyProteinTargetG: json['daily_protein_target_g'] as int?,
        dailyCarbsTargetG: json['daily_carbs_target_g'] as int?,
        dailyFatTargetG: json['daily_fat_target_g'] as int?,
        dailyFiberTargetG: json['daily_fiber_target_g'] as int?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'unit_system': unitSystem,
        'primary_goal': primaryGoal,
        'fitness_level': fitnessLevel,
        'activity_level': activityLevel,
        'workout_location': workoutLocation,
        'training_days_per_week': trainingDaysPerWeek,
        'preferred_session_minutes': preferredSessionMinutes,
        'default_rest_seconds': defaultRestSeconds,
        'daily_water_target_ml': dailyWaterTargetMl,
        'targets_are_manual': targetsAreManual,
        'ai_context_opt_in': aiContextOptIn,
        'date_of_birth': dateOfBirth?.toIso8601String().split('T').first,
        'gender': gender,
        'height_cm': heightCm,
        'current_weight_kg': currentWeightKg,
        'target_weight_kg': targetWeightKg,
        'available_equipment': availableEquipment,
        'daily_calorie_target': dailyCalorieTarget,
        'daily_protein_target_g': dailyProteinTargetG,
        'daily_carbs_target_g': dailyCarbsTargetG,
        'daily_fat_target_g': dailyFatTargetG,
        'daily_fiber_target_g': dailyFiberTargetG,
      };
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.refreshExpiresAt,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final DateTime refreshExpiresAt;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
        expiresIn: json['expires_in'] as int? ?? 900,
        refreshExpiresAt: DateTime.tryParse('${json['refresh_expires_at']}') ??
            DateTime.now().add(const Duration(days: 30)),
        user: AuthUser.fromJson(
          Map<String, dynamic>.from(json['user'] as Map<dynamic, dynamic>),
        ),
      );
}

/// Onboarding answers, collected across the wizard and submitted once.
class OnboardingDraft {
  const OnboardingDraft({
    this.fullName,
    this.dateOfBirth,
    this.gender = 'undisclosed',
    this.heightCm,
    this.currentWeightKg,
    this.targetWeightKg,
    this.unitSystem = 'metric',
    this.primaryGoal = 'general_fitness',
    this.fitnessLevel = 'beginner',
    this.activityLevel = 'moderate',
    this.workoutLocation = 'gym',
    this.availableEquipment = const <String>[],
    this.trainingDaysPerWeek = 3,
    this.preferredSessionMinutes = 60,
  });

  final String? fullName;
  final DateTime? dateOfBirth;
  final String gender;
  final double? heightCm;
  final double? currentWeightKg;
  final double? targetWeightKg;
  final String unitSystem;
  final String primaryGoal;
  final String fitnessLevel;
  final String activityLevel;
  final String workoutLocation;
  final List<String> availableEquipment;
  final int trainingDaysPerWeek;
  final int preferredSessionMinutes;

  bool get isComplete => heightCm != null && currentWeightKg != null;

  OnboardingDraft copyWith({
    String? fullName,
    DateTime? dateOfBirth,
    String? gender,
    double? heightCm,
    double? currentWeightKg,
    double? targetWeightKg,
    String? unitSystem,
    String? primaryGoal,
    String? fitnessLevel,
    String? activityLevel,
    String? workoutLocation,
    List<String>? availableEquipment,
    int? trainingDaysPerWeek,
    int? preferredSessionMinutes,
  }) =>
      OnboardingDraft(
        fullName: fullName ?? this.fullName,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        gender: gender ?? this.gender,
        heightCm: heightCm ?? this.heightCm,
        currentWeightKg: currentWeightKg ?? this.currentWeightKg,
        targetWeightKg: targetWeightKg ?? this.targetWeightKg,
        unitSystem: unitSystem ?? this.unitSystem,
        primaryGoal: primaryGoal ?? this.primaryGoal,
        fitnessLevel: fitnessLevel ?? this.fitnessLevel,
        activityLevel: activityLevel ?? this.activityLevel,
        workoutLocation: workoutLocation ?? this.workoutLocation,
        availableEquipment: availableEquipment ?? this.availableEquipment,
        trainingDaysPerWeek: trainingDaysPerWeek ?? this.trainingDaysPerWeek,
        preferredSessionMinutes:
            preferredSessionMinutes ?? this.preferredSessionMinutes,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (fullName != null && fullName!.isNotEmpty) 'full_name': fullName,
        if (dateOfBirth != null)
          'date_of_birth': dateOfBirth!.toIso8601String().split('T').first,
        'gender': gender,
        'height_cm': heightCm,
        'current_weight_kg': currentWeightKg,
        if (targetWeightKg != null) 'target_weight_kg': targetWeightKg,
        'unit_system': unitSystem,
        'primary_goal': primaryGoal,
        'fitness_level': fitnessLevel,
        'activity_level': activityLevel,
        'workout_location': workoutLocation,
        'available_equipment': availableEquipment,
        'training_days_per_week': trainingDaysPerWeek,
        'preferred_session_minutes': preferredSessionMinutes,
        'estimate_nutrition_targets': true,
      };
}
