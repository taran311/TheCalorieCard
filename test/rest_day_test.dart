// Rest days ("freeze card"): today only, at most 2 per Monday–Sunday week,
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
    // Friday 9 Oct 2026, noon. Its week runs Mon 5 – Sun 11 Oct.
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

  test('the week starts on Monday', () {
    expect(RestDays.weekStart(DateTime(2026, 10, 9, 15)),
        DateTime(2026, 10, 5));
    expect(RestDays.weekStart(DateTime(2026, 10, 5)), DateTime(2026, 10, 5));
    expect(RestDays.weekStart(DateTime(2026, 10, 11, 23)),
        DateTime(2026, 10, 5));
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
    expect(await RestDays.leftThisWeek(uid), 1);
  });

  test('a third rest day in the same week is refused', () async {
    await setLog('2026-10-05', {'rest_day': true});
    await setLog('2026-10-06', {'rest_day': true});
    expect(await RestDays.leftThisWeek(uid), 0);
    await expectLater(
        RestDays.start(uid), throwsA(isA<RestDayLimitReached>()));
    expect(RestDays.isRest(await log(w.today)), isFalse);
  });

  test("last week's rest days don't count", () async {
    await setLog('2026-10-03', {'rest_day': true});
    await setLog('2026-10-04', {'rest_day': true});
    expect(await RestDays.leftThisWeek(uid), 2);
    await RestDays.start(uid);
    expect(RestDays.isRest(await log(w.today)), isTrue);
  });

  test('an ended rest day frees the slot again', () async {
    await setLog('2026-10-05', {'rest_day': true});
    await RestDays.start(uid);
    expect(await RestDays.leftThisWeek(uid), 0);
    // Starting again on a day that already is one is fine.
    await RestDays.start(uid);
    await RestDays.end(uid);
    expect((await log(w.today))!['rest_day'], isFalse);
    expect(await RestDays.leftThisWeek(uid), 1);
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
