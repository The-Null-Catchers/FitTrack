import 'app_localizations.dart';

/// Localised labels for the exercise taxonomy.
///
/// Muscle groups, equipment, difficulty and exercise type arrive from the data
/// as stable slugs (`full_body`, `resistance_band`). Title-casing the slug
/// gives an English label in every language, so each one gets a real
/// translation instead. An unknown slug falls back to a readable form of
/// itself rather than showing a raw key.
extension CategoryLabels on AppLocalizations {
  String category(String slug) {
    final String? key = _keys[slug];
    if (key != null) return t(key);
    return slug
        .split('_')
        .map((String p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
        .join(' ');
  }

  static const Map<String, String> _keys = <String, String>{
    // muscle groups
    'chest': 'catMuscleChest',
    'back': 'catMuscleBack',
    'legs': 'catMuscleLegs',
    'shoulders': 'catMuscleShoulders',
    'arms': 'catMuscleArms',
    'core': 'catMuscleCore',
    'full_body': 'catMuscleFullBody',
    'mobility': 'catMuscleMobility',
    // equipment
    'barbell': 'catEquipBarbell',
    'dumbbell': 'catEquipDumbbell',
    'machine': 'catEquipMachine',
    'cable': 'catEquipCable',
    'bodyweight': 'catEquipBodyweight',
    'kettlebell': 'catEquipKettlebell',
    'resistance_band': 'catEquipResistanceBand',
    'cardio_machine': 'catEquipCardioMachine',
    'other': 'catEquipOther',
    // difficulty
    'beginner': 'catLevelBeginner',
    'intermediate': 'catLevelIntermediate',
    'advanced': 'catLevelAdvanced',
    // exercise type — 'cardio' is shared with the muscle group above
    'cardio': 'catMuscleCardio',
    'strength': 'catTypeStrength',
    'stretching': 'catTypeStretching',
    'balance': 'catTypeBalance',
    'plyometric': 'catTypePlyometric',
  };
}
