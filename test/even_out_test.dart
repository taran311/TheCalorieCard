// "Spread it over the week": going over one day takes a little off the
// next few days' cards, gently and only when asked.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/even_out.dart';

import 'test_helpers.dart';

void main() {
  late TestWorld w;

  setUp(() async {
    w = TestWorld()..install(); // Friday 9 Oct 2026, 12:00
    await w.addProfile();
  });

  tearDown(TestWorld.uninstall);

  test('300 over on a Friday: 150 less on Saturday and Sunday', () async {
    final plan =
        await EvenOut.start(TestWorld.uid, overBy: 300, goal: 2000);
    expect(plan, isNotNull);
    expect(plan!.perDay, 150);
    expect(plan.from, '2026-10-10');
    expect(plan.until, '2026-10-11');
    expect(plan.days, 2);

    // Today's card isn't touched.
    expect((await w.card())['calories'], 2000);

    // Saturday starts lower.
    w.now = DateTime(2026, 10, 10, 8);
    await BalanceService.ensureDailyReset(TestWorld.uid);
    expect((await w.card())['calories'], 1850);

    // Monday is back to normal.
    w.now = DateTime(2026, 10, 12, 8);
    await BalanceService.ensureDailyReset(TestWorld.uid);
    expect((await w.card())['calories'], 2000);
  });

  test('stopping gives today back', () async {
    await EvenOut.start(TestWorld.uid, overBy: 300, goal: 2000);
    w.now = DateTime(2026, 10, 10, 8);
    await BalanceService.ensureDailyReset(TestWorld.uid);
    expect(await EvenOut.stop(TestWorld.uid), 150);
    expect((await w.card())['calories'], 2000);
    final doc = await BalanceService.userDataDoc(TestWorld.uid);
    expect(EvenOutPlan.fromData(doc!.data()), isNull);
  });

  test('gentle: at most 10% of the goal and never below 1,200', () {
    final friday = DateTime(2026, 10, 9);
    // 1,000 over across 2 days would be 500 a day: capped at 200.
    expect(EvenOut.perDayFor(1000, 2000, friday), 200);
    // A 1,300 budget can only go down to 1,200.
    expect(EvenOut.perDayFor(1000, 1300, friday), 100);
    expect(EvenOut.perDayFor(500, 1200, friday), 0);
  });

  test('closing over: the preview matches what spreading does', () async {
    final now = DateTime(2026, 10, 9, 21);
    final p = EvenOut.preview(null, overBy: 300, goal: 2000, now: now);
    expect(p, isNotNull);
    expect(p!.perDay, 150);
    expect(p.days, 2);
    expect(EvenOut.preview(null, overBy: 0, goal: 2000, now: now), isNull);
  });

  test('going over again joins the plan already running', () async {
    // Wednesday: 300 over, spread Thu to Sun (75 a day).
    w.now = DateTime(2026, 10, 7, 21);
    final first = await EvenOut.start(TestWorld.uid, overBy: 300, goal: 2000);
    expect(first!.perDay, 75);
    // Thursday: 100 over again. 3 days of the old plan are left (225),
    // so 325 over Fri to Sun.
    w.now = DateTime(2026, 10, 8, 21);
    final p = EvenOut.preview(first, overBy: 100, goal: 2000, now: w.now)!;
    expect(p.total, 325);
    expect(p.days, 3);
    expect(p.perDay, 109);
    final second = await EvenOut.start(TestWorld.uid, overBy: 100, goal: 2000);
    expect(second!.perDay, p.perDay);
    expect(second.until, '2026-10-11');
  });

  group('saving while a plan runs pays it off first', () {
    // Wednesday: 300 over, spread Thu to Sun at 75 a day. Thursday's card
    // starts at 1,925; ending it with [leftThursday] left.
    Future<void> overWednesdayThenSave(double leftThursday,
        {bool pots = false}) async {
      w = TestWorld(now: DateTime(2026, 10, 7, 21))..install();
      await w.addProfile();
      if (pots) await BalanceService.setPotsEnabled(TestWorld.uid, true);
      await EvenOut.start(TestWorld.uid, overBy: 300, goal: 2000);
      w.now = DateTime(2026, 10, 8, 8);
      await BalanceService.ensureDailyReset(TestWorld.uid);
      expect((await w.card())['calories'], 1925);
      await w.addEntry(
          at: DateTime(2026, 10, 8, 12), calories: 1925 - leftThursday);
      final doc = await BalanceService.userDataDoc(TestWorld.uid);
      await doc!.reference.update({'calories': leftThursday});
      w.now = DateTime(2026, 10, 9, 8);
      await BalanceService.ensureDailyReset(TestWorld.uid);
    }

    test('part paid: the rest is spread over the days left', () async {
      await overWednesdayThenSave(100);
      // 225 still owed Fri to Sun, 100 paid: 125 over 3 days is 42.
      final card = await w.card();
      expect(EvenOutPlan.fromData(card)!.perDay, 42);
      expect(card['calories'], 2000 - 42);
      final log = await w.db
          .collection('daily_logs')
          .doc('${TestWorld.uid}_2026-10-08')
          .get();
      expect(BalanceService.planPaidFrom(log.data()), 100);
    });

    test('paid off: the plan ends and the rest goes in the pot', () async {
      await overWednesdayThenSave(300, pots: true);
      final card = await w.card();
      expect(EvenOutPlan.fromData(card), isNull);
      expect(card['calories'], 2000);
      // 300 saved, 225 cleared the plan, 75 in the pot.
      expect(BalanceService.potFrom(card), 75);
    });

    test('the preview matches', () {
      expect(
          BalanceService.planPaydown(
              left: 100, eaten: 1825, goal: 2000, owed: 225),
          100);
      expect(
          BalanceService.planPaydown(
              left: 300, eaten: 1625, goal: 2000, owed: 225),
          225);
      expect(
          BalanceService.planPaydown(
              left: 1900, eaten: 100, goal: 2000, owed: 225),
          0,
          reason: "a day you didn't really log doesn't count");
    });
  });
}
