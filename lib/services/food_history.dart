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

  /// Up to [limit] past foods matching what's being typed, most recent
  /// first, each food once. Every word typed has to be in the name
  /// (ignoring case and order), and amounts are left out, so "2 hash br"
  /// finds "3 McCain hash browns". Needs 2+ letters.
  static List<CardTransaction> search(
    List<CardTransaction> foods,
    String query, {
    int limit = 5,
  }) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u00C0-\u024F]+'))
        .where((w) => w.isNotEmpty && !RegExp(r'^\d').hasMatch(w))
        .toList();
    if (words.join().length < 2) return const [];
    final seen = <String>{};
    final out = <CardTransaction>[];
    final sorted = [...foods]..sort((a, b) => b.time.compareTo(a.time));
    for (final tx in sorted) {
      final name = tx.description.toLowerCase();
      if (!words.every(name.contains)) continue;
      if (!seen.add(keyOf(tx))) continue;
      out.add(tx);
      if (out.length >= limit) break;
    }
    return out;
  }

  static String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Exactly this food logged before (same words, ignoring case and
  /// spacing): their own numbers if they've set some, otherwise the latest
  /// one looked up. Reused as it is, so typing it again needs no lookup
  /// (quicker, and no AI cost). Null if it's new.
  static CardTransaction? sameFood(List<CardTransaction> foods, String query) {
    final own = ownNumbersFor(foods, query);
    if (own != null) return own;
    final q = _norm(query);
    if (q.isEmpty) return null;
    CardTransaction? best;
    for (final tx in foods) {
      if (tx.isRecipe || _norm(tx.description) != q) continue;
      if (best == null || tx.time.isAfter(best.time)) best = tx;
    }
    return best;
  }

  /// The person's own numbers for exactly this food, if they've set them
  /// before ("my protein shake" fixed to 210 kcal): the latest such entry
  /// with the same name, ignoring case and spacing. Null otherwise.
  static CardTransaction? ownNumbersFor(
      List<CardTransaction> foods, String query) {
    String norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final q = norm(query);
    if (q.isEmpty) return null;
    CardTransaction? best;
    for (final tx in foods) {
      if (!tx.ownNumbers || tx.isRecipe || norm(tx.description) != q) continue;
      if (best == null || tx.time.isAfter(best.time)) best = tx;
    }
    return best;
  }
}
