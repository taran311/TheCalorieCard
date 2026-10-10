import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:namer_app/services/achievement_service.dart';
import 'package:namer_app/services/balance_service.dart';

/// Shared actions for logging food, plus a signal other screens listen to.
class FoodLog {
  FoodLog._();

  /// Bumped whenever food is logged or removed, so screens that are kept
  /// alive (the Card tab) know to refresh.
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  static void notifyChanged() => changed.value = changed.value + 1;

  static const meals = ['Breakfast', 'Lunch', 'Dinner', 'Snacks'];

  /// A meal name as shown and saved now. Breakfast used to be saved as
  /// "Brekkie", so older entries read as Breakfast too.
  static String displayMeal(String meal) =>
      meal.trim().toLowerCase() == 'brekkie' ? 'Breakfast' : meal;

  /// The meal a saved entry belongs to (no meal saved counts as Breakfast,
  /// as it always has).
  static String mealOf(Object? stored) =>
      displayMeal(stored == null ? 'Breakfast' : '$stored');

  static String _uid(String? userId) {
    final uid = userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    return uid;
  }

  /// "2", "1.5", "0.3": no trailing ".0".
  static String formatAmount(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    final s = value.toStringAsFixed(2);
    return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  /// The number in a serving size such as "Per 2 Servings" or "450 g".
  /// Never zero or negative, so it's always safe to divide by.
  static double servingAmount(String servingSize) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(servingSize);
    final value = match != null ? double.tryParse(match.group(1)!) : null;
    return value != null && value > 0 ? value : 1.0;
  }

  /// True for serving sizes measured in grams ("450 g").
  static bool isGrams(String servingSize) =>
      servingSize.contains('g') &&
      !servingSize.toLowerCase().contains('serving');

  /// Serving size label as saved on a recipe: "450 g" or "Per 2 Servings".
  static String servingLabel(double amount, {required bool grams}) {
    final shown = formatAmount(amount);
    if (grams) return '$shown g';
    return 'Per $shown Serving${amount != 1 ? 's' : ''}';
  }

  /// Portion label for [multiplier] of a recipe whose serving is
  /// [servingSize] (e.g. "Per 1 Serving" or "450 g").
  static String portionLabel(String servingSize, double multiplier) {
    final value = servingAmount(servingSize) * multiplier;
    if (isGrams(servingSize)) return '${value.toStringAsFixed(0)} g';
    return servingLabel(value, grams: false);
  }

  /// Logs [multiplier] servings of a recipe to today and charges the card.
  static Future<void> logRecipe({
    required String recipeId,
    required Map<String, dynamic> recipe,
    required String meal,
    required double multiplier,
    String? userId,
  }) async {
    if (!multiplier.isFinite || multiplier <= 0) {
      throw ArgumentError('Portion must be more than zero');
    }
    final uid = _uid(userId);

    final amount = Macros(
      calories: BalanceService.number(recipe['total_calories']) ?? 0,
      protein: BalanceService.number(recipe['total_protein']) ?? 0,
      carbs: BalanceService.number(recipe['total_carbs']) ?? 0,
      fat: BalanceService.number(recipe['total_fat']) ?? 0,
    ).scaled(multiplier);
    final servingSize =
        (recipe['serving_size'] as String?) ?? 'Per 1 Serving';

    await BalanceService.logEntries(uid, [
      {
        'food_description': 'Recipe: ${recipe['name'] ?? ''}',
        ...amount.toEntryFields(),
        'food_portion': portionLabel(servingSize, multiplier),
        'foodCategory': meal,
        'recipe_id': recipeId,
        'is_recipe': true,
      }
    ]);

    await _afterLogging(uid, foods: 1);
  }

  /// Logs individual foods to [meal] and charges the card. Each item needs
  /// `name`, `calories`, `protein`, `carbs`, `fat` and optionally `portion`.
  ///
  /// Calories are stored as whole numbers, and the card is charged exactly
  /// what's stored, so removing a food later refunds the same amount.
  static Future<void> logFoods({
    required List<Map<String, dynamic>> items,
    required String meal,
    String? userId,
  }) async {
    final uid = _uid(userId);
    final entries = [
      for (final item in items)
        {
          'food_description': (item['name'] ?? 'Food').toString(),
          'food_portion': (item['portion'] ?? '').toString(),
          ...Macros(
            calories:
                (BalanceService.number(item['calories']) ?? 0).roundToDouble(),
            protein: BalanceService.number(item['protein']) ?? 0,
            carbs: BalanceService.number(item['carbs']) ?? 0,
            fat: BalanceService.number(item['fat']) ?? 0,
          ).toEntryFields(),
          'foodCategory': meal,
        }
    ];
    await BalanceService.logEntries(uid, entries);
    await _afterLogging(
      uid,
      foods: entries.length,
      scans: items.where((i) => i['source'] == 'barcode').length,
    );
  }

  /// Removes a logged food and refunds the card if it was today's.
  static Future<void> remove(String entryId, {String? userId}) async {
    await BalanceService.deleteEntry(_uid(userId), entryId);
    notifyChanged();
  }

  static Future<void> _afterLogging(String uid,
      {int foods = 1, int scans = 0}) async {
    notifyChanged();
    // Achievements are a bonus: the food is already logged, so a failure
    // here must not look like the logging failed (that invites a retry
    // and a duplicate entry). recordLogging never throws.
    await AchievementService.recordLogging(uid, foods: foods, scans: scans);
  }
}
