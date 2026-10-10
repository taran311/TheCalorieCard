import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';

/// A food someone logs often at a meal, for one-tap logging ("Usuals").
class UsualFood {
  final String name;
  final String portion;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  /// How many times it was logged at this meal in the window.
  final int count;

  /// When it was last logged (null if the entry had no time).
  final DateTime? lastLogged;

  const UsualFood({
    required this.name,
    required this.portion,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.count,
    this.lastLogged,
  });

  /// "Porridge · 412" for the chip.
  String get label => '$name · ${calories.round()}';

  /// In the shape [FoodLog.logFoods] takes.
  Map<String, dynamic> toLogItem() => {
        'name': name,
        'portion': portion,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'source': 'recent',
      };
}

class Usuals {
  Usuals._();

  /// How far back to look.
  static const days = 30;

  /// Fewer logs than this isn't a habit yet.
  static const minCount = 2;

  static const maxShown = 4;

  /// Recipes are logged through the recipe sheet (with servings), so they
  /// don't belong in a plain one-tap row.
  static bool _isRecipe(Map<String, dynamic> e) =>
      e['is_recipe'] == true ||
      e['recipe_id'] != null ||
      e['foodCategory'] == BalanceService.recipeCategory ||
      '${e['food_description'] ?? ''}'.startsWith('Recipe:');

  /// The foods most often logged to [meal] among [entries] (`user_food`
  /// data), most frequent first, then most recent. Same food means same
  /// name and portion (ignoring case and spaces). Each uses the calories
  /// and macros from its latest log.
  static List<UsualFood> rank(
    Iterable<Map<String, dynamic>> entries, {
    required String meal,
    int limit = maxShown,
    int minimum = minCount,
  }) {
    final groups = <String, _Group>{};
    for (final e in entries) {
      if (_isRecipe(e)) continue;
      if (FoodLog.mealOf(e['foodCategory']) != meal) continue;
      final name = '${e['food_description'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final portion = '${e['food_portion'] ?? ''}'.trim();
      final key = '${name.toLowerCase()}|${portion.toLowerCase()}';
      final when = BalanceService.entryDate(e);
      final g = groups.putIfAbsent(key, () => _Group());
      g.count++;
      final latest = g.latestAt;
      if (g.latest == null ||
          (when != null && (latest == null || when.isAfter(latest)))) {
        g.latest = e;
        g.latestAt = when;
      }
    }

    final ranked = groups.values.where((g) => g.count >= minimum).toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        if (byCount != 0) return byCount;
        final ta = a.latestAt, tb = b.latestAt;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });

    return [for (final g in ranked.take(limit)) g.toUsual()];
  }

  /// Loads the last [days] of [userId]'s food and ranks it for [meal].
  static Future<List<UsualFood>> load(String userId, String meal) async {
    final now = BalanceService.now();
    final start = BalanceService.startOfDay(BalanceService.addDays(now, -days));
    final end = BalanceService.addDays(BalanceService.startOfDay(now), 1);
    final docs = await BalanceService.entriesBetween(userId, start, end);
    return rank(docs.map((d) => d.data()), meal: meal);
  }
}

class _Group {
  int count = 0;
  Map<String, dynamic>? latest;
  DateTime? latestAt;

  UsualFood toUsual() {
    final e = latest!;
    final m = Macros.fromEntry(e);
    return UsualFood(
      name: '${e['food_description']}'.trim(),
      portion: '${e['food_portion'] ?? ''}'.trim(),
      calories: m.calories,
      protein: m.protein,
      carbs: m.carbs,
      fat: m.fat,
      count: count,
      lastLogged: latestAt,
    );
  }
}
