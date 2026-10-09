import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/calorie_sense.dart';
import 'package:namer_app/services/spend_category.dart';

/// One food and how many times it was logged.
class FoodCount {
  final String name;
  final int count;
  final double calories;

  const FoodCount(this.name, this.count, this.calories);
}

/// A month in review, like a banking app's monthly summary / "Wrapped".
class MonthWrap {
  final DateTime month; // first day of the month
  final int daysLogged; // days with any food
  final int finishedDays;
  final int onBudgetDays;
  final int bestStreak; // longest run of finished days this month
  final double totalCalories;
  final double averageCalories; // per logged day
  final double totalProtein;
  final List<FoodCount> topFoods; // most logged first, up to 5
  final SpendCategory? topCategory;
  final double calorieSense; // this month's average, 0 if none
  final int senseGuesses;

  const MonthWrap({
    required this.month,
    required this.daysLogged,
    required this.finishedDays,
    required this.onBudgetDays,
    required this.bestStreak,
    required this.totalCalories,
    required this.averageCalories,
    required this.totalProtein,
    required this.topFoods,
    required this.topCategory,
    required this.calorieSense,
    required this.senseGuesses,
  });

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'
  ];

  String get monthName => nameOf(month);

  /// "October 2026".
  static String nameOf(DateTime month) =>
      '${_months[month.month - 1]} ${month.year}';

  bool get isEmpty => daysLogged == 0;

  /// Plain-text version for sharing in chat.
  String toShareText() {
    final lines = <String>[
      '📊 My ${_months[month.month - 1]} on The Calorie Card',
      '🗓️ $daysLogged days logged · $onBudgetDays on budget',
      if (bestStreak > 0) '🔥 Best streak: $bestStreak days',
      '🍽️ Avg ${averageCalories.round()} kcal a day',
      if (topFoods.isNotEmpty)
        '⭐ Top food: ${topFoods.first.name} (×${topFoods.first.count})',
      if (topCategory != null) '💳 Biggest spend: ${topCategory!.label}',
      if (senseGuesses > 0)
        '🎯 Calorie Sense: ${calorieSense.round()}% over $senseGuesses guesses',
    ];
    return lines.join('\n');
  }
}

class WrappedService {
  WrappedService._();

  /// Builds the summary for the month containing [month].
  static Future<MonthWrap> load(String uid, DateTime month) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final today = BalanceService.startOfDay(BalanceService.now());

    final days = <DateTime>[];
    for (var d = start; d.isBefore(end) && !d.isAfter(today);
        d = BalanceService.addDays(d, 1)) {
      days.add(d);
    }

    final results = await Future.wait<Object?>([
      BalanceService.entriesBetween(uid, start, end),
      Future.wait(days.map((d) => BalanceService.db
          .collection('daily_logs')
          .doc('${uid}_${BalanceService.dateKey(d)}')
          .get())),
      BalanceService.db.collection('users').doc(uid).get(),
    ]);

    final entries =
        results[0] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final logs = results[1] as List<DocumentSnapshot<Map<String, dynamic>>>;
    final userDoc = results[2] as DocumentSnapshot<Map<String, dynamic>>;

    final loggedDays = <String>{};
    final counts = <String, FoodCount>{};
    var calories = 0.0, protein = 0.0;
    final items = <({String description, bool isRecipe, double calories})>[];

    for (final doc in entries) {
      final data = doc.data();
      final when = BalanceService.entryDate(data);
      if (when != null) loggedDays.add(BalanceService.dateKey(when));
      final m = Macros.fromEntry(data);
      calories += m.calories;
      protein += m.protein;

      final name = (data['food_description'] ?? 'Food').toString().trim();
      final key = name.toLowerCase();
      final prev = counts[key];
      counts[key] = FoodCount(
          prev?.name ?? name, (prev?.count ?? 0) + 1,
          (prev?.calories ?? 0) + m.calories);
      items.add((
        description: name,
        isRecipe: data['is_recipe'] == true,
        calories: m.calories,
      ));
    }

    var finished = 0, onBudget = 0, run = 0, best = 0;
    for (final log in logs) {
      final data = log.data();
      if (data != null && data['finished'] == true) {
        finished++;
        run++;
        if (run > best) best = run;
        final balances = data['balances'];
        final left =
            balances is Map ? BalanceService.number(balances['calories']) : null;
        if (left != null && left >= 0) onBudget++;
      } else {
        run = 0;
      }
    }

    final top = counts.values.toList()
      ..sort((a, b) => b.count != a.count
          ? b.count.compareTo(a.count)
          : b.calories.compareTo(a.calories));
    final categories = SpendInsights.breakdown(items);

    final isThisMonth =
        CalorieSense.monthKey(start) == CalorieSense.monthKey(today);
    final sense = isThisMonth
        ? CalorieSense.thisMonth(userDoc.data())
        : (average: 0.0, count: 0);

    return MonthWrap(
      month: start,
      daysLogged: loggedDays.length,
      finishedDays: finished,
      onBudgetDays: onBudget,
      bestStreak: best,
      totalCalories: calories,
      averageCalories:
          loggedDays.isEmpty ? 0 : calories / loggedDays.length,
      totalProtein: protein,
      topFoods: top.take(5).toList(),
      topCategory: categories.isEmpty ? null : categories.first.category,
      calorieSense: sense.average,
      senseGuesses: sense.count,
    );
  }
}
