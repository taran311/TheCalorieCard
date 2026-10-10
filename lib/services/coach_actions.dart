import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/food_resolver.dart';
import 'package:namer_app/services/recipe_service.dart';

/// A change Coach has proposed. Nothing happens until the user accepts.
class CoachAction {
  final String type;
  final Map<String, dynamic> data;

  const CoachAction(this.type, this.data);

  static const types = {
    'log_food',
    'log_recipe',
    'remove_food',
    'create_recipe',
    'delete_recipe',
  };

  static CoachAction? fromJson(dynamic j) {
    if (j is! Map) return null;
    final type = '${j['type'] ?? ''}';
    if (!types.contains(type)) return null;
    return CoachAction(type, Map<String, dynamic>.from(j));
  }

  String get meal {
    final m = FoodLog.displayMeal('${data['meal'] ?? ''}');
    return FoodLog.meals.firstWhere(
      (x) => x.toLowerCase() == m.toLowerCase(),
      orElse: () => 'Snacks',
    );
  }

  List<String> strings(String key) => [
        for (final v in (data[key] is List ? data[key] as List : const []))
          if ('$v'.trim().isNotEmpty) '$v'.trim()
      ];

  double get servings {
    final v = BalanceService.number(data['servings']) ?? 1.0;
    return v.isFinite && v > 0 ? v : 1;
  }
}

/// One row on a proposal card.
class ProposalLine {
  final String name;
  final String detail;
  final Macros? macros;

  /// Couldn't be found or worked out; left out if accepted.
  final bool skipped;

  /// Calories are a rough estimate, worth a glance.
  final bool estimate;

  const ProposalLine({
    required this.name,
    this.detail = '',
    this.macros,
    this.skipped = false,
    this.estimate = false,
  });
}

/// A proposal worked out and ready to show, with what accepting does.
class PreparedAction {
  final CoachAction action;
  final String title;
  final String icon;
  final List<ProposalLine> lines;

  /// Total effect on the card (positive = spent, negative = refunded), or
  /// null when it doesn't touch the card (recipes).
  final Macros? total;
  final String? note;
  final String acceptLabel;
  final bool destructive;

  /// Makes the change and returns a short "done" message.
  final Future<String> Function() apply;

  /// Plain-English summary for Coach's memory of the chat.
  final String summary;

  const PreparedAction({
    required this.action,
    required this.title,
    required this.icon,
    required this.lines,
    required this.apply,
    required this.summary,
    this.total,
    this.note,
    this.acceptLabel = 'Accept',
    this.destructive = false,
  });
}

class CoachActionException implements Exception {
  final String message;
  const CoachActionException(this.message);

  @override
  String toString() => message;
}

class CoachActions {
  CoachActions._();

  static String _kcal(double v) => '${v.round()} kcal';

  /// Looks up what's needed (real nutrition from the food database, the
  /// recipe, the entries) so the card shows exactly what will change.
  static Future<PreparedAction> prepare(CoachAction a, String uid) {
    switch (a.type) {
      case 'log_food':
        return _logFood(a, uid);
      case 'log_recipe':
        return _logRecipe(a, uid);
      case 'remove_food':
        return _removeFood(a, uid);
      case 'create_recipe':
        return _createRecipe(a, uid);
      case 'delete_recipe':
        return _deleteRecipe(a, uid);
    }
    throw const CoachActionException("Coach suggested something I can't do.");
  }

  static Future<List<(String, ResolvedFood?)>> _resolve(
      List<String> queries) async {
    final results = await FoodResolver.resolveAll(queries);
    return [
      for (var i = 0; i < queries.length; i++)
        (queries[i], i < results.length ? results[i] : null)
    ];
  }

  static Macros _macrosOf(ResolvedFood f) => Macros(
        calories: f.calories,
        protein: f.protein,
        carbs: f.carbs,
        fat: f.fat,
      );

  static ProposalLine _foodLine(String query, ResolvedFood? f) {
    if (f == null || f.calories <= 0) {
      return ProposalLine(
        name: query,
        detail: "Couldn't find this one, so it'll be left out",
        skipped: true,
      );
    }
    final m = _macrosOf(f);
    return ProposalLine(
      name: f.name.isEmpty ? query : f.name,
      detail: [
        if (f.portion.isNotEmpty) f.portion,
        _kcal(m.calories),
      ].join(' · '),
      macros: m,
      estimate: f.needsReview,
    );
  }

