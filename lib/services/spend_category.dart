import 'package:flutter/material.dart';

/// Where calories went, like the spending categories in a banking app.
///
/// Worked out from the food's description (and whether it was a recipe),
/// so it also works for everything logged before categories existed.
enum SpendCategory {
  homeCooked('Home cooked', Icons.soup_kitchen_outlined, Color(0xFF10B981)),
  takeaway('Takeaway & eating out', Icons.delivery_dining, Color(0xFFF97316)),
  drinks('Drinks', Icons.local_cafe_outlined, Color(0xFF0EA5E9)),
  alcohol('Alcohol', Icons.local_bar_outlined, Color(0xFFA855F7)),
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

  static const _alcohol = [
    'beer', 'lager', 'ale', 'pale ale', 'ipa', 'stout', 'porter', 'guinness',
    'cider', 'wine', 'prosecco', 'champagne', 'cava', 'spritz', 'aperol',
    'pimms', 'sangria', 'vodka', 'gin', 'rum', 'whisky', 'whiskey',
    'bourbon', 'scotch', 'tequila', 'brandy', 'cognac', 'sambuca', 'jager',
    'jagerbomb', 'baileys', 'liqueur', 'sherry', 'martini', 'negroni',
    'mojito', 'margarita', 'daiquiri', 'cosmopolitan', 'pina colada',
    'bloody mary', 'cocktail', 'shandy', 'alcopop', 'hard seltzer',
    'white claw', 'smirnoff ice', 'wkd', 'bacardi', 'kopparberg',
    'rekorderlig', 'stella', 'peroni', 'corona', 'heineken', 'carling',
    'budweiser', 'moretti', 'cobra', 'kronenbourg', 'fosters', 'coors',
    'madri', 'desperados', 'strongbow', 'thatchers', 'magners', 'brewdog',
    'g and t', 'g&t',
    // Wine as people order it: by colour, glass, bottle or grape.
    'red wine', 'white wine', 'rose', 'glass of red',
    'glass of white', 'glass of rose', 'bottle of red', 'bottle of white',
    'bottle of rose', 'large red', 'large white', 'large rose',
    'small red', 'small white', 'medium red', 'medium white', 'malbec',
    'merlot', 'shiraz', 'rioja', 'pinot grigio', 'pinot noir',
    'sauvignon blanc', 'sauvignon', 'chardonnay', 'cabernet', 'tempranillo',
    'chianti', 'zinfandel', 'riesling', 'albarino', 'picpoul', 'sancerre',
    'chablis', 'port', 'vermouth', 'mulled wine',
    // Spirits as people order them.
    'shot', 'double vodka', 'double gin', 'double rum', 'double whisky',
    'vodka coke', 'rum and coke', 'jack and coke', 'jack daniels',
    'gin and tonic', 'espresso martini', 'pornstar martini', 'old fashioned',
    'long island', 'whisky sour', 'amaretto sour', 'pisco sour', 'amaretto', 'disaronno', 'limoncello', 'ouzo',
    'soju', 'sake', 'mead', 'tia maria', 'kahlua', 'southern comfort',
    'malibu', 'captain morgan', 'jameson', 'hennessy', 'absolut',
    'gordons', 'tanqueray', 'hendricks', 'bombay sapphire',
    // More beers and ciders.
    'pils', 'pilsner', 'craft beer', 'camden hells',
    'hells', 'asahi', 'san miguel', 'estrella', 'birra moretti', 'tiger',
    'kingfisher', 'carlsberg', 'amstel', 'beck', 'becks', 'cruzcampo',
    'grolsch', 'staropramen', 'doom bar', 'old speckled hen', 'punk ipa',
    'neck oil', 'angry orchard', 'old mout', 'aspall', 'westons',
  ];

  /// A pint (or half) on its own is almost always beer or cider; milk and
  /// soft drinks by the pint say so.
  static const _pintOf = ['pint', 'half pint', 'pints'];
  static const _pintNotAlcohol = [
    'milk', 'water', 'squash', 'juice', 'coke', 'cola', 'lemonade',
    'pepsi', 'soda', 'orange', 'lime', 'tonic', 'j2o', 'appletiser',
  ];

  /// Alcohol-free versions: drinks, not alcohol.
  static const _alcoholFree = [
    'alcohol free', 'non alcoholic', 'zero alcohol', '0 0', 'ginger beer',
    'ginger ale', 'root beer', 'nosecco', 'mocktail', 'virgin', 'shirley temple',
  ];

