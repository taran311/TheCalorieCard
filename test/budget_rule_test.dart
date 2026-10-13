// "On budget" has 5% leeway: 50 kcal over a 2,000 kcal day still counts.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/budget_rule.dart';
import 'package:namer_app/services/friend_activity.dart';
import 'package:namer_app/services/statement_service.dart';

void main() {
  test('up to 5% over still counts', () {
    expect(BudgetRule.allowance(2000), 100);
    expect(BudgetRule.onBudget(200, 2000), isTrue);
    expect(BudgetRule.onBudget(0, 2000), isTrue);
    expect(BudgetRule.onBudget(-50, 2000), isTrue);
    expect(BudgetRule.onBudget(-100, 2000), isTrue);
    expect(BudgetRule.onBudget(-101, 2000), isFalse);
    expect(BudgetRule.justOver(-50, 2000), isTrue);
    expect(BudgetRule.justOver(50, 2000), isFalse);
    expect(BudgetRule.justOver(-300, 2000), isFalse);
  });

  test('no goal known: no leeway', () {
    expect(BudgetRule.onBudget(-1, null), isFalse);
    expect(BudgetRule.onBudget(0, null), isTrue);
  });

  test('from a day log, using that day\'s own budget', () {
    expect(
        BudgetRule.fromLog({
          'balances': {'calories': -60},
          'totals': {'calories': 2060},
        }),
        isTrue);
    expect(
        BudgetRule.fromLog({
          'balances': {'calories': -300},
          'totals': {'calories': 2300},
        }),
        isFalse);
    expect(
        BudgetRule.fromLog({
          'balances': {'calories': -60},
          'goals': {'calorie_goal': 2000},
        }),
        isTrue);
    expect(BudgetRule.fromLog({'finished': true}), isNull);
  });

  test('a statement day just over counts, and says so', () {
    final day = DaySummary(DateTime(2026, 10, 8), const [],
        finished: true, closingBalance: -50, dayGoal: 2000);
    expect(day.onBudget(2000), isTrue);
    expect(day.justOver(2000), isTrue);
    expect(day.left(2000), -50);
    expect(day.overBy(2000), isNull);

    final over = DaySummary(DateTime(2026, 10, 7), const [],
        finished: true, closingBalance: -250, dayGoal: 2000);
    expect(over.onBudget(2000), isFalse);
    expect(over.justOver(2000), isFalse);
    expect(over.overBy(2000), 250);
  });

  test("friends' days use the same leeway", () {
    const close = FriendDay(finished: true, spent: 2080, budget: 2000);
    const over = FriendDay(finished: true, spent: 2300, budget: 2000);
    expect(close.onTrack, isTrue);
    expect(over.onTrack, isFalse);
  });
}
