import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/calorie_sense.dart';
import 'package:namer_app/services/card_design_service.dart';

/// Everything the hiscores need for one person.
class PlayerStats {
  final String userId;
  final String name;
  final bool isMe;

  /// Finished days logged this calendar month.
  final int daysLogged;

  /// Finished days this month that ended with the card not overdrawn.
  final int daysOnBudget;

  /// Consecutive finished days, ending today or yesterday.
  final int streak;

  /// Protein logged since Monday, in grams.
  final double proteinThisWeek;

  /// Average "guess the price" score this month (0-100), and how many
  /// guesses it's based on.
  final double calorieSense;
  final int senseGuesses;

  const PlayerStats({
    required this.userId,
    required this.name,
    required this.isMe,
    required this.daysLogged,
    required this.daysOnBudget,
    required this.streak,
    required this.proteinThisWeek,
    this.calorieSense = 0,
    this.senseGuesses = 0,
  });
}

/// Builds friend leaderboards. Every request for every friend runs at the
/// same time, instead of one after another like before.
class LeaderboardService {
  LeaderboardService._();

  static FirebaseFirestore get _db => BalanceService.db;

  /// How far back we look for streaks.
  static const _streakLookbackDays = 40;

  static String displayName(String? email) {
    if (email == null || email.isEmpty) return 'Unknown';
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  static Future<List<PlayerStats>> load({
    required String myUserId,
    required List<String> friendIds,
  }) {
    final ids = <String>{myUserId, ...friendIds}.toList();
    return Future.wait(ids.map((id) => _loadOne(id, id == myUserId)));
  }

  /// Recomputes your own stats, which also records your best streak (it
  /// unlocks card designs). Called when you finish a day.
  static Future<void> refreshMine(String uid) => _loadOne(uid, true);

  static Future<PlayerStats> _loadOne(String userId, bool isMe) async {
    final now = BalanceService.now();
    final today = BalanceService.startOfDay(now);
    final monthStart = DateTime(now.year, now.month, 1);
    final weekStart = BalanceService.addDays(today, -(today.weekday - 1));

    // Days so far this month (today.day), or the streak window if longer.
    final lookback =
        now.day > _streakLookbackDays ? now.day : _streakLookbackDays;
    final days = [
      for (var i = 0; i < lookback; i++) BalanceService.addDays(today, -i),
    ];

    final userFuture = _db.collection('users').doc(userId).get();
    // Only this week's food is needed (for protein), not the whole history.
    final foodFuture = BalanceService.entriesBetween(
        userId, weekStart, BalanceService.addDays(today, 1));
    final logFutures = [
      for (final d in days)
        _db
            .collection('daily_logs')
            .doc('${userId}_${BalanceService.dateKey(d)}')
            .get(),
    ];

    final userDoc = await userFuture;
    final logs = await Future.wait(logFutures);

    // Which days were "finished", and did they end on budget?
    final finished = <String, bool>{}; // dateKey -> onBudget
    for (final doc in logs) {
      final data = doc.data();
      if (data == null || data['finished'] != true) continue;
      final key = (data['date_key'] ?? '').toString();
      final balances = data['balances'];
      final remaining =
          balances is Map ? balances['calories'] : null;
      final onBudget = remaining is num ? remaining >= 0 : false;
      finished[key] = onBudget;
    }

    var daysLogged = 0;
    var daysOnBudget = 0;
    for (final d in days) {
      if (d.isBefore(monthStart)) continue;
      final key = BalanceService.dateKey(d);
      if (finished.containsKey(key)) {
        daysLogged++;
        if (finished[key] == true) daysOnBudget++;
      }
    }

    // Streak: today counts if finished; if not, the streak can still be
    // alive from yesterday (today isn't over yet).
    var streak = 0;
    final start = finished.containsKey(BalanceService.dateKey(today)) ? 0 : 1;
    for (var i = start; i < days.length; i++) {
      if (finished.containsKey(BalanceService.dateKey(days[i]))) {
        streak++;
      } else {
        break;
      }
    }

    double protein = 0;
    try {
      final food = await foodFuture;
      for (final doc in food) {
        protein += BalanceService.number(doc.data()['food_protein']) ?? 0;
      }
    } catch (_) {
      // Leave protein at 0 if this friend's food can't be read.
    }

    if (isMe) {
      // Longest streak unlocks card designs; not worth failing hiscores over.
      CardDesignService.recordStreak(userId, streak).catchError((_) {});
    }
    final sense = CalorieSense.thisMonth(userDoc.data());

    return PlayerStats(
      userId: userId,
      name: isMe
          ? 'You'
          : displayName(userDoc.data()?['email'] as String?),
      isMe: isMe,
      daysLogged: daysLogged,
      daysOnBudget: daysOnBudget,
      streak: streak,
      proteinThisWeek: protein,
      calorieSense: sense.average,
      senseGuesses: sense.count,
    );
  }
}
