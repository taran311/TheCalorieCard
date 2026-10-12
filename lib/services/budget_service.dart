import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/spend_category.dart';
import 'package:namer_app/services/statement_service.dart';

/// What a budget limits: one meal (per day) or one spending category
/// (per week), like the category budgets in a banking app.
enum BudgetKind { meal, category }

/// One optional limit, e.g. Snacks 300 kcal a day, or Snacks & sweets
/// 1,000 kcal a week. These are guides only: they never change the card.
class Budget {
  final BudgetKind kind;

  /// The meal name ('Snacks') or the [SpendCategory] name ('snacks').
  final String key;
  final double limit;

  const Budget(this.kind, this.key, this.limit);

  /// Category budgets run Monday to Sunday: a treat or a takeaway isn't an
  /// every-day thing, so a weekly limit is fairer. Meals reset daily.
  bool get weekly => kind == BudgetKind.category;

  SpendCategory? get category {
    if (kind != BudgetKind.category) return null;
    for (final c in SpendCategory.values) {
      if (c.name == key) return c;
    }
    return null;
  }

  /// "Snacks" or "Snacks & sweets".
  String get name => category?.label ?? key;

  /// "today" or "this week".
  String get period => weekly ? 'this week' : 'today';

  /// "300 kcal a day" or "1,000 kcal a week".
  String get limitLabel =>
      '${BudgetService.kcal(limit)} kcal a ${weekly ? 'week' : 'day'}';
}

/// The budgets saved on the user's `user_data` doc as
/// `budgets: {meal: {Snacks: 300}, category: {snacks: 1000}}`.
class BudgetSettings {
  /// Meal name → kcal a day.
  final Map<String, double> meal;

  /// [SpendCategory] name → kcal a week.
  final Map<String, double> category;

  const BudgetSettings({this.meal = const {}, this.category = const {}});

  static const empty = BudgetSettings();

  /// Reads `budgets` from a `user_data` doc. Anything unreadable, zero or
  /// negative is ignored, and unknown categories are dropped.
  factory BudgetSettings.fromProfile(Map<String, dynamic>? data) {
    final raw = data?['budgets'];
    if (raw is! Map) return empty;
    Map<String, double> read(Object? m, bool Function(String) known) {
      final out = <String, double>{};
      if (m is! Map) return out;
      for (final e in m.entries) {
        final key = '${e.key}';
        final v = BalanceService.number(e.value);
        if (v != null && v > 0 && known(key)) out[key] = v;
      }
      return out;
    }

    return BudgetSettings(
      meal: read(raw['meal'], (k) => BudgetService.mealNames.contains(k)),
      category: read(raw['category'],
          (k) => SpendCategory.values.any((c) => c.name == k)),
    );
  }

  bool get isEmpty => meal.isEmpty && category.isEmpty;

  /// Every budget: meals in the usual order, then categories.
  List<Budget> get all => [
        for (final m in BudgetService.mealNames)
          if (meal[m] != null) Budget(BudgetKind.meal, m, meal[m]!),
        for (final c in SpendCategory.values)
          if (category[c.name] != null)
            Budget(BudgetKind.category, c.name, category[c.name]!),
      ];

  double? mealLimit(String m) => meal[m];
  double? categoryLimit(SpendCategory c) => category[c.name];

  /// A copy with [m]'s daily limit set, or removed when [limit] is null.
  BudgetSettings withMeal(String m, double? limit) {
    final next = Map<String, double>.from(meal);
    if (limit == null || limit <= 0) {
      next.remove(m);
    } else {
      next[m] = limit;
    }
    return BudgetSettings(meal: next, category: category);
  }

  /// A copy with [c]'s weekly limit set, or removed when [limit] is null.
  BudgetSettings withCategory(SpendCategory c, double? limit) {
    final next = Map<String, double>.from(category);
    if (limit == null || limit <= 0) {
      next.remove(c.name);
    } else {
      next[c.name] = limit;
    }
    return BudgetSettings(meal: meal, category: next);
  }

  Map<String, dynamic> toMap() => {
        'meal': {for (final e in meal.entries) e.key: e.value.round()},
        'category': {for (final e in category.entries) e.key: e.value.round()},
      };
}

/// How much of a budget has gone in its current period.
class BudgetProgress {
  final Budget budget;
  final double used;

  /// The day (`2026-10-09`) or week (its Monday) this covers. Alerts are
  /// remembered per period, so each shows at most once a day / week.
  final String periodKey;

  const BudgetProgress(this.budget, this.used, this.periodKey);

  double get fraction => budget.limit <= 0 ? 0 : used / budget.limit;

  /// Can go negative when over.
  double get left => budget.limit - used;

  bool get over => used > budget.limit;

  /// 100 once the budget is used up, 80 from 80%, else null.
  int? get alertLevel {
    if (budget.limit <= 0) return null;
    if (fraction >= 1) return 100;
    if (fraction >= 0.8) return 80;
    return null;
  }

  /// "Snacks today: 240 of 300 kcal".
  String get summary => '${budget.name} ${budget.period}: '
      '${BudgetService.kcal(used)} of ${BudgetService.kcal(budget.limit)} kcal';

