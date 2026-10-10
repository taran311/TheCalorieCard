import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

/// One day's weight. Always kg; the units service converts for display.
class WeighIn {
  final String dateKey;

  /// Local midnight of [dateKey].
  final DateTime date;
  final double kg;

  const WeighIn({required this.dateKey, required this.date, required this.kg});

  /// Reads a `weigh_ins` document, or null if it's unusable.
  static WeighIn? fromMap(Map<String, dynamic> data) {
    final key = data['date_key'];
    final kg = BalanceService.number(data['kg']);
    if (key is! String || kg == null || kg <= 0) return null;
    final date = WeightService.parseDateKey(key);
    if (date == null) return null;
    return WeighIn(dateKey: key, date: date, kg: kg);
  }

  @override
  String toString() => 'WeighIn($dateKey, $kg kg)';
}

/// What the weight trend says about the daily goal, after a few weeks.
class WeightCheckIn {
  /// The goal being checked: 'lose', 'maintain' or 'gain'.
  final String mode;

  /// The actual trend over the last four weeks (negative = losing).
  final double kgPerWeek;

  /// Suggested change to the daily goal in kcal (0 = on track).
  final int suggestedChange;

  /// The trend suggests eating less, but the goal is already at the
  /// safe minimum, so we don't suggest going lower.
  final bool atSafeMinimum;

  const WeightCheckIn({
    required this.mode,
    required this.kgPerWeek,
    required this.suggestedChange,
    this.atSafeMinimum = false,
  });

  bool get onTrack => suggestedChange == 0 && !atSafeMinimum;
}

/// The weight log: one weigh-in per day in `weigh_ins`, with id
/// `{uid}_{date_key}` so logging twice in a day just corrects it.
/// Fields: `user_id`, `date_key` (yyyy-MM-dd, local), `kg`, `created_at`.
class WeightService {
  WeightService._();

  static const collection = 'weigh_ins';

  /// How much history the check-in needs before it says anything.
  static const checkInAfterDays = 21;

  static CollectionReference<Map<String, dynamic>> get _col =>
      BalanceService.db.collection(collection);

  static String docId(String uid, String dateKey) => '${uid}_$dateKey';

  static DateTime? parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  /// Saves [kg] for [on] (today by default), replacing that day's entry.
  static Future<void> log(String uid, double kg, {DateTime? on}) async {
    if (!kg.isFinite || kg <= 0) {
      throw ArgumentError('Weight must be more than zero: $kg');
    }
    final key = BalanceService.dateKey(on ?? BalanceService.now());
    await _col.doc(docId(uid, key)).set({
      'user_id': uid,
      'date_key': key,
      'kg': (kg * 100).round() / 100,
      'created_at': Timestamp.fromDate(BalanceService.now()),
    });
  }

  static Future<void> delete(String uid, String dateKey) =>
      _col.doc(docId(uid, dateKey)).delete();

  /// Parses documents into weigh-ins, oldest first, one per day.
  static List<WeighIn> fromMaps(Iterable<Map<String, dynamic>> maps) {
    final byDay = <String, WeighIn>{};
    for (final m in maps) {
      final w = WeighIn.fromMap(m);
      if (w != null) byDay[w.dateKey] = w;
    }
    return byDay.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Every weigh-in for [uid], oldest first. A single-field query, so no
  /// Firestore index is needed.
  static Future<List<WeighIn>> history(String uid) async {
    final snap = await _col.where('user_id', isEqualTo: uid).get();
    return fromMaps(snap.docs.map((d) => d.data()));
  }

  /// Like [history], kept up to date.
  static Stream<List<WeighIn>> watch(String uid) => _col
      .where('user_id', isEqualTo: uid)
      .snapshots()
      .map((s) => fromMaps(s.docs.map((d) => d.data())));

  /// The weigh-ins from the last [days] days (today included).
  static List<WeighIn> lastDays(List<WeighIn> all, int days, {DateTime? now}) {
    final today = BalanceService.startOfDay(now ?? BalanceService.now());
    final from = BalanceService.addDays(today, -(days - 1));
    return [
      for (final w in all)
        if (!w.date.isBefore(from)) w
    ];
  }

  /// For each weigh-in, the average of the weigh-ins in the [windowDays]
  /// days up to and including it. Smooths out day-to-day water weight.
  static List<double> smoothed(List<WeighIn> points, {int windowDays = 7}) {
    final out = <double>[];
    for (var i = 0; i < points.length; i++) {
      final end = points[i].date;
      var sum = 0.0;
      var n = 0;
      for (var j = i; j >= 0; j--) {
        if (end.difference(points[j].date).inDays >= windowDays) break;
        sum += points[j].kg;
        n++;
      }
      out.add(sum / n);
    }
    return out;
  }

  /// The best-fit trend in kg per week (negative = losing), or null with
  /// fewer than two days to compare.
  static double? weeklyTrend(List<WeighIn> points) {
    if (points.length < 2) return null;
    final origin = points.first.date;
    final xs = [
      for (final p in points) p.date.difference(origin).inHours / 24.0
    ];
    final ys = [for (final p in points) p.kg];
    final n = xs.length;
    final mx = xs.reduce((a, b) => a + b) / n;
    final my = ys.reduce((a, b) => a + b) / n;
    var sxy = 0.0;
    var sxx = 0.0;
    for (var i = 0; i < n; i++) {
      sxy += (xs[i] - mx) * (ys[i] - my);
      sxx += (xs[i] - mx) * (xs[i] - mx);
    }
    if (sxx == 0) return null;
    final perDay = sxy / sxx;
    return perDay.isFinite ? perDay * 7 : null;
  }

  /// Compares the last four weeks' trend with what the goal implies, once
  /// there's at least three weeks of it. Null until then.
  ///
  /// Suggestions are small (100–150 kcal) and never take the goal below
  /// [floorKcal], the safe minimum.
  static WeightCheckIn? checkIn({
    required List<WeighIn> history,
    required String? mode,
    required double goalKcal,
    double? floorKcal,
    DateTime? now,
  }) {
    final recent = lastDays(history, 28, now: now);
    if (recent.length < 4) return null;
    final span = recent.last.date.difference(recent.first.date).inHours / 24;
    if (span < checkInAfterDays - 0.5) return null;
    final rate = weeklyTrend(recent);
    if (rate == null) return null;

    final m = (mode == 'maintain' || mode == 'gain') ? mode! : 'lose';
    var change = 0;
    switch (m) {
      case 'lose':
        // Not really losing: eat a little less. Losing over 1 kg a week:
        // that's faster than is comfortable, so eat a little more.
        if (rate > -0.1) {
          change = -150;
        } else if (rate < -1.0) {
          change = 150;
        }
      case 'gain':
        if (rate < 0.05) {
          change = 150;
        } else if (rate > 0.5) {
          change = -100;
        }
      default:
        if (rate > 0.25) {
          change = -100;
        } else if (rate < -0.25) {
          change = 100;
        }
    }

    var atFloor = false;
    if (change < 0 && floorKcal != null && floorKcal.isFinite) {
      final room = goalKcal - floorKcal;
      if (room < 100) {
        change = 0;
        atFloor = true;
      } else if (room < -change) {
        change = -100;
      }
    }
    if (goalKcal + change > 10000) change = 0;

    return WeightCheckIn(
      mode: m,
      kgPerWeek: rate,
      suggestedChange: change,
      atSafeMinimum: atFloor,
    );
  }
}
