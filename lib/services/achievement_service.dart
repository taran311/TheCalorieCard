import 'package:cloud_firestore/cloud_firestore.dart';

class AchievementService {
  static Future<void> markFirstTimeLogger(String userId) async {
    final docRef =
        FirebaseFirestore.instance.collection('user_achievements').doc(userId);
    await docRef.set({
      'first_time_logger': true,
      'first_time_logger_unlocked_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamUserAchievements(
      String userId) {
    return FirebaseFirestore.instance
        .collection('user_achievements')
        .doc(userId)
        .snapshots();
  }

  static Future<void> updateAchievementsForUser(String userId) async {
    final logsSnapshot = await FirebaseFirestore.instance
        .collection('daily_logs')
        .where('user_id', isEqualTo: userId)
        .where('finished', isEqualTo: true)
        .get();

    final logs = logsSnapshot.docs.map((doc) {
      final data = doc.data();
      final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime(1970);
      final totals = (data['totals'] as Map<String, dynamic>?) ?? {};
      final calories = (totals['calories'] as num?)?.toDouble() ?? 0;
      final protein = (totals['protein'] as num?)?.toDouble() ?? 0;
      final carbs = (totals['carbs'] as num?)?.toDouble() ?? 0;
      return _DailyLogSummary(
        date: DateTime(date.year, date.month, date.day),
        calories: calories,
        protein: protein,
        carbs: carbs,
      );
    }).toList();

    logs.sort((a, b) => a.date.compareTo(b.date));

    bool anyCarbZero = logs.any((l) => l.carbs == 0);
    int ketoStreak = _maxConsecutive(logs, (l) => l.carbs == 0);

    bool anyCalZero = logs.any((l) => l.calories == 0);
    int calZeroStreak = _maxConsecutive(logs, (l) => l.calories == 0);

    final now = DateTime.now();
    final calZeroThisMonth = logs
      .where((l) =>
        l.calories == 0 &&
        l.date.year == now.year &&
        l.date.month == now.month)
      .length;

    int proteinStreak =
        _maxConsecutive(logs, (l) => l.protein > 150);

    final updates = <String, dynamic>{};

    if (anyCarbZero) {
      updates['keto_novice'] = true;
      updates['keto_novice_unlocked_at'] = FieldValue.serverTimestamp();
    }
    if (ketoStreak >= 7) {
      updates['keto_apprentice'] = true;
      updates['keto_apprentice_unlocked_at'] = FieldValue.serverTimestamp();
    }
    if (ketoStreak >= 30) {
      updates['keto_expert'] = true;
      updates['keto_expert_unlocked_at'] = FieldValue.serverTimestamp();
    }

    if (anyCalZero) {
      updates['fast_1'] = true;
      updates['fast_1_unlocked_at'] = FieldValue.serverTimestamp();
    }
    if (calZeroStreak >= 2) {
      updates['fast_2'] = true;
      updates['fast_2_unlocked_at'] = FieldValue.serverTimestamp();
    }
    if (calZeroThisMonth >= 4) {
      updates['fast_4_month'] = true;
      updates['fast_4_month_unlocked_at'] = FieldValue.serverTimestamp();
    }

    if (proteinStreak >= 7) {
      updates['cultivating_mass'] = true;
      updates['cultivating_mass_unlocked_at'] = FieldValue.serverTimestamp();
    }

    if (updates.isNotEmpty) {
      final docRef = FirebaseFirestore.instance
          .collection('user_achievements')
          .doc(userId);
      await docRef.set(updates, SetOptions(merge: true));
    }
  }

  static int _maxConsecutive(
      List<_DailyLogSummary> logs, bool Function(_DailyLogSummary) test) {
    int maxStreak = 0;
    int currentStreak = 0;
    DateTime? prevDate;
    bool prevMatched = false;

    for (final log in logs) {
      final matched = test(log);
      if (matched) {
        if (prevDate != null &&
            prevMatched &&
            log.date.difference(prevDate).inDays == 1) {
          currentStreak += 1;
        } else {
          currentStreak = 1;
        }
        maxStreak = currentStreak > maxStreak ? currentStreak : maxStreak;
      } else {
        currentStreak = 0;
      }

      prevDate = log.date;
      prevMatched = matched;
    }

    return maxStreak;
  }
}

class _DailyLogSummary {
  final DateTime date;
  final double calories;
  final double protein;
  final double carbs;

  _DailyLogSummary({
    required this.date,
    required this.calories,
    required this.protein,
    required this.carbs,
  });
}