  /// "60 kcal left" or "20 kcal over".
  String get leftLabel => over
      ? '${BudgetService.kcal(-left)} kcal over'
      : '${BudgetService.kcal(left)} kcal left';

  /// Identifies one alert (budget, period and level) for "don't show this
  /// again": `meal|Snacks|2026-10-09|80`.
  String alertId(int level) =>
      '${budget.kind.name}|${budget.key}|$periodKey|$level';

  /// The inbox message. Gentle on purpose: a budget is a guide, not a rule.
  String alertMessage(int level) {
    if (level >= 100) {
      return budget.weekly
          ? "You've used your ${budget.name} budget this week. "
              'It starts again on Monday.'
          : "You've used your ${budget.name} budget for today. "
              'It starts again tomorrow.';
    }
    // Rounded down, and never "100%" before it's actually used up.
    final pct = (used * 100 / budget.limit).floor().clamp(80, 99);
    return "You've used $pct% of your ${budget.name} budget ${budget.period}.";
  }
}

class BudgetService {
  BudgetService._();

  /// The meals a budget can be set for (as saved now: Breakfast, Lunch,
  /// Dinner, Snacks).
  static List<String> get mealNames => FoodLog.meals;

  /// "1,000": whole kcal with thousands separators.
  static String kcal(double v) {
    final n = v.isFinite ? v.round() : 0;
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}$buf';
  }

  /// True if [tx] counts towards [b].
  static bool counts(Budget b, CardTransaction tx) => switch (b.kind) {
        BudgetKind.meal =>
          FoodLog.displayMeal(tx.category).trim().toLowerCase() ==
              b.key.toLowerCase(),
        BudgetKind.category => tx.spendCategory.name == b.key,
      };

  /// Progress on every budget in [settings] at [now], from [foods] (any
  /// range that covers this week; others are ignored). Pure, so it's
  /// tested without Firestore.
  static List<BudgetProgress> progress(BudgetSettings settings,
      Iterable<CardTransaction> foods, DateTime now) {
    final today = BalanceService.dateKey(now);
    final week = BalanceService.weekKey(now);
    final list = foods.toList();
    return [
      for (final b in settings.all)
        BudgetProgress(
          b,
          list
              .where((tx) =>
                  (b.weekly
                      ? BalanceService.weekKey(tx.time) == week
                      : BalanceService.dateKey(tx.time) == today) &&
                  counts(b, tx))
              .fold<double>(
                  0, (s, tx) => s + (tx.calories > 0 ? tx.calories : 0)),
          b.weekly ? week : today,
        ),
    ];
  }

  /// The alerts to show at [now]: the highest level each budget has
  /// reached this period, unless that one was dismissed ([seen] holds
  /// [BudgetProgress.alertId]s). Figures from an earlier day or week are
  /// ignored, so nothing stale shows after midnight.
  static List<({BudgetProgress progress, int level})> alerts(
      List<BudgetProgress> progress, Set<String> seen, DateTime now) {
    final current = {BalanceService.dateKey(now), BalanceService.weekKey(now)};
    return [
      for (final p in progress)
        if (p.alertLevel != null &&
            current.contains(p.periodKey) &&
            !seen.contains(p.alertId(p.alertLevel!)))
          (progress: p, level: p.alertLevel!),
    ];
  }

  /// Dismissed alert ids still worth remembering at [now]: ones for today
  /// or this week. Older ones can never show again, so they're dropped.
  static List<String> pruneSeen(Iterable<String> seen, DateTime now) {
    final today = BalanceService.dateKey(now);
    final week = BalanceService.weekKey(now);
    return [
      for (final id in seen)
        if (id.split('|').length == 4 &&
            (id.split('|')[2] == today || id.split('|')[2] == week))
          id
    ];
  }

  /// The saved budgets (empty before onboarding or when none are set).
  static Future<BudgetSettings> load(String userId) async {
    final doc = await BalanceService.userDataDoc(userId);
    return BudgetSettings.fromProfile(doc?.data());
  }

  /// Saves [settings] in place of the old budgets.
  static Future<void> save(String userId, BudgetSettings settings) async {
    final doc = await BalanceService.userDataDoc(userId);
    if (doc == null) throw StateError('No profile to update');
    // Cleared first, then written, so a removed budget is really gone
    // (one atomic batch, so the budgets are never seen half-saved).
    final batch = BalanceService.db.batch();
    batch.update(doc.reference, {'budgets': FieldValue.delete()});
    batch.update(doc.reference, {'budgets': settings.toMap()});
    await batch.commit();
  }

  /// Progress on [settings] right now: reads this week's food (Monday to
  /// today). No reads at all when there are no budgets.
  static Future<List<BudgetProgress>> loadProgress(
      String userId, BudgetSettings settings) async {
    if (settings.isEmpty) return const [];
    final now = BalanceService.now();
    final today = BalanceService.startOfDay(now);
    final monday = BalanceService.addDays(today, -(today.weekday - 1));
    final statement = await StatementService.loadRange(
        userId, monday, BalanceService.addDays(today, 1),
        withLogs: false);
    return progress(settings, statement.recent, now);
  }
}
