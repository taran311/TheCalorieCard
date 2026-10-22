import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

/// Thrown by [RestDays.start] when this month's rest days are used up.
class RestDayLimitReached implements Exception {
  const RestDayLimitReached();

  @override
  String toString() => "You've used all your rest days this month.";
}

/// Thrown by [RestDays.start] and [RestDays.end] for a day that can't be
/// changed any more (only today and yesterday can).
class RestDayTooLate implements Exception {
  const RestDayTooLate();

  @override
  String toString() => 'Only today or yesterday can be a rest day.';
}

/// Rest days: "freeze the card" for a holiday, a celebration or a refeed.
///
/// A day is marked with `rest_day: true` on its `daily_logs/{uid}_{date}`
/// doc. While it's on, food can't be added, and streaks skip the day (see
/// Streaks.compute): paused, not broken. Up to [maxPerMonth] per calendar
/// month, taken together (a long weekend away) or spread out. Today can be
/// started or ended, and so can yesterday until midnight (forgot to take
/// it), like closing yesterday late. Nothing further back.
class RestDays {
  RestDays._();

  /// About one a week on average, without making routine weekend skips
  /// free (which would hide the days people most often overeat).
  static const maxPerMonth = 4;

  /// True if a `daily_logs` doc's data marks a rest day.
  static bool isRest(Map<String, dynamic>? log) => log?['rest_day'] == true;

  /// "2026-10" for any day in October 2026.
  static String monthKey(DateTime day) =>
      BalanceService.dateKey(day).substring(0, 7);

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

  /// Rest days taken in the calendar month [day] falls in (default: this
  /// month), as date keys.
  static Future<Set<String>> takenInMonth(String uid, {DateTime? day}) async {
    final month = monthKey(day ?? BalanceService.now());
    final snap = await BalanceService.db
        .collection('daily_logs')
        .where('user_id', isEqualTo: uid)
        .where('rest_day', isEqualTo: true)
        .get();
    return {
      for (final key in keysFrom(snap.docs.map((d) => d.data())))
        if (key.startsWith(month)) key,
    };
  }

  /// How many more rest days can be taken in [day]'s month (default this
  /// month). A day that already is one counts as taken.
  static Future<int> leftThisMonth(String uid, {DateTime? day}) async {
    final taken = await takenInMonth(uid, day: day);
    final left = maxPerMonth - taken.length;
    return left < 0 ? 0 : left;
  }

  /// [day] (default today) as the start of its day, if it can still be
  /// changed: today or yesterday. Otherwise throws [RestDayTooLate].
  static DateTime _changeable(DateTime? day) {
    final today = BalanceService.startOfDay(BalanceService.now());
    final d = BalanceService.startOfDay(day ?? today);
    final key = BalanceService.dateKey(d);
    if (key != BalanceService.dateKey(today) &&
        key != BalanceService.dateKey(BalanceService.addDays(today, -1))) {
      throw const RestDayTooLate();
    }
    return d;
  }

  /// Makes [day] (today, or yesterday) a rest day. Throws
  /// [RestDayLimitReached] if that month's are used up (doing it again on
  /// a day that already is one is fine), or [RestDayTooLate].
  static Future<void> start(String uid, {DateTime? day}) async {
    final d = _changeable(day);
    final key = BalanceService.dateKey(d);
    final taken = await takenInMonth(uid, day: d);
    if (!taken.contains(key) && taken.length >= maxPerMonth) {
      throw const RestDayLimitReached();
    }
    await _write(uid, d, true);
  }

  /// Ends [day]'s rest day (today, or yesterday): a normal day again.
  static Future<void> end(String uid, {DateTime? day}) =>
      _write(uid, _changeable(day), false);

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
