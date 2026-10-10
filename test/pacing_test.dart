// "Safe to spend" pacing: how much each meal still to come can have.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/pacing.dart';

DateTime at(int hour) => DateTime(2026, 10, 9, hour, 0);

void main() {
  test('evening with only dinner left: all of it bar the snack reserve', () {
    final plan = Pacing.plan(
      left: 720,
      now: at(18),
      mealsWithFood: {'Breakfast', 'Lunch'},
    )!;
    expect(plan.meals, ['Dinner']);
    expect(plan.snackReserve, 70);
    expect(plan.perMeal, 650);
    expect(plan.message, 'About 650 kcal for dinner');
  });

  test('late morning, lunch and dinner to come: split evenly', () {
    final plan = Pacing.plan(
      left: 1000,
      now: at(12),
      mealsWithFood: {'Breakfast'},
    )!;
    expect(plan.meals, ['Lunch', 'Dinner']);
    expect(plan.snackReserve, 100);
    expect(plan.perMeal, 450);
    expect(plan.message, '≈ 450 kcal each for lunch and dinner');
  });

  test('snacks already logged: nothing kept back', () {
    final plan = Pacing.plan(
      left: 900,
      now: at(16),
      mealsWithFood: {'Breakfast', 'Lunch', 'Snacks'},
    )!;
    expect(plan.snackReserve, 0);
    expect(plan.perMeal, 900);
  });

  test('early morning: all three main meals, listed with commas', () {
    final plan =
        Pacing.plan(left: 2000, now: at(7), mealsWithFood: const {})!;
    expect(plan.meals, ['Breakfast', 'Lunch', 'Dinner']);
    expect(plan.snackReserve, 200);
    expect(plan.perMeal, 600);
    expect(plan.message, '≈ 600 kcal each for breakfast, lunch and dinner');
  });

  test('a missed meal that is already behind us is not counted', () {
    // 4pm, nothing logged: breakfast and lunch are past, only dinner left.
    final plan =
        Pacing.plan(left: 1500, now: at(16), mealsWithFood: const {})!;
    expect(plan.meals, ['Dinner']);
  });

  test('nothing to say when over, empty, or every meal is done', () {
    expect(Pacing.plan(left: 0, now: at(12), mealsWithFood: const {}), isNull);
    expect(
        Pacing.plan(left: -200, now: at(12), mealsWithFood: const {}), isNull);
    expect(
        Pacing.plan(
            left: 500,
            now: at(12),
            mealsWithFood: {'Breakfast', 'Lunch', 'Dinner'}),
        isNull);
    // After 9pm there's no main meal left to plan.
    expect(Pacing.plan(left: 500, now: at(22), mealsWithFood: const {}),
        isNull);
  });

  test('too little left to be worth splitting', () {
    expect(
        Pacing.plan(left: 60, now: at(12), mealsWithFood: {'Breakfast'}),
        isNull);
  });

  test('the Add food button guesses the meal from the time', () {
    expect(Pacing.mealAt(at(7)), 'Breakfast');
    expect(Pacing.mealAt(at(10)), 'Breakfast');
    expect(Pacing.mealAt(at(11)), 'Lunch');
    expect(Pacing.mealAt(at(14)), 'Lunch');
    expect(Pacing.mealAt(at(15)), 'Dinner');
    expect(Pacing.mealAt(at(20)), 'Dinner');
    expect(Pacing.mealAt(at(21)), 'Snacks');
    expect(Pacing.mealAt(at(2)), 'Breakfast');
  });

  test('big numbers get a thousands separator', () {
    final plan = Pacing.plan(
        left: 2500, now: at(18), mealsWithFood: {'Breakfast', 'Lunch'})!;
    expect(plan.message, 'About 2,250 kcal for dinner');
  });
}
