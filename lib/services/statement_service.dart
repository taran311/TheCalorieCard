import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/spend_category.dart';

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

  /// Logged as a whole recipe (counts as home cooked).
  final bool isRecipe;

  /// The numbers are the person's own: they set the calories themselves
  /// (added by hand, or fixed an estimate), so typing the same food again
  /// uses these rather than a fresh lookup.
  final bool ownNumbers;

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
    this.isRecipe = false,
    this.ownNumbers = false,
  });

  /// Its "where it went" category (see [SpendCategory]).
  SpendCategory get spendCategory => isRecipe
      ? SpendCategory.homeCooked
      : SpendCategory.fromDescription(description);
}

/// Totals for one calendar day.
class DaySummary {
  final DateTime day;
  final List<CardTransaction> transactions;

  /// From the day's `daily_logs` snapshot, when there is one: whether you
  /// finished (closed) the day, what was left on the card when you did,
  /// and the calorie goal that day.
  final bool finished;
  final double? closingBalance;
  final double? dayGoal;

  /// A planned rest day (`daily_logs.rest_day`), shown as 🏖️ on the calendar.
  final bool restDay;

  DaySummary(this.day, this.transactions,
      {this.finished = false,
      this.closingBalance,
      this.dayGoal,
      this.restDay = false});

  double get calories => transactions.fold(0, (s, t) => s + t.calories);
  double get protein => transactions.fold(0, (s, t) => s + t.protein);
  double get carbs => transactions.fold(0, (s, t) => s + t.carbs);
  double get fat => transactions.fold(0, (s, t) => s + t.fat);

  /// The day's budget: its own goal if saved, else [fallback].
  double? budget(double? fallback) => dayGoal ?? fallback;

  /// The one definition of "on budget", shared with High scores and
  /// Challenges: a finished day is on budget if the card closed in credit
  /// (so pot top-ups count). Otherwise it's spending against that day's
  /// goal (or [fallback], today's goal). Null when there's nothing to judge.
  bool? onBudget(double? fallback) {
    final closing = closingBalance;
    if (finished && closing != null) return closing >= 0;
    if (transactions.isEmpty) return null;
    final b = budget(fallback);
    if (b == null) return null;
    return calories <= b;
  }

  /// How far over budget the day went (a positive number), or null when it
  /// wasn't over. Uses the same rule as [onBudget]: a finished day by what
  /// the card closed on, otherwise spending against the day's budget.
  double? overBy(double? fallback) {
    if (onBudget(fallback) != false) return null;
    final closing = closingBalance;
    if (finished && closing != null) return -closing;
    final b = budget(fallback);
    return b == null ? null : calories - b;
  }
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

  /// Days on budget ([DaySummary.onBudget]). Today only counts once you've
  /// finished it.
  int get daysUnderBudget {
    final today = BalanceService.dateKey(BalanceService.now());
    return days
        .where((d) =>
            (d.finished || BalanceService.dateKey(d.day) != today) &&
            d.onBudget(dailyBudget) == true)
        .length;
  }

  double get averageCalories {
    final logged = days.where((d) => d.transactions.isNotEmpty).toList();
    if (logged.isEmpty) return 0;
    return logged.fold<double>(0, (s, d) => s + d.calories) / logged.length;
  }

