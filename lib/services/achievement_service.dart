import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/achievements.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/calorie_sense.dart';
import 'package:namer_app/services/challenge_service.dart';

/// Stores achievements on `user_achievements/{uid}`:
///   <id>: true, <id>_unlocked_at: timestamp   (kept for good once earned)
///   progress: {<id>: number}                  (so friends can see it too)
///   stats: {foods_logged, scans, splits, ...} (running counters)
class AchievementService {
  AchievementService._();

  static DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      BalanceService.db.collection('user_achievements').doc(uid);

  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamUserAchievements(
          String userId) =>
      _doc(userId).snapshots();

  /// Adds to a running counter (e.g. 'splits', 'pot_spends'). Never throws:
  /// a missed count isn't worth failing the action that earned it.
  static Future<void> bump(String uid, String counter, [int by = 1]) async {
    if (by <= 0) return;
    try {
      await _doc(uid).set({
        'stats': {counter: FieldValue.increment(by)},
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Called after food is logged: unlocks "First Swipe" straight away and
  /// counts foods (and barcode scans).
  static Future<void> recordLogging(String uid,
      {int foods = 1, int scans = 0}) async {
    try {
      await _doc(uid).set({
        'first_time_logger': true,
        'stats': {
          'foods_logged': FieldValue.increment(foods),
          if (scans > 0) 'scans': FieldValue.increment(scans),
        },
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Kept for older callers.
  static Future<void> markFirstTimeLogger(String userId) =>
      recordLogging(userId, foods: 0);

  /// Re-checks every achievement. Returns the ones unlocked just now.
  static Future<List<Achievement>> updateAchievementsForUser(String userId) =>
      evaluate(userId);

  /// Works out progress from your history, saves it, and unlocks anything
  /// newly earned. Returns the newly unlocked achievements.
  static Future<List<Achievement>> evaluate(String uid) async {
    final db = BalanceService.db;
    final results = await Future.wait<Object?>([
      _doc(uid).get(),
      db
          .collection('daily_logs')
          .where('user_id', isEqualTo: uid)
          .where('finished', isEqualTo: true)
          .get(),
      db.collection('users').doc(uid).get(),
      BalanceService.userDataDoc(uid),
      _safe(() => db
          .collection('direct_debits')
          .where('user_id', isEqualTo: uid)
          .limit(1)
          .get()),
      _safe(() => db
          .collection('recipes')
          .where('user_id', isEqualTo: uid)
          .limit(1)
          .get()),
    ]);

    final achData =
        (results[0] as DocumentSnapshot<Map<String, dynamic>>).data() ??
            const <String, dynamic>{};
    final logs = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final user =
        (results[2] as DocumentSnapshot<Map<String, dynamic>>).data() ??
            const <String, dynamic>{};
    final profile =
        (results[3] as DocumentSnapshot<Map<String, dynamic>>?)?.data() ??
            const <String, dynamic>{};
    final debits = results[4] as QuerySnapshot<Map<String, dynamic>>?;
    final recipes = results[5] as QuerySnapshot<Map<String, dynamic>>?;

    final already = <String>{
      for (final a in Achievements.all)
        if (achData[a.id] == true) a.id
    };

    final days = [
      for (final d in logs.docs)
        if (AchievementDay.fromLog(d.data(), fallbackGoals: profile) != null)
          AchievementDay.fromLog(d.data(), fallbackGoals: profile)!
    ];

    final statsRaw = achData['stats'];
    final counters = <String, num>{
      if (statsRaw is Map)
        for (final e in statsRaw.entries)
          if (e.value is num) '${e.key}': e.value as num
    };

    final friends = user['friends'];
    final sense = CalorieSense.thisMonth(user);
    final design = user['card_design'];

    final challenge = await _challengeResults(uid, already);

    final progress = AchievementEngine.progress(AchievementInputs(
      days: days,
      counters: counters,
      friendCount: friends is List ? friends.length : 0,
      customCard: design is String && design.isNotEmpty && design != 'midnight',
      calorieSenseAverage: sense.average,
      calorieSenseCount: sense.count,
      hasDirectDebit: debits?.docs.isNotEmpty ?? false,
      pot: BalanceService.potFrom(profile),
      inChallenge: challenge.inChallenge,
      wonChallenge: challenge.won,
      teamGoalHit: challenge.teamGoal,
      recipesSaved: recipes?.docs.length ?? 0,
    ));

    final newly = AchievementEngine.unlocked(progress).difference(already);

    await _doc(uid).set({
      'progress': progress,
      'evaluated_at': FieldValue.serverTimestamp(),
      for (final id in newly) ...{
        id: true,
        '${id}_unlocked_at': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));

    return [
      for (final a in Achievements.all)
        if (newly.contains(a.id)) a
    ];
  }

  static Future<T?> _safe<T>(Future<T> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return null;
    }
  }

  /// Challenge achievements from this week's and last week's challenges.
  /// Scores are only fetched for finished challenges, and only while the
  /// related achievements are still locked.
  static Future<({bool inChallenge, bool won, bool teamGoal})>
      _challengeResults(String uid, Set<String> already) async {
    var inChallenge = false, won = false, teamGoal = false;
    try {
      final list = await ChallengeService.forUser(uid).first;
      inChallenge = list.isNotEmpty;
      for (final c in list.where((c) => c.isOver)) {
        final isGroup = c.type == ChallengeType.group;
        if (isGroup && (teamGoal || already.contains('team_goal'))) continue;
        if (!isGroup && (won || already.contains('challenge_win'))) continue;
        final scores = await ChallengeService.scores(c);
        if (scores.isEmpty) continue;
        if (isGroup) {
          final total = scores.fold<int>(0, (s, e) => s + e.finishedDays);
          if (c.target > 0 && total >= c.target) teamGoal = true;
        } else {
          final top = scores.first;
          final outright = top.onBudgetDays > 0 &&
              (scores.length < 2 || scores[1].onBudgetDays < top.onBudgetDays);
          if (outright && top.userId == uid) won = true;
        }
      }
    } catch (_) {}
    return (inChallenge: inChallenge, won: won, teamGoal: teamGoal);
  }
}
