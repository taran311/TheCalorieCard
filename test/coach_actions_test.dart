// Tests for changes Coach proposes: nothing changes until apply(), and
// applying changes the diary and card exactly like doing it by hand.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/coach_actions.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/recipe_service.dart';

import 'test_helpers.dart';

void main() {
  late TestWorld w;

  setUp(() async {
    w = TestWorld()..install();
    await w.addProfile();
  });

  tearDown(TestWorld.uninstall);

  test('parses actions and tidies the meal name', () {
    final a = CoachAction.fromJson(
        {'type': 'log_food', 'meal': 'lunch', 'items': ['2 eggs', ' ']});
    expect(a, isNotNull);
    expect(a!.meal, 'Lunch');
    expect(a.strings('items'), ['2 eggs']);
    expect(CoachAction.fromJson({'type': 'hack_the_planet'}), isNull);
    expect(CoachAction.fromJson('nope'), isNull);
    // No meal (or not a meal): the one for the time of day. The test clock
    // says 12:00, which is lunchtime.
    expect(
        CoachAction.fromJson({'type': 'log_food', 'meal': '???'})!.meal, 'Lunch');
    expect(CoachAction.fromJson({'type': 'log_food'})!.meal, 'Lunch');
    w.now = DateTime(2026, 10, 9, 8, 0);
    expect(CoachAction.fromJson({'type': 'log_food'})!.meal, 'Breakfast');
    w.now = DateTime(2026, 10, 9, 23, 0);
    expect(CoachAction.fromJson({'type': 'log_food'})!.meal, 'Snacks');
  });

  test('Breakfast used to be saved as Brekkie: both read as Breakfast', () {
    expect(FoodLog.mealOf('Brekkie'), 'Breakfast');
    expect(FoodLog.mealOf(null), 'Breakfast');
    expect(FoodLog.mealOf('Lunch'), 'Lunch');
    expect(
        CoachAction.fromJson({'type': 'log_food', 'meal': 'brekkie'})!.meal,
        'Breakfast');
  });

  test('remove_food: shows the item, changes nothing until accepted, '
      'then refunds the card', () async {
    await FoodLog.logFoods(userId: TestWorld.uid, meal: 'Snacks', items: [
      {
        'name': 'Crisps',
        'portion': '1 bag',
        'calories': 190,
        'protein': 2,
        'carbs': 18,
        'fat': 12,
      }
    ]);
    final id = (await w.foodRows(meal: 'Snacks')).single['id'] as String;
    expect((await w.card())['calories'], 1810);

    final prepared = await CoachActions.prepare(
      CoachAction('remove_food', {
        'entry_ids': [id]
      }),
      TestWorld.uid,
    );
    expect(prepared.lines.single.name, 'Crisps');
    expect(prepared.total!.calories, -190);
    expect((await w.card())['calories'], 1810, reason: 'not applied yet');

    await prepared.apply();
    expect(await w.foodRows(meal: 'Snacks'), isEmpty);
    expect((await w.card())['calories'], 2000);
  });

  test("remove_food won't touch someone else's food", () async {
    final id = await w.addEntry(uid: TestWorld.otherUid, at: w.now);
    expect(
      () => CoachActions.prepare(
          CoachAction('remove_food', {
            'entry_ids': [id]
          }),
          TestWorld.uid),
      throwsA(isA<CoachActionException>()),
    );
  });

  test('log_recipe: one serving of a two-serving recipe is half', () async {
    final recipeId = await RecipeService.create(
      TestWorld.uid,
      name: 'Chilli',
      servingSize: 'Per 2 Servings',
      ingredients: const [
        RecipeIngredient(
          name: 'Mince',
          macros: Macros(calories: 800, protein: 80, carbs: 0, fat: 50),
        ),
      ],
    );

    final prepared = await CoachActions.prepare(
      CoachAction('log_recipe',
          {'recipe_id': recipeId, 'meal': 'Dinner', 'servings': 1}),
      TestWorld.uid,
    );
    expect(prepared.title, 'Add to Dinner');
    expect(prepared.total!.calories, 400);
    expect((await w.card())['calories'], 2000, reason: 'not applied yet');

    await prepared.apply();
    expect((await w.card())['calories'], 1600);
    final logged = await w.foodRows(meal: 'Dinner');
    expect(logged.single['food_description'], 'Recipe: Chilli');
  });

  test('log_recipe: the meal can be changed on the card before accepting',
      () async {
    final recipeId = await RecipeService.create(
      TestWorld.uid,
      name: 'Soup',
      servingSize: 'Per 1 Serving',
      ingredients: const [
        RecipeIngredient(
          name: 'Veg',
          macros: Macros(calories: 200, protein: 5, carbs: 30, fat: 4),
        ),
      ],
    );
    final prepared = await CoachActions.prepare(
      CoachAction('log_recipe', {'recipe_id': recipeId, 'meal': 'Lunch'}),
      TestWorld.uid,
    );
    expect(prepared.meal, 'Lunch');
    await prepared.apply(meal: 'Dinner');
    expect(await w.foodRows(meal: 'Lunch'), isEmpty);
    expect((await w.foodRows(meal: 'Dinner')).single['food_description'],
        'Recipe: Soup');
    expect((await w.card())['calories'], 1800);
  });

  test('remove_food: a line taken out on the card is kept', () async {
    await FoodLog.logFoods(userId: TestWorld.uid, meal: 'Snacks', items: [
      {'name': 'Crisps', 'calories': 190, 'protein': 2, 'carbs': 18, 'fat': 12},
      {'name': 'Apple', 'calories': 80, 'protein': 0, 'carbs': 20, 'fat': 0},
    ]);
    final rows = await w.foodRows(meal: 'Snacks');
    final ids = [for (final r in rows) r['id'] as String];
    expect((await w.card())['calories'], 1730);

    final prepared = await CoachActions.prepare(
      CoachAction('remove_food', {'entry_ids': ids}),
      TestWorld.uid,
    );
    expect(prepared.removable, isTrue);
    expect(prepared.lines, hasLength(2));
    final appleAt = prepared.lines.indexWhere((l) => l.name == 'Apple');
    expect(prepared.keptCount({appleAt}), 1);
    expect(prepared.totalWithout({appleAt})!.calories, -190);
    expect(prepared.keptCount({0, 1}), 0);

    await prepared.apply(without: {appleAt});
    final left = await w.foodRows(meal: 'Snacks');
    expect(left.single['food_description'], 'Apple');
    expect((await w.card())['calories'], 1920);
  });

  test('delete_recipe removes it from Recipes', () async {
    final recipeId = await RecipeService.create(
      TestWorld.uid,
      name: 'Porridge',
      servingSize: 'Per 1 Serving',
      ingredients: const [
        RecipeIngredient(
          name: 'Oats',
          macros: Macros(calories: 300, protein: 10, carbs: 50, fat: 6),
        ),
      ],
    );
    final prepared = await CoachActions.prepare(
      CoachAction('delete_recipe', {'recipe_id': recipeId}),
      TestWorld.uid,
    );
    expect(prepared.destructive, isTrue);
    await prepared.apply();
    expect((await w.db.collection('recipes').doc(recipeId).get()).exists,
        isFalse);
  });
}
