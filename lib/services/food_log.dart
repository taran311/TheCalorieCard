import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:namer_app/services/achievement_service.dart';
import 'package:namer_app/services/balance_service.dart';

/// Shared actions for logging food, plus a signal other screens listen to.
class FoodLog {
  FoodLog._();

  /// Bumped whenever food is logged or removed outside the Card screen,
  /// so the Card screen (kept alive in its tab) knows to refresh.
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  static void notifyChanged() => changed.value = changed.value + 1;

  static const meals = ['Brekkie', 'Lunch', 'Dinner', 'Snacks'];

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  /// Portion label for [multiplier] of a recipe whose serving is
  /// [servingSize] (e.g. "Per 1 Serving" or "450 g").
  static String portionLabel(String servingSize, double multiplier) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(servingSize);
    final base = match != null ? double.parse(match.group(1)!) : 1.0;
    final value = base * multiplier;
    final isGrams = servingSize.contains('g') &&
        !servingSize.toLowerCase().contains('serving');
    if (isGrams) return '${value.toStringAsFixed(0)} g';
    final shown = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return 'Per $shown Serving${value != 1 ? 's' : ''}';
  }

  /// Logs [multiplier] servings of a recipe to today and spends it from
  /// the card.
  static Future<void> logRecipe({
    required String recipeId,
    required Map<String, dynamic> recipe,
    required String meal,
    required double multiplier,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');

    final calories = _num(recipe['total_calories']) * multiplier;
    final protein = _num(recipe['total_protein']) * multiplier;
    final carbs = _num(recipe['total_carbs']) * multiplier;
    final fat = _num(recipe['total_fat']) * multiplier;
    final servingSize =
        (recipe['serving_size'] as String?) ?? 'Per 1 Serving';

    await FirebaseFirestore.instance.collection('user_food').add({
      'user_id': uid,
      'food_description': 'Recipe: ${recipe['name'] ?? ''}',
      'food_calories': calories,
      'food_protein': protein,
      'food_carbs': carbs,
      'food_fat': fat,
      'food_portion': portionLabel(servingSize, multiplier),
      'foodCategory': meal,
      'recipe_id': recipeId,
      'is_recipe': true,
      'time_added': DateTime.now(),
      'created_at': FieldValue.serverTimestamp(),
    });

    await BalanceService.spend(
      uid,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
    );

    try {
      await AchievementService.markFirstTimeLogger(uid);
    } catch (_) {}

    notifyChanged();
  }
}
