import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/calorie_game.dart';
import 'package:namer_app/services/games_service.dart';

void main() {
  group('Levels', () {
    test('start at level 1 and need 100, then 150, then 200 XP', () {
      expect(Levels.of(0).level, 1);
      expect(Levels.of(99).level, 1);
      expect(Levels.of(100).level, 2);
      expect(Levels.of(249).level, 2);
      expect(Levels.of(250).level, 3);
      expect(Levels.of(450).level, 4);
    });

    test('progress within a level', () {
      final l = Levels.of(175); // level 2: 75 of 150
      expect(l.into, 75);
      expect(l.needed, 150);
      expect(l.toNext, 75);
      expect(l.progress, closeTo(0.5, 0.0001));
    });

    test('titles change at the listed levels', () {
      expect(Levels.titleFor(1).title, 'Rookie');
      expect(Levels.titleFor(2).title, 'Rookie');
      expect(Levels.titleFor(3).title, 'Label Reader');
      expect(Levels.titleFor(10).title, 'Calorie Detective');
      expect(Levels.titleFor(99).title, 'Calorie Oracle');
    });

    test('negative XP counts as none', () {
      expect(Levels.of(-50).level, 1);
      expect(Levels.of(-50).total, 0);
    });
  });

  group('Xp', () {
    test('up to 10 a guess', () {
      expect(Xp.forScore(100), 10);
      expect(Xp.forScore(94), 9);
      expect(Xp.forScore(95), 10);
      expect(Xp.forScore(4), 0);
      expect(Xp.forScore(0), 0);
      expect(Xp.forScore(150), 10);
    });

    test('XpResult spots a level up', () {
      expect(const XpResult(95, 105).levelledUp, isTrue);
      expect(const XpResult(10, 20).levelledUp, isFalse);
      expect(const XpResult(95, 105).gained, 10);
    });
  });

  group('Daily challenge', () {
    test('is the same five foods all day, for everyone', () {
      final a = GamesService.dailyFoods('2026-10-11');
      final b = GamesService.dailyFoods('2026-10-11');
      expect(a.length, GamesService.dailyRounds);
      expect([for (final f in a) f.name], [for (final f in b) f.name]);
    });

    test('changes from day to day', () {
      final days = {
        for (var d = 1; d <= 10; d++)
          GamesService.dailyFoods('2026-10-${d.toString().padLeft(2, '0')}')
              .map((f) => f.name)
              .join('|')
      };
      expect(days.length, greaterThan(5));
    });

    test('never repeats a food in one day', () {
      final foods = GamesService.dailyFoods('2026-12-25');
      expect({for (final f in foods) '${f.name}|${f.portion}'}.length,
          foods.length);
    });

    test('dayKey pads month and day', () {
      expect(GamesService.dayKey(DateTime(2026, 3, 7)), '2026-03-07');
    });
  });

  group('Guess the Meal', () {
    test('every meal has items and a sensible total', () {
      final ids = <String>{};
      for (final m in kGameMeals) {
        expect(ids.add(m.id), isTrue, reason: 'duplicate id ${m.id}');
        expect(m.items, isNotEmpty);
        expect(m.total, greaterThan(100), reason: m.id);
        expect(m.total, lessThan(4000), reason: m.id);
      }
    });

    test('whole days add up their meals', () {
      final weekday = kGameMeals.firstWhere((m) => m.id == 'day_weekday');
      expect(weekday.total, 397 + 712 + 504 + 689);
    });

    test('a round has 3 meals, at most one whole day, never a pair', () {
      for (var seed = 0; seed < 200; seed++) {
        final meals = GamesService.dealMeals(random: Random(seed));
        expect(meals.length, GamesService.mealsPerRound);
        expect(meals.where((m) => m.kind == MealKind.day).length,
            lessThanOrEqualTo(1));
        final pairs = [
          for (final m in meals)
            if (m.pair != null) m.pair
        ];
        expect(pairs.toSet().length, pairs.length);
        expect(meals.map((m) => m.id).toSet().length, meals.length);
      }
    });

    test('avoids recently seen meals when it can', () {
      final seen = {for (final m in kGameMeals.take(20)) m.id};
      final meals =
          GamesService.dealMeals(random: Random(1), avoid: seen);
      for (final m in meals) {
        expect(seen.contains(m.id), isFalse);
      }
    });

    test('biggest item comes first in the reveal', () {
      final fryUp = kGameMeals.firstWhere((m) => m.id == 'fry_up');
      final kcal = [for (final i in fryUp.biggestFirst) i.kcal];
      expect(kcal, [...kcal]..sort((a, b) => b.compareTo(a)));
    });
  });

  group('GamesProgress', () {
    test('reads the games map', () {
      final now = DateTime(2026, 10, 11);
      final p = GamesProgress.fromUser({
        'games': {
          'xp': 340,
          'month': '2026-10',
          'month_xp': 120,
          'daily': {
            'day': '2026-10-11',
            'guesses': [100, 200, 300, 400, 500],
            'score': 412,
          },
          'meal_day': '2026-10-11',
          'meal_rounds': 2,
        },
      }, now: now);
      expect(p.xp, 340);
      expect(p.monthXp, 120);
      expect(p.dailyDoneOn('2026-10-11'), isTrue);
      expect(p.dailyDoneOn('2026-10-12'), isFalse);
      expect(p.dailyScoreOn('2026-10-11'), 412);
      expect(p.mealXpRoundsLeft('2026-10-11'), 1);
      expect(p.mealXpRoundsLeft('2026-10-12'), Xp.mealRoundsPerDay);
    });

    test("last month's XP doesn't count for this month", () {
      final p = GamesProgress.fromUser({
        'games': {'xp': 50, 'month': '2026-09', 'month_xp': 50},
      }, now: DateTime(2026, 10, 1));
      expect(p.monthXp, 0);
      expect(p.xp, 50);
    });

    test('nothing stored yet', () {
      final p = GamesProgress.fromUser(null);
      expect(p.xp, 0);
      expect(p.level.level, 1);
    });
  });

  test('share line', () {
    final line =
        GamesService.shareLine('2026-10-11', [95, 72, 55, 30, 100]);
    expect(line, contains('11 Oct'));
    expect(line, contains('352/500'));
    expect(line, contains('🟩🟨🟧🟥🟩'));
  });

  test('friend game XP: guesses plus the win bonus', () {
    final g = CalorieGame(
      id: 'g',
      playerIds: const ['a', 'b'],
      names: const {'a': 'A', 'b': 'B'},
      createdBy: 'a',
      foods: const [
        GameFood('🍌', 'Banana', '1', 100),
        GameFood('🍎', 'Apple', '1', 100),
      ],
      guesses: const {
        'a': [100, 100],
        'b': [50, 150],
      },
      status: GameStatus.finished,
      winner: 'a',
      updatedAt: null,
    );
    expect(Xp.forFriendGame(g, 'a'), 10 + 10 + Xp.winBonus);
    expect(Xp.forFriendGame(g, 'b'), 5 + 5);
  });
}
