import 'package:namer_app/services/balance_service.dart';

/// The one rule for whether a day was "on budget", used everywhere (the
/// Statement, calendar, streak-adjacent stats, High scores, Challenges,
/// Wrapped, achievements and friends' days).
///
/// A little leeway: being 50 kcal over a 2,000 kcal day isn't a failure,
/// so up to [leeway] (5%) over still counts as on budget, shown as "just
/// over". Nobody's calorie count is that precise anyway.
class BudgetRule {
  BudgetRule._();

  static const leeway = 0.05;

  /// How far over [goal] a day can go and still count (5% of it).
  static double allowance(double? goal) =>
      goal == null || goal <= 0 ? 0 : goal * leeway;

  /// From what was left at the end of the day (negative = over).
  static bool onBudget(double left, double? goal) =>
      left >= -allowance(goal);

  /// Over, but within the leeway: counts as on budget.
  static bool justOver(double left, double? goal) =>
      left < 0 && onBudget(left, goal);

  /// From a `daily_logs` doc: on budget if it closed within the leeway.
  /// Null when there's no closing balance to judge.
  static bool? fromLog(Map<String, dynamic>? log) {
    final balances = log?['balances'];
    final left =
        balances is Map ? BalanceService.number(balances['calories']) : null;
    if (left == null) return null;
    final totals = log?['totals'];
    final goals = log?['goals'];
    final spent =
        totals is Map ? BalanceService.number(totals['calories']) : null;
    var goal = goals is Map ? BalanceService.number(goals['calorie_goal']) : null;
    // The day's real budget (pot top-ups included) when we can tell it.
    if (spent != null && left + spent > 0) goal = left + spent;
    return onBudget(left, goal);
  }
}
