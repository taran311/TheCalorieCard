// "Usuals": the foods someone logs most often at a meal, for one-tap logging.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/usuals.dart';

import 'test_helpers.dart';

Map<String, dynamic> food(
  String name, {
  String portion = '1 bowl',
  String meal = 'Breakfast',
  double calories = 300,
  DateTime? at,
  Map<String, dynamic> extra = const {},
}) =>
    {
      'food_description': name,
      'food_portion': portion,
      'foodCategory': meal,
      'food_calories': calories,
      'food_protein': 10,
      'food_carbs': 40,
      'food_fat': 5,
      if (at != null) 'time_added': Timestamp.fromDate(at),
      ...extra,
    };

DateTime day(int d) => DateTime(2026, 10, d, 8);

void main() {
  test('most frequent first, needs at least two logs, only this meal', () {
    final usuals = Usuals.rank([
      food('Porridge', at: day(1)),
      food('Porridge', at: day(2)),
      food('Porridge', at: day(3)),
      food('Toast', portion: '2 slices', at: day(1)),
      food('Toast', portion: '2 slices', at: day(2)),
      food('Banana', at: day(3)), // only once
      food('Soup', meal: 'Lunch', at: day(1)),
      food('Soup', meal: 'Lunch', at: day(2)),
    ], meal: 'Breakfast');

    expect(usuals.map((u) => u.name), ['Porridge', 'Toast']);
    expect(usuals.first.count, 3);
  });

  test('same name and portion is one food, ignoring case and spaces', () {
    final usuals = Usuals.rank([
      food('Porridge ', at: day(1)),
      food('porridge', at: day(2)),
      food('Porridge', portion: '2 bowls', at: day(3)),
    ], meal: 'Breakfast');
    expect(usuals, hasLength(1));
    expect(usuals.single.count, 2);
  });

  test('uses the latest calories, and the chip label shows them', () {
    final usuals = Usuals.rank([
      food('Porridge', calories: 380, at: day(1)),
      food('Porridge', calories: 412, at: day(5)),
      food('Porridge', calories: 400, at: day(3)),
    ], meal: 'Breakfast');
    expect(usuals.single.calories, 412);
    expect(usuals.single.label, 'Porridge · 412');
    expect(usuals.single.toLogItem()['calories'], 412);
  });

  test('recipes are skipped', () {
    final usuals = Usuals.rank([
      food('Recipe: Chilli', at: day(1), extra: {'is_recipe': true}),
      food('Recipe: Chilli', at: day(2), extra: {'is_recipe': true}),
      food('Stew', at: day(1), extra: {'recipe_id': 'r1'}),
      food('Stew', at: day(2), extra: {'recipe_id': 'r1'}),
    ], meal: 'Breakfast');
    expect(usuals, isEmpty);
  });

  test('ties go to the most recent, and at most four are shown', () {
    const names = ['A', 'B', 'C', 'D', 'E'];
    final entries = [
      for (var i = 0; i < names.length; i++) ...[
        food(names[i], at: day(1 + i)),
        food(names[i], at: day(10 + i)),
      ],
    ];
    final usuals = Usuals.rank(entries, meal: 'Breakfast');
    expect(usuals.map((u) => u.name), ['E', 'D', 'C', 'B']);
  });

  test('old "Brekkie" entries count as breakfast', () {
    final usuals = Usuals.rank([
      food('Porridge', meal: 'Brekkie', at: day(1)),
      food('Porridge', at: day(2)),
    ], meal: 'Breakfast');
    expect(usuals.single.count, 2);
  });

  group('load', () {
    late TestWorld w;

    setUp(() async {
      w = TestWorld()..install();
      await w.addProfile();
    });

    tearDown(TestWorld.uninstall);

    test('only looks at the last 30 days of your own food', () async {
      final now = w.now;
      await w.addEntry(
          at: now.subtract(const Duration(days: 2)),
          meal: 'Breakfast',
          description: 'Porridge');
      await w.addEntry(
          at: now.subtract(const Duration(days: 5)),
          meal: 'Breakfast',
          description: 'Porridge');
      // Too long ago.
      await w.addEntry(
          at: now.subtract(const Duration(days: 40)),
          meal: 'Breakfast',
          description: 'Muesli');
      await w.addEntry(
          at: now.subtract(const Duration(days: 41)),
          meal: 'Breakfast',
          description: 'Muesli');
      // Someone else's.
      await w.addEntry(
          uid: TestWorld.otherUid,
          at: now.subtract(const Duration(days: 1)),
          meal: 'Breakfast',
          description: 'Eggs');
      await w.addEntry(
          uid: TestWorld.otherUid,
          at: now.subtract(const Duration(days: 2)),
          meal: 'Breakfast',
          description: 'Eggs');

      final usuals = await Usuals.load(TestWorld.uid, 'Breakfast');
      expect(usuals.map((u) => u.name), ['Porridge']);
      expect(usuals.single.count, 2);
    });
  });
}
