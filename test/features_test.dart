// Tests for the social and banking features: split the bill, challenges,
// direct debits, pots, Calorie Sense, card designs, spending insights and
// the monthly Wrapped.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/calorie_sense.dart';
import 'package:namer_app/services/card_design_service.dart';
import 'package:namer_app/services/challenge_service.dart';
import 'package:namer_app/services/direct_debit_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/spend_category.dart';
import 'package:namer_app/services/split_service.dart';
import 'package:namer_app/services/wrapped_service.dart';
import 'package:namer_app/ui/calorie_card.dart';

import 'test_helpers.dart';

const me = TestWorld.uid;
const friend = TestWorld.otherUid;

Matcher near(num value) => closeTo(value, 0.0001);

void main() {
  late TestWorld w;

  setUp(() async {
    w = TestWorld()..install(); // Friday 9 Oct 2026, 12:00
    await w.addProfile();
    await w.addProfile(uid: friend);
  });

  tearDown(TestWorld.uninstall);

  const pizza = [
    {
      'name': 'Pepperoni pizza',
      'calories': 1800,
      'protein': 75,
      'carbs': 210,
      'fat': 72,
      'portion': '1 large',
    },
    {
      'name': 'Garlic bread',
      'calories': 600,
      'protein': 15,
      'carbs': 72,
      'fat': 27,
      'portion': '',
    },
  ];

  group('Split the bill', () {
    test('your share is logged and the friend gets a request', () async {
      await SplitService.create(
        uid: me,
        fromName: 'taran',
        items: pizza,
        friendIds: [friend],
        meal: 'Dinner',
      );

      // 2400 kcal split two ways.
      expect((await w.card())['calories'], near(2000 - 1200));
      expect((await w.card(uid: friend))['calories'], near(2000));

      final pending = await SplitService.pendingFor(friend).first;
      expect(pending, hasLength(1));
      expect(pending.single.fromName, 'taran');
      expect(pending.single.calories, near(1200));
      expect(pending.single.items.first['portion'], '1/2 share of 1 large');
      expect(pending.single.items.last['portion'], '1/2 share');
    });

    test("accepting logs the friend's share once, even on a double tap",
        () async {
      await SplitService.create(
          uid: me, fromName: 'taran', items: pizza, friendIds: [friend],
          meal: 'Dinner');
      final split = (await SplitService.pendingFor(friend).first).single;

      await SplitService.accept(friend, split);
      await SplitService.accept(friend, split);

      expect((await w.card(uid: friend))['calories'], near(800));
      expect(await SplitService.pendingFor(friend).first, isEmpty);
    });

    test('declining changes nothing on the card', () async {
      await SplitService.create(
          uid: me, fromName: 'taran', items: pizza, friendIds: [friend],
          meal: 'Dinner');
      final split = (await SplitService.pendingFor(friend).first).single;

      await SplitService.decline(friend, split);

      expect((await w.card(uid: friend))['calories'], near(2000));
      expect(await SplitService.pendingFor(friend).first, isEmpty);
    });

    test("someone the bill wasn't split with can't accept it", () async {
      await SplitService.create(
          uid: me, fromName: 'taran', items: pizza, friendIds: [friend],
          meal: 'Dinner');
      final split = (await SplitService.pendingFor(friend).first).single;

      expect(await SplitService.accept('stranger', split), isFalse);
      expect(await w.foodRows(meal: 'Dinner'), hasLength(2)); // just mine
    });

    test("an accepted share can't be declined afterwards", () async {
      await SplitService.create(
          uid: me, fromName: 'taran', items: pizza, friendIds: [friend],
          meal: 'Dinner');
      final split = (await SplitService.pendingFor(friend).first).single;

      expect(await SplitService.accept(friend, split), isTrue);
      expect(await SplitService.decline(friend, split), isFalse);
      expect((await w.card(uid: friend))['calories'], near(800));
    });

    test('the preview matches what each person logs', () {
      expect(SplitService.shareCalories(pizza, 2), near(1200));
      expect(SplitService.shareCalories(pizza, 3), near(800));
    });

    test('three ways means a third each', () {
      final share = SplitService.shareOf(pizza, 3);
      expect(share.first['calories'], near(600));
      expect(share.first['protein'], near(25));
    });

    test('you need at least one friend', () async {
      await expectLater(
        SplitService.create(
            uid: me, fromName: 'taran', items: pizza, friendIds: [me],
            meal: 'Dinner'),
        throwsArgumentError,
      );
      expect((await w.card())['calories'], near(2000));
    });
  });

  group('Challenges', () {
    Future<void> finished(String uid, String key, num left) => w.db
        .collection('daily_logs')
        .doc('${uid}_$key')
        .set({'finished': true, 'balances': {'calories': left}});

    test('head-to-head ranks by days on budget this week', () async {
      await ChallengeService.create(
          uid: me, type: ChallengeType.headToHead, friendIds: [friend]);
      // Week of Mon 5 Oct.
      await finished(me, '2026-10-05', 100);
      await finished(me, '2026-10-06', -20); // finished but over
      await finished(friend, '2026-10-05', 10);
      await finished(friend, '2026-10-07', 0);
      await finished(friend, '2026-10-04', 500); // last week: ignored

      final c = (await ChallengeService.forUser(me).first).single;
      final scores = await ChallengeService.scores(c);

      expect(scores.first.userId, friend);
      expect(scores.first.onBudgetDays, 2);
      expect(scores.last.onBudgetDays, 1);
      expect(scores.last.finishedDays, 2);
      expect(c.start, DateTime(2026, 10, 5));
    });

    test('team goal adds up finished days', () async {
      await ChallengeService.create(
          uid: me, type: ChallengeType.group, friendIds: [friend], target: 5);
      await finished(me, '2026-10-05', 0);
      await finished(friend, '2026-10-06', -300);
      final c = (await ChallengeService.forUser(friend).first).single;
      final scores = await ChallengeService.scores(c);
      expect(c.target, 5);
      expect(scores.fold<int>(0, (s, e) => s + e.finishedDays), 2);
    });

    test('leaving removes you', () async {
      await ChallengeService.create(
          uid: me, type: ChallengeType.headToHead, friendIds: [friend]);
      final c = (await ChallengeService.forUser(me).first).single;
      await ChallengeService.leave(me, c);
      expect(await ChallengeService.forUser(me).first, isEmpty);
      expect(await ChallengeService.forUser(friend).first, hasLength(1));
    });
  });

  group('Direct debits', () {
    final latte = {
      'food_description': 'Oat latte',
      'food_portion': '12oz',
      'food_calories': 150,
      'food_protein': 4,
      'food_carbs': 20,
      'food_fat': 6,
      'foodCategory': 'Brekkie',
      'time_added': Timestamp.fromDate(DateTime(2026, 10, 9, 8)),
    };

    test('set up twice from the same food: still one debit', () async {
      await DirectDebitService.createFromEntry(me, latte);
      await DirectDebitService.createFromEntry(me, latte);
      expect(await DirectDebitService.forUser(me).first, hasLength(1));
    });

    test('set up from an older entry: due today', () async {
      await DirectDebitService.createFromEntry(me, {
        ...latte,
        'time_added': Timestamp.fromDate(DateTime(2026, 10, 7, 8)),
      });
      final d = (await DirectDebitService.forUser(me).first).single;
      expect(d.isDueToday, isTrue);
    });

    test('set up from today\'s food: not due again until tomorrow', () async {
      await DirectDebitService.createFromEntry(me, latte);
      final d = (await DirectDebitService.forUser(me).first).single;
      expect(d.isDueToday, isFalse);

      w.now = DateTime(2026, 10, 10, 8);
      final tomorrow = (await DirectDebitService.forUser(me).first).single;
      expect(tomorrow.isDueToday, isTrue);
    });

    test('paying logs it once, even if tapped twice', () async {
      await DirectDebitService.createFromEntry(me, latte);
      w.now = DateTime(2026, 10, 10, 8);
      final d = (await DirectDebitService.forUser(me).first).single;

      expect(await DirectDebitService.pay(me, d), isTrue);
      expect(await DirectDebitService.pay(me, d), isFalse);

      // New day: full goal, minus one latte.
      expect((await w.card())['calories'], near(2000 - 150));
      final logged = await w.foodRows(meal: 'Brekkie');
      expect(logged.where((r) => r['food_description'] == 'Oat latte'),
          hasLength(1));
    });

    test('skipping means not due today and nothing logged', () async {
      await DirectDebitService.createFromEntry(me, latte);
      w.now = DateTime(2026, 10, 10, 8);
      final d = (await DirectDebitService.forUser(me).first).single;
      await DirectDebitService.skipToday(d);
      final after = (await DirectDebitService.forUser(me).first).single;
      expect(after.isDueToday, isFalse);
      expect(await DirectDebitService.pay(me, after), isFalse);
      expect(await w.foodRows(), isEmpty);
    });
  });

  group('Pots', () {
    Future<void> potsOn({double? leftYesterday, String? balanceDate}) async {
      w = TestWorld()..install();
      await w.addProfile(
          balanceDate: balanceDate ?? '2026-10-08',
          calories: leftYesterday ?? 2000);
      await BalanceService.setPotsEnabled(me, true);
    }

    test('a day with food saves its leftover, up to 150', () async {
      await potsOn(leftYesterday: 400);
      await w.addEntry(at: DateTime(2026, 10, 8, 12), calories: 1600);

      await BalanceService.ensureDailyReset(me);

      final card = await w.card();
      expect(BalanceService.potFrom(card), near(150));
      expect(card['calories'], near(2000)); // today starts full
    });

    test('a small leftover saves exactly that', () async {
      await potsOn(leftYesterday: 60);
      await w.addEntry(at: DateTime(2026, 10, 8, 12), calories: 1940);
      await BalanceService.ensureDailyReset(me);
      expect(BalanceService.potFrom(await w.card()), near(60));
    });

    test("a day without logging doesn't fill the pot", () async {
      await potsOn(leftYesterday: 2000);
      await BalanceService.ensureDailyReset(me);
      expect(BalanceService.potFrom(await w.card()), near(0));
    });

    test('logging one tiny snack doesn\'t bank the leftover', () async {
      await potsOn(leftYesterday: 1950);
      await w.addEntry(at: DateTime(2026, 10, 8, 12), calories: 50);
      await BalanceService.ensureDailyReset(me);
      expect(BalanceService.potFrom(await w.card()), near(0));
    });

    test('an overspent day adds nothing', () async {
      await potsOn(leftYesterday: -250);
      await w.addEntry(at: DateTime(2026, 10, 8, 12), calories: 2250);
      await BalanceService.ensureDailyReset(me);
      expect(BalanceService.potFrom(await w.card()), near(0));
    });

    test('the pot tops out at 750 a week', () async {
      await potsOn(leftYesterday: 500);
      final ud = await BalanceService.userDataDoc(me);
      await ud!.reference.update({'pot': 700, 'pot_week': '2026-10-05'});
      await w.addEntry(at: DateTime(2026, 10, 8, 12), calories: 1500);
      await BalanceService.ensureDailyReset(me);
      expect(BalanceService.potFrom(await w.card()), near(750));
    });

    test('it empties on Monday', () async {
      // Sunday's leftover belongs to last week's pot, which is closed.
      w = TestWorld(now: DateTime(2026, 10, 12, 9))..install(); // Monday
      await w.addProfile(balanceDate: '2026-10-11', calories: 300);
      await BalanceService.setPotsEnabled(me, true);
      final ud = await BalanceService.userDataDoc(me);
      await ud!.reference.update({'pot': 600, 'pot_week': '2026-10-05'});
      await w.addEntry(at: DateTime(2026, 10, 11, 12), calories: 1700);

      await BalanceService.ensureDailyReset(me);

      expect(BalanceService.potFrom(await w.card()), near(0));
    });

    test('moving the pot adds it to today and empties it', () async {
      await potsOn(leftYesterday: 400);
      await w.addEntry(at: DateTime(2026, 10, 8, 12), calories: 1600);
      await BalanceService.ensureDailyReset(me);

      final moved = await BalanceService.spendPot(me);

      expect(moved, near(150));
      final card = await w.card();
      expect(card['calories'], near(2150));
      expect(BalanceService.potFrom(card), near(0));
    });

    test('pot spent today survives a settings change', () async {
      await potsOn(leftYesterday: 400);
      await w.addEntry(at: DateTime(2026, 10, 8, 12), calories: 1600);
      await BalanceService.ensureDailyReset(me);
      await BalanceService.spendPot(me);

      await BalanceService.applyGoals(me, goals: TestWorld.goals);

      expect((await w.card())['calories'], near(2150));
    });

    test('pot spent today is not saved again tomorrow', () async {
      await potsOn(leftYesterday: 400);
      await w.addEntry(at: DateTime(2026, 10, 8, 12), calories: 1600);
      await BalanceService.ensureDailyReset(me); // pot 150
      await BalanceService.spendPot(me); // today 2150, pot 0
      await FoodLog.logFoods(userId: me, meal: 'Lunch', items: [
        {'name': 'Lunch', 'calories': 2000, 'protein': 0, 'carbs': 0, 'fat': 0}
      ]); // 150 left, all of it from the pot

      w.now = DateTime(2026, 10, 10, 8);
      await BalanceService.ensureDailyReset(me);

      expect(BalanceService.potFrom(await w.card()), near(0));
    });

    test('turning pots off empties the pot', () async {
      await potsOn(leftYesterday: 400);
      await w.addEntry(at: DateTime(2026, 10, 8, 12), calories: 1600);
      await BalanceService.ensureDailyReset(me);
      await BalanceService.setPotsEnabled(me, false);
      expect(BalanceService.potFrom(await w.card()), near(0));
      expect(await BalanceService.spendPot(me), near(0));
    });

    test('pots off: nothing is saved', () async {
      w = TestWorld()..install();
      await w.addProfile(balanceDate: '2026-10-08', calories: 400);
      await w.addEntry(at: DateTime(2026, 10, 8, 12), calories: 1600);
      await BalanceService.ensureDailyReset(me);
      expect(BalanceService.potFrom(await w.card()), near(0));
    });
  });

  group('Calorie Sense', () {
    test('scores', () {
      expect(CalorieSense.score(350, 350), 100);
      expect(CalorieSense.score(400, 350), 86);
      expect(CalorieSense.score(700, 350), 0);
      expect(CalorieSense.score(30, 10), 60); // small foods judged vs 50
      expect(CalorieSense.score(double.nan, 100), 0);
    });

    test('this month\'s average builds up and unlocks Sunset', () async {
      for (var i = 0; i < 9; i++) {
        await CalorieSense.record(me, 80);
      }
      var user = (await w.db.collection('users').doc(me).get()).data();
      expect(CalorieSense.thisMonth(user).count, 9);
      expect(CardDesignService.isUnlocked(CardDesign.sunset, user), isFalse);

      await CalorieSense.record(me, 90);
      user = (await w.db.collection('users').doc(me).get()).data();
      expect(CalorieSense.thisMonth(user).average, near(81));
      expect(CardDesignService.isUnlocked(CardDesign.sunset, user), isTrue);
    });

    test('a new month starts fresh', () async {
      await CalorieSense.record(me, 50);
      w.now = DateTime(2026, 11, 2, 9);
      await CalorieSense.record(me, 90);
      final user = (await w.db.collection('users').doc(me).get()).data();
      expect(CalorieSense.thisMonth(user).count, 1);
      expect(CalorieSense.thisMonth(user).average, near(90));
    });
  });

  group('Card designs', () {
    test('streaks unlock Emerald at 7 and Metal at 30', () async {
      await CardDesignService.recordStreak(me, 6);
      var user = (await w.db.collection('users').doc(me).get()).data();
      expect(CardDesignService.isUnlocked(CardDesign.emerald, user), isFalse);

      await CardDesignService.recordStreak(me, 7);
      await CardDesignService.recordStreak(me, 3); // never goes down
      user = (await w.db.collection('users').doc(me).get()).data();
      expect(user!['best_streak'], 7);
      expect(CardDesignService.isUnlocked(CardDesign.emerald, user), isTrue);
      expect(CardDesignService.isUnlocked(CardDesign.metal, user), isFalse);
    });

    test("a locked choice falls back to Midnight", () async {
      await CardDesignService.choose(me, CardDesign.metal);
      final user = (await w.db.collection('users').doc(me).get()).data();
      expect(CardDesignService.designOf(user).id, 'midnight');
    });
  });

  group('Where it went', () {
    test('foods land in sensible categories', () {
      SpendCategory c(String d) => SpendCategory.fromDescription(d);
      expect(c('Recipe: Chilli'), SpendCategory.homeCooked);
      expect(c('Big Mac meal'), SpendCategory.takeaway);
      expect(c("Nando's half chicken"), SpendCategory.takeaway);
      expect(c('Oat latte'), SpendCategory.drinks);
      expect(c('Chocolate milkshake'), SpendCategory.drinks);
      expect(c('Green tea'), SpendCategory.drinks);
      expect(c('Rump steak'), SpendCategory.meals); // not "tea"
      expect(c('Kale salad'), SpendCategory.fruitVeg); // not "ale"
      expect(c('Dairy Milk bar'), SpendCategory.snacks);
      expect(c('Banana'), SpendCategory.fruitVeg);
      expect(c('Chicken and rice'), SpendCategory.meals);
      expect(c('Watermelon'), SpendCategory.fruitVeg); // not "water"
      expect(c('Ginger chicken'), SpendCategory.meals); // not "gin"
      expect(c('Strawberries'), SpendCategory.fruitVeg);
      expect(c('Vegan burger'), SpendCategory.meals); // not "veg"
      expect(c('Pretzel'), SpendCategory.meals); // not "Pret"
      expect(c('Two cookies'), SpendCategory.snacks);
    });

    test('breakdown adds up and sorts biggest first', () {
      final rows = SpendInsights.breakdown([
        (description: 'Latte', isRecipe: false, calories: 150),
        (description: 'Coke', isRecipe: false, calories: 140),
        (description: 'Chilli', isRecipe: true, calories: 600),
      ]);
      expect(rows.first.category, SpendCategory.homeCooked);
      expect(rows.first.share, near(600 / 890));
      expect(rows.last.category, SpendCategory.drinks);
      expect(rows.last.count, 2);
    });
  });

  group('Monthly Wrapped', () {
    test('counts days, top foods, streaks and on-budget days', () async {
      await w.addEntry(at: DateTime(2026, 10, 1, 8), description: 'Oats',
          calories: 300, protein: 10);
      await w.addEntry(at: DateTime(2026, 10, 2, 8), description: 'oats',
          calories: 300, protein: 10);
      await w.addEntry(at: DateTime(2026, 10, 2, 13), description: 'Big Mac',
          calories: 550, protein: 25);
      await w.addEntry(at: DateTime(2026, 9, 30, 8), description: 'Oats',
          calories: 300); // last month
      for (final k in ['2026-10-01', '2026-10-02', '2026-10-04']) {
        await w.db.collection('daily_logs').doc('${me}_$k').set({
          'finished': true,
          'balances': {'calories': k == '2026-10-04' ? -10 : 200},
        });
      }

      final wrap = await WrappedService.load(me, DateTime(2026, 10, 15));

      expect(wrap.daysLogged, 2);
      expect(wrap.totalCalories, near(1150));
      expect(wrap.averageCalories, near(575));
      expect(wrap.totalProtein, near(45));
      expect(wrap.topFoods.first.name, 'Oats');
      expect(wrap.topFoods.first.count, 2);
      expect(wrap.finishedDays, 3);
      expect(wrap.onBudgetDays, 2);
      expect(wrap.bestStreak, 2);
      expect(wrap.toShareText(), contains('October'));
    });
  });
}
