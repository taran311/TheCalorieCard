import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Calories and macros for one food entry, or a total of several.
class Macros {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;

  const Macros({
    this.calories = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
  });

  static const zero = Macros();

  Macros operator +(Macros o) => Macros(
        calories: calories + o.calories,
        protein: protein + o.protein,
        carbs: carbs + o.carbs,
        fat: fat + o.fat,
      );

  Macros operator -(Macros o) => Macros(
        calories: calories - o.calories,
        protein: protein - o.protein,
        carbs: carbs - o.carbs,
        fat: fat - o.fat,
      );

  Macros scaled(double by) => Macros(
        calories: calories * by,
        protein: protein * by,
        carbs: carbs * by,
        fat: fat * by,
      );

  bool get isValid =>
      [calories, protein, carbs, fat].every((v) => v.isFinite && v >= 0);

  /// Reads `food_calories` etc. from a `user_food` document.
  factory Macros.fromEntry(Map<String, dynamic> data) => Macros(
        calories: BalanceService.number(data['food_calories']) ?? 0,
        protein: BalanceService.number(data['food_protein']) ?? 0,
        carbs: BalanceService.number(data['food_carbs']) ?? 0,
        fat: BalanceService.number(data['food_fat']) ?? 0,
      );

  Map<String, dynamic> toEntryFields() => {
        'food_calories': calories,
        'food_protein': protein,
        'food_carbs': carbs,
        'food_fat': fat,
      };

  @override
  String toString() =>
      'Macros(kcal: $calories, P: $protein, C: $carbs, F: $fat)';
}

/// Owns every change to the calorie card balance stored in `user_data`.
///
/// Rules that keep the balance correct:
///  1. Logging or removing food and moving the balance happen in ONE batch
///     write, so they can't get out of step (no "logged but never charged").
///  2. Balance changes use [FieldValue.increment], so two devices writing at
///     once can't overwrite each other.
///  3. The balance belongs to one calendar day (`balance_date`, local time).
///     The first time it's touched on a new day, it's rebuilt from the goals
///     minus whatever has already been logged today.
class BalanceService {
  BalanceService._();

  static FirebaseFirestore? _dbOverride;

  /// The Firestore instance every service uses (a fake one in tests).
  static FirebaseFirestore get db => _dbOverride ?? FirebaseFirestore.instance;
  static FirebaseFirestore get _db => db;

  /// Tests swap in a fake Firestore here.
  @visibleForTesting
  static set firestore(FirebaseFirestore? db) => _dbOverride = db;

  /// The current time. Tests replace this to check day changes.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static DateTime now() => clock();

  /// `foodCategory` used for recipe ingredient documents in `user_food`.
  static const String recipeCategory = 'Recipe';

  static String dateKey(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static bool isToday(DateTime? date) {
    if (date == null) return false;
    return dateKey(date) == dateKey(now());
  }

  static bool sameDay(DateTime? a, DateTime? b) =>
      a != null && b != null && dateKey(a) == dateKey(b);

  static double? number(dynamic v) {
    double? d;
    if (v is num) d = v.toDouble();
    if (v is String) d = double.tryParse(v);
    return d != null && d.isFinite ? d : null;
  }

  /// The user's `user_data` document, or null if they haven't onboarded yet.
  static Future<DocumentSnapshot<Map<String, dynamic>>?> userDataDoc(
      String userId) async {
    final snap = await _db
        .collection('user_data')
        .where('user_id', isEqualTo: userId)
        .limit(1)
        .get();
    return snap.docs.isEmpty ? null : snap.docs.first;
  }

  static DateTime? entryDate(Map<String, dynamic> data) {
    final timeAdded = data['time_added'];
    final createdAt = data['created_at'];
    if (timeAdded is Timestamp) return timeAdded.toDate();
    if (timeAdded is DateTime) return timeAdded;
    if (createdAt is Timestamp) return createdAt.toDate();
    if (createdAt is DateTime) return createdAt;
    return null;
  }

  /// True for documents that are food eaten (not recipe ingredients).
  static bool isLogEntry(Map<String, dynamic> data) =>
      data['foodCategory'] != recipeCategory;

  /// Set once a range query fails because the Firestore index isn't there
  /// (see [entriesBetween]); after that we read the whole history instead.
  static bool _rangeQueriesUnavailable = false;

  static bool _isMissingIndex(Object e) =>
      e is FirebaseException && e.code == 'failed-precondition';

  static void _noteMissingIndex(Object e) {
    _rangeQueriesUnavailable = true;
    // The message includes a link that creates the index in one click.
    debugPrint('Firestore index for user_food (user_id, time_added) is '
        'missing, so the app is reading full history instead. $e');
  }

  /// Start of the local day [d] falls in.
  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// [d] moved by [days] calendar days, keeping the time of day.
  ///
  /// Use this instead of `d.add(Duration(days: n))`: when the clocks change
  /// a day is 23 or 25 hours long, and adding 24-hour blocks can land on
  /// the wrong date (e.g. skipping a day in late March).
  static DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month,
      d.day + days, d.hour, d.minute, d.second, d.millisecond, d.microsecond);

