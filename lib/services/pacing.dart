/// "Safe to spend" pacing for the Card screen: how much of what's left
/// each meal still to come can have, so the day doesn't run out at dinner.
///
/// Pure (no Firestore, no clock of its own) so it's easy to test.
class PacingPlan {
  /// Main meals still to come that nothing's been logged to yet, in order.
  final List<String> meals;

  /// About how much each of [meals] can have (rounded to 10 kcal).
  final int perMeal;

  /// Kept back for snacks (0 if snacks already have something).
  final int snackReserve;

  const PacingPlan({
    required this.meals,
    required this.perMeal,
    required this.snackReserve,
  });

  /// One friendly line, e.g. "About 650 kcal for dinner" or
  /// "≈ 450 kcal each for lunch and dinner".
  String get message {
    final names = meals.map((m) => m.toLowerCase()).toList();
    final String list;
    if (names.length == 1) {
      list = names.first;
    } else {
      list = '${names.sublist(0, names.length - 1).join(', ')} '
          'and ${names.last}';
    }
    final amount = Pacing.formatKcal(perMeal);
    return meals.length == 1
        ? 'About $amount kcal for $list'
        : '≈ $amount kcal each for $list';
  }
}

class Pacing {
  Pacing._();

  static const mainMeals = ['Breakfast', 'Lunch', 'Dinner'];

  /// Share of what's left kept back for snacks while they're empty.
  static const snackShare = 0.10;

  /// Below this a "per meal" figure isn't much help, so nothing's shown.
  static const minPerMeal = 50;

  /// The meal food is most likely for at [now], used to pre-select the
  /// Add food button: breakfast before 11, lunch before 3pm, dinner
  /// before 9pm, snacks after.
  static String mealAt(DateTime now) {
    final hour = now.hour;
    if (hour < 11) return 'Breakfast';
    if (hour < 15) return 'Lunch';
    if (hour < 21) return 'Dinner';
    return 'Snacks';
  }

  /// Whether [meal] is still to come at [now]. Matches the Add food
  /// button's guess: breakfast until 11, lunch until 3pm, dinner until 9pm.
  static bool isAhead(String meal, DateTime now) {
    final hour = now.hour;
    switch (meal) {
      case 'Breakfast':
        return hour < 11;
      case 'Lunch':
        return hour < 15;
      case 'Dinner':
        return hour < 21;
      default:
        return true;
    }
  }

  /// The plan for the rest of today, or null when there's nothing useful
  /// to say (nothing left, or no empty main meal still to come).
  ///
  /// [left] is the calories left on the card; [mealsWithFood] the meals
  /// that already have something logged today.
  static PacingPlan? plan({
    required num left,
    required DateTime now,
    required Set<String> mealsWithFood,
  }) {
    if (!left.isFinite || left <= 0) return null;
    final meals = [
      for (final m in mainMeals)
        if (!mealsWithFood.contains(m) && isAhead(m, now)) m
    ];
    if (meals.isEmpty) return null;
    final reserve = mealsWithFood.contains('Snacks')
        ? 0
        : _roundTo10(left * snackShare);
    final perMeal = _roundTo10((left - reserve) / meals.length);
    if (perMeal < minPerMeal) return null;
    return PacingPlan(meals: meals, perMeal: perMeal, snackReserve: reserve);
  }

  static int _roundTo10(num v) => ((v / 10).round() * 10).toInt();

  /// 1,250 style.
  static String formatKcal(int value) {
    final n = value.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < n.length; i++) {
      if (i > 0 && (n.length - i) % 3 == 0) b.write(',');
      b.write(n[i]);
    }
    return b.toString();
  }
}
