// Tests for creating, editing and deleting recipes, and how that interacts
// with food already logged from them.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/recipe_service.dart';

import 'test_helpers.dart';

const uid = TestWorld.uid;

Matcher near(num value) => closeTo(value, 0.0001);

const mince = RecipeIngredient(
  name: 'Beef mince',
  macros: Macros(calories: 500, protein: 40, carbs: 0, fat: 35),
  portion: '200 g',
);
const beans = RecipeIngredient(
  name: 'Kidney beans',
  macros: Macros(calories: 220, protein: 14, carbs: 38, fat: 1),
  portion: '1 can',
);

void main() {
  late TestWorld w;

  setUp(() async {
    w = TestWorld()..install();
    await w.addProfile();
  });

  tearDown(TestWorld.uninstall);

  Future<Map<String, dynamic>?> recipe(String id) async =>
      (await w.db.collection('recipes').doc(id).get()).data();

  Future<List<Map<String, dynamic>>> ingredientRows(String recipeId) async =>
      (await w.foodRows(meal: BalanceService.recipeCategory))
          .where((r) => r['recipe_id'] == recipeId)
          .toList();

  test('adding a brand new recipe adds it to Recipes with the right totals',
      () async {
    final id = await RecipeService.create(uid,
        name: '  Chilli  ',
        servingSize: 'Per 2 Servings',
        ingredients: [mince, beans]);

    final r = (await recipe(id))!;
    expect(r['user_id'], uid);
    expect(r['name'], 'Chilli');
    expect(r['serving_size'], 'Per 2 Servings');
    expect(r['total_calories'], near(720));
    expect(r['total_protein'], near(54));
    expect(r['total_carbs'], near(38));
    expect(r['total_fat'], near(36));

    final rows = await ingredientRows(id);
    expect(rows, hasLength(2));
    expect((r['food_item_ids'] as List).toSet(),
        rows.map((e) => e['id']).toSet());
    expect(rows.every((e) => e['user_id'] == uid), isTrue);
  });

  test("creating a recipe doesn't touch the card", () async {
    await RecipeService.create(uid,
        name: 'Chilli', servingSize: 'Per 1 Serving', ingredients: [mince]);
    expect((await w.card())['calories'], near(2000));
    expect((await BalanceService.todaysTotals(uid)).calories, near(0));
  });

  test('a recipe needs a name and at least one ingredient', () async {
    await expectLater(
        RecipeService.create(uid,
            name: ' ', servingSize: 'Per 1 Serving', ingredients: [mince]),
        throwsArgumentError);
    await expectLater(
        RecipeService.create(uid,
            name: 'Empty', servingSize: 'Per 1 Serving', ingredients: []),
        throwsArgumentError);
    expect((await w.db.collection('recipes').get()).docs, isEmpty);
  });

  test('deleting a recipe removes it and its ingredients from Recipes',
      () async {
    final id = await RecipeService.create(uid,
        name: 'Chilli', servingSize: 'Per 1 Serving', ingredients: [mince, beans]);

    await RecipeService.delete(uid, id);

    expect(await recipe(id), isNull);
    expect(await ingredientRows(id), isEmpty);
  });

  test("deleting a recipe keeps food you've logged from it, and the balance",
      () async {
    final id = await RecipeService.create(uid,
        name: 'Chilli', servingSize: 'Per 1 Serving', ingredients: [mince]);
    await FoodLog.logRecipe(
        userId: uid,
        recipeId: id,
        recipe: (await recipe(id))!,
        meal: 'Dinner',
        multiplier: 1);
    expect((await w.card())['calories'], near(1500));

    await RecipeService.delete(uid, id);

    expect((await w.card())['calories'], near(1500));
    final logged = await w.foodRows(meal: 'Dinner');
    expect(logged.single['food_description'], 'Recipe: Chilli');
  });

  test('deleting a recipe stops it being shared', () async {
    final id = await RecipeService.create(uid,
        name: 'Chilli', servingSize: 'Per 1 Serving', ingredients: [mince]);
    await w.db.collection('shared_recipes').add({
      'recipe_id': id,
      'shared_by_user_id': uid,
      'shared_with_user_id': TestWorld.otherUid,
    });

    await RecipeService.delete(uid, id);

    expect((await w.db.collection('shared_recipes').get()).docs, isEmpty);
  });

  test("you can't delete or edit someone else's recipe", () async {
    final id = await RecipeService.create(TestWorld.otherUid,
        name: 'Theirs', servingSize: 'Per 1 Serving', ingredients: [mince]);

    await expectLater(
        RecipeService.delete(uid, id), throwsA(isA<StateError>()));
    await expectLater(
        RecipeService.update(uid, id,
            name: 'Mine now', servingSize: 'Per 1 Serving', ingredients: [beans]),
        throwsA(isA<StateError>()));
    expect((await recipe(id))!['name'], 'Theirs');
  });

  test('editing a recipe replaces its ingredients and totals', () async {
    final id = await RecipeService.create(uid,
        name: 'Chilli', servingSize: 'Per 1 Serving', ingredients: [mince, beans]);

    await RecipeService.update(uid, id,
        name: 'Bean chilli', servingSize: '450 g', ingredients: [beans]);

    final r = (await recipe(id))!;
    expect(r['name'], 'Bean chilli');
    expect(r['serving_size'], '450 g');
    expect(r['total_calories'], near(220));
    final rows = await ingredientRows(id);
    expect(rows.map((e) => e['food_description']), ['Kidney beans']);
  });

  test("editing a recipe doesn't change food already logged from it",
      () async {
    final id = await RecipeService.create(uid,
        name: 'Chilli', servingSize: 'Per 1 Serving', ingredients: [mince]);
    await FoodLog.logRecipe(
        userId: uid,
        recipeId: id,
        recipe: (await recipe(id))!,
        meal: 'Lunch',
        multiplier: 1);

    await RecipeService.update(uid, id,
        name: 'Chilli', servingSize: 'Per 1 Serving', ingredients: [beans]);

    expect((await w.card())['calories'], near(1500));
    expect((await w.foodRows(meal: 'Lunch')).single['food_calories'],
        near(500));
  });

  test('logging an edited recipe uses the new totals', () async {
    final id = await RecipeService.create(uid,
        name: 'Chilli', servingSize: 'Per 1 Serving', ingredients: [mince]);
    await RecipeService.update(uid, id,
        name: 'Chilli', servingSize: 'Per 1 Serving', ingredients: [beans]);

    await FoodLog.logRecipe(
        userId: uid,
        recipeId: id,
        recipe: (await recipe(id))!,
        meal: 'Lunch',
        multiplier: 1);

    expect((await w.card())['calories'], near(2000 - 220));
  });
}
