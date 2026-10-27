import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/achievement_service.dart';

/// A shared meal split between friends, like splitting a bill.
///
/// Stored in `bill_splits`:
///   from_user_id, from_name, title, meal, people,
///   items: [{name, calories, protein, carbs, fat, portion}]  (one share)
///   to_user_ids: [...], status: {uid: 'pending'|'accepted'|'declined'}
class BillSplit {
  final String id;
  final String fromUserId;
  final String fromName;
  final String title;
  final String meal;
  final int people;
  final List<Map<String, dynamic>> items;
  final Map<String, String> status;
  final DateTime? createdAt;

  const BillSplit({
    required this.id,
    required this.fromUserId,
    required this.fromName,
    required this.title,
    required this.meal,
    required this.people,
    required this.items,
    required this.status,
    this.createdAt,
  });

  double get calories => items.fold(
      0, (total, i) => total + (BalanceService.number(i['calories']) ?? 0));

  /// 'pending', 'accepted' or 'declined' for people the bill was split
  /// with; 'none' for anyone else (so they can't accept it).
  String statusFor(String uid) => status[uid] ?? 'none';

  factory BillSplit.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final created = d['created_at'];
    return BillSplit(
      id: doc.id,
      fromUserId: (d['from_user_id'] ?? '').toString(),
      fromName: (d['from_name'] ?? 'A friend').toString(),
      title: (d['title'] ?? 'Shared meal').toString(),
      meal: FoodLog.displayMeal((d['meal'] ?? 'Dinner').toString()),
      people: (BalanceService.number(d['people']) ?? 2).round(),
      items: [
        for (final i in (d['items'] as List? ?? const []))
          if (i is Map) Map<String, dynamic>.from(i)
      ],
      status: {
        for (final e in ((d['status'] as Map?) ?? const {}).entries)
          e.key.toString(): e.value.toString()
      },
      createdAt: created is Timestamp ? created.toDate() : null,
    );
  }
}

class SplitService {
  SplitService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      BalanceService.db.collection('bill_splits');

  /// One person's share of [items] when split [people] ways.
  static List<Map<String, dynamic>> shareOf(
      List<Map<String, dynamic>> items, int people) {
    if (people < 2) throw ArgumentError('A split needs at least 2 people');
    return shareAt(items, 1 / people);
  }

  /// [fraction] of [items] (a third is 1/3), as one person's share.
  static List<Map<String, dynamic>> shareAt(
      List<Map<String, dynamic>> items, double fraction) {
    if (!fraction.isFinite || fraction <= 0 || fraction >= 1) {
      throw ArgumentError('A share is more than none and less than all');
    }
    double n(dynamic v) => BalanceService.number(v) ?? 0;
    return [
      for (final item in items)
        {
          'name': (item['name'] ?? 'Food').toString(),
          'calories': (n(item['calories']) * fraction).roundToDouble(),
          'protein': n(item['protein']) * fraction,
          'carbs': n(item['carbs']) * fraction,
          'fat': n(item['fat']) * fraction,
          'portion': _sharePortion(item['portion'], fraction),
        }
    ];
  }

  /// Each friend's share when you have [mine] and the rest is split evenly
  /// between [friends] of them.
  static double friendShare(double mine, int friends) =>
      friends < 1 ? 0 : (1 - mine) / friends;

  static String _sharePortion(dynamic portion, double fraction) {
    final p = (portion ?? '').toString().trim();
    final f = fractionLabel(fraction);
    return p.isEmpty ? '$f share' : '$f share of $p';
  }

  static const _fractions = [
    (1, 2), (1, 3), (2, 3), (1, 4), (3, 4), (1, 5), (2, 5), (3, 5), (4, 5),
    (1, 6), (5, 6), (1, 8), (3, 8), (5, 8), (7, 8), (1, 12),
  ];

  /// "1/3", "3/4"; anything else as a percentage ("42%").
  static String fractionLabel(double f) {
    for (final (a, b) in _fractions) {
      if ((f - a / b).abs() < 0.004) return '$a/$b';
    }
    for (var b = 2; b <= 12; b++) {
      final a = (f * b).round();
      if (a > 0 && (f - a / b).abs() < 0.004) return '$a/$b';
    }
    return '${(f * 100).round()}%';
  }

  /// Splits [items] between you and [friendIds]: logs your share now and
  /// sends each friend a request for theirs. Returns the split's id.
  static Future<String> create({
    required String uid,
    required String fromName,
    required List<Map<String, dynamic>> items,
    required List<String> friendIds,
    required String meal,
    String? title,
    double? mine,
  }) async {
    final others = friendIds.where((id) => id != uid).toSet().toList();
    if (others.isEmpty) throw ArgumentError('Pick at least one friend');
    if (items.isEmpty) throw ArgumentError('Nothing to split');

    // [mine]: your share (default an even split); the rest is split evenly.
    final myPart = mine ?? 1 / (others.length + 1);
    final share = shareAt(items, friendShare(myPart, others.length));
    final myShare = shareAt(items, myPart);
    final name = (title == null || title.trim().isEmpty)
        ? _titleFor(items)
        : title.trim();

    // Send the requests first: if that fails, nothing has been logged, so
    // trying again can't charge your share twice.
    final ref = await _col.add({
      'from_user_id': uid,
      'from_name': fromName,
      'title': name,
      'meal': meal,
      'people': others.length + 1,
      'items': share,
      'to_user_ids': others,
      'status': {for (final id in others) id: 'pending'},
      'created_at': FieldValue.serverTimestamp(),
    });

    try {
      await FoodLog.logFoods(items: myShare, meal: meal, userId: uid);
    } catch (_) {
      // Your share didn't log, so withdraw the requests too.
      try {
        await ref.delete();
      } catch (_) {}
      rethrow;
    }
    await AchievementService.bump(uid, 'splits');
    return ref.id;
  }

