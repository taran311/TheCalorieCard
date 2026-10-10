import 'package:namer_app/services/statement_service.dart';

/// Foods you've logged before, for one-tap re-adding on Add food: the
/// "Or add again" chips and the suggestions while you type.
///
/// Nothing here is looked up again: a food comes back with exactly the
/// numbers it was logged with.
class FoodHistory {
  /// Every food logged in the window, newest first (recipes left out:
  /// they're logged from Recipes).
  final List<CardTransaction> foods;

  const FoodHistory(this.foods);

  static const empty = FoodHistory([]);

  /// How far back suggestions look.
  static const days = 90;

  /// Loads the last [days] days for [uid].
  static Future<FoodHistory> load(String uid) async {
    // Only the foods are needed: skip the 90 per-day daily_logs reads.
    final statement =
        await StatementService.load(uid, days: days, withLogs: false);
    return FoodHistory([
      for (final tx in statement.recent)
        if (!tx.description.startsWith('Recipe:') &&
            tx.description.trim().isNotEmpty)
          tx
    ]);
  }

  /// Same food, same portion: one suggestion.
  static String keyOf(CardTransaction tx) =>
      '${tx.description.trim().toLowerCase()}|${tx.portion.trim().toLowerCase()}';

  /// Up to [limit] foods to offer again for [meal]: the ones logged most
  /// often for that meal first, then the most recent. Each food appears
  /// once, with the numbers from the last time it was logged.
  static List<CardTransaction> rankForMeal(
    List<CardTransaction> foods,
    String meal, {
    int limit = 10,
  }) {
    final wanted = meal.trim().toLowerCase();
    final latest = <String, CardTransaction>{};
    final order = <String, int>{}; // position of the latest (0 = newest)
    final counts = <String, int>{};
    final sorted = [...foods]..sort((a, b) => b.time.compareTo(a.time));
    for (final tx in sorted) {
      final key = keyOf(tx);
      if (!latest.containsKey(key)) {
        latest[key] = tx;
        order[key] = order.length;
      }
      if (tx.category.trim().toLowerCase() == wanted) {
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }
    final keys = latest.keys.toList()
      ..sort((a, b) {
        final byCount = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
        if (byCount != 0) return byCount;
        return order[a]!.compareTo(order[b]!);
      });
    return [for (final k in keys.take(limit)) latest[k]!];
  }

  /// Up to [limit] past foods whose name contains [query] (ignoring
  /// case), most recent first, each food once. Needs 2+ letters.
  static List<CardTransaction> search(
    List<CardTransaction> foods,
    String query, {
    int limit = 5,
  }) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    final seen = <String>{};
    final out = <CardTransaction>[];
    final sorted = [...foods]..sort((a, b) => b.time.compareTo(a.time));
    for (final tx in sorted) {
      if (!tx.description.toLowerCase().contains(q)) continue;
      if (!seen.add(keyOf(tx))) continue;
      out.add(tx);
      if (out.length >= limit) break;
    }
    return out;
  }
}