  static Future<PreparedAction> _logFood(CoachAction a, String uid) async {
    final queries = a.strings('items');
    if (queries.isEmpty) {
      throw const CoachActionException('There was nothing to add.');
    }
    final resolved = await _resolve(queries);
    final lines = [for (final (q, f) in resolved) _foodLine(q, f)];
    final ok = [
      for (final (q, f) in resolved)
        if (f != null && f.calories > 0) (q, f)
    ];
    if (ok.isEmpty) {
      throw const CoachActionException(
          "I couldn't find those foods. Try describing them differently?");
    }
    final total = ok.fold<Macros>(Macros.zero, (s, x) => s + _macrosOf(x.$2));
    final meal = a.meal;
    final names = ok.map((x) => x.$2.name.isEmpty ? x.$1 : x.$2.name);

    return PreparedAction(
      action: a,
      title: 'Add to $meal',
      icon: '🍽️',
      lines: lines,
      total: total,
      note: lines.any((l) => l.estimate)
          ? 'Some amounts are estimates. You can edit them after.'
          : null,
      acceptLabel: 'Add',
      summary: 'add ${names.join(', ')} to $meal (${_kcal(total.calories)})',
      apply: () async {
        await FoodLog.logFoods(
          meal: meal,
          userId: uid,
          items: [
            for (final (q, f) in ok)
              {
                'name': f.name.isEmpty ? q : f.name,
                'portion': f.portion,
                'calories': f.calories,
                'protein': f.protein,
                'carbs': f.carbs,
                'fat': f.fat,
              }
          ],
        );
        return 'Added ${ok.length} item${ok.length == 1 ? '' : 's'} to '
            '$meal (${_kcal(total.calories.roundToDouble())})';
      },
    );
  }

  static Future<Map<String, dynamic>> _ownRecipe(
      String uid, String recipeId) async {
    if (recipeId.isEmpty) {
      throw const CoachActionException("I couldn't find that recipe.");
    }
    final doc = await BalanceService.db.collection('recipes').doc(recipeId).get();
    final data = doc.data();
    if (!doc.exists || data == null || data['user_id'] != uid) {
      throw const CoachActionException("I couldn't find that recipe.");
    }
    return data;
  }

  static Future<PreparedAction> _logRecipe(CoachAction a, String uid) async {
    final id = '${a.data['recipe_id'] ?? ''}';
    final recipe = await _ownRecipe(uid, id);
    final servingSize = (recipe['serving_size'] as String?) ?? 'Per 1 Serving';
    // "Servings" as they'd say it; gram-based recipes count whole recipes.
    final multiplier = FoodLog.isGrams(servingSize)
        ? a.servings
        : a.servings / FoodLog.servingAmount(servingSize);
    final macros = Macros(
      calories: BalanceService.number(recipe['total_calories']) ?? 0,
      protein: BalanceService.number(recipe['total_protein']) ?? 0,
      carbs: BalanceService.number(recipe['total_carbs']) ?? 0,
      fat: BalanceService.number(recipe['total_fat']) ?? 0,
    ).scaled(multiplier);
    final name = '${recipe['name'] ?? 'Recipe'}';
    final meal = a.meal;

    return PreparedAction(
      action: a,
      title: 'Add to $meal',
      icon: '🥘',
      lines: [
        ProposalLine(
          name: name,
          detail:
              '${FoodLog.portionLabel(servingSize, multiplier)} · ${_kcal(macros.calories)}',
          macros: macros,
        ),
      ],
      total: macros,
      acceptLabel: 'Add',
      summary: 'add $name to $meal (${_kcal(macros.calories)})',
      apply: () async {
        await FoodLog.logRecipe(
          recipeId: id,
          recipe: recipe,
          meal: meal,
          multiplier: multiplier,
          userId: uid,
        );
        return 'Added $name to $meal';
      },
    );
  }

