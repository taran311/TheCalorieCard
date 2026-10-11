import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

/// Thrown by [RestDays.start] when this week's rest days are used up.
class RestDayLimitReached implements Exception {
  const RestDayLimitReached();

  @override
  String toString() => "You've used both rest days this week.";
}

/// Rest days: "freeze the card" for a holiday or a celebration.
///
/// Today is marked with `rest_day: true` on its `daily_logs/{uid}_{date}`
/// doc. While it's on, food can't be added, and streaks skip the day (see
/// Streaks.compute): paused, not broken. Up to [maxPerWeek] per
/// Monday–Sunday week, and only today can be started or ended.
class RestDays {
  RestDays._();

  static const maxPerWeek = 2;

  /// True if a `daily_logs` doc's data marks a rest day.
  static bool isRest(Map<String, dynamic>? log) => log?['rest_day'] == true;

  /// The Monday that starts [day]'s week (midnight).
  static DateTime weekStart(DateTime day) {
    final d = BalanceService.startOfDay(day);
    return BalanceService.addDays(d, -(d.weekday - 1));
  }

  /// Date keys of the `daily_logs` docs in [logs] that are rest days.
  static Set<String> keysFrom(Iterable<Map<String, dynamic>?> logs) => {
        for (final log in logs)
          if (isRest(log) && (log?['date_key'] ?? '').toString().isNotEmpty)
            log!['date_key'].toString(),
      };

  static DocumentReference<Map<String, dynamic>> _ref(
          String uid, DateTime day) =>
      BalanceService.db
          .collection('daily_logs')
          .doc('${uid}_${BalanceService.dateKey(day)}');

  /// Rest days taken in the Monday–Sunday week [day] falls in (default:
  /// this week), as date keys.
  static Future<Set<String>> takenInWeek(String uid, {DateTime? day}) async {
    final monday = weekStart(day ?? BalanceService.now());
    final snaps = await Future.wait([
      for (var i = 0; i < 7; i++)
        _ref(uid, BalanceService.addDays(monday, i)).get(),
    ]);
    return {
      for (var i = 0; i < 7; i++)
        if (isRest(snaps[i].data()))
          BalanceService.dateKey(BalanceService.addDays(monday, i)),
    };
  }

  /// How many more rest days can be taken this week. Today counts as
  /// taken if it already is one.
  static Future<int> leftThisWeek(String uid) async {
    final taken = await takenInWeek(uid);
    final left = maxPerWeek - taken.length;
    return left < 0 ? 0 : left;
  }

  /// Makes today a rest day. Throws [RestDayLimitReached] if this week's
  /// are used up (doing it again on a day that already is one is fine).
  static Future<void> start(String uid) async {
    final today = BalanceService.startOfDay(BalanceService.now());
    final key = BalanceService.dateKey(today);
    final taken = await takenInWeek(uid, day: today);
    if (!taken.contains(key) && taken.length >= maxPerWeek) {
      throw const RestDayLimitReached();
    }
    await _write(uid, today, true);
  }

  /// Ends today's rest day ("Unfreeze"): today is a normal day again.
  static Future<void> end(String uid) =>
      _write(uid, BalanceService.startOfDay(BalanceService.now()), false);

  /// Merged into the day's doc, with the same user_id / date_key / date
  /// fields as the Card screen's other daily_logs writes.
  static Future<void> _write(String uid, DateTime day, bool rest) {
    return _ref(uid, day).set({
      'user_id': uid,
      'date_key': BalanceService.dateKey(day),
      'date': Timestamp.fromDate(day),
      'rest_day': rest,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
