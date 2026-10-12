import 'package:namer_app/services/analytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/achievement_service.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/leaderboard_service.dart';
import 'package:namer_app/services/rest_days.dart';

/// Closing yesterday, today: forgetting to tap Close shouldn't cost a
/// streak. Only yesterday, only until midnight, and only if food was
/// logged, so nobody can go back and rewrite last week.
class LateClose {
  LateClose._();

  static DateTime _yesterday() => BalanceService.addDays(
      BalanceService.startOfDay(BalanceService.now()), -1);

  static DocumentReference<Map<String, dynamic>> _log(String uid, DateTime d) =>
      BalanceService.db
          .collection('daily_logs')
          .doc('${uid}_${BalanceService.dateKey(d)}');

  /// Whether yesterday's day log, plus whether food was logged, leaves it
  /// open to close: food logged, not closed, not a rest day.
  static bool canClose(Map<String, dynamic>? log, {required bool hadFood}) =>
      hadFood && log?['finished'] != true && !RestDays.isRest(log);

  /// Yesterday's date if it can still be closed, otherwise null.
  static Future<DateTime?> openYesterday(String uid) async {
    final day = _yesterday();
    final log = (await _log(uid, day).get()).data();
    if (log?['finished'] == true || RestDays.isRest(log)) return null;
    final entries = await BalanceService.entriesOn(uid, day);
    final hadFood =
        entries.any((d) => '${d.data()['foodCategory'] ?? ''}' != 'Recipe');
    return canClose(log, hadFood: hadFood) ? day : null;
  }

  /// Closes yesterday, as if it had been closed on time. Returns false if
  /// it can't be (already closed, a rest day, or it's no longer yesterday).
  static Future<bool> closeYesterday(String uid, DateTime day) async {
    if (BalanceService.dateKey(day) != BalanceService.dateKey(_yesterday())) {
      return false;
    }
    final ref = _log(uid, day);
    final snap = await ref.get();
    final log = snap.data();
    if (log?['finished'] == true || RestDays.isRest(log)) return false;

    // The day's own snapshot (its closing balance and goal) was saved as
    // food was logged yesterday, so it's kept as it is. Only a day with no
    // snapshot gets its foods and totals filled in here.
    final fill = <String, dynamic>{};
    if (!snap.exists || log?['totals'] == null) {
      final docs = await BalanceService.entriesOn(uid, day);
      final totals = BalanceService.totalOf(docs.map((d) => d.data()));
      fill['food_entries'] = [
        for (final d in docs) {'id': d.id, ...d.data()}
      ];
      fill['totals'] = {
        'calories': totals.calories,
        'protein': totals.protein,
        'carbs': totals.carbs,
        'fat': totals.fat,
      };
    }
    await ref.set({
      'user_id': uid,
      'date_key': BalanceService.dateKey(day),
      'date': Timestamp.fromDate(day),
      'finished': true,
      'closed_late': true,
      ...fill,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    Analytics.track('day_closed');

    // Streak, best streak and achievements catch up straight away.
    try {
      await MyStreak.load(uid, force: true);
    } catch (_) {}
    try {
      await LeaderboardService.refreshMine(uid);
    } catch (_) {}
    try {
      await AchievementService.updateAchievementsForUser(uid);
    } catch (_) {}
    return true;
  }
}