  /// Foods that borrow a drink's name: neither alcohol nor a drink.
  static const _namedAfterDrink = [
    'wine gum', 'rum and raisin', 'beer battered', 'beer batter',
    'wine vinegar', 'cider vinegar', 'wine sauce', 'wine gravy',
    'tequila lime', 'cola bottle', 'rose harissa', 'rosehip', 'rose water',
    'rosewater', 'sour cream', 'sourdough', 'sour sweets', 'sour patch',
    'sweet and sour', 'sweet & sour', 'hot and sour', 'shot of espresso',
    'espresso shot', 'wheatgrass shot', 'ginger shot', 'port salut',
    'portobello', 'tiger bread', 'tiger prawn', 'tiger loaf', 'tiger nut',
  ];

  static const _drinks = [
    'coffee', 'latte', 'cappuccino', 'americano', 'flat white', 'espresso',
    'mocha', 'macchiato', 'frappuccino', 'tea', 'hot chocolate', 'cola',
    'coke', 'pepsi', 'sprite', 'fanta', 'lemonade', 'juice', 'smoothie',
    'milkshake', 'shake', 'red bull', 'monster', 'lucozade', 'energy drink',
    'squash', 'water', 'kombucha', 'oat milk', 'glass of milk', 'pint',
    'seltzer', 'tonic', 'ginger beer', 'ginger ale', 'root beer',
    'nosecco', 'mocktail', 'virgin mojito', 'shirley temple',
  ];

  static const _snacks = [
    'crisps', 'crisp', 'chips', 'chocolate', 'biscuit', 'cookie', 'cake',
    'sweets', 'candy', 'donut', 'doughnut', 'muffin', 'brownie', 'ice cream',
    'protein bar', 'cereal bar', 'flapjack', 'popcorn', 'pringles', 'kitkat',
    'snickers', 'mars', 'twix', 'haribo', 'dairy milk', 'croissant',
    'pastry', 'cheesecake', 'pudding', 'dessert', 'nuts', 'peanuts',
    'wine gum', 'cola bottle', 'gummies', 'jelly babies', 'skittles',
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

  /// Category for a logged food from its `user_food` fields: the one the
  /// person picked (`spend_category`) if they changed it, otherwise worked
  /// out from the name.
  static SpendCategory of(Map<String, dynamic> entry) {
    final chosen = byName(entry['spend_category']);
    if (chosen != null) return chosen;
    if (entry['is_recipe'] == true) return SpendCategory.homeCooked;
    return fromDescription((entry['food_description'] ?? '').toString());
  }

  /// The category called [name] (as saved), or null.
  static SpendCategory? byName(Object? name) {
    for (final c in SpendCategory.values) {
      if (c.name == name) return c;
    }
    return null;
  }

  static SpendCategory fromDescription(String description) {
    // "rosé" as "rose": accents would otherwise split the word.
    final lower = description
        .toLowerCase()
        .replaceAll(RegExp('[éèê]'), 'e');
    if (lower.startsWith('recipe:')) return SpendCategory.homeCooked;
    final text = ' ${lower.replaceAll(RegExp(r"[^a-z0-9&]+"), ' ')} ';
    if (_hasAny(text, _takeaway)) return SpendCategory.takeaway;
    final borrowed = _hasAny(text, _namedAfterDrink);
    final pint = _hasAny(text, _pintOf) && !_hasAny(text, _pintNotAlcohol);
    if (!borrowed && (_hasAny(text, _alcohol) || pint)) {
      // "Alcohol free lager", "Heineken 0.0": a drink, not alcohol.
      return _hasAny(text, _alcoholFree)
          ? SpendCategory.drinks
          : SpendCategory.alcohol;
    }
    // "chocolate milkshake" is a drink; "chocolate bar" a snack.
    if (!borrowed && _hasAny(text, _drinks)) return SpendCategory.drinks;
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
              items) =>
      breakdownBy([
        for (final item in items)
          (
            category: item.isRecipe
                ? SpendCategory.homeCooked
                : SpendCategory.fromDescription(item.description),
            calories: item.calories,
          )
      ]);

  /// The same, for foods whose category is already known (including one
  /// the person picked).
  static List<CategorySpend> breakdownBy(
      Iterable<({SpendCategory category, double calories})> items) {
    final totals = <SpendCategory, double>{};
    final counts = <SpendCategory, int>{};
    var all = 0.0;
    for (final item in items) {
      final c = item.category;
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
