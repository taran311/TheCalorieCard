import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

/// One logged food item, presented like a card transaction.
class CardTransaction {
  final String id;
  final String description;
  final String portion;
  final String category;
  final DateTime time;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  const CardTransaction({
    required this.id,
    required this.description,
    required this.portion,
    required this.category,
    required this.time,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
  });
}

/// Totals for one calendar day.
class DaySummary {
  final DateTime day;
  final List<CardTransaction> transactions;

  DaySummary(this.day, this.transactions);

  double get calories => transactions.fold(0, (s, t) => s + t.calories);
  double get protein => transactions.fold(0, (s, t) => s + t.protein);
  double get carbs => transactions.fold(0, (s, t) => s + t.carbs);
  double get fat => transactions.fold(0, (s, t) => s + t.fat);
}

/// A bank-style statement: recent days of spending against the daily budget.
class Statement {
  final double? dailyBudget;
  final List<DaySummary> days; // oldest first, one entry per day

  Statement({required this.dailyBudget, required this.days});

  List<CardTransaction> get recent {
    final all = [for (final d in days) ...d.transactions];
    all.sort((a, b) => b.time.compareTo(a.time));
    return all;
  }

  /// Days (excluding today) where something was logged and spending stayed
  /// within budget.
  int get daysUnderBudget {
    if (dailyBudget == null) return 0;
    final today = BalanceService.dateKey(BalanceService.now());
    return days
        .where((d) =>
            BalanceService.dateKey(d.day) != today &&
            d.transactions.isNotEmpty &&
            d.calories <= dailyBudget!)
        .length;
  }

  double get averageCalories {
    final logged = days.where((d) => d.transactions.isNotEmpty).toList();
    if (logged.isEmpty) return 0;
    return logged.fold<double>(0, (s, d) => s + d.calories) / logged.length;
  }
}

class StatementService {
  StatementService._();

  static double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Builds a statement for the last [days] days (including today).
  static Future<Statement> load(String userId, {int days = 7}) async {
    final today = BalanceService.startOfDay(BalanceService.now());
    final start = BalanceService.addDays(today, -(days - 1));
    final end = BalanceService.addDays(today, 1);

    // Only the days on the statement are fetched, not the whole history.
    final results = await Future.wait<Object?>([
      BalanceService.entriesBetween(userId, start, end),
      BalanceService.userDataDoc(userId),
    ]);

    final foodDocs =
        results[0] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final userDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>?;

    final byDay = <String, List<CardTransaction>>{};
    for (final doc in foodDocs) {
      final data = doc.data();
      final time = BalanceService.entryDate(data);
      if (time == null) continue;

      byDay.putIfAbsent(BalanceService.dateKey(time), () => []).add(
            CardTransaction(
              id: doc.id,
              description: (data['food_description'] ?? 'Food').toString(),
              portion: (data['food_portion'] ?? '').toString(),
              category: (data['foodCategory'] ?? '').toString(),
              time: time,
              calories: _num(data['food_calories']) ?? 0,
              protein: _num(data['food_protein']) ?? 0,
              carbs: _num(data['food_carbs']) ?? 0,
              fat: _num(data['food_fat']) ?? 0,
            ),
          );
    }

    final summaries = <DaySummary>[];
    for (var i = 0; i < days; i++) {
      final day = BalanceService.addDays(start, i);
      final list = byDay[BalanceService.dateKey(day)] ?? <CardTransaction>[];
      list.sort((a, b) => b.time.compareTo(a.time));
      summaries.add(DaySummary(day, list));
    }

    final userData = userDoc?.data();
    return Statement(
      dailyBudget:
          userData == null ? null : BalanceService.calorieGoalFrom(userData),
      days: summaries,
    );
  }
}
