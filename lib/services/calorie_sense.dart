import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

/// "Guess the price": how well you can estimate calories before the lookup
/// comes back. Scores feed the Calorie Sense hiscore.
///
/// Only a monthly running total is stored, on your `users` document (which
/// friends can already read for hiscores):
///   calorie_sense: {month: '2026-10', total: 812, count: 10}
class CalorieSense {
  CalorieSense._();

  /// 0-100: how close [guess] was to [actual]. Within 10% scores 90+.
  /// Small foods are judged against at least 50 kcal, so being 20 kcal off
  /// on a 10 kcal coffee isn't a zero.
  static int score(double guess, double actual) {
    if (!guess.isFinite || !actual.isFinite || actual < 0 || guess < 0) {
      return 0;
    }
    final error = (guess - actual).abs() / (actual < 50 ? 50 : actual);
    final raw = (100 * (1 - error)).round();
    return raw < 0 ? 0 : (raw > 100 ? 100 : raw);
  }

  /// A friendly verdict for a score.
  static String verdict(int score) {
    if (score >= 95) return 'Bang on!';
    if (score >= 85) return 'So close';
    if (score >= 70) return 'Not bad';
    if (score >= 50) return 'Bit off';
    return 'Way off';
  }

  static String monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  /// Adds a scored guess to this month's running total.
  static Future<void> record(String uid, int score) async {
    final ref = BalanceService.db.collection('users').doc(uid);
    final month = monthKey(BalanceService.now());
    await BalanceService.db.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      final current = snap.data()?['calorie_sense'];
      final sameMonth = current is Map && current['month'] == month;
      final double total =
          sameMonth ? (BalanceService.number(current['total']) ?? 0) : 0;
      final double count =
          sameMonth ? (BalanceService.number(current['count']) ?? 0) : 0;
      final newTotal = total + score;
      final newCount = count + 1;
      final value = <String, dynamic>{
        'calorie_sense': {
          'month': month,
          'total': newTotal,
          'count': newCount,
        },
        // 10+ guesses averaging 75%+ in a month unlocks the Sunset card,
        // and it's kept for good.
        if (newCount >= 10 && newTotal / newCount >= 75)
          'card_unlocks': FieldValue.arrayUnion(['sunset']),
      };
      if (snap.exists) {
        tx.update(ref, value);
      } else {
        tx.set(ref, value, SetOptions(merge: true));
      }
    });
  }

  /// This month's average score and number of guesses, from a `users` doc.
  static ({double average, int count}) thisMonth(Map<String, dynamic>? user) {
    final s = user?['calorie_sense'];
    if (s is! Map || s['month'] != monthKey(BalanceService.now())) {
      return (average: 0, count: 0);
    }
    final count = (BalanceService.number(s['count']) ?? 0).round();
    final total = BalanceService.number(s['total']) ?? 0;
    return (average: count > 0 ? total / count : 0, count: count);
  }
}
