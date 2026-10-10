// Editing a logged food (portion, calories, meal) and undoing a log: the
// card must always be charged or refunded exactly the difference.

import 'package:flutter_test/flutter_test.dart';
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

  Future<LoggedFoods> logToast({String source = 'fatsecret'}) =>
      FoodLog.logFoods(userId: uid, meal: 'Breakfast', items: [
        {
          'name': 'Toast',
          'portion': '1 slice',
          'calories': 100,
          'protein': 4,
          'carbs': 18,
          'fat': 1,
          'source': source,
        }
      ]);

  Future<Map<String, dynamic>> entry(String id) async =>
      (await w.db.collection('user_food').doc(id).get()).data()!;

  test('logging returns the new ids and calories, and remembers estimates',
      () async {
    final logged = await logToast(source: 'ai');
    expect(logged.count, 1);
    expect(logged.calories, 100);
    expect(logged.meal, 'Breakfast');
    final e = await entry(logged.ids.single);
    expect(e['food_source'], 'ai');
    expect(e['food_estimate'], isTrue);

    final db = await logToast();
    expect((await entry(db.ids.single))['food_estimate'], isNull);
  });

  test('undo takes the food back off and refunds the card', () async {
    final logged = await logToast();
    expect((await w.card())['calories'], near(1900));
    await FoodLog.undo(logged, userId: uid);
    expect((await w.card())['calories'], near(2000));
    expect(await w.foodRows(), isEmpty);
  });

  test('doubling a portion charges the difference, and edits never compound',
      () async {
    final id = (await logToast()).ids.single;
    await FoodLog.updateEntry(id,
        entry: await entry(id), multiplier: 2, userId: uid);
    var e = await entry(id);
    expect(e['food_calories'], near(200));
    expect(e['food_protein'], near(8));
    expect(e['food_portion'], '2 × 1 slice');
    expect(FoodLog.multiplierOf(e), 2);
    expect((await w.card())['calories'], near(1800));
    expect((await w.card())['protein_balance'], near(150 - 8));

    // Back to half of the original, not half of the doubled one.
    await FoodLog.updateEntry(id, entry: e, multiplier: 0.5, userId: uid);
    e = await entry(id);
    expect(e['food_calories'], near(50));
    expect(e['food_portion'], '0.5 × 1 slice');
    expect((await w.card())['calories'], near(1950));

    // And back to as logged.
    await FoodLog.updateEntry(id, entry: e, multiplier: 1, userId: uid);
    e = await entry(id);
    expect(e['food_calories'], near(100));
    expect(e['food_portion'], '1 slice');
    expect((await w.card())['calories'], near(1900));
  });

  test('fixing calories replaces them and clears the estimate mark', () async {
    final id = (await logToast(source: 'ai')).ids.single;
    await FoodLog.updateEntry(id,
        entry: await entry(id), calories: 160, userId: uid);
    final e = await entry(id);
    expect(e['food_calories'], near(160));
    expect(e['food_protein'], near(4));
    expect(e['food_estimate'], isFalse);
    expect((await w.card())['calories'], near(1840));
  });

  test('moving to another meal leaves the card alone', () async {
    final id = (await logToast()).ids.single;
    await FoodLog.updateEntry(id,
        entry: await entry(id), meal: 'Lunch', userId: uid);
    expect((await entry(id))['foodCategory'], 'Lunch');
    expect((await w.card())['calories'], near(1900));
  });

  test("editing an older day's food doesn't touch today's card", () async {
    final id = await w.addEntry(
        at: w.now.subtract(const Duration(days: 2)), calories: 300);
    await FoodLog.updateEntry(id,
        entry: await entry(id), multiplier: 2, userId: uid);
    expect((await entry(id))['food_calories'], near(600));
    expect((await w.card())['calories'], near(2000));
  });

  test('a zero or negative portion is refused', () async {
    final id = (await logToast()).ids.single;
    expect(
      () async => FoodLog.updateEntry(id,
          entry: await entry(id), multiplier: 0, userId: uid),
      throwsArgumentError,
    );
  });
}