  /// A food already on your card ([entryId], [entry]) as an item to split.
  static Map<String, dynamic> itemFromEntry(Map<String, dynamic> entry) {
    final m = Macros.fromEntry(entry);
    return {
      'name': (entry['food_description'] ?? 'Food').toString(),
      'calories': m.calories,
      'protein': m.protein,
      'carbs': m.carbs,
      'fat': m.fat,
      'portion': (entry['food_portion'] ?? '').toString(),
    };
  }

  /// Splits a food you've already logged between you and [friendIds]:
  /// sends each friend a request for their share, then brings your entry
  /// down to your share (the card gets the difference back). Returns the
  /// split's id.
  static Future<String> splitLogged({
    required String uid,
    required String fromName,
    required String entryId,
    required Map<String, dynamic> entry,
    required List<String> friendIds,
    double? mine,
  }) async {
    final others = friendIds.where((id) => id != uid).toSet().toList();
    if (others.isEmpty) throw ArgumentError('Pick at least one friend');
    final people = others.length + 1;
    final myPart = mine ?? 1 / people;
    final item = itemFromEntry(entry);
    final share = shareAt([item], friendShare(myPart, others.length));
    final meal = FoodLog.mealOf(entry['foodCategory']?.toString());

    // Requests first: if they fail, your entry hasn't changed.
    final ref = await _col.add({
      'from_user_id': uid,
      'from_name': fromName,
      'title': item['name'],
      'meal': meal,
      'people': people,
      'items': share,
      'to_user_ids': others,
      'status': {for (final id in others) id: 'pending'},
      'created_at': FieldValue.serverTimestamp(),
    });

    try {
      // Same food, your share of the amount: "2 × 1 sausage" split evenly
      // two ways is 1 sausage, with its numbers scaled to match.
      final m = FoodLog.multiplierOf(entry) * myPart;
      // Calories fixed by hand stay fixed: your share of what's shown.
      final kcal = (Macros.fromEntry(entry).calories * myPart).roundToDouble();
      final scaled = FoodLog.baseOf(entry).scaled(m).calories;
      await FoodLog.updateEntry(entryId,
          entry: entry,
          multiplier: m,
          calories: (scaled - kcal).abs() > 1 ? kcal : null,
          userId: uid);
    } catch (_) {
      // Your entry didn't change, so withdraw the requests too.
      try {
        await ref.delete();
      } catch (_) {}
      rethrow;
    }
    await AchievementService.bump(uid, 'splits');
    return ref.id;
  }

  static String _titleFor(List<Map<String, dynamic>> items) {
    final first = (items.first['name'] ?? 'Shared meal').toString();
    return items.length == 1 ? first : '$first + ${items.length - 1} more';
  }

  /// Splits waiting for your answer, newest first.
  static Stream<List<BillSplit>> pendingFor(String uid) {
    return _col
        .where('to_user_ids', arrayContains: uid)
        .snapshots()
        .map((snap) {
      final list = [
        for (final d in snap.docs)
          if (BillSplit.fromDoc(d).statusFor(uid) == 'pending')
            BillSplit.fromDoc(d)
      ]..sort((a, b) => (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0)));
      return list;
    });
  }

  /// Logs your share to [meal] (defaults to the split's meal) and marks the
  /// request accepted. Safe against double taps and a second device: only
  /// a pending request can be accepted.
  ///
  /// Returns false if it had already been answered (nothing logged).
  static Future<bool> accept(String uid, BillSplit split,
      {String? meal}) async {
    final ref = _col.doc(split.id);
    final claimed = await BalanceService.db.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return false;
      if (BillSplit.fromDoc(snap).statusFor(uid) != 'pending') return false;
      tx.update(ref, {'status.$uid': 'accepted'});
      return true;
    });
    if (!claimed) return false;

    try {
      await FoodLog.logFoods(
          items: split.items, meal: meal ?? split.meal, userId: uid);
    } catch (e) {
      // Put it back so it can be tried again.
      await ref.update({'status.$uid': 'pending'});
      rethrow;
    }
    return true;
  }

  /// Declines your share. Only a pending request can be declined, so a
  /// second device can't undo one you've already accepted.
  static Future<bool> decline(String uid, BillSplit split) {
    final ref = _col.doc(split.id);
    return BalanceService.db.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return false;
      if (BillSplit.fromDoc(snap).statusFor(uid) != 'pending') return false;
      tx.update(ref, {'status.$uid': 'declined'});
      return true;
    });
  }

  /// Total calories in one share (what each person, you included, logs).
  static double shareCalories(List<Map<String, dynamic>> items, int people) =>
      caloriesAt(items, 1 / people);

  /// What [fraction] of [items] comes to (rounded per item, as logged).
  static double caloriesAt(List<Map<String, dynamic>> items, double fraction) =>
      shareAt(items, fraction).fold(
          0.0, (total, i) => total + (BalanceService.number(i['calories']) ?? 0));
}