  /// Foods whose name contains [query] (ignoring case), like a bank's
  /// transaction search. Days with a match, newest first, each holding only
  /// its matching foods (newest first). Empty for a blank query.
  List<DaySummary> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final d in days.reversed)
        if (d.transactions
            .any((t) => t.description.toLowerCase().contains(q)))
          DaySummary(
            d.day,
            [
              for (final t in d.transactions)
                if (t.description.toLowerCase().contains(q)) t
            ],
            finished: d.finished,
            closingBalance: d.closingBalance,
            dayGoal: d.dayGoal,
            restDay: d.restDay,
          ),
    ];
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
  ///
  /// Each day's `daily_logs` snapshot is read too (unless [withLogs] is
  /// false), so finished days are judged the way High scores judge them.
  static Future<Statement> load(String userId,
      {int days = 7, bool withLogs = true}) {
    final today = BalanceService.startOfDay(BalanceService.now());
    return loadRange(userId, BalanceService.addDays(today, -(days - 1)),
        BalanceService.addDays(today, 1),
        withLogs: withLogs);
  }

  /// Builds a statement for the calendar days from [first] up to (not
  /// including) [end], e.g. one month for the calendar view. Both are
  /// treated as dates (the time of day is ignored).
  static Future<Statement> loadRange(String userId, DateTime first,
      DateTime end,
      {bool withLogs = true}) async {
    final start = BalanceService.startOfDay(first);
    final stop = BalanceService.startOfDay(end);
    final dayList = <DateTime>[];
    for (var d = start; d.isBefore(stop); d = BalanceService.addDays(d, 1)) {
      dayList.add(d);
    }
    // An empty range just gives an empty statement.
    final rangeEnd =
        dayList.isEmpty ? start : BalanceService.addDays(dayList.last, 1);

    // Only the days on the statement are fetched, not the whole history.
    final results = await Future.wait<Object?>([
      BalanceService.entriesBetween(userId, start, rangeEnd),
      BalanceService.userDataDoc(userId),
      withLogs ? _dailyLogs(userId, dayList) : Future.value(null),
    ]);

    final foodDocs =
        results[0] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
    final userDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>?;
    final logs = (results[2] as Map<String, Map<String, dynamic>>?) ??
        const <String, Map<String, dynamic>>{};

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
              category: FoodLog.displayMeal((data['foodCategory'] ?? '').toString()),
              time: time,
              calories: _num(data['food_calories']) ?? 0,
              protein: _num(data['food_protein']) ?? 0,
              carbs: _num(data['food_carbs']) ?? 0,
              fat: _num(data['food_fat']) ?? 0,
              isRecipe: data['is_recipe'] == true,
              ownNumbers: data['food_edited'] == true ||
                  data['food_source'] == 'manual' ||
                  data['food_source'] == 'yours',
            ),
          );
    }

    final summaries = <DaySummary>[];
    for (final day in dayList) {
      final key = BalanceService.dateKey(day);
      final list = byDay[key] ?? <CardTransaction>[];
      list.sort((a, b) => b.time.compareTo(a.time));
      final log = logs[key];
      final balances = log?['balances'];
      final goals = log?['goals'];
      final goal = goals is Map ? _num(goals['calorie_goal']) : null;
      summaries.add(DaySummary(
        day,
        list,
        finished: log?['finished'] == true,
        closingBalance:
            balances is Map ? _num(balances['calories']) : null,
        dayGoal: goal != null && goal > 0 ? goal : null,
        restDay: log?['rest_day'] == true,
      ));
    }

    final userData = userDoc?.data();
    return Statement(
      dailyBudget:
          userData == null ? null : BalanceService.calorieGoalFrom(userData),
      days: summaries,
    );
  }

  /// `daily_logs` data by date key, for the days that have one. History
  /// that can't be read just means falling back to the food totals.
  static Future<Map<String, Map<String, dynamic>>> _dailyLogs(
      String userId, List<DateTime> days) async {
    try {
      final docs = await Future.wait(days.map((d) => BalanceService.db
          .collection('daily_logs')
          .doc('${userId}_${BalanceService.dateKey(d)}')
          .get()));
      return {
        for (var i = 0; i < days.length; i++)
          if (docs[i].data() != null)
            BalanceService.dateKey(days[i]): docs[i].data()!
      };
    } catch (_) {
      return const {};
    }
  }

  /// Your last 7 full days (up to yesterday) against the 7 before.
  static Future<WeekDigest> weekDigest(String uid) async {
    final s = await load(uid, days: 15);
    // s.days: 14 full days, oldest first, then today (left out: it isn't
    // over yet, so it would drag the averages down).
    final full = s.days.sublist(0, 14);
    return WeekDigest(
      thisWeek: WeekNumbers.from(full.sublist(7), s.dailyBudget),
      lastWeek: WeekNumbers.from(full.sublist(0, 7), s.dailyBudget),
      start: full[7].day,
    );
  }
}

/// The headline numbers for one run of days.
class WeekNumbers {
  final int daysLogged;
  final int daysOnBudget;
  final int finishedDays;

  /// Per day with food logged.
  final double averageCalories;
  final double averageProtein;

  const WeekNumbers({
    required this.daysLogged,
    required this.daysOnBudget,
    required this.finishedDays,
    required this.averageCalories,
    required this.averageProtein,
  });

  factory WeekNumbers.from(List<DaySummary> days, double? fallbackBudget) {
    final logged = days.where((d) => d.transactions.isNotEmpty).toList();
    double avg(double Function(DaySummary) f) => logged.isEmpty
        ? 0.0
        : logged.fold<double>(0, (s, d) => s + f(d)) / logged.length;
    return WeekNumbers(
      daysLogged: logged.length,
      daysOnBudget:
          days.where((d) => d.onBudget(fallbackBudget) == true).length,
      finishedDays: days.where((d) => d.finished).length,
      averageCalories: avg((d) => d.calories),
      averageProtein: avg((d) => d.protein),
    );
  }
}

/// "Your week": the last 7 full days compared with the 7 before.
class WeekDigest {
  final WeekNumbers thisWeek;
  final WeekNumbers lastWeek;

  /// First day of [thisWeek].
  final DateTime start;

  const WeekDigest({
    required this.thisWeek,
    required this.lastWeek,
    required this.start,
  });

  bool get isEmpty => thisWeek.daysLogged == 0 && thisWeek.finishedDays == 0;

  /// "▲ 2", "▼ 120", or "same" (rounded to whole numbers).
  static String change(num now, num before, {String unit = ''}) {
    final diff = (now - before).round();
    if (diff == 0) return 'same';
    return '${diff > 0 ? '▲' : '▼'} ${diff.abs()}$unit';
  }

  /// Plain text for sharing in chat.
  String toShareText() {
    final t = thisWeek, l = lastWeek;
    String days(int n) => n == 1 ? '1 day' : '$n days';
    return [
      '📈 My week on The Calorie Card',
      '✅ ${days(t.daysOnBudget)} on budget '
          '(${change(t.daysOnBudget, l.daysOnBudget)} on the week before)',
      '🏁 ${days(t.finishedDays)} finished '
          '(${change(t.finishedDays, l.finishedDays)})',
      '🍽️ Avg ${t.averageCalories.round()} kcal a day '
          '(${change(t.averageCalories, l.averageCalories)})',
      '💪 Avg ${t.averageProtein.round()}g protein a day '
          '(${change(t.averageProtein, l.averageProtein, unit: 'g')})',
    ].join('\n');
  }
}
