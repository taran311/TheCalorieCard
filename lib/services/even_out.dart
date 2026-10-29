import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/coach_service.dart';

/// A "Spread it over the week" plan, from `user_data.even_out`:
///   {per_day: 80, from: '2026-10-13', until: '2026-10-18',
///    over_by: 320, set_on: '2026-10-12'}
/// Each day from [from] to [until] starts [perDay] kcal lower
/// (BalanceService.evenOutToday applies it when the card resets).
class EvenOutPlan {
  final int perDay;
  final String from;
  final String until;
  final int overBy;
  final String setOn;

  const EvenOutPlan({
    required this.perDay,
    required this.from,
    required this.until,
    required this.overBy,
    required this.setOn,
  });

  static EvenOutPlan? fromData(Map<String, dynamic>? data) {
    final e = data?['even_out'];
    if (e is! Map) return null;
    final perDay = (BalanceService.number(e['per_day']) ?? 0).round();
    final from = '${e['from'] ?? ''}';
    final until = '${e['until'] ?? ''}';
    if (perDay <= 0 || from.isEmpty || until.isEmpty) return null;
    return EvenOutPlan(
      perDay: perDay,
      from: from,
      until: until,
      overBy: (BalanceService.number(e['over_by']) ?? 0).round(),
      setOn: '${e['set_on'] ?? ''}',
    );
  }

  bool activeOn(String day) =>
      day.compareTo(from) >= 0 && day.compareTo(until) <= 0;

  /// Over: [day] comes after its last day.
  bool endedBefore(String day) => day.compareTo(until) > 0;

  static DateTime? _parse(String key) => DateTime.tryParse(key);

  /// Days it runs for in total.
  int get days {
    final a = _parse(from), b = _parse(until);
    if (a == null || b == null) return 0;
    return b.difference(a).inDays + 1;
  }

  /// Days still to come after [day] (not counting [day] itself).
  int daysAfter(String day) {
    final d = _parse(day), b = _parse(until);
    if (d == null || b == null) return 0;
    return max(0, b.difference(d).inDays);
  }
}

class EvenOut {
  EvenOut._();

  /// A day's budget is never taken below this by a plan.
  static const minBudget = 1200;

  /// kcal a day for going [overBy] over a [goal] budget: the same gentle
  /// plan the card suggests (at most 10% of the goal, 200 kcal), and never
  /// below [minBudget].
  static int perDayFor(int overBy, double goal, DateTime today) {
    final plan = OffsetPlan.compute(overBy: overBy, goal: goal, today: today);
    var perDay = plan.perDay;
    if (goal - perDay < minBudget) perDay = max(0, (goal - minBudget).floor());
    return perDay;
  }

  static Stream<EvenOutPlan?> watch(String uid) => BalanceService.db
      .collection('user_data')
      .where('user_id', isEqualTo: uid)
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isEmpty ? null : EvenOutPlan.fromData(s.docs.first.data()));

  /// What [start] would set up for going [overBy] over today: the rest of
  /// an [old] plan still running joins it. Null if there's nothing to
  /// spread.
  static ({int perDay, int days, int total})? preview(EvenOutPlan? old,
      {required int overBy, required double goal, required DateTime now}) {
    final todayKey = BalanceService.dateKey(BalanceService.startOfDay(now));
    final carried = old != null && !old.endedBefore(todayKey)
        ? old.perDay * old.daysAfter(todayKey)
        : 0;
    final total = max(0, overBy) + carried;
    final days = OffsetPlan.compute(overBy: total, goal: goal, today: now).days;
    final perDay = perDayFor(total, goal, now);
    if (overBy <= 0 || perDay <= 0 || days <= 0) return null;
    return (perDay: perDay, days: days, total: total);
  }

  /// Starts (or replaces) a plan for going [overBy] over today: from
  /// tomorrow to the end of the week (all next week on a Sunday). Null if
  /// there's nothing to spread.
  static Future<EvenOutPlan?> start(String uid,
      {required int overBy, required double goal}) async {
    final now = BalanceService.now();
    final today = BalanceService.startOfDay(now);
    final todayKey = BalanceService.dateKey(today);
    final doc = await BalanceService.userDataDoc(uid);
    if (doc == null) return null;

    final p = preview(EvenOutPlan.fromData(doc.data()),
        overBy: overBy, goal: goal, now: now);
    if (p == null) return null;
    final (:perDay, :days, :total) = p;
    final from = BalanceService.addDays(today, 1);
    final plan = EvenOutPlan(
      perDay: perDay,
      from: BalanceService.dateKey(from),
      until: BalanceService.dateKey(BalanceService.addDays(from, days - 1)),
      overBy: total,
      setOn: todayKey,
    );
    await doc.reference.update({
      'even_out': {
        'per_day': plan.perDay,
        'from': plan.from,
        'until': plan.until,
        'over_by': plan.overBy,
        'set_on': plan.setOn,
      },
    });
    return plan;
  }

  /// Stops the plan. If it had already taken today's kcal off the card,
  /// they go back on. Returns the kcal given back today.
  static Future<int> stop(String uid) async {
    final doc = await BalanceService.userDataDoc(uid);
    if (doc == null) return 0;
    final data = doc.data() ?? const <String, dynamic>{};
    final today = BalanceService.dateKey(BalanceService.now());
    final appliedToday = data['balance_date'] == today
        ? BalanceService.evenOutToday(data).round()
        : 0;
    await doc.reference.update({
      'even_out': FieldValue.delete(),
      if (appliedToday > 0) 'calories': FieldValue.increment(appliedToday),
    });
    return appliedToday;
  }
}
