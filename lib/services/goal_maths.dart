import 'dart:math' as math;

import 'package:namer_app/services/balance_service.dart';

/// The calorie sums behind "Calculate for me", shared by Get started,
/// Goals and profile and the weight log. Pure functions, so they're tested
/// without Firebase.

/// Below this a goal gets a gentle "that's very low" note in "Set my own".
const int lowCalorieWarningKcal = 1200;

/// Calories burned at rest (Mifflin–St Jeor). Null if anything's missing.
double? restingCalories({
  required num? age,
  required num? heightCm,
  required num? weightKg,
  required bool male,
}) {
  if (age == null || heightCm == null || weightKg == null) return null;
  final v =
      (10 * weightKg) + (6.25 * heightCm) - (5 * age) + (male ? 5 : -161);
  return v.isFinite ? v.toDouble() : null;
}

/// Calories a day to stay the same weight: resting calories times an
/// activity factor for [exerciseLevel] (0 = little or none ... 4 = 10+
/// hours a week). Null if age, height or weight is missing.
double? maintenanceCalories({
  required num? age,
  required num? heightCm,
  required num? weightKg,
  required bool male,
  required double exerciseLevel,
}) {
  final rest = restingCalories(
      age: age, heightCm: heightCm, weightKg: weightKg, male: male);
  if (rest == null) return null;
  const multipliers = [1.2, 1.375, 1.55, 1.725, 1.9];
  final level = exerciseLevel.isFinite
      ? exerciseLevel.round().clamp(0, 4).toInt()
      : 0;
  return rest * multipliers[level];
}

/// The lowest "Lose" goal we'll ever suggest: never below what your body
/// uses at rest, and never below 1,200 kcal (women) or 1,500 kcal (men),
/// the usual safe minimums without medical supervision.
double safeMinimumCalories({required bool male, double? resting}) {
  final floor = male ? 1500.0 : 1200.0;
  final r = resting ?? 0.0;
  return r.isFinite ? math.max(r, floor) : floor;
}

/// The suggested daily calorie goal for a goal [mode] ('lose', 'maintain'
/// or 'gain'; anything else counts as 'lose', as Settings does). [floor]
/// (see [safeMinimumCalories]) keeps "Lose" from going too low.
int suggestedCalorieGoal(double maintenance, String? mode, {double? floor}) {
  if (mode == 'maintain') return maintenance.round();
  if (mode == 'gain') return (maintenance * 1.15).round();
  final lose = maintenance * 0.85;
  if (floor != null && floor.isFinite && lose < floor) return floor.round();
  return lose.round();
}

/// Calories from macros: 4 per gram of protein and carbs, 9 per gram of fat.
int caloriesFromMacros(num protein, num carbs, num fat) =>
    (protein * 4 + carbs * 4 + fat * 9).round();

/// A default macro split for a calorie goal (30% protein, 40% carbs,
/// 30% fat), used when there are no AI targets.
Macros defaultMacrosFor(int calories) => Macros(
      calories: calories.toDouble(),
      protein: (calories * 0.30 / 4).round().toDouble(),
      carbs: (calories * 0.40 / 4).round().toDouble(),
      fat: (calories * 0.30 / 9).round().toDouble(),
    );

/// [current]'s macros scaled to a new calorie goal, so someone who chose a
/// high-protein split keeps it when the calories change. Falls back to
/// [defaultMacrosFor] when there are no macros to scale.
Macros macrosScaledTo(Macros current, int calories) {
  final fromMacros =
      current.protein * 4 + current.carbs * 4 + current.fat * 9;
  if (!fromMacros.isFinite || fromMacros <= 0 || calories <= 0) {
    return defaultMacrosFor(calories);
  }
  final f = calories / fromMacros;
  return Macros(
    calories: calories.toDouble(),
    protein: (current.protein * f).round().toDouble(),
    carbs: (current.carbs * f).round().toDouble(),
    fat: (current.fat * f).round().toDouble(),
  );
}

/// Coach's targets per goal (`{'lose': {'calories', 'protein_g', 'carbs_g',
/// 'fat_g'}, ...}`), with "lose" raised to [floor] if Coach went lower and
/// its macros scaled up to match. Everything else is passed through.
Map<String, dynamic> withSafeLoseTarget(
    Map<String, dynamic> targets, num floor) {
  final lose = targets['lose'];
  if (lose is! Map) return targets;
  final kcal = BalanceService.number(lose['calories']);
  final min = floor.round();
  if (kcal == null || kcal >= min) return targets;
  final scaled = macrosScaledTo(
    Macros(
      calories: kcal,
      protein: BalanceService.number(lose['protein_g']) ?? 0,
      carbs: BalanceService.number(lose['carbs_g']) ?? 0,
      fat: BalanceService.number(lose['fat_g']) ?? 0,
    ),
    min,
  );
  return {
    ...targets,
    'lose': {
      ...Map<String, dynamic>.from(lose),
      'calories': min,
      'protein_g': scaled.protein.round(),
      'carbs_g': scaled.carbs.round(),
      'fat_g': scaled.fat.round(),
    },
  };
}
