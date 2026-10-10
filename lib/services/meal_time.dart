/// Which meal people most likely mean at a given time of day, for places
/// that have to pick one without asking (the recipe sheet, Coach).
class MealTime {
  MealTime._();

  /// Breakfast before 11, Lunch until 3, Dinner 5–10pm, otherwise Snacks.
  static String forHour(int hour) {
    if (hour < 11) return 'Breakfast';
    if (hour < 15) return 'Lunch';
    if (hour >= 17 && hour < 22) return 'Dinner';
    return 'Snacks';
  }
}