  /// Food eaten (recipe ingredients excluded) with `time_added` in
  /// [start, end), oldest first.
  ///
  /// Only those days are fetched, not the whole history. This needs a
  /// composite index on `user_food`: `user_id` ascending, `time_added`
  /// ascending. Until it exists, this falls back to reading everything.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      entriesBetween(String userId, DateTime start, DateTime end) async {
    final all = _db.collection('user_food').where('user_id', isEqualTo: userId);

    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
    if (_rangeQueriesUnavailable) {
      docs = (await all.get()).docs;
    } else {
      try {
        docs = (await all
                .where('time_added', isGreaterThanOrEqualTo: start)
                .where('time_added', isLessThan: end)
                .get())
            .docs;
      } catch (e) {
        if (!_isMissingIndex(e)) rethrow;
        _noteMissingIndex(e);
        docs = (await all.get()).docs;
      }
    }

    final inRange = docs.where((d) {
      final data = d.data();
      final t = entryDate(data);
      return isLogEntry(data) && t != null && !t.isBefore(start) && t.isBefore(end);
    }).toList()
      ..sort((a, b) =>
          entryDate(a.data())!.compareTo(entryDate(b.data())!));
    return inRange;
  }

  /// Live updates of food logged by [userIds] (up to 30) in [start, end).
  /// Falls back to the whole history if the index isn't there yet.
  /// Callers still filter by date, since a fallback returns everything.
  static Stream<QuerySnapshot<Map<String, dynamic>>> entrySnapshotsBetween(
      List<String> userIds, DateTime start, DateTime end) {
    final all = _db.collection('user_food').where('user_id', whereIn: userIds);
    if (_rangeQueriesUnavailable) return all.snapshots();

    final controller = StreamController<QuerySnapshot<Map<String, dynamic>>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;

    void listen(Query<Map<String, dynamic>> query, {required bool ranged}) {
      sub = query.snapshots().listen(
        controller.add,
        onError: (Object e, StackTrace st) {
          if (ranged && _isMissingIndex(e)) {
            _noteMissingIndex(e);
            sub?.cancel();
            listen(all, ranged: false);
          } else {
            controller.addError(e, st);
          }
        },
      );
    }

    controller.onListen = () {
      listen(
        all
            .where('time_added', isGreaterThanOrEqualTo: start)
            .where('time_added', isLessThan: end),
        ranged: true,
      );
    };
    controller.onCancel = () => sub?.cancel();
    return controller.stream;
  }

  /// Every food eaten on [day] (local time), recipe ingredients excluded.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> entriesOn(
      String userId, DateTime day) {
    final start = startOfDay(day);
    return entriesBetween(userId, start, addDays(start, 1));
  }

  /// One-off tidy-up so date-range queries see every entry.
  ///
  /// Some early entries only have `created_at`, and a query on `time_added`
  /// can't see those. This copies `created_at` into `time_added` for them,
  /// once per user (remembered in `user_data`). Returns how many entries it
  /// fixed.
  static Future<int> backfillEntryTimes(String userId) async {
    final profile = await userDataDoc(userId);
    if (profile == null || profile.data()?['entry_times_backfilled'] == true) {
      return 0;
    }

    final snap = await _db
        .collection('user_food')
        .where('user_id', isEqualTo: userId)
        .get();
    final missing = snap.docs.where((d) {
      final data = d.data();
      return isLogEntry(data) &&
          data['time_added'] == null &&
          data['created_at'] is Timestamp;
    }).toList();

    for (var i = 0; i < missing.length; i += 450) {
      final batch = _db.batch();
      for (final d in missing.skip(i).take(450)) {
        batch.update(d.reference, {'time_added': d.data()['created_at']});
      }
      await batch.commit();
    }
    await profile.reference.update({'entry_times_backfilled': true});
    return missing.length;
  }

  static Macros totalOf(Iterable<Map<String, dynamic>> entries) =>
      entries.fold(Macros.zero, (sum, e) => sum + Macros.fromEntry(e));

  /// Sum of calories/macros logged today (local time).
  static Future<Macros> todaysTotals(String userId) async {
    final docs = await entriesOn(userId, now());
    return totalOf(docs.map((d) => d.data()));
  }

  /// Daily calorie goal. Older accounts created before `calorie_goal` was
  /// saved at signup fall back to the calories implied by their macro goals.
  static double? calorieGoalFrom(Map<String, dynamic> data) {
    final explicit = number(data['calorie_goal']);
    if (explicit != null && explicit > 0) return explicit;

    final p = number(data['protein_goal']) ?? 0;
    final c = number(data['carbs_goal']) ?? 0;
    final f = number(data['fats_goal']) ?? 0;
    final fromMacros = p * 4 + c * 4 + f * 9;
    return fromMacros > 0 ? fromMacros : null;
  }

  /// The user's goals as a [Macros], or null if there's no calorie goal.
  static Macros? goalsFrom(Map<String, dynamic> data) {
    final calories = calorieGoalFrom(data);
    if (calories == null) return null;
    return Macros(
      calories: calories,
      protein: number(data['protein_goal']) ?? 0,
      carbs: number(data['carbs_goal']) ?? 0,
      fat: number(data['fats_goal']) ?? 0,
    );
  }

  static Map<String, dynamic> _balanceFields(Macros goals, Macros eaten) {
    final left = goals - eaten;
    return {
      'calories': left.calories,
      'protein_balance': left.protein,
      'carbs_balance': left.carbs,
      'fats_balance': left.fat,
      'balance_date': dateKey(now()),
    };
  }

  /// Resets the card to today's goals if the stored balance is from an
  /// earlier day (or always, with [force]). Safe to call often: it's a
  /// single read when there's nothing to do.
  ///
  /// Returns true if the balance was rebuilt.
  static Future<bool> ensureDailyReset(String userId,
      {bool force = false}) async {
    final doc = await userDataDoc(userId);
    if (doc == null) return false;
    final data = doc.data() ?? {};

    if (!force && data['balance_date'] == dateKey(now())) return false;

    final goals = goalsFrom(data);
    if (goals == null) return false; // Nothing sensible to reset to.

    final eaten = await todaysTotals(userId);
    // Re-check inside a transaction: if another write (another device, or
    // a second tap) already started today's balance, leave it alone rather
    // than overwrite charges made since.
    return _db.runTransaction<bool>((tx) async {
      final fresh = await tx.get(doc.reference);
      if (!force && fresh.data()?['balance_date'] == dateKey(now())) {
        return false;
      }
      tx.update(doc.reference, _balanceFields(goals, eaten));
      return true;
    });
  }

  /// Field updates that move the balance by [amount].
  /// Positive amounts = food eaten (balance goes down).
  static Map<String, dynamic> spendUpdate(Macros amount) {
    return {
      'calories': FieldValue.increment(-amount.calories),
      'protein_balance': FieldValue.increment(-amount.protein),
      'carbs_balance': FieldValue.increment(-amount.carbs),
      'fats_balance': FieldValue.increment(-amount.fat),
    };
  }

  /// Logs food to today and charges the card, all in one write.
  ///
  /// Each entry needs `food_description` and its macros (see
  /// [Macros.toEntryFields]); `user_id` and `time_added` are filled in.
  /// Returns the new document ids.
  static Future<List<String>> logEntries(
      String userId, List<Map<String, dynamic>> entries) async {
    if (entries.isEmpty) return const [];

    var total = Macros.zero;
    for (final e in entries) {
      final m = Macros.fromEntry(e);
      if (!m.isValid) {
        throw ArgumentError('Food amounts must be zero or more: $m');
      }
      total += m;
    }

    // Bring the card onto today's balance first. The new entries aren't
    // written yet, so the rebuild doesn't count them and we charge them
    // exactly once below.
    await ensureDailyReset(userId);
    final userDoc = await userDataDoc(userId);

    final batch = _db.batch();
    final ids = <String>[];
    final time = now();
    for (final e in entries) {
      final ref = _db.collection('user_food').doc();
      ids.add(ref.id);
      batch.set(ref, {
        ...e,
        'user_id': userId,
        'time_added': time,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
    if (userDoc != null) {
      batch.update(userDoc.reference, spendUpdate(total));
    }
    await batch.commit();
    return ids;
  }

  /// Removes a logged food and, if it was today's, refunds the card, all in
  /// one write. Returns the removed entry's macros, or null if it was
  /// already gone.
  static Future<Macros?> deleteEntry(String userId, String entryId) async {
    final ref = _db.collection('user_food').doc(entryId);
    final snap = await ref.get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    if (data['user_id'] != userId) {
      throw StateError("Can't remove someone else's food");
    }

    final amount = Macros.fromEntry(data);
    final today = isLogEntry(data) && isToday(entryDate(data));

    // Rebuild first if it's a new day: the rebuild still sees this entry,
    // and the refund below takes it back off exactly once.
    if (today) await ensureDailyReset(userId);
    final userDoc = today ? await userDataDoc(userId) : null;

    final batch = _db.batch();
    batch.delete(ref);
    if (userDoc != null) {
      batch.update(userDoc.reference, spendUpdate(amount.scaled(-1)));
    }
    await batch.commit();
    return amount;
  }

  /// Saves new goals and sets today's balance to goals minus what's already
  /// been eaten today.
  ///
  /// [extra] is stored alongside (age, weight and so on).
  static Future<void> applyGoals(
    String userId, {
    required Macros goals,
    Map<String, dynamic> extra = const {},
  }) async {
    if (!goals.isValid || goals.calories <= 0) {
      throw ArgumentError('Calorie goal must be more than zero: $goals');
    }
    final doc = await userDataDoc(userId);
    if (doc == null) throw StateError('No profile to update');
    final eaten = await todaysTotals(userId);
    await doc.reference.update({
      ...extra,
      'calorie_goal': goals.calories,
      'protein_goal': goals.protein,
      'carbs_goal': goals.carbs,
      'fats_goal': goals.fat,
      ..._balanceFields(goals, eaten),
    });
  }

  /// Deletes everything logged today and puts the card back to the full
  /// daily goals. Recipe ingredients are kept. Returns how many entries
  /// were removed.
  static Future<int> clearToday(String userId) async {
    final docs = await entriesOn(userId, now());
    // Batches hold up to 500 writes.
    for (var i = 0; i < docs.length; i += 450) {
      final batch = _db.batch();
      for (final d in docs.skip(i).take(450)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    await ensureDailyReset(userId, force: true);
    return docs.length;
  }
}
