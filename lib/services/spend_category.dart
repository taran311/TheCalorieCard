import 'package:flutter/material.dart';

/// Where calories went, like the spending categories in a banking app.
///
/// Worked out from the food's description (and whether it was a recipe),
/// so it also works for everything logged before categories existed.
enum SpendCategory {
  homeCooked('Home cooked', Icons.soup_kitchen_outlined, Color(0xFF10B981)),
  takeaway('Takeaway & eating out', Icons.delivery_dining, Color(0xFFF97316)),
  drinks('Drinks', Icons.local_cafe_outlined, Color(0xFF0EA5E9)),
  snacks('Snacks & sweets', Icons.cookie_outlined, Color(0xFFEC4899)),
  fruitVeg('Fruit & veg', Icons.eco_outlined, Color(0xFF84CC16)),
  meals('Meals & other', Icons.restaurant_outlined, Color(0xFF6366F1));

  final String label;
  final IconData icon;
  final Color color;

  const SpendCategory(this.label, this.icon, this.color);

  static const _takeaway = [
    'mcdonald', 'kfc', 'burger king', 'subway', 'greggs',
    'nando', 'domino', 'pizza hut', 'papa john', 'five guys', 'wagamama',
    'leon', 'pret', 'itsu', 'wasabi', 'taco bell', 'popeyes', 'wendy',
    'chipotle', 'deliveroo', 'uber eats', 'just eat', 'takeaway', 'take away',
    'kebab', 'chippy', 'fish and chips', 'fish & chips', 'fish chips', 'big mac', 'mcflurry',
    'whopper', 'zinger', 'happy meal', 'chicken nuggets', 'mcnuggets',
  ];

  static const _drinks = [
    'coffee', 'latte', 'cappuccino', 'americano', 'flat white', 'espresso',
    'mocha', 'macchiato', 'frappuccino', 'tea', 'hot chocolate', 'cola',
    'coke', 'pepsi', 'sprite', 'fanta', 'lemonade', 'juice', 'smoothie',
    'milkshake', 'shake', 'beer', 'lager', 'pale ale', 'cider', 'wine', 'prosecco',
    'champagne', 'vodka', 'gin', 'rum', 'whisky', 'whiskey', 'tequila',
    'cocktail', 'red bull', 'monster', 'lucozade', 'energy drink', 'squash',
    'water', 'kombucha', 'oat milk', 'glass of milk', 'pint',
  ];

  static const _snacks = [
    'crisps', 'crisp', 'chips', 'chocolate', 'biscuit', 'cookie', 'cake',
    'sweets', 'candy', 'donut', 'doughnut', 'muffin', 'brownie', 'ice cream',
    'protein bar', 'cereal bar', 'flapjack', 'popcorn', 'pringles', 'kitkat',
    'snickers', 'mars', 'twix', 'haribo', 'dairy milk', 'croissant',
    'pastry', 'cheesecake', 'pudding', 'dessert', 'nuts', 'peanuts',
  ];

  static const _fruitVeg = [
    'apple', 'banana', 'orange', 'grape', 'berries', 'strawberr', 'blueberr',
    'raspberr', 'melon', 'watermelon', 'pear', 'peach', 'plum', 'mango',
    'pineapple', 'kiwi', 'satsuma', 'clementine', 'salad', 'carrot',
    'broccoli', 'spinach', 'kale', 'cucumber', 'tomato', 'pepper', 'lettuce',
    'avocado', 'vegetables', 'veg',
  ];

  static final Map<String, RegExp> _patterns = {};

  /// True if any of [words] appears in [text] as whole word(s), allowing
  /// plural endings. So "tea" matches "green tea" but not "teacake",
  /// "rum" doesn't match "rump steak", and "strawberr" matches
  /// "strawberry" and "strawberries".
  static bool _hasAny(String text, List<String> words) {
    for (final w in words) {
      final pattern = _patterns.putIfAbsent(
          w, () => RegExp(' ${RegExp.escape(w)}(?:s|es|y|ies)? '));
      if (pattern.hasMatch(text)) return true;
    }
    return false;
  }

  /// Category for a logged food from its `user_food` fields.
  static SpendCategory of(Map<String, dynamic> entry) {
    if (entry['is_recipe'] == true) return SpendCategory.homeCooked;
    return fromDescription((entry['food_description'] ?? '').toString());
  }

  static SpendCategory fromDescription(String description) {
    final lower = description.toLowerCase();
    if (lower.startsWith('recipe:')) return SpendCategory.homeCooked;
    final text = ' ${lower.replaceAll(RegExp(r"[^a-z0-9&]+"), ' ')} ';
    if (_hasAny(text, _takeaway)) return SpendCategory.takeaway;
    // "chocolate milkshake" is a drink; "chocolate bar" a snack.
    if (_hasAny(text, _drinks)) return SpendCategory.drinks;
    if (_hasAny(text, _snacks)) return SpendCategory.snacks;
    if (_hasAny(text, _fruitVeg)) return SpendCategory.fruitVeg;
    return SpendCategory.meals;
  }
}

/// One row of a "where it went" breakdown.
class CategorySpend {
  final SpendCategory category;
  final double calories;
  final double share; // 0..1 of the total
  final int count;

  const CategorySpend(this.category, this.calories, this.share, this.count);
}

class SpendInsights {
  SpendInsights._();

  /// Totals per category, biggest first. Empty categories are left out.
  static List<CategorySpend> breakdown(
      Iterable<({String description, bool isRecipe, double calories})>
          items) {
    final totals = <SpendCategory, double>{};
    final counts = <SpendCategory, int>{};
    var all = 0.0;
    for (final item in items) {
      final c = item.isRecipe
          ? SpendCategory.homeCooked
          : SpendCategory.fromDescription(item.description);
      final kcal = item.calories > 0 ? item.calories : 0.0;
      totals[c] = (totals[c] ?? 0) + kcal;
      counts[c] = (counts[c] ?? 0) + 1;
      all += kcal;
    }
    final rows = [
      for (final e in totals.entries)
        if (e.value > 0)
          CategorySpend(e.key, e.value, all > 0 ? e.value / all : 0,
              counts[e.key] ?? 0)
    ]..sort((a, b) => b.calories.compareTo(a.calories));
    return rows;
  }
}
