class ServingOption {
  const ServingOption({required this.label, required this.grams});

  final String label;
  final double grams;

  factory ServingOption.fromJson(Map<String, dynamic> json) => ServingOption(
        label: json['label'] as String,
        grams: (json['grams'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'label': label, 'grams': grams};
}

/// A catalogue or custom food. Nutrients are always per 100 g.
class Food {
  const Food({
    required this.id,
    required this.name,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    required this.fiberPer100g,
    required this.defaultServingGrams,
    this.nameAr,
    this.brand,
    this.barcode,
    this.servingOptions = const <ServingOption>[],
    this.isCustom = false,
    this.isVerified = false,
    this.isFavorite = false,
  });

  final String id;
  final String name;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double fiberPer100g;
  final double defaultServingGrams;
  final String? nameAr;
  final String? brand;
  final String? barcode;
  final List<ServingOption> servingOptions;
  final bool isCustom;
  final bool isVerified;
  final bool isFavorite;

  String displayName(String languageCode) =>
      languageCode == 'ar' && (nameAr?.isNotEmpty ?? false) ? nameAr! : name;

  /// Calories for a given portion.
  double caloriesFor(double grams) => caloriesPer100g * grams / 100;

  factory Food.fromJson(Map<String, dynamic> json) => Food(
        id: json['id'] as String,
        name: json['name'] as String,
        caloriesPer100g: (json['calories_per_100g'] as num?)?.toDouble() ?? 0,
        proteinPer100g: (json['protein_per_100g'] as num?)?.toDouble() ?? 0,
        carbsPer100g: (json['carbs_per_100g'] as num?)?.toDouble() ?? 0,
        fatPer100g: (json['fat_per_100g'] as num?)?.toDouble() ?? 0,
        fiberPer100g: (json['fiber_per_100g'] as num?)?.toDouble() ?? 0,
        defaultServingGrams:
            (json['default_serving_grams'] as num?)?.toDouble() ?? 100,
        nameAr: json['name_ar'] as String?,
        brand: json['brand'] as String?,
        barcode: json['barcode'] as String?,
        servingOptions:
            ((json['serving_options'] as List<dynamic>?) ?? const <dynamic>[])
                .map((dynamic item) => ServingOption.fromJson(
                    Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
                .toList(),
        isCustom: json['is_custom'] as bool? ?? false,
        isVerified: json['is_verified'] as bool? ?? false,
        isFavorite: json['is_favorite'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'name_ar': nameAr,
        'brand': brand,
        'barcode': barcode,
        'calories_per_100g': caloriesPer100g,
        'protein_per_100g': proteinPer100g,
        'carbs_per_100g': carbsPer100g,
        'fat_per_100g': fatPer100g,
        'fiber_per_100g': fiberPer100g,
        'default_serving_grams': defaultServingGrams,
        'serving_options':
            servingOptions.map((ServingOption option) => option.toJson()).toList(),
        'is_custom': isCustom,
        'is_verified': isVerified,
        'is_favorite': isFavorite,
      };
}

class MealItem {
  const MealItem({
    required this.id,
    required this.foodName,
    required this.grams,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    this.foodId,
    this.servingLabel,
    this.quantity = 1,
    this.position = 0,
  });

  final String id;
  final String foodName;
  final double grams;
  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final String? foodId;
  final String? servingLabel;
  final double quantity;
  final int position;

  factory MealItem.fromJson(Map<String, dynamic> json) => MealItem(
        id: json['id'] as String? ?? '',
        foodName: json['food_name'] as String,
        grams: (json['grams'] as num?)?.toDouble() ?? 0,
        calories: (json['calories'] as num?)?.toDouble() ?? 0,
        proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
        carbsG: (json['carbs_g'] as num?)?.toDouble() ?? 0,
        fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
        fiberG: (json['fiber_g'] as num?)?.toDouble() ?? 0,
        foodId: json['food_id'] as String?,
        servingLabel: json['serving_label'] as String?,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
        position: json['position'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'food_id': foodId,
        'food_name': foodName,
        'serving_label': servingLabel,
        'quantity': quantity,
        'grams': grams,
        'calories': calories,
        'protein_g': proteinG,
        'carbs_g': carbsG,
        'fat_g': fatG,
        'fiber_g': fiberG,
        'position': position,
      };
}

class Meal {
  const Meal({
    required this.id,
    required this.loggedOn,
    required this.mealType,
    required this.totalCalories,
    required this.totalProteinG,
    required this.totalCarbsG,
    required this.totalFatG,
    required this.totalFiberG,
    this.name,
    this.items = const <MealItem>[],
    this.isSavedTemplate = false,
  });

  final String id;
  final DateTime loggedOn;
  final String mealType;
  final double totalCalories;
  final double totalProteinG;
  final double totalCarbsG;
  final double totalFatG;
  final double totalFiberG;
  final String? name;
  final List<MealItem> items;
  final bool isSavedTemplate;

  factory Meal.fromJson(Map<String, dynamic> json) => Meal(
        id: json['id'] as String,
        loggedOn: DateTime.parse(json['logged_on'] as String),
        mealType: json['meal_type'] as String? ?? 'snack',
        totalCalories: (json['total_calories'] as num?)?.toDouble() ?? 0,
        totalProteinG: (json['total_protein_g'] as num?)?.toDouble() ?? 0,
        totalCarbsG: (json['total_carbs_g'] as num?)?.toDouble() ?? 0,
        totalFatG: (json['total_fat_g'] as num?)?.toDouble() ?? 0,
        totalFiberG: (json['total_fiber_g'] as num?)?.toDouble() ?? 0,
        name: json['name'] as String?,
        items: ((json['items'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) => MealItem.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
        isSavedTemplate: json['is_saved_template'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'logged_on': loggedOn.toIso8601String().split('T').first,
        'meal_type': mealType,
        'name': name,
        'total_calories': totalCalories,
        'total_protein_g': totalProteinG,
        'total_carbs_g': totalCarbsG,
        'total_fat_g': totalFatG,
        'total_fiber_g': totalFiberG,
        'items': items.map((MealItem item) => item.toJson()).toList(),
        'is_saved_template': isSavedTemplate,
      };
}

class MacroProgress {
  const MacroProgress({required this.consumed, this.target, this.remaining, this.percent});

  final double consumed;
  final double? target;
  final double? remaining;
  final double? percent;

  double get fraction =>
      target == null || target == 0 ? 0 : (consumed / target!).clamp(0.0, 1.0);

  bool get isOver => remaining != null && remaining! < 0;

  factory MacroProgress.fromJson(Map<String, dynamic> json) => MacroProgress(
        consumed: (json['consumed'] as num?)?.toDouble() ?? 0,
        target: (json['target'] as num?)?.toDouble(),
        remaining: (json['remaining'] as num?)?.toDouble(),
        percent: (json['percent'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'consumed': consumed,
        'target': target,
        'remaining': remaining,
        'percent': percent,
      };
}

class NutritionDay {
  const NutritionDay({
    required this.loggedOn,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.waterMl,
    this.meals = const <Meal>[],
  });

  final DateTime loggedOn;
  final MacroProgress calories;
  final MacroProgress proteinG;
  final MacroProgress carbsG;
  final MacroProgress fatG;
  final MacroProgress fiberG;
  final MacroProgress waterMl;
  final List<Meal> meals;

  List<Meal> mealsOfType(String type) =>
      meals.where((Meal meal) => meal.mealType == type).toList();

  double caloriesOfType(String type) => mealsOfType(type)
      .fold<double>(0, (double sum, Meal meal) => sum + meal.totalCalories);

  factory NutritionDay.fromJson(Map<String, dynamic> json) => NutritionDay(
        loggedOn: DateTime.parse(json['logged_on'] as String),
        calories: MacroProgress.fromJson(
          Map<String, dynamic>.from(json['calories'] as Map<dynamic, dynamic>),
        ),
        proteinG: MacroProgress.fromJson(
          Map<String, dynamic>.from(json['protein_g'] as Map<dynamic, dynamic>),
        ),
        carbsG: MacroProgress.fromJson(
          Map<String, dynamic>.from(json['carbs_g'] as Map<dynamic, dynamic>),
        ),
        fatG: MacroProgress.fromJson(
          Map<String, dynamic>.from(json['fat_g'] as Map<dynamic, dynamic>),
        ),
        fiberG: MacroProgress.fromJson(
          Map<String, dynamic>.from(json['fiber_g'] as Map<dynamic, dynamic>),
        ),
        waterMl: MacroProgress.fromJson(
          Map<String, dynamic>.from(json['water_ml'] as Map<dynamic, dynamic>),
        ),
        meals: ((json['meals'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic item) =>
                Meal.fromJson(Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'logged_on': loggedOn.toIso8601String().split('T').first,
        'calories': calories.toJson(),
        'protein_g': proteinG.toJson(),
        'carbs_g': carbsG.toJson(),
        'fat_g': fatG.toJson(),
        'fiber_g': fiberG.toJson(),
        'water_ml': waterMl.toJson(),
        'meals': meals.map((Meal meal) => meal.toJson()).toList(),
      };
}
