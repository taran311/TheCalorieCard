// Tests for Calorie Coach's ready-made questions and greeting.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/coach_service.dart';

CoachContext ctx({
  double left = 800,
  double proteinEaten = 100,
  int hour = 12,
  List<String> foods = const ['Porridge'],
}) =>
    CoachContext(
      calorieGoal: 2000,
      caloriesLeft: left,
      goals: const Macros(calories: 2000, protein: 150, carbs: 200, fat: 60),
      eaten: Macros(calories: 2000 - left, protein: proteinEaten),
      todaysFoods: foods,
      daysOverThisWeek: 1,
      daysLoggedThisWeek: 5,
      averageThisWeek: 1850,
      hour: hour,
    );

void main() {
  List<String> labels(CoachContext? c) =>
      CoachService.promptsFor(c).map((p) => p.label).toList();

  test('under budget offers meal ideas with what is left', () {
    final l = labels(ctx(left: 640));
    expect(l.first, 'Meal ideas for my 640 kcal');
    expect(l, isNot(contains('I went over today')));
  });

  test('over budget leads with comfort and balancing', () {
    final prompts = CoachService.promptsFor(ctx(left: -300));
    expect(prompts.first.label, 'I went over today');
    expect(prompts.first.question, contains('300 kcal'));
    expect(prompts.map((p) => p.label), contains('Help me balance it out'));
    expect(prompts.map((p) => p.label), isNot(contains('Plan my dinner')));
  });

  test('protein, dinner and breakfast prompts depend on the day', () {
    expect(labels(ctx(proteinEaten: 60)), contains('Help me hit my protein'));
    expect(labels(ctx(proteinEaten: 145)),
        isNot(contains('Help me hit my protein')));
    expect(labels(ctx(hour: 18)), contains('Plan my dinner'));
    expect(labels(ctx(hour: 8)), contains('Breakfast ideas'));
    expect(labels(ctx(hour: 8)), isNot(contains('Plan my dinner')));
  });

  test('works with no numbers at all', () {
    final l = labels(null);
    expect(l, contains('Motivate me'));
    expect(CoachService.greeting(null, name: 'Sam'), startsWith('Hi Sam!'));
  });

  test('greeting is kind when over', () {
    final g = CoachService.greeting(ctx(left: -250));
    expect(g, contains('250 kcal over'));
    expect(g, contains("that's okay"));
  });

  test('context sent to Coach is rounded and capped', () {
    final json = ctx(foods: List.generate(30, (i) => 'Food $i')).toJson();
    expect(json['calories_left_today'], 800);
    expect((json['foods_today'] as List), hasLength(20));
    expect(json['time_of_day'], 'afternoon');
  });
}