  static Future<PreparedAction> _removeFood(CoachAction a, String uid) async {
    final ids = a.strings('entry_ids');
    final found = <(String, Map<String, dynamic>)>[];
    for (final id in ids) {
      final doc = await BalanceService.db.collection('user_food').doc(id).get();
      final data = doc.data();
      // Only your own food, logged today (not recipe ingredients).
      if (doc.exists &&
          data != null &&
          data['user_id'] == uid &&
          BalanceService.isLogEntry(data) &&
          BalanceService.isToday(BalanceService.entryDate(data))) {
        found.add((id, data));
      }
    }
    if (found.isEmpty) {
      throw const CoachActionException(
          "I couldn't find that in today's diary. It may already be gone.");
    }
    final lines = [
      for (final (_, d) in found)
        ProposalLine(
          name: '${d['food_description'] ?? 'Food'}',
          detail: [
            if ('${d['food_portion'] ?? ''}'.isNotEmpty) '${d['food_portion']}',
            FoodLog.displayMeal('${d['foodCategory'] ?? ''}'),
            _kcal(Macros.fromEntry(d).calories),
          ].where((s) => s.isNotEmpty).join(' · '),
          macros: Macros.fromEntry(d),
        )
    ];
    final total =
        found.fold<Macros>(Macros.zero, (s, x) => s + Macros.fromEntry(x.$2));

    return PreparedAction(
      action: a,
      title: 'Remove from today',
      icon: '🗑️',
      lines: lines,
      total: total.scaled(-1),
      acceptLabel: 'Remove',
      destructive: true,
      summary: 'remove ${lines.map((l) => l.name).join(', ')}',
      apply: () async {
        for (final (id, _) in found) {
          await FoodLog.remove(id, userId: uid);
        }
        return 'Removed ${found.length} item${found.length == 1 ? '' : 's'}: '
            '${_kcal(total.calories)} back on your card';
      },
    );
  }

  static Future<PreparedAction> _createRecipe(
      CoachAction a, String uid) async {
    final name = '${a.data['name'] ?? ''}'.trim();
    final queries = a.strings('ingredients');
    if (name.isEmpty || queries.isEmpty) {
      throw const CoachActionException('That recipe was missing details.');
    }
    final resolved = await _resolve(queries);
    final lines = [for (final (q, f) in resolved) _foodLine(q, f)];
    final ingredients = [
      for (final (q, f) in resolved)
        if (f != null && f.calories > 0)
          RecipeIngredient(
            name: f.name.isEmpty ? q : f.name,
            macros: _macrosOf(f),
            portion: f.portion,
          )
    ];
    if (ingredients.isEmpty) {
      throw const CoachActionException(
          "I couldn't find those ingredients. Try again with more detail?");
    }
    final servings = a.servings;
    final servingSize = FoodLog.servingLabel(servings, grams: false);
    final total = ingredients.fold<Macros>(Macros.zero, (s, i) => s + i.macros);

    return PreparedAction(
      action: a,
      title: 'Save recipe: $name',
      icon: '📖',
      lines: lines,
      note: 'Makes ${FoodLog.formatAmount(servings)} '
          'serving${servings == 1 ? '' : 's'}: about '
          '${_kcal(total.calories / servings)} each. '
          "Saving doesn't add it to today.",
      acceptLabel: 'Save',
      summary: 'save a recipe called $name',
      apply: () async {
        await RecipeService.create(
          uid,
          name: name,
          servingSize: servingSize,
          ingredients: ingredients,
        );
        return 'Saved "$name" to your Recipes';
      },
    );
  }

  static Future<PreparedAction> _deleteRecipe(
      CoachAction a, String uid) async {
    final id = '${a.data['recipe_id'] ?? ''}';
    final recipe = await _ownRecipe(uid, id);
    final name = '${recipe['name'] ?? 'Recipe'}';
    return PreparedAction(
      action: a,
      title: 'Delete recipe',
      icon: '🗑️',
      lines: [
        ProposalLine(
          name: name,
          detail: '${recipe['serving_size'] ?? ''}',
        ),
      ],
      note: "Anything you've already logged from it stays in your diary.",
      acceptLabel: 'Delete',
      destructive: true,
      summary: 'delete the recipe $name',
      apply: () async {
        await RecipeService.delete(uid, id);
        return 'Deleted "$name" from your Recipes';
      },
    );
  }
}
