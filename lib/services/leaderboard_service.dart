import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

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

  const PlayerStats({
    required this.userId,
    required this.name,
    required this.isMe,
    required this.daysLogged,
    required this.daysOnBudget,
    required this.streak,
    required this.proteinThisWeek,
  });
}

/// Builds friend leaderboards. Every request for every friend runs at the
/// same time, instead of one after another like before.
class LeaderboardService {
  LeaderboardService._();

  static final _db = FirebaseFirestore.instance;

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

  static Future<PlayerStats> _loadOne(String userId, bool isMe) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));

    final lookback = today.difference(monthStart).inDays + 1 >
            _streakLookbackDays
        ? today.difference(monthStart).inDays + 1
        : _streakLookbackDays;
    final days = [
      for (var i = 0; i < lookback; i++) today.subtract(Duration(days: i)),
    ];

    final userFuture = _db.collection('users').doc(userId).get();
    final foodFuture =
        _db.collection('user_food').where('user_id', isEqualTo: userId).get();
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
      for (final doc in food.docs) {
        final data = doc.data();
        if (data['foodCategory'] == BalanceService.recipeCategory) continue;
        final t = BalanceService.entryDate(data);
        if (t == null || t.isBefore(weekStart)) continue;
        final p = data['food_protein'];
        if (p is num) protein += p.toDouble();
      }
    } catch (_) {
      // Leave protein at 0 if this friend's food can't be read.
    }

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
    );
  }
}
