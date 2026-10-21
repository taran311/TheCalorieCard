import 'package:namer_app/services/portion_amount.dart';
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

  /// Same food, same kind of portion: one suggestion. Compared by one
  /// portion ("30g serving"), so "1.67 × 30g serving" and "30g serving" of
  /// the same food are one chip (the latest amount is the one offered).
  static String keyOf(CardTransaction tx) =>
      '${tx.description.trim().toLowerCase()}|'
      '${tx.basePortion.trim().toLowerCase()}';

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

  /// The same food logged before in a different amount, and how much to
  /// scale it by: "10g surreal" after "40g Surreal" is that entry × 0.25,
  /// so it needs no lookup. Works for weights and volumes (g, kg, oz, ml,
  /// l, fl oz) and counts ("2 crumpets" after "4 crumpets"); the food
  /// words have to match (ignoring case, order, plurals and "of"). Their
  /// own numbers first, otherwise the latest. Null if there's nothing to
  /// scale from.
  static ({CardTransaction tx, double factor})? scaledFood(
      List<CardTransaction> foods, String query) {
    final want = amountOf(query);
    final key = foodKey(query);
    if (want == null || key.isEmpty) return null;
    ({CardTransaction tx, double factor})? best;
    for (final tx in foods) {
      if (tx.isRecipe || foodKey(tx.description) != key) continue;
      final had = amountOf(tx.description);
      if (had == null || had.unit != want.unit) continue;
      // The amount typed, times any change made to it when it was logged
      // ("40g" changed to ×1.5 was 60 g).
      final eaten = had.amount * (tx.multiplier > 0 ? tx.multiplier : 1);
      final factor = want.amount / eaten;
      if (!factor.isFinite || factor < 0.02 || factor > 50) continue;
      final b = best;
      final better = b == null ||
          (tx.ownNumbers && !b.tx.ownNumbers) ||
          (tx.ownNumbers == b.tx.ownNumbers && tx.time.isAfter(b.tx.time));
      if (better) best = (tx: tx, factor: factor);
    }
    return best;
  }

  /// How much [text] says, as grams ('g'), ml ('ml') or a count
  /// ('count'): "40g surreal" is 40 g, "1.5 oz nuts" 42.5 g, "330ml oat
  /// milk" 330 ml, "3 crumpets" 3. Null if it doesn't say.
  ///
  /// Only when there's one clear amount: "30g oats with 200ml oat milk" or
  /// "2 x 30g bars" can't be scaled by a single number, so they're null.
  static ({double amount, String unit})? amountOf(String text) {
    final digit = RegExp(r'\d');
    final weights = PortionAmount.amountsIn(text);
    if (weights > 1) return null;
    if (weights == 1) {
      if (digit.hasMatch(PortionAmount.withoutAmounts(text))) return null;
      final size = PortionAmount.sizeOf(text);
      if (size == null) return null;
      return (amount: size.amount, unit: size.volume ? 'ml' : 'g');
    }
    final count = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*(?:x\s+)?(?=[a-z])',
            caseSensitive: false)
        .firstMatch(text);
    if (count == null || digit.hasMatch(text.substring(count.end))) {
      return null;
    }
    final n = double.tryParse(count.group(1)!);
    return n == null || n <= 0 ? null : (amount: n, unit: 'count');
  }

  /// The food words of [text], without the amount: "40g Surreal",
  /// "surreal 10 g" and "Surreal (25g)" are all "surreal". Lower case,
  /// plurals made singular, "of", "a" and "the" left out, in a fixed order.
  static String foodKey(String text) {
    final words = PortionAmount.withoutAmounts(text)
        .toLowerCase()
        .split(RegExp(r'[^a-z\u00C0-\u024F]+'))
        .where((w) => w.isNotEmpty && !_fillers.contains(w))
        .map(_singular)
        .toList()
      ..sort();
    return words.join(' ');
  }

  static const _fillers = {'of', 'a', 'an', 'the', 'x'};

  static String _singular(String w) {
    if (w.length > 4 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
    if (w.length > 4 && RegExp(r'(ches|shes|xes|oes)$').hasMatch(w)) {
      return w.substring(0, w.length - 2);
    }
    if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) {
      return w.substring(0, w.length - 1);
    }
    return w;
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
