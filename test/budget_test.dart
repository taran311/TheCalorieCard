// Tests for meal and category budgets: reading/saving them on the profile,
// the progress maths, and when the gentle 80% / 100% heads-ups show.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/budget_service.dart';
import 'package:namer_app/services/spend_category.dart';
import 'package:namer_app/services/statement_service.dart';

import 'test_helpers.dart';

const uid = TestWorld.uid;

CardTransaction food(String description, double kcal, DateTime at,
        {String meal = 'Lunch', bool isRecipe = false}) =>
    CardTransaction(
      id: '$description-$at',
      description: description,
      portion: '',
      category: meal,
      time: at,
      calories: kcal,
      protein: 0,
      carbs: 0,
      fat: 0,
      isRecipe: isRecipe,
    );

void main() {
  // Friday 9 Oct 2026, noon (the TestWorld clock). The week began Mon 5th.
  final now = DateTime(2026, 10, 9, 12);

  group('Budget settings', () {
    test('read from the profile, ignoring junk and unknown keys', () {
      final s = BudgetSettings.fromProfile({
        'budgets': {
          'meal': {'Snacks': 300, 'Lunch': '600', 'Elevenses': 200, 'Dinner': 0},
          'category': {'snacks': 1000, 'treats': 500, 'drinks': -5},
        },
      });
      expect(s.meal, {'Snacks': 300, 'Lunch': 600});
      expect(s.category, {'snacks': 1000});
      expect(s.all.map((b) => b.key), ['Lunch', 'Snacks', 'snacks']);
      expect(BudgetSettings.fromProfile(null).isEmpty, isTrue);
      expect(BudgetSettings.fromProfile({'budgets': 'x'}).isEmpty, isTrue);
    });

    test('meals are daily, categories weekly, with readable names', () {
      const meal = Budget(BudgetKind.meal, 'Snacks', 300);
      const cat = Budget(BudgetKind.category, 'takeaway', 1500);
      expect(meal.weekly, isFalse);
      expect(meal.name, 'Snacks');
      expect(meal.limitLabel, '300 kcal a day');
      expect(cat.weekly, isTrue);
      expect(cat.category, SpendCategory.takeaway);
      expect(cat.name, 'Takeaway & eating out');
      expect(cat.limitLabel, '1,500 kcal a week');
    });

    test('set and remove', () {
      var s = BudgetSettings.empty
          .withMeal('Snacks', 300)
          .withCategory(SpendCategory.drinks, 700);
      expect(s.toMap(), {
        'meal': {'Snacks': 300},
        'category': {'drinks': 700},
      });
      s = s.withMeal('Snacks', null).withCategory(SpendCategory.drinks, 0);
      expect(s.isEmpty, isTrue);
    });
  });

  group('Budget progress', () {
    test('meal budgets count today only, category budgets this week', () {
      final settings = BudgetSettings.empty
          .withMeal('Snacks', 300)
          .withCategory(SpendCategory.snacks, 1000);
      final foods = [
        food('Chocolate bar', 240, DateTime(2026, 10, 9, 10), meal: 'Snacks'),
        food('Apple', 50, DateTime(2026, 10, 9, 11), meal: 'Snacks'),
        food('Crisps', 180, DateTime(2026, 10, 8, 15), meal: 'Snacks'),
        food('Cake', 400, DateTime(2026, 10, 5, 15), meal: 'Lunch'),
        // Last week (Sunday 4th): doesn't count.
        food('Cookie', 500, DateTime(2026, 10, 4, 15), meal: 'Snacks'),
        // A recipe is home cooked, whatever its name.
        food('Chocolate cake', 300, DateTime(2026, 10, 9, 9),
            meal: 'Snacks', isRecipe: true),
      ];

      final p = BudgetService.progress(settings, foods, now);

      final snacksToday = p.firstWhere((x) => x.budget.kind == BudgetKind.meal);
      expect(snacksToday.used, 240 + 50 + 300);
      expect(snacksToday.periodKey, '2026-10-09');
      expect(snacksToday.summary, 'Snacks today: 590 of 300 kcal');
      expect(snacksToday.over, isTrue);
      expect(snacksToday.leftLabel, '290 kcal over');

      final sweetsWeek =
          p.firstWhere((x) => x.budget.kind == BudgetKind.category);
      expect(sweetsWeek.used, 240 + 180 + 400); // not the apple or recipe
      expect(sweetsWeek.periodKey, '2026-10-05');
      expect(sweetsWeek.summary,
          'Snacks & sweets this week: 820 of 1,000 kcal');
      expect(sweetsWeek.leftLabel, '180 kcal left');
    });

    test('old "Brekkie" entries count as Breakfast', () {
      final settings = BudgetSettings.empty.withMeal('Breakfast', 400);
      final p = BudgetService.progress(settings,
          [food('Toast', 200, DateTime(2026, 10, 9, 8), meal: 'Brekkie')], now);
      expect(p.single.used, 200);
    });

    test('alert levels and messages', () {
      const b = Budget(BudgetKind.category, 'snacks', 1000);
      expect(BudgetProgress(b, 790, 'w').alertLevel, isNull);
      expect(BudgetProgress(b, 800, 'w').alertLevel, 80);
      expect(BudgetProgress(b, 999, 'w').alertLevel, 80);
      expect(BudgetProgress(b, 1000, 'w').alertLevel, 100);
      expect(BudgetProgress(b, 1300, 'w').alertLevel, 100);
      expect(BudgetProgress(b, 860, 'w').alertMessage(80),
          "You've used 86% of your Snacks & sweets budget this week.");
      expect(BudgetProgress(b, 999, 'w').alertMessage(80),
          contains('99%'));
      expect(BudgetProgress(b, 1000, 'w').alertMessage(100),
          contains('starts again on Monday'));
      const meal = Budget(BudgetKind.meal, 'Snacks', 300);
      expect(BudgetProgress(meal, 300, 'd').alertMessage(100),
          contains('starts again tomorrow'));
    });

    test('each alert shows once per period, and stale ones never', () {
      const b = Budget(BudgetKind.meal, 'Snacks', 300);
      final today = BudgetProgress(b, 250, '2026-10-09');
      final yesterday = BudgetProgress(b, 290, '2026-10-08');

      var shown = BudgetService.alerts([today, yesterday], {}, now);
      expect(shown.single.level, 80);
      expect(shown.single.progress.periodKey, '2026-10-09');

      final seen = {today.alertId(80)};
      expect(BudgetService.alerts([today], seen, now), isEmpty);

      // Reaching 100% is a new alert, even after dismissing 80%.
      final full = BudgetProgress(b, 320, '2026-10-09');
      shown = BudgetService.alerts([full], seen, now);
      expect(shown.single.level, 100);

      // Only today's and this week's dismissals are kept.
      expect(
        BudgetService.pruneSeen([
          'meal|Snacks|2026-10-09|80',
          'category|snacks|2026-10-05|100',
          'meal|Snacks|2026-10-08|80',
          'junk',
        ], now),
        ['meal|Snacks|2026-10-09|80', 'category|snacks|2026-10-05|100'],
      );
    });
  });

  group('Budgets in Firestore', () {
    late TestWorld w;

    setUp(() async {
      w = TestWorld()..install();
      await w.addProfile();
    });

    tearDown(TestWorld.uninstall);

    test('saved on the profile and read back', () async {
      expect((await BudgetService.load(uid)).isEmpty, isTrue);

      await BudgetService.save(
          uid,
          BudgetSettings.empty
              .withMeal('Snacks', 300)
              .withCategory(SpendCategory.takeaway, 1500));
      expect((await w.card())['budgets'], {
        'meal': {'Snacks': 300},
        'category': {'takeaway': 1500},
      });

      // Removing one replaces the whole map, so it's really gone.
      final s = await BudgetService.load(uid);
      await BudgetService.save(uid, s.withMeal('Snacks', null));
      expect((await BudgetService.load(uid)).all.map((b) => b.key),
          ['takeaway']);
    });

    test('progress reads only this week, and nothing without budgets',
        () async {
      await w.addEntry(
          at: DateTime(2026, 10, 9, 10), calories: 250, meal: 'Snacks',
          description: 'Crisps');
      await w.addEntry(
          at: DateTime(2026, 10, 6, 19), calories: 900, meal: 'Dinner',
          description: "McDonald's McPlant meal");
      await w.addEntry(
          at: DateTime(2026, 10, 3, 19), calories: 1200, meal: 'Dinner',
          description: "Domino's vegan pizza"); // last week

      expect(await BudgetService.loadProgress(uid, BudgetSettings.empty),
          isEmpty);

      final p = await BudgetService.loadProgress(
          uid,
          BudgetSettings.empty
              .withMeal('Snacks', 300)
              .withCategory(SpendCategory.takeaway, 1000));
      expect(p.map((x) => x.used), [250, 900]);
      expect(p.map((x) => x.alertLevel), [80, 80]);
    });
  });
}
