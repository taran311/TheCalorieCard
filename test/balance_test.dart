// Tests for every way the calorie card balance changes: logging and
// removing food and recipes, new days, settings changes and clearing.
//
// Run with:  flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';

import 'test_helpers.dart';

const uid = TestWorld.uid;

Matcher near(num value) => closeTo(value, 0.0001);

void main() {
  late TestWorld w;

  setUp(() async {
    w = TestWorld()..install();
    await w.addProfile();
  });

  tearDown(TestWorld.uninstall);

  Future<void> logBanana({String meal = 'Brekkie'}) => FoodLog.logFoods(
        userId: uid,
        meal: meal,
        items: [
          {
            'name': 'Banana',
            'calories': 105.4,
            'protein': 1.3,
            'carbs': 27.0,
            'fat': 0.4,
            'portion': '118g',
          }
        ],
      );

  const chilli = {
    'name': 'Chilli',
    'serving_size': 'Per 1 Serving',
    'total_calories': 600,
    'total_protein': 40.0,
    'total_carbs': 50.0,
    'total_fat': 20.0,
  };

  group('Individual food', () {
    test('adding a food subtracts its calories, protein, carbs and fat',
        () async {
      await logBanana();

      final card = await w.card();
      expect(card['calories'], near(2000 - 105)); // stored rounded
      expect(card['protein_balance'], near(150 - 1.3));
      expect(card['carbs_balance'], near(200 - 27));
      expect(card['fats_balance'], near(60 - 0.4));

      final rows = await w.foodRows();
      expect(rows, hasLength(1));
      expect(rows.single['food_description'], 'Banana');
      expect(rows.single['food_calories'], 105);
      expect(rows.single['foodCategory'], 'Brekkie');
      expect(BalanceService.isToday(BalanceService.entryDate(rows.single)),
          isTrue);
    });

    test('removing a food adds back exactly what it cost', () async {
      await logBanana();
      final id = (await w.foodRows()).single['id'] as String;

      await FoodLog.remove(id, userId: uid);

      final card = await w.card();
      expect(card['calories'], near(2000));
      expect(card['protein_balance'], near(150));
      expect(card['carbs_balance'], near(200));
      expect(card['fats_balance'], near(60));
      expect(await w.foodRows(), isEmpty);
    });

    test('adding and removing many times never drifts the balance',
        () async {
      for (var i = 0; i < 25; i++) {
        await logBanana();
        final id = (await w.foodRows()).single['id'] as String;
        await FoodLog.remove(id, userId: uid);
      }
      final card = await w.card();
      expect(card['calories'], near(2000));
      expect(card['protein_balance'], near(150));
    });

    test('several foods in one go are all charged', () async {
      await FoodLog.logFoods(userId: uid, meal: 'Lunch', items: [
        {'name': 'Rice', 'calories': 200, 'protein': 4, 'carbs': 44, 'fat': 0.5},
        {'name': 'Chicken', 'calories': 165, 'protein': 31, 'carbs': 0, 'fat': 3.6},
      ]);
      final card = await w.card();
      expect(card['calories'], near(2000 - 365));
      expect(card['protein_balance'], near(150 - 35));
      expect(await w.foodRows(meal: 'Lunch'), hasLength(2));
    });

    test('two foods logged at the same moment are both charged', () async {
      await Future.wait([
        logBanana(meal: 'Brekkie'),
        logBanana(meal: 'Snacks'),
      ]);
      expect((await w.card())['calories'], near(2000 - 210));
    });

    test('negative amounts are refused and nothing changes', () async {
      await expectLater(
        FoodLog.logFoods(userId: uid, meal: 'Lunch', items: [
          {'name': 'Bad', 'calories': -500, 'protein': 0, 'carbs': 0, 'fat': 0}
        ]),
        throwsArgumentError,
      );
      expect((await w.card())['calories'], near(2000));
      expect(await w.foodRows(), isEmpty);
    });

    test('removing the same food twice only refunds once', () async {
      await logBanana();
      final id = (await w.foodRows()).single['id'] as String;
      await FoodLog.remove(id, userId: uid);
      await FoodLog.remove(id, userId: uid); // e.g. a double tap
      expect((await w.card())['calories'], near(2000));
    });

    test("you can't remove someone else's food", () async {
      final id = await w.addEntry(uid: TestWorld.otherUid, at: w.now);
      await expectLater(
          BalanceService.deleteEntry(uid, id), throwsA(isA<StateError>()));
      expect(await w.foodRows(), hasLength(1));
    });

    test('older entries with numbers saved as text still count', () async {
      await w.db.collection('user_food').add({
        'user_id': uid,
        'food_description': 'Legacy',
        'food_calories': '120',
        'food_protein': '5',
        'food_carbs': '10',
        'food_fat': '2',
        'foodCategory': 'Lunch',
        'time_added': w.now,
      });
      final totals = await BalanceService.todaysTotals(uid);
      expect(totals.calories, near(120));
      expect(totals.protein, near(5));
    });

    test('logging works before a profile exists (no crash)', () async {
      final fresh = TestWorld()..install();
      await FoodLog.logFoods(userId: 'new-user', meal: 'Lunch', items: [
        {'name': 'Toast', 'calories': 90, 'protein': 3, 'carbs': 15, 'fat': 1}
      ]);
      expect(await fresh.foodRows(), hasLength(1));
    });
  });

  group('Recipes logged to today', () {
    test('adding a recipe subtracts its totals', () async {
      await FoodLog.logRecipe(
          userId: uid,
          recipeId: 'r1',
          recipe: chilli,
          meal: 'Dinner',
          multiplier: 1);

      final card = await w.card();
      expect(card['calories'], near(1400));
      expect(card['protein_balance'], near(110));
      expect(card['carbs_balance'], near(150));
      expect(card['fats_balance'], near(40));

      final row = (await w.foodRows()).single;
      expect(row['food_description'], 'Recipe: Chilli');
      expect(row['food_portion'], 'Per 1 Serving');
      expect(row['foodCategory'], 'Dinner');
      expect(row['recipe_id'], 'r1');
      expect(row['is_recipe'], isTrue);
    });

    test('portions scale the amount charged (1.5 servings)', () async {
      await FoodLog.logRecipe(
          userId: uid,
          recipeId: 'r1',
          recipe: chilli,
          meal: 'Dinner',
          multiplier: 1.5);
      final card = await w.card();
      expect(card['calories'], near(2000 - 900));
      expect(card['protein_balance'], near(150 - 60));
      expect((await w.foodRows()).single['food_portion'], 'Per 1.5 Servings');
    });

    test('gram-based recipes scale too (225 g of a 450 g recipe)', () async {
      await FoodLog.logRecipe(
          userId: uid,
          recipeId: 'r2',
          recipe: {...chilli, 'serving_size': '450 g'},
          meal: 'Lunch',
          multiplier: 0.5);
      expect((await w.card())['calories'], near(1700));
      expect((await w.foodRows()).single['food_portion'], '225 g');
    });

    test('deleting a recipe from today adds back its totals', () async {
      await FoodLog.logRecipe(
          userId: uid,
          recipeId: 'r1',
          recipe: chilli,
          meal: 'Dinner',
          multiplier: 2);
      final id = (await w.foodRows()).single['id'] as String;

      await FoodLog.remove(id, userId: uid);

      final card = await w.card();
      expect(card['calories'], near(2000));
      expect(card['protein_balance'], near(150));
      expect(card['carbs_balance'], near(200));
      expect(card['fats_balance'], near(60));
    });

    for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
      test('a portion of $bad is refused and nothing changes', () async {
        await expectLater(
          FoodLog.logRecipe(
              userId: uid,
              recipeId: 'r1',
              recipe: chilli,
              meal: 'Dinner',
              multiplier: bad),
          throwsArgumentError,
        );
        expect((await w.card())['calories'], near(2000));
        expect(await w.foodRows(), isEmpty);
      });
    }

    test('a recipe with missing totals logs as 0 rather than crashing',
        () async {
      await FoodLog.logRecipe(
          userId: uid,
          recipeId: 'r3',
          recipe: {'name': 'Mystery'},
          meal: 'Snacks',
          multiplier: 1);
      expect((await w.card())['calories'], near(2000));
      expect(await w.foodRows(), hasLength(1));
    });
  });

  group('New day', () {
    test('first log of a new day starts from the full goal, charged once',
        () async {
      // Yesterday ended 300 over budget.
      w = TestWorld()..install();
      await w.addProfile(balanceDate: '2026-10-08', calories: -300);

      await logBanana();

      // 2000 goal - 105 banana. Yesterday's overspend doesn't carry over
      // and the banana isn't charged twice by the reset.
      expect((await w.card())['calories'], near(1895));
      expect((await w.card())['balance_date'], w.today);
    });

    test('food logged today on another device is counted by the reset',
        () async {
      w = TestWorld()..install();
      await w.addProfile(balanceDate: '2026-10-08', calories: 50);
      await w.addEntry(at: DateTime(2026, 10, 9, 8), calories: 400);

      await logBanana();

      expect((await w.card())['calories'], near(2000 - 400 - 105));
    });

    test("deleting yesterday's food doesn't change today's card", () async {
      final id = await w.addEntry(at: DateTime(2026, 10, 8, 19), calories: 500);

      await FoodLog.remove(id, userId: uid);

      expect((await w.card())['calories'], near(2000));
      expect(await w.foodRows(), isEmpty);
    });

    test('a food added at 23:59 and removed at 00:01 leaves the new day full',
        () async {
      w = TestWorld(now: DateTime(2026, 10, 9, 23, 59))..install();
      await w.addProfile();
      await logBanana();
      expect((await w.card())['calories'], near(1895));

      w.now = DateTime(2026, 10, 10, 0, 1);
      final id = (await w.foodRows()).single['id'] as String;
      await FoodLog.remove(id, userId: uid);
      await BalanceService.ensureDailyReset(uid);

      final card = await w.card();
      expect(card['calories'], near(2000));
      expect(card['balance_date'], '2026-10-10');
    });

    test('only food from today counts towards today', () async {
      await w.addEntry(at: DateTime(2026, 10, 8, 23, 59, 59), calories: 700);
      await w.addEntry(at: DateTime(2026, 10, 9, 0, 0, 0), calories: 300);
      await w.addEntry(at: DateTime(2026, 10, 10, 0, 0, 1), calories: 900);

      final totals = await BalanceService.todaysTotals(uid);
      expect(totals.calories, near(300));
    });

    test('the reset is safe to call repeatedly', () async {
      w = TestWorld()..install();
      await w.addProfile(balanceDate: '2026-10-08', calories: 10);
      expect(await BalanceService.ensureDailyReset(uid), isTrue);
      await logBanana();
      expect(await BalanceService.ensureDailyReset(uid), isFalse);
      expect((await w.card())['calories'], near(1895));
    });

    test('recipe ingredient rows never count as food eaten', () async {
      await w.db.collection('user_food').add({
        'user_id': uid,
        'food_description': 'Mince (ingredient)',
        'food_calories': 800,
        'foodCategory': BalanceService.recipeCategory,
        'recipe_id': 'r1',
        'time_added': w.now,
      });
      expect((await BalanceService.todaysTotals(uid)).calories, near(0));
      expect(await BalanceService.ensureDailyReset(uid, force: true), isTrue);
      expect((await w.card())['calories'], near(2000));
    });
  });

  group('Settings', () {
    test("new goals replace today's card, minus food already eaten",
        () async {
      await FoodLog.logFoods(userId: uid, meal: 'Lunch', items: [
        {'name': 'Lunch', 'calories': 500, 'protein': 30, 'carbs': 40, 'fat': 10}
      ]);

      await BalanceService.applyGoals(
        uid,
        goals: const Macros(calories: 2500, protein: 180, carbs: 250, fat: 70),
        extra: {'weight': 80, 'goal_source': 'manual'},
      );

      final card = await w.card();
      expect(card['calorie_goal'], near(2500));
      expect(card['protein_goal'], near(180));
      expect(card['calories'], near(2000)); // 2500 - 500
      expect(card['protein_balance'], near(150)); // 180 - 30
      expect(card['carbs_balance'], near(210));
      expect(card['fats_balance'], near(60));
      expect(card['balance_date'], w.today);
      expect(card['weight'], 80);
      expect(card['goal_source'], 'manual');
    });

    test('saving the same goals again leaves the balance alone', () async {
      await logBanana();
      final before = await w.card();
      await BalanceService.applyGoals(uid, goals: TestWorld.goals);
      final after = await w.card();
      expect(after['calories'], near(before['calories'] as num));
      expect(after['protein_balance'], near(before['protein_balance'] as num));
    });

    test('a goal below what you have eaten puts the card over budget',
        () async {
      await w.addEntry(at: w.now, calories: 800);
      await BalanceService.applyGoals(uid,
          goals: const Macros(calories: 600, protein: 50, carbs: 50, fat: 20));
      expect((await w.card())['calories'], near(-200));
    });

    test("yesterday's food doesn't affect the new balance", () async {
      await w.addEntry(at: DateTime(2026, 10, 8, 20), calories: 900);
      await BalanceService.applyGoals(uid,
          goals: const Macros(calories: 1800, protein: 120, carbs: 180, fat: 50));
      expect((await w.card())['calories'], near(1800));
    });

    for (final bad in [0.0, -100.0, double.nan]) {
      test('a calorie goal of $bad is refused', () async {
        await expectLater(
          BalanceService.applyGoals(uid,
              goals: Macros(calories: bad, protein: 1, carbs: 1, fat: 1)),
          throwsArgumentError,
        );
        expect((await w.card())['calorie_goal'], near(2000));
      });
    }

    test("clear today removes today's food only and refills the card",
        () async {
      await logBanana();
      await FoodLog.logRecipe(
          userId: uid,
          recipeId: 'r1',
          recipe: chilli,
          meal: 'Dinner',
          multiplier: 1);
      await w.addEntry(at: DateTime(2026, 10, 8, 12), description: 'Yesterday');
      await w.db.collection('user_food').add({
        'user_id': uid,
        'food_description': 'Ingredient',
        'food_calories': 300,
        'foodCategory': BalanceService.recipeCategory,
        'recipe_id': 'r1',
        'time_added': w.now,
      });

      final removed = await BalanceService.clearToday(uid);

      expect(removed, 2);
      final left = (await w.foodRows()).map((r) => r['food_description']);
      expect(left, containsAll(['Yesterday', 'Ingredient']));
      expect(left, hasLength(2));
      final card = await w.card();
      expect(card['calories'], near(2000));
      expect(card['protein_balance'], near(150));
    });
  });

  group('Goals', () {
    test('older profiles without calorie_goal use their macros', () {
      expect(
        BalanceService.calorieGoalFrom(
            {'protein_goal': 150, 'carbs_goal': 200, 'fats_goal': 60}),
        near(150 * 4 + 200 * 4 + 60 * 9),
      );
      expect(BalanceService.calorieGoalFrom({}), isNull);
      expect(BalanceService.calorieGoalFrom({'calorie_goal': 0}), isNull);
    });
  });
}
