import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/food_log.dart';

/// Something you have every day (a morning latte), queued each morning for
/// a one-tap confirm. Stored in `direct_debits`.
class DirectDebit {
  final String id;
  final String name;
  final String portion;
  final String meal;
  final Macros macros;
  final String? lastPaidKey;
  final String? lastSkippedKey;

  const DirectDebit({
    required this.id,
    required this.name,
    required this.portion,
    required this.meal,
    required this.macros,
    this.lastPaidKey,
    this.lastSkippedKey,
  });

  /// Not yet paid or skipped today.
  bool get isDueToday {
    final today = BalanceService.dateKey(BalanceService.now());
    return lastPaidKey != today && lastSkippedKey != today;
  }

  Map<String, dynamic> get asFoodItem => {
        'name': name,
        'portion': portion,
        'calories': macros.calories,
        'protein': macros.protein,
        'carbs': macros.carbs,
        'fat': macros.fat,
      };

  factory DirectDebit.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return DirectDebit(
      id: doc.id,
      name: (d['name'] ?? 'Food').toString(),
      portion: (d['portion'] ?? '').toString(),
      meal: FoodLog.mealOf(d['meal']),
      macros: Macros(
        calories: BalanceService.number(d['calories']) ?? 0,
        protein: BalanceService.number(d['protein']) ?? 0,
        carbs: BalanceService.number(d['carbs']) ?? 0,
        fat: BalanceService.number(d['fat']) ?? 0,
      ),
      lastPaidKey: d['last_paid'] as String?,
      lastSkippedKey: d['last_skipped'] as String?,
    );
  }
}

class DirectDebitService {
  DirectDebitService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      BalanceService.db.collection('direct_debits');

  /// Sets up a daily debit from a logged food's `user_food` fields.
  ///
  /// One debit per food and meal: setting the same one up twice updates it
  /// rather than adding a second (which would log it twice every morning).
  /// If the food was eaten today, today counts as paid.
  static Future<String> createFromEntry(
      String uid, Map<String, dynamic> entry) async {
    final m = Macros.fromEntry(entry);
    if (!m.isValid) throw ArgumentError('Food amounts must be zero or more');
    final name = (entry['food_description'] ?? 'Food').toString();
    final meal = FoodLog.mealOf(entry['foodCategory']);
    final slug = '$meal $name'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final ref = _col.doc('${uid}_$slug');
    final eatenToday =
        BalanceService.isToday(BalanceService.entryDate(entry));

    await ref.set({
      'user_id': uid,
      'name': name,
      'portion': (entry['food_portion'] ?? '').toString(),
      'meal': meal,
      'calories': m.calories,
      'protein': m.protein,
      'carbs': m.carbs,
      'fat': m.fat,
      if (eatenToday) 'last_paid': BalanceService.dateKey(BalanceService.now()),
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return ref.id;
  }

  static Stream<List<DirectDebit>> forUser(String uid) => _col
      .where('user_id', isEqualTo: uid)
      .snapshots()
      .map((s) => [for (final d in s.docs) DirectDebit.fromDoc(d)]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  /// Logs today's payment. Claims the day first, so a double tap or a
  /// second device can't log it twice. Returns false if already handled.
  static Future<bool> pay(String uid, DirectDebit debit) async {
    final ref = _col.doc(debit.id);
    final today = BalanceService.dateKey(BalanceService.now());
    final claimed = await BalanceService.db.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      final d = snap.data();
      if (d == null || d['user_id'] != uid) return false;
      if (d['last_paid'] == today || d['last_skipped'] == today) return false;
      tx.update(ref, {'last_paid': today});
      return true;
    });
    if (!claimed) return false;
    try {
      await FoodLog.logFoods(
          items: [debit.asFoodItem], meal: debit.meal, userId: uid);
    } catch (e) {
      await ref.update({'last_paid': debit.lastPaidKey});
      rethrow;
    }
    return true;
  }

  static Future<void> skipToday(DirectDebit debit) => _col
      .doc(debit.id)
      .update({'last_skipped': BalanceService.dateKey(BalanceService.now())});

  static Future<void> cancel(DirectDebit debit) => _col.doc(debit.id).delete();
}
