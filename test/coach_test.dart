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
    // Numbers that didn't load aren't shown as "0 kcal".
    expect(l, contains('Meal ideas'));
    expect(l.where((x) => x.contains('kcal')), isEmpty);
  });

  test('add food, save a recipe and remove something start a message '
      'instead of sending a vague one', () {
    final prompts = CoachService.promptsFor(ctx(hour: 8));
    final add = prompts.firstWhere((p) => p.label == 'Add food for me');
    expect(add.prefill, 'Add to breakfast: ');
    expect(add.question, isEmpty);
    final save = prompts.firstWhere((p) => p.label == 'Save a recipe');
    expect(save.prefill, isNotNull);
    // Ordinary chips still send their question.
    final motivate = prompts.firstWhere((p) => p.label == 'Motivate me');
    expect(motivate.prefill, isNull);
    expect(motivate.question, isNotEmpty);
    expect(
        CoachService.promptsFor(ctx(hour: 13))
            .firstWhere((p) => p.label == 'Add food for me')
            .prefill,
        'Add to lunch: ');
  });

  test('greeting is kind when over', () {
    final g = CoachService.greeting(ctx(left: -250));
    expect(g, contains('250 kcal over'));
    expect(g, contains("that's okay"));
  });

  test('dining out and drinks night out are offered near the top', () {
    final prompts = CoachService.promptsFor(ctx());
    final i = prompts.indexWhere((p) => p.outing == CoachOuting.diningOut);
    final j = prompts.indexWhere((p) => p.outing == CoachOuting.drinksOut);
    expect(i, inInclusiveRange(0, 5));
    expect(j, i + 1);
    expect(prompts[i].label, 'Dining out');
    // Also there when over, and with no numbers.
    expect(labels(ctx(left: -200)), contains('Drinks night out'));
    expect(labels(null), contains('Dining out'));
  });

  test('dining out question carries the place and calories left', () {
    final q = CoachService.diningOutQuestion(ctx(left: 900, proteinEaten: 110),
        kind: 'Italian', place: 'Zizzi');
    expect(q, contains('Zizzi (Italian)'));
    expect(q, contains('900 kcal left'));
    expect(q, contains('40g of protein'));
    expect(CoachService.diningOutQuestion(ctx(), kind: 'Pub'),
        contains('at a pub'));
    final over = CoachService.diningOutQuestion(ctx(left: -150),
        kind: 'Indian', drinking: true);
    expect(over, contains('150 kcal over'));
    expect(over, contains('a drink or two'));
    expect(over, contains('lighter options'));
  });

  test('drinks night question lists drinks and asks how many fit', () {
    final q = CoachService.drinksOutQuestion(ctx(left: 700),
        drinks: ['Lager', 'Spirits & mixers'], size: 'probably a few',
        eating: true);
    expect(q, contains('lager and spirits & mixers'));
    expect(q, contains('probably a few'));
    expect(q, contains('eating out too'));
    expect(q, contains('700 kcal left'));
    expect(q, contains('How many drinks'));
    expect(
        CoachService.drinksOutQuestion(null, drinks: [], size: 'just a couple'),
        contains("not sure what I'll drink"));
  });

  test('context sent to Coach is rounded and capped', () {
    final json = ctx(foods: List.generate(30, (i) => 'Food $i')).toJson();
    expect(json['calories_left_today'], 800);
    expect((json['foods_today'] as List), hasLength(20));
    expect(json['time_of_day'], 'afternoon');
  });
}
