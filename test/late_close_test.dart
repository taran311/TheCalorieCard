// Closing yesterday the next day, so a forgotten tap doesn't cost a streak.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/late_close.dart';

import 'test_helpers.dart';

void main() {
  late TestWorld w;

  setUp(() async {
    w = TestWorld()..install(); // Friday 9 Oct 2026, 12:00
    await w.addProfile();
  });

  tearDown(TestWorld.uninstall);

  Future<Map<String, dynamic>?> log(String key) async =>
      (await w.db.collection('daily_logs').doc('${TestWorld.uid}_$key').get())
          .data();

  test('a logged, unclosed yesterday can be closed today', () async {
    await w.addEntry(at: DateTime(2026, 10, 8, 13), calories: 600);
    final day = await LateClose.openYesterday(TestWorld.uid);
    expect(day, DateTime(2026, 10, 8));

    expect(await LateClose.closeYesterday(TestWorld.uid, day!), isTrue);
    final saved = await log('2026-10-08');
    expect(saved?['finished'], isTrue);
    expect(saved?['closed_late'], isTrue);
    expect((saved?['totals'] as Map)['calories'], 600);

    // Once closed, it isn't offered again.
    expect(await LateClose.openYesterday(TestWorld.uid), isNull);
  });

  test('nothing to offer when yesterday had no food', () async {
    expect(await LateClose.openYesterday(TestWorld.uid), isNull);
  });

  test("yesterday's saved snapshot is kept, only marked closed", () async {
    await w.addEntry(at: DateTime(2026, 10, 8, 13), calories: 600);
    await w.db.collection('daily_logs').doc('${TestWorld.uid}_2026-10-08').set({
      'user_id': TestWorld.uid,
      'date_key': '2026-10-08',
      'totals': {'calories': 600},
      'balances': {'calories': 1400},
      'finished': false,
    });
    await LateClose.closeYesterday(TestWorld.uid, DateTime(2026, 10, 8));
    final saved = await log('2026-10-08');
    expect(saved?['finished'], isTrue);
    expect((saved?['balances'] as Map)['calories'], 1400);
  });

  test('only yesterday, and never a rest day', () async {
    // Two days ago: too late.
    await w.addEntry(at: DateTime(2026, 10, 7, 13));
    expect(await LateClose.closeYesterday(TestWorld.uid, DateTime(2026, 10, 7)),
        isFalse);

    expect(LateClose.canClose({'rest_day': true}, hadFood: true), isFalse);
    expect(LateClose.canClose({'finished': true}, hadFood: true), isFalse);
    expect(LateClose.canClose(null, hadFood: false), isFalse);
    expect(LateClose.canClose(null, hadFood: true), isTrue);
  });

  group('fixing yesterday (forgot something)', () {
    final yesterday = DateTime(2026, 10, 8);

    Future<void> closedYesterday() async {
      await w.addEntry(at: DateTime(2026, 10, 8, 13), calories: 1500,
          protein: 80, carbs: 150, fat: 50);
      await w.db
          .collection('daily_logs')
          .doc('${TestWorld.uid}_2026-10-08')
          .set({
        'user_id': TestWorld.uid,
        'date_key': '2026-10-08',
        'totals': {'calories': 1500, 'protein': 80, 'carbs': 150, 'fat': 50},
        'balances': {
          'calories': 500,
          'protein_balance': 70,
          'carbs_balance': 50,
          'fats_balance': 20,
        },
        'finished': true,
      });
    }

    test('only yesterday can be fixed', () {
      expect(LateClose.isYesterday(DateTime(2026, 10, 8, 23)), isTrue);
      expect(LateClose.isYesterday(DateTime(2026, 10, 9)), isFalse);
      expect(LateClose.isYesterday(DateTime(2026, 10, 7)), isFalse);
    });

    test("two Oreos go on yesterday, not today's card", () async {
      await closedYesterday();
      final cardBefore = (await w.card())['calories'];

      FoodLog.logDay = yesterday;
      try {
        await FoodLog.logFoods(
            userId: TestWorld.uid,
            meal: 'Snacks',
            items: [
              {
                'name': 'Oreo',
                'portion': '2 biscuits',
                'calories': 106,
                'protein': 1,
                'carbs': 16,
                'fat': 4,
              }
            ]);
      } finally {
        FoodLog.logDay = null;
      }

      // Today's card is untouched.
      expect((await w.card())['calories'], cardBefore);
      // The Oreos are on yesterday.
      final oreo = (await w.foodRows())
          .firstWhere((r) => r['food_description'] == 'Oreo');
      final at = BalanceService.entryDate(oreo)!;
      expect(BalanceService.dateKey(at), '2026-10-08');

      await LateClose.syncDay(TestWorld.uid, yesterday);
      final saved = await log('2026-10-08');
      expect((saved?['totals'] as Map)['calories'], 1606);
      expect((saved?['balances'] as Map)['calories'], 394);
      expect((saved?['balances'] as Map)['protein_balance'], 69);
      expect(saved?['finished'], isTrue, reason: 'stays closed');
    });

    test('removing something from yesterday gives it back to that day',
        () async {
      await closedYesterday();
      final extra = await w.addEntry(
          at: DateTime(2026, 10, 8, 20), calories: 200, protein: 0,
          carbs: 0, fat: 0);
      await LateClose.syncDay(TestWorld.uid, yesterday);
      expect((await log('2026-10-08'))?['balances']['calories'], 300);

      await FoodLog.remove(extra, userId: TestWorld.uid);
      await LateClose.syncDay(TestWorld.uid, yesterday);
      final saved = await log('2026-10-08');
      expect((saved?['totals'] as Map)['calories'], 1500);
      expect((saved?['balances'] as Map)['calories'], 500);
    });
  });
}
