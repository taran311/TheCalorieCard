// Rest days ("freeze card"): today only, at most 4 per calendar month,
// saved on daily_logs without touching the rest of the day's history, and
// skipped by streaks.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/leaderboard_service.dart';
import 'package:namer_app/services/rest_days.dart';

import 'test_helpers.dart';

const uid = TestWorld.uid;

void main() {
  late TestWorld w;

  setUp(() async {
    // Friday 9 Oct 2026, noon.
    w = TestWorld()..install();
    await w.addProfile();
  });

  tearDown(TestWorld.uninstall);

  Future<Map<String, dynamic>?> log(String dateKey) async =>
      (await w.db.collection('daily_logs').doc('${uid}_$dateKey').get())
          .data();

  Future<void> setLog(String dateKey, Map<String, dynamic> data) => w.db
      .collection('daily_logs')
      .doc('${uid}_$dateKey')
      .set({'user_id': uid, 'date_key': dateKey, ...data});

  test('rest days are counted per calendar month', () {
    expect(RestDays.maxPerMonth, 4);
    expect(RestDays.monthKey(DateTime(2026, 10, 9, 15)), '2026-10');
    expect(RestDays.monthKey(DateTime(2026, 10, 31, 23)), '2026-10');
    expect(RestDays.monthKey(DateTime(2026, 11, 1)), '2026-11');
  });

  test('starting one marks today and keeps the rest of the day', () async {
    await setLog(w.today, {
      'finished': false,
      'totals': {'calories': 300},
    });
    await RestDays.start(uid);
    final data = (await log(w.today))!;
    expect(data['rest_day'], isTrue);
    expect(data['user_id'], uid);
    expect(data['date_key'], w.today);
    expect(RestDays.isRest(data), isTrue);
    expect((data['totals'] as Map)['calories'], 300,
        reason: 'merged, not overwritten');
    expect(await RestDays.leftThisMonth(uid), 3);
  });

  test('a fifth rest day in the same month is refused', () async {
    await setLog('2026-10-01', {'rest_day': true});
    await setLog('2026-10-02', {'rest_day': true});
    await setLog('2026-10-03', {'rest_day': true});
    await setLog('2026-10-04', {'rest_day': true});
    expect(await RestDays.leftThisMonth(uid), 0);
    await expectLater(
        RestDays.start(uid), throwsA(isA<RestDayLimitReached>()));
    expect(RestDays.isRest(await log(w.today)), isFalse);
  });

  test("last month's rest days don't count", () async {
    await setLog('2026-09-27', {'rest_day': true});
    await setLog('2026-09-28', {'rest_day': true});
    await setLog('2026-09-29', {'rest_day': true});
    await setLog('2026-09-30', {'rest_day': true});
    expect(await RestDays.leftThisMonth(uid), 4);
    await RestDays.start(uid);
    expect(RestDays.isRest(await log(w.today)), isTrue);
  });

  test('a few in a row are fine (a long weekend away)', () async {
    await setLog('2026-10-07', {'rest_day': true});
    await setLog('2026-10-08', {'rest_day': true});
    await RestDays.start(uid); // Friday 9th
    expect(await RestDays.leftThisMonth(uid), 1);
  });

  test('an ended rest day frees the slot again', () async {
    await setLog('2026-10-01', {'rest_day': true});
    await setLog('2026-10-02', {'rest_day': true});
    await setLog('2026-10-05', {'rest_day': true});
    await RestDays.start(uid);
    expect(await RestDays.leftThisMonth(uid), 0);
    // Starting again on a day that already is one is fine.
    await RestDays.start(uid);
    await RestDays.end(uid);
    expect((await log(w.today))!['rest_day'], isFalse);
    expect(await RestDays.leftThisMonth(uid), 1);
  });

  test('keysFrom picks out rest days', () {
    expect(
      RestDays.keysFrom([
        {'date_key': '2026-10-05', 'rest_day': true},
        {'date_key': '2026-10-06', 'finished': true},
        null,
        {'date_key': '2026-10-07', 'rest_day': false},
      ]),
      {'2026-10-05'},
    );
  });

  test('streaks read from daily_logs skip rest days', () async {
    // Finished Mon–Wed, rest day Thursday, today (Fri) not finished yet.
    await setLog('2026-10-05', {'finished': true});
    await setLog('2026-10-06', {'finished': true});
    await setLog('2026-10-07', {'finished': true});
    await setLog('2026-10-08', {'rest_day': true});
    final r = await LeaderboardService.streakFor(uid);
    expect(r.current, 3);
    expect(r.rested, {'2026-10-08'});
    expect(r.frozen, isEmpty);
  });

  test('dateKey helper agrees with the test clock', () {
    expect(BalanceService.dateKey(w.now), '2026-10-09');
  });
}
