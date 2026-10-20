// Tests for the suggested budget under the limit box ("Lately you have
// about 900 kcal a week. Try 810").

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/budget_service.dart';
import 'package:namer_app/services/spend_category.dart';
import 'package:namer_app/services/statement_service.dart';

CardTransaction tx(String name, double kcal, {String meal = 'Dinner'}) =>
    CardTransaction(
      id: name,
      description: name,
      portion: '',
      category: meal,
      time: DateTime(2026, 10, 1, 19),
      calories: kcal,
      protein: 0,
      carbs: 0,
      fat: 0,
    );

DaySummary day(int d, List<CardTransaction> txs) =>
    DaySummary(DateTime(2026, 10, d), txs);

void main() {
  const alcohol = Budget(BudgetKind.category, 'alcohol', 0);
  const dinner = Budget(BudgetKind.meal, 'Dinner', 0);

  test('a weekly usual from logged days only', () {
    final days = [
      for (var d = 1; d <= 14; d++)
        day(d, [
          tx('Tofu stir fry', 500),
          if (d % 7 == 5) tx('2 pints', 400), // one night a week
        ]),
      // Days with nothing logged don't drag the average down.
      for (var d = 15; d <= 28; d++) day(d, const []),
    ];
    expect(BudgetService.usualFor(alcohol, days), closeTo(400, 0.01));
    expect(BudgetService.usualFor(dinner, days), closeTo(500 + 800 / 14, 0.01));
  });

  test('not enough logged days: no suggestion', () {
    final days = [for (var d = 1; d <= 4; d++) day(d, [tx('2 pints', 400)])];
    expect(BudgetService.usualFor(alcohol, days), isNull);
  });

  test('treats scale with your calorie goal; alcohol never does', () {
    expect(BudgetService.suggestedForGoal(SpendCategory.snacks, 2000), 1400);
    expect(BudgetService.suggestedForGoal(SpendCategory.snacks, 1350), 950);
    expect(BudgetService.suggestedForGoal(SpendCategory.snacks, 2800), 1950);
    expect(BudgetService.suggestedForGoal(SpendCategory.takeaway, 2000), 2100);
    expect(BudgetService.suggestedForGoal(SpendCategory.alcohol, 3000), isNull);
    expect(BudgetService.suggestedForGoal(SpendCategory.fruitVeg, 2000), isNull);
    expect(BudgetService.suggestedForGoal(SpendCategory.snacks, null), isNull);
  });

  test('the suggestion is a little under, never over', () {
    expect(BudgetService.suggestedFrom(400), 360);
    expect(BudgetService.suggestedFrom(987), 890);
    expect(BudgetService.suggestedFrom(20), isNull); // hardly any
    expect(BudgetService.suggestedFrom(null), isNull);
  });
}
