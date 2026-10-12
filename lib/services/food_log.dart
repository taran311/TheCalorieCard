import 'package:namer_app/services/analytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:namer_app/services/achievement_service.dart';
import 'package:namer_app/services/balance_service.dart';

/// What was just logged, so the screen that asked can offer Undo.
class LoggedFoods {
  final List<String> ids;
  final double calories;
  final String meal;

  const LoggedFoods(this.ids, this.calories, this.meal);

  static const none = LoggedFoods([], 0, '');

  int get count => ids.length;
}

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

  /// When set (to yesterday), foods and recipes logged go on that day
  /// instead of today, and today's card isn't charged. The Card screen sets
  /// it while you add something you forgot yesterday, and clears it after.
  static DateTime? logDay;

  /// Logs [multiplier] servings of a recipe to today and charges the card.
  static Future<LoggedFoods> logRecipe({
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

    final one = Macros(
      calories: BalanceService.number(recipe['total_calories']) ?? 0,
      protein: BalanceService.number(recipe['total_protein']) ?? 0,
      carbs: BalanceService.number(recipe['total_carbs']) ?? 0,
      fat: BalanceService.number(recipe['total_fat']) ?? 0,
    );
    final amount = one.scaled(multiplier);
    final servingSize =
        (recipe['serving_size'] as String?) ?? 'Per 1 Serving';

    final ids = await BalanceService.logEntries(uid, day: logDay, [
      {
        'food_description': 'Recipe: ${recipe['name'] ?? ''}',
        ...amount.toEntryFields(),
        'food_portion': portionLabel(servingSize, multiplier),
        'foodCategory': meal,
        'recipe_id': recipeId,
        'is_recipe': true,
        // So editing it later starts from the servings logged.
        'food_serving_size': servingSize,
        if ((multiplier - 1).abs() > 1e-9) ...{
          'food_base': one.toEntryFields(),
          'food_portion_base': portionLabel(servingSize, 1),
          'food_multiplier': multiplier,
        },
      }
    ]);

    await _afterLogging(uid, foods: 1);
    return LoggedFoods(ids, amount.calories.roundToDouble(), meal);
  }

  /// Logs individual foods to [meal] and charges the card. Each item needs
  /// `name`, `calories`, `protein`, `carbs`, `fat` and optionally `portion`.
  ///
  /// Calories are stored as whole numbers, and the card is charged exactly
  /// what's stored, so removing a food later refunds the same amount.
  ///
  /// Where it came from (`source`: database, AI estimate, scan…) and
  /// whether it's worth a second look (`needs_review`) are kept on the
  /// entry, so the diary can mark estimates.
  static Future<LoggedFoods> logFoods({
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
          ..._portionFields(item),
          if (item['source'] != null) 'food_source': '${item['source']}',
          if (item['needs_review'] == true || item['source'] == 'ai')
            'food_estimate': true,
        }
    ];
    final ids = await BalanceService.logEntries(uid, entries, day: logDay);
    Analytics.track('food_logged');
    await _afterLogging(
      uid,
      foods: entries.length,
      scans: items.where((i) => i['source'] == 'barcode').length,
    );
    return LoggedFoods(
      ids,
      entries.fold<double>(
          0, (s, e) => s + (BalanceService.number(e['food_calories']) ?? 0)),
      meal,
    );
  }

  /// For an item logged at a multiple of what was looked up ("×2.5"): the
  /// single portion and the multiple, so editing it later starts from
  /// ×2.5 rather than treating 2.5 portions as one.
  static Map<String, dynamic> _portionFields(Map<String, dynamic> item) {
    final m = BalanceService.number(item['multiplier']);
    final base = item['base'];
    if (m == null || !m.isFinite || m <= 0 || (m - 1).abs() < 1e-9) {
      return const {};
    }
    if (base is! Map) return const {};
    return {
      'food_base': Macros(
        calories: BalanceService.number(base['calories']) ?? 0,
        protein: BalanceService.number(base['protein']) ?? 0,
        carbs: BalanceService.number(base['carbs']) ?? 0,
        fat: BalanceService.number(base['fat']) ?? 0,
      ).toEntryFields(),
      'food_portion_base':
          (item['base_portion'] ?? item['portion'] ?? '').toString(),
      'food_multiplier': m,
    };
  }

  /// Takes back what was just logged (the Undo on "Added …").
  static Future<void> undo(LoggedFoods logged, {String? userId}) async {
    final uid = _uid(userId);
    for (final id in logged.ids) {
      await BalanceService.deleteEntry(uid, id);
    }
    notifyChanged();
  }

  /// Changes a logged food and charges or refunds the card the difference.
  ///
  /// [multiplier] is relative to the food as first logged (1 = as logged,
  /// 2 = double), so editing twice never compounds. [calories] replaces
  /// the calories outright (for fixing an estimate; macros are kept).
  /// [meal] moves it to another meal.
  static Future<void> updateEntry(
    String entryId, {
    required Map<String, dynamic> entry,
    double? multiplier,
    double? calories,
    String? meal,
    String? userId,
  }) async {
    final uid = _uid(userId);
    final base = baseOf(entry);
    final basePortion = basePortionOf(entry);
    final servingSize = entry['food_serving_size'];
    Macros? macros;
    final fields = <String, dynamic>{};

    if (multiplier != null) {
      if (!multiplier.isFinite || multiplier <= 0) {
        throw ArgumentError('Portion must be more than zero');
      }
      final scaled = base.scaled(multiplier);
      macros = Macros(
        calories: scaled.calories.roundToDouble(),
        protein: scaled.protein,
        carbs: scaled.carbs,
        fat: scaled.fat,
      );
      fields.addAll({
        'food_base': base.toEntryFields(),
        'food_portion_base': basePortion,
        'food_multiplier': multiplier,
        'food_portion': servingSize is String
            ? portionLabel(servingSize, multiplier)
            : multiplier == 1
                ? basePortion
                : basePortion.isEmpty
                    ? '×${formatAmount(multiplier)}'
                    : '${formatAmount(multiplier)} × $basePortion',
      });
    }
    if (calories != null) {
      if (!calories.isFinite || calories < 0) {
        throw ArgumentError('Calories must be zero or more');
      }
      final current = macros ?? Macros.fromEntry(entry);
      macros = Macros(
        calories: calories.roundToDouble(),
        protein: current.protein,
        carbs: current.carbs,
        fat: current.fat,
      );
      fields['food_estimate'] = false;
      fields['food_edited'] = true;
    }
    if (meal != null) fields['foodCategory'] = meal;
    if (fields.isEmpty && macros == null) return;

    await BalanceService.updateEntry(uid, entryId,
        macros: macros, fields: fields);
    notifyChanged();
  }

  /// Longest note kept on a food (like a bank transaction note).
  static const maxNoteLength = 200;

  /// The note on a logged food ("at Nando's with Sam"), or '' if none.
  static String noteOf(Map<String, dynamic> entry) =>
      (entry['food_note'] ?? '').toString().trim();

  /// Saves (or, if blank, removes) the note on a logged food. Only
  /// `food_note` is written: the calories and the card are left alone.
  static Future<void> setNote(String entryId, String note,
      {String? userId}) async {
    var text = note.trim();
    if (text.length > maxNoteLength) text = text.substring(0, maxNoteLength);
    await BalanceService.updateEntry(_uid(userId), entryId, fields: {
      'food_note': text.isEmpty ? FieldValue.delete() : text,
    });
    notifyChanged();
  }

  /// One portion of the food (before any multiple: "2.5 × 1 slice" is
  /// 2.5 of this).
  static Macros baseOf(Map<String, dynamic> entry) {
    final b = entry['food_base'];
    if (b is Map) return Macros.fromEntry(Map<String, dynamic>.from(b));
    final old = _olderMultiple(entry);
    if (old != null) return Macros.fromEntry(entry).scaled(1 / old.multiplier);
    return Macros.fromEntry(entry);
  }

  /// How many portions it is (1 if just one).
  static double multiplierOf(Map<String, dynamic> entry) {
    final m = BalanceService.number(entry['food_multiplier']);
    if (m != null && m > 0) return m;
    return _olderMultiple(entry)?.multiplier ?? 1;
  }

  /// The single portion's label ("1 slice" for "2.5 × 1 slice").
  static String basePortionOf(Map<String, dynamic> entry) {
    final stored = entry['food_portion_base'];
    if (stored != null) return '$stored';
    final old = _olderMultiple(entry);
    if (old != null) return old.portion;
    return '${entry['food_portion'] ?? ''}';
  }

  static final _timesPortion =
      RegExp(r'^\s*(\d+(?:\.\d+)?)\s*×\s*(.*)$');

  /// Foods logged at a multiple before the multiple was saved with them:
  /// their portion still reads "2.5 × 1 slice", so the multiple can be
  /// worked out from that.
  static ({double multiplier, String portion})? _olderMultiple(
      Map<String, dynamic> entry) {
    if (entry['food_multiplier'] != null || entry['food_base'] != null) {
      return null;
    }
    final match = _timesPortion.firstMatch('${entry['food_portion'] ?? ''}');
    final m = match == null ? null : double.tryParse(match.group(1)!);
    if (m == null || !m.isFinite || m <= 0 || (m - 1).abs() < 1e-9) {
      return null;
    }
    return (multiplier: m, portion: match!.group(2)!.trim());
  }

  /// Removes a logged food and refunds the card if it was today's.
  static Future<void> remove(String entryId, {String? userId}) async {
    await BalanceService.deleteEntry(_uid(userId), entryId);
    notifyChanged();
  }

  /// [remove], keeping what the entry held so Undo can put it back exactly
  /// ([restore]). Null if it was already gone.
  static Future<Map<String, dynamic>?> removeForUndo(String entryId,
      {String? userId}) async {
    final data = await BalanceService.removeEntry(_uid(userId), entryId);
    notifyChanged();
    return data;
  }

  /// Undo for [removeForUndo]: the same entry back, and the card charged.
  static Future<void> restore(String entryId, Map<String, dynamic> data,
      {String? userId}) async {
    await BalanceService.restoreEntry(_uid(userId), entryId, data);
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
