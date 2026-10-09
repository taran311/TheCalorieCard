// Tests for how achievements are worked out from your finished days.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/achievement_service.dart';
import 'package:namer_app/services/achievements.dart';

import 'test_helpers.dart';

/// A finished day with a 2000 kcal goal (150P / 200C / 60F).
AchievementDay day(
  DateTime date, {
  double eaten = 1800,
  double? left,
  double protein = 100,
  double carbs = 150,
  double fat = 50,
  List<String> foods = const ['Chicken and rice'],
  String meal = 'Lunch',
}) =>
    AchievementDay(
      date: date,
      eaten: eaten,
      left: left ?? 2000 - eaten,
      calorieGoal: 2000,
      protein: protein,
      carbs: carbs,
      fat: fat,
      proteinGoal: 150,
      carbsGoal: 200,
      fatGoal: 60,
      entries: [
        for (final f in foods) {'food_description': f, 'foodCategory': meal}
      ],
    );

Map<String, int> progressOf(List<AchievementDay> days,
        [AchievementInputs Function(List<AchievementDay>)? build]) =>
    AchievementEngine.progress(
        build != null ? build(days) : AchievementInputs(days: days));

void main() {
  test('every achievement has a unique id and a progress value', () {
    final ids = Achievements.all.map((a) => a.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    final progress = AchievementEngine.progress(const AchievementInputs());
    for (final a in Achievements.all) {
      expect(progress.containsKey(a.id), isTrue, reason: a.id);
    }
  });

  group('Streaks', () {
    test('consecutive days count, across a month end', () {
      final p = progressOf([
        day(DateTime(2026, 10, 30)),
        day(DateTime(2026, 10, 31)),
        day(DateTime(2026, 11, 1)),
        day(DateTime(2026, 11, 3)), // gap
      ]);
      expect(p['streak_starter'], 3);
      expect(p['first_finish'], 4);
    });

    test('the same day logged twice counts once', () {
      final p = progressOf([
        day(DateTime(2026, 10, 1)),
        day(DateTime(2026, 10, 1)),
      ]);
      expect(p['days_30'], 1);
    });
  });

  group('On budget', () {
    test("a day counts once you've eaten at least half your goal", () {
      expect(day(DateTime(2026, 10, 1), eaten: 1800).isGood, isTrue);
      expect(day(DateTime(2026, 10, 1), eaten: 900).isGood, isFalse);
      expect(day(DateTime(2026, 10, 1), eaten: 2100).isGood, isFalse);
    });

    test("not eating earns nothing", () {
      final p = progressOf([
        for (var i = 1; i <= 7; i++)
          day(DateTime(2026, 10, i), eaten: 0, foods: const []),
      ]);
      expect(p['budget_1'], 0);
      expect(p['perfect_week'], 0);
      expect(p['budget_streak_14'], 0);
      expect(p['bullseye'], 0);
    });

    test('bullseye is 0–50 kcal left', () {
      final p = progressOf([
        day(DateTime(2026, 10, 1), eaten: 1970),
        day(DateTime(2026, 10, 2), eaten: 1900),
      ]);
      expect(p['bullseye'], 1);
    });

    test('weekend warrior needs Saturday and Sunday', () {
      // 10 Oct 2026 is a Saturday.
      expect(
          progressOf([day(DateTime(2026, 10, 10)), day(DateTime(2026, 10, 11))])[
              'weekend_warrior'],
          1);
      expect(
          progressOf([day(DateTime(2026, 10, 9)), day(DateTime(2026, 10, 10))])[
              'weekend_warrior'],
          0);
    });

    test('perfect week is Monday to Sunday, all on budget', () {
      // Monday 5 Oct to Sunday 11 Oct 2026.
      final week = [for (var i = 5; i <= 11; i++) day(DateTime(2026, 10, i))];
      expect(progressOf(week)['perfect_week'], 1);
      final oneOver = [...week]
        ..[3] = day(DateTime(2026, 10, 8), eaten: 2300);
      expect(progressOf(oneOver)['perfect_week'], 0);
    });

    test('comeback: on budget the day after going over', () {
      final p = progressOf([
        day(DateTime(2026, 10, 1), eaten: 2400),
        day(DateTime(2026, 10, 2)),
      ]);
      expect(p['comeback'], 1);
    });
  });

  group('Nutrition', () {
    test('macro master needs all three macros within 10%', () {
      final hit = day(DateTime(2026, 10, 1),
          eaten: 1950, protein: 145, carbs: 210, fat: 58);
      final miss = day(DateTime(2026, 10, 2),
          eaten: 1950, protein: 100, carbs: 210, fat: 58);
      expect(progressOf([hit, miss])['macro_master'], 1);
    });

    test('protein streak uses your own goal', () {
      final p = progressOf([
        day(DateTime(2026, 10, 1), protein: 160),
        day(DateTime(2026, 10, 2), protein: 150),
        day(DateTime(2026, 10, 3), protein: 120),
      ]);
      expect(p['cultivating_mass'], 2);
      expect(p['protein_30'], 2);
    });

    test('five a day counts fruit and veg in one day', () {
      final p = progressOf([
        day(DateTime(2026, 10, 1), foods: const [
          'Apple',
          'Banana',
          'Carrot sticks',
          'Kale salad',
          'Strawberries',
          'Chicken',
        ]),
      ]);
      expect(p['five_a_day'], 5);
    });

    test('breakfast, recipes, takeaways and variety', () {
      final p = progressOf([
        day(DateTime(2026, 10, 1), foods: const ['Porridge'], meal: 'Brekkie'),
        day(DateTime(2026, 10, 2), foods: const ['Recipe: Chilli']),
        day(DateTime(2026, 10, 3), foods: const ['Big Mac meal']),
        day(DateTime(2026, 10, 4), foods: const ['Recipe: Chilli', 'Apple']),
      ]);
      expect(p['breakfast_club'], 1);
      expect(p['home_chef'], 2);
      expect(p['takeaway_free'], 2); // 1st-2nd, then 4th after the Big Mac
      expect(p['variety'], 4); // porridge, chilli, big mac, apple
    });
  });

  test('extras come from counters and profile', () {
    final p = AchievementEngine.progress(const AchievementInputs(
      counters: {'splits': 2, 'scans': 10, 'bang_on': 1, 'pot_spends': 1},
      friendCount: 5,
      customCard: true,
      calorieSenseAverage: 88,
      calorieSenseCount: 12,
      hasDirectDebit: true,
      pot: 750,
      inChallenge: true,
    ));
    final unlocked = AchievementEngine.unlocked(p);
    expect(
        unlocked,
        containsAll([
          'split_1',
          'scanner',
          'bang_on',
          'pot_treat',
          'friends_5',
          'first_friend',
          'card_custom',
          'sharp_eye',
          'direct_debit',
          'pot_saver',
          'challenge_join',
        ]));
    expect(unlocked.contains('challenge_win'), isFalse);
  });

  group('Saved achievements', () {
    late TestWorld w;

    setUp(() async {
      w = TestWorld()..install();
      await w.addProfile();
    });

    tearDown(TestWorld.uninstall);

    Future<void> finishedDay(DateTime d, double eaten) =>
        w.db.collection('daily_logs').doc('${TestWorld.uid}_${d.day}').set({
          'user_id': TestWorld.uid,
          'date': Timestamp.fromDate(d),
          'finished': true,
          'totals': {'calories': eaten, 'protein': 100, 'carbs': 150, 'fat': 50},
          'balances': {'calories': 2000 - eaten},
          'goals': {
            'calorie_goal': 2000,
            'protein_goal': 150,
            'carbs_goal': 200,
            'fats_goal': 60,
          },
          'food_entries': [
            {'food_description': 'Chicken and rice', 'foodCategory': 'Lunch'}
          ],
        });

    test('unlocks once, saves progress, and keeps unlocks', () async {
      await finishedDay(DateTime(2026, 10, 6), 1800);
      await finishedDay(DateTime(2026, 10, 7), 1800);
      await finishedDay(DateTime(2026, 10, 8), 1800);

      final first = await AchievementService.evaluate(TestWorld.uid);
      final ids = first.map((a) => a.id);
      expect(ids, containsAll(['first_finish', 'streak_starter', 'budget_1']));

      final again = await AchievementService.evaluate(TestWorld.uid);
      expect(again, isEmpty);

      final doc = (await w.db
              .collection('user_achievements')
              .doc(TestWorld.uid)
              .get())
          .data()!;
      expect(doc['streak_starter'], isTrue);
      expect((doc['progress'] as Map)['streak_7'], 3);
    });
  });
}
