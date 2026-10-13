// Tests for typing foods into Add food (splitting a list, decimal commas)
// and for re-adding foods from your history.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/food_history.dart';
import 'package:namer_app/services/food_resolver.dart';
import 'package:namer_app/services/meal_time.dart';
import 'package:namer_app/services/statement_service.dart';

CardTransaction tx(
  String description, {
  String portion = '',
  String meal = 'Breakfast',
  required DateTime at,
  double calories = 100,
  bool ownNumbers = false,
}) =>
    CardTransaction(
      id: '$description-$at',
      ownNumbers: ownNumbers,
      description: description,
      portion: portion,
      category: meal,
      time: at,
      calories: calories,
      protein: 1,
      carbs: 2,
      fat: 3,
    );

void main() {
  group('splitItems', () {
    test('commas, semicolons and new lines separate foods', () {
      expect(FoodResolver.splitItems('2 crumpets, toast;coffee\n banana '),
          ['2 crumpets', 'toast', 'coffee', 'banana']);
      expect(FoodResolver.splitItems(' , ;\n'), isEmpty);
    });

    test('a comma between two digits is a decimal comma', () {
      expect(FoodResolver.splitItems('1,5 kg potatoes, 2 crumpets'),
          ['1,5 kg potatoes', '2 crumpets']);
      expect(FoodResolver.splitItems('rice 1,5'), ['rice 1,5']);
      // After a number but followed by a space or letter: a separator.
      expect(FoodResolver.splitItems('crumpets 2, toast'), ['crumpets 2', 'toast']);
      expect(FoodResolver.splitItems('crumpets 2,toast'), ['crumpets 2', 'toast']);
      expect(FoodResolver.splitItems('crumpets,2 toast'), ['crumpets', '2 toast']);
    });
  });

  group('takeFinished (while typing)', () {
    test('keeps the food still being typed exactly as typed', () {
      final t = FoodResolver.takeFinished('2 crumpets, toa');
      expect(t.done, ['2 crumpets']);
      expect(t.rest, 'toa');
      final none = FoodResolver.takeFinished('banana');
      expect(none.done, isEmpty);
      expect(none.rest, 'banana');
    });

    test('a comma straight after a number waits for the next character', () {
      final waiting = FoodResolver.takeFinished('rice 1,');
      expect(waiting.done, isEmpty);
      expect(waiting.rest, 'rice 1,');
      final decimal = FoodResolver.takeFinished('rice 1,5');
      expect(decimal.done, isEmpty);
      expect(decimal.rest, 'rice 1,5');
      final separator = FoodResolver.takeFinished('rice 1, ');
      expect(separator.done, ['rice 1']);
      expect(separator.rest, '');
    });

    test('a trailing separator finishes the food', () {
      final t = FoodResolver.takeFinished('apple;');
      expect(t.done, ['apple']);
      expect(t.rest, '');
    });
  });

  group('FoodHistory', () {
    final day = DateTime(2026, 10, 9, 8);
    final foods = [
      tx('Porridge', portion: '1 bowl', meal: 'Breakfast', at: day),
      tx('Porridge',
          portion: '1 bowl',
          meal: 'Breakfast',
          at: day.subtract(const Duration(days: 1))),
      tx('Porridge',
          portion: '1 bowl',
          meal: 'Breakfast',
          at: day.subtract(const Duration(days: 2))),
      tx('Toast',
          meal: 'Breakfast', at: day.subtract(const Duration(days: 3))),
      tx('Toast',
          meal: 'Breakfast', at: day.subtract(const Duration(days: 4))),
      // Most recent of all, but had for lunch.
      tx('Sandwich', meal: 'Lunch', at: day.add(const Duration(hours: 4))),
      // Same name, different portion: offered separately.
      tx('Porridge',
          portion: '2 bowls',
          meal: 'Lunch',
          at: day.add(const Duration(hours: 1)),
          calories: 300),
    ];

    test('ranks by how often each was had for the meal, then recency', () {
      final ranked = FoodHistory.rankForMeal(foods, 'Breakfast');
      expect(ranked.map((t) => '${t.description}|${t.portion}'), [
        'Porridge|1 bowl',
        'Toast|',
        'Sandwich|',
        'Porridge|2 bowls',
      ]);
      // Uses the numbers from the latest time it was logged.
      expect(ranked.first.time, day);
      final lunch = FoodHistory.rankForMeal(foods, 'Lunch', limit: 2);
      expect(lunch.map((t) => t.description), ['Sandwich', 'Porridge']);
      expect(lunch.last.portion, '2 bowls');
    });

    test('search matches part of the name, ignoring case, each food once',
        () {
      final hits = FoodHistory.search(foods, 'PORR');
      expect(hits.map((t) => t.portion), ['2 bowls', '1 bowl']);
      expect(FoodHistory.search(foods, 'o', limit: 5), isEmpty,
          reason: 'needs two letters');
      expect(FoodHistory.search(foods, 'oa'), hasLength(1));
      expect(FoodHistory.search(foods, 'pizza'), isEmpty);
    });

    test('search: every word typed, any order, amounts left out', () {
      final had = [
        tx('3 McCain hash browns', at: day, calories: 240),
        tx('Tofoo naked tofu 100g', at: day, calories: 120),
      ];
      expect(FoodHistory.search(had, 'hash br').single.calories, 240);
      expect(FoodHistory.search(had, '2 hash browns'), hasLength(1));
      expect(FoodHistory.search(had, 'browns mccain'), hasLength(1));
      expect(FoodHistory.search(had, 'tofu 200g'), hasLength(1));
      expect(FoodHistory.search(had, 'hash tofu'), isEmpty);
      expect(FoodHistory.search(had, '3 '), isEmpty, reason: 'no letters');
    });

    test('the same food typed again is reused: own numbers first', () {
      final had = [
        tx('3 McCain hash browns',
            at: day, calories: 240),
        tx('3 mccain  hash browns ',
            at: day.subtract(const Duration(days: 2)), calories: 306),
        tx('Oat latte', at: day, calories: 150),
        tx('oat latte',
            at: day.subtract(const Duration(days: 5)),
            calories: 130,
            ownNumbers: true),
      ];
      expect(FoodHistory.sameFood(had, '3 MCCAIN HASH BROWNS')?.calories, 240,
          reason: 'the latest one');
      expect(FoodHistory.sameFood(had, 'oat latte')?.calories, 130,
          reason: 'numbers they set themselves win');
      expect(FoodHistory.sameFood(had, '2 McCain hash browns'), isNull);
      expect(FoodHistory.sameFood(had, ''), isNull);
    });

    test('your own numbers for a food typed again: same name, latest', () {
      final mine = [
        tx('My protein shake', at: day, calories: 180, ownNumbers: true),
        tx('my  protein shake ',
            at: day.add(const Duration(days: 1)),
            calories: 210,
            ownNumbers: true),
        // Looked up, not set by them: not theirs to reuse.
        tx('2 crumpets', at: day, calories: 150),
      ];
      expect(FoodHistory.ownNumbersFor(mine, 'MY PROTEIN SHAKE')?.calories,
          210);
      expect(FoodHistory.ownNumbersFor(mine, '2 crumpets'), isNull);
      expect(FoodHistory.ownNumbersFor(mine, 'protein shake'), isNull);
    });
  });

  test('meal for the time of day', () {
    expect(MealTime.forHour(7), 'Breakfast');
    expect(MealTime.forHour(12), 'Lunch');
    expect(MealTime.forHour(16), 'Snacks');
    expect(MealTime.forHour(19), 'Dinner');
    expect(MealTime.forHour(23), 'Snacks');
  });
}
