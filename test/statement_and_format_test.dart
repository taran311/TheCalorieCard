// Tests for the statement (history) and the small formatting helpers the
// card and recipe screens rely on.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/leaderboard_service.dart';
import 'package:namer_app/services/statement_service.dart';
import 'package:namer_app/ui/calorie_card.dart';

import 'test_helpers.dart';

const uid = TestWorld.uid;

void main() {
  group('Statement', () {
    late TestWorld w;

    setUp(() async {
      w = TestWorld()..install();
      await w.addProfile();
    });

    tearDown(TestWorld.uninstall);

    test('groups food by day, newest first, and skips recipe ingredients',
        () async {
      await w.addEntry(at: DateTime(2026, 10, 9, 8), calories: 300);
      await w.addEntry(at: DateTime(2026, 10, 9, 13), calories: 600);
      await w.addEntry(at: DateTime(2026, 10, 7, 19), calories: 2500);
      await w.db.collection('user_food').add({
        'user_id': uid,
        'food_description': 'Ingredient',
        'food_calories': 999,
        'foodCategory': BalanceService.recipeCategory,
        'time_added': DateTime(2026, 10, 9, 9),
      });

      final s = await StatementService.load(uid, days: 7);

      expect(s.days, hasLength(7));
      expect(BalanceService.dateKey(s.days.last.day), '2026-10-09');
      expect(s.days.last.calories, closeTo(900, 0.001));
      expect(s.days.last.transactions.first.calories, 600); // newest first
      final twoDaysAgo =
          s.days.firstWhere((d) => BalanceService.dateKey(d.day) == '2026-10-07');
      expect(twoDaysAgo.calories, closeTo(2500, 0.001));
      expect(s.recent, hasLength(3));
    });

    test('days under budget ignores today and empty days', () async {
      await w.addEntry(at: DateTime(2026, 10, 9, 8), calories: 100); // today
      await w.addEntry(at: DateTime(2026, 10, 8, 8), calories: 1800); // under
      await w.addEntry(at: DateTime(2026, 10, 7, 8), calories: 2400); // over

      final s = await StatementService.load(uid, days: 7);

      expect(s.dailyBudget, 2000);
      expect(s.daysUnderBudget, 1);
    });
  });

  group('Portions', () {
    test('recipe portion labels', () {
      expect(FoodLog.portionLabel('Per 1 Serving', 1), 'Per 1 Serving');
      expect(FoodLog.portionLabel('Per 1 Serving', 1.5), 'Per 1.5 Servings');
      expect(FoodLog.portionLabel('Per 2 Servings', 0.5), 'Per 1 Serving');
      expect(FoodLog.portionLabel('450 g', 0.5), '225 g');
      expect(FoodLog.portionLabel('450.0 g', 1), '450 g');
    });

    test('serving amounts are never zero (safe to divide by)', () {
      expect(FoodLog.servingAmount('Per 2.5 Servings'), 2.5);
      expect(FoodLog.servingAmount('0 g'), 1);
      expect(FoodLog.servingAmount('nonsense'), 1);
      expect(FoodLog.servingAmount(''), 1);
    });

    test('amounts drop a trailing .0', () {
      expect(FoodLog.formatAmount(2), '2');
      expect(FoodLog.formatAmount(1.5), '1.5');
      expect(FoodLog.formatAmount(0.25), '0.25');
      expect(FoodLog.formatAmount(1.333333), '1.33');
    });

    test('recipe serving labels', () {
      expect(FoodLog.servingLabel(450, grams: true), '450 g');
      expect(FoodLog.servingLabel(1, grams: false), 'Per 1 Serving');
      expect(FoodLog.servingLabel(2, grams: false), 'Per 2 Servings');
      expect(FoodLog.isGrams('450 g'), isTrue);
      expect(FoodLog.isGrams('Per 1 Serving'), isFalse);
    });
  });

  group('Card text', () {
    test('kcal figures get thousands separators and never crash', () {
      expect(formatCardKcal(1840), '1,840');
      expect(formatCardKcal(1234567), '1,234,567');
      expect(formatCardKcal(-250.6), '251'); // sign is drawn separately
      expect(formatCardKcal(0), '0');
      expect(formatCardKcal(double.nan), '0');
      expect(formatCardKcal(double.infinity), '0');
    });

    test('cardholder name from an email address', () {
      expect(cardholderFromEmail('sam.jones@gmail.com'), 'Sam Jones');
      expect(cardholderFromEmail('a_b-c+d@x.com'), 'A B C D');
      expect(cardholderFromEmail('taran@x.com'), 'Taran');
      expect(cardholderFromEmail('@x.com'), '');
    });
  });

  group('Date-range reads', () {
    late TestWorld w;

    setUp(() async {
      w = TestWorld()..install();
      await w.addProfile();
    });

    tearDown(TestWorld.uninstall);

    test('only the requested days are returned, oldest first', () async {
      await w.addEntry(at: DateTime(2026, 10, 9, 18), description: 'Dinner');
      await w.addEntry(at: DateTime(2026, 10, 9, 8), description: 'Brekkie');
      await w.addEntry(at: DateTime(2026, 10, 8, 23, 59), description: 'Late');
      await w.addEntry(at: DateTime(2026, 10, 10, 0, 0), description: 'Tomorrow');

      final docs = await BalanceService.entriesOn(uid, w.now);

      expect(docs.map((d) => d.data()['food_description']),
          ['Brekkie', 'Dinner']);
    });

    test('old entries with only created_at are found after the backfill',
        () async {
      await w.db.collection('user_food').add({
        'user_id': uid,
        'food_description': 'Old recipe log',
        'food_calories': 450,
        'foodCategory': 'Dinner',
        'created_at': Timestamp.fromDate(DateTime(2026, 10, 9, 7)),
      });
      // A date-range read can't see it yet: it has no time_added.
      expect(await BalanceService.entriesOn(uid, w.now), isEmpty);

      expect(await BalanceService.backfillEntryTimes(uid), 1);

      final docs = await BalanceService.entriesOn(uid, w.now);
      expect(docs.single.data()['food_description'], 'Old recipe log');
      expect((await w.card())['entry_times_backfilled'], isTrue);
      // Only runs once.
      expect(await BalanceService.backfillEntryTimes(uid), 0);
    });

    test('the backfill leaves recipe ingredient rows alone', () async {
      final ref = await w.db.collection('user_food').add({
        'user_id': uid,
        'food_description': 'Ingredient',
        'foodCategory': BalanceService.recipeCategory,
        'created_at': Timestamp.fromDate(w.now),
      });
      expect(await BalanceService.backfillEntryTimes(uid), 0);
      expect((await ref.get()).data()!['time_added'], isNull);
    });

    test('calendar day arithmetic crosses months and years', () {
      expect(BalanceService.addDays(DateTime(2026, 3, 31), 1),
          DateTime(2026, 4, 1));
      expect(BalanceService.addDays(DateTime(2026, 1, 1), -1),
          DateTime(2025, 12, 31));
      expect(BalanceService.addDays(DateTime(2026, 3, 29, 0, 30), -1),
          DateTime(2026, 3, 28, 0, 30));
      expect(BalanceService.addDays(DateTime(2024, 2, 28), 1),
          DateTime(2024, 2, 29));
    });

    test('hiscores: protein since Monday, finished days and streak',
        () async {
      // Friday 9 Oct 2026: the week started Monday 5 Oct.
      await w.addEntry(at: DateTime(2026, 10, 5, 9), protein: 50);
      await w.addEntry(at: DateTime(2026, 10, 9, 9), protein: 30);
      await w.addEntry(at: DateTime(2026, 10, 4, 9), protein: 100); // last week
      Future<void> finished(String key, num left) => w.db
              .collection('daily_logs')
              .doc('${uid}_$key')
              .set({
            'date_key': key,
            'finished': true,
            'balances': {'calories': left},
          });
      await finished('2026-10-08', 100); // on budget
      await finished('2026-10-07', -50); // over budget
      await finished('2026-10-05', 10); // gap on the 6th ends the streak

      final stats = (await LeaderboardService.load(
              myUserId: uid, friendIds: const []))
          .single;

      expect(stats.isMe, isTrue);
      expect(stats.proteinThisWeek, closeTo(80, 0.001));
      expect(stats.daysLogged, 3);
      expect(stats.daysOnBudget, 2);
      expect(stats.streak, 2); // 8th and 7th; today isn't over yet
    });
  });
}
