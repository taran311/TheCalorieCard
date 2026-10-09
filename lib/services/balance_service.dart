import 'package:cloud_firestore/cloud_firestore.dart';

/// Owns every change to the calorie card balance stored in `user_data`.
///
/// Two rules keep the balance correct:
///  1. Spending / refunding uses [FieldValue.increment], so two writes landing
///     at the same time (two devices, a slow network) can't overwrite each
///     other.
///  2. The balance belongs to one calendar day (`balance_date`, local time).
///     The first time we touch it on a new day, it's rebuilt from the goals
///     minus whatever has already been logged today.
class BalanceService {
  BalanceService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

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
    return dateKey(date) == dateKey(DateTime.now());
  }

  /// The user's `user_data` document, or null if they haven't onboarded yet.
  static Future<DocumentSnapshot<Map<String, dynamic>>?> userDataDoc(
      String userId) async {
    final snap = await _db
        .collection('user_data')
        .where('user_id', isEqualTo: userId)
        .limit(1)
        .get(const GetOptions(source: Source.server));
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

  /// Sum of calories/macros logged today (local time).
  static Future<Map<String, double>> todaysTotals(String userId) async {
    final snap = await _db
        .collection('user_food')
        .where('user_id', isEqualTo: userId)
        .get(const GetOptions(source: Source.server));

    double calories = 0, protein = 0, carbs = 0, fats = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      // Recipe ingredients live in user_food too, but they're the recipe's
      // building blocks, not food eaten. Only real log entries count.
      if (data['foodCategory'] == recipeCategory) continue;
      if (!isToday(entryDate(data))) continue;
      calories += (data['food_calories'] as num?)?.toDouble() ?? 0;
      protein += (data['food_protein'] as num?)?.toDouble() ?? 0;
      carbs += (data['food_carbs'] as num?)?.toDouble() ?? 0;
      fats += (data['food_fat'] as num?)?.toDouble() ?? 0;
    }
    return {
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fats': fats,
    };
  }

  static double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Daily calorie goal. Older accounts created before `calorie_goal` was
  /// saved at signup fall back to the calories implied by their macro goals.
  static double? calorieGoalFrom(Map<String, dynamic> data) {
    final explicit = _num(data['calorie_goal']);
    if (explicit != null && explicit > 0) return explicit;

    final p = _num(data['protein_goal']) ?? 0;
    final c = _num(data['carbs_goal']) ?? 0;
    final f = _num(data['fats_goal']) ?? 0;
    final fromMacros = p * 4 + c * 4 + f * 9;
    return fromMacros > 0 ? fromMacros : null;
  }

  /// Resets the card to today's goals if the stored balance is from an
  /// earlier day. Safe to call often: it's a single read when nothing to do.
  ///
  /// Returns true if a reset happened (callers may want to refresh the card).
  static Future<bool> ensureDailyReset(String userId) async {
    final doc = await userDataDoc(userId);
    if (doc == null) return false;
    final data = doc.data() ?? {};

    final today = dateKey(DateTime.now());
    if (data['balance_date'] == today) return false;

    final calorieGoal = calorieGoalFrom(data);
    if (calorieGoal == null) return false; // Nothing sensible to reset to.

    final totals = await todaysTotals(userId);
    await doc.reference.update({
      'calories': calorieGoal - totals['calories']!,
      'protein_balance':
          (_num(data['protein_goal']) ?? 0) - totals['protein']!,
      'carbs_balance': (_num(data['carbs_goal']) ?? 0) - totals['carbs']!,
      'fats_balance': (_num(data['fats_goal']) ?? 0) - totals['fats']!,
      'balance_date': today,
    });
    return true;
  }

  /// Field updates that move the balance by the given amounts.
  /// Positive amounts = food eaten (balance goes down).
  static Map<String, dynamic> spendUpdate({
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
  }) {
    return {
      'calories': FieldValue.increment(-calories),
      'protein_balance': FieldValue.increment(-protein),
      'carbs_balance': FieldValue.increment(-carbs),
      'fats_balance': FieldValue.increment(-fat),
    };
  }

  /// Atomically spend from the card (food added).
  ///
  /// Call this AFTER the food entry has been written. If this triggers the
  /// daily reset, the reset already counted that entry, so we stop there
  /// rather than charging it twice.
  static Future<void> spend(
    String userId, {
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
  }) async {
    if (await ensureDailyReset(userId)) return;
    final doc = await userDataDoc(userId);
    if (doc == null) return;
    await doc.reference.update(spendUpdate(
        calories: calories, protein: protein, carbs: carbs, fat: fat));
  }

  /// Atomically refund to the card (food removed). Call AFTER the entry has
  /// been deleted, for the same reason as [spend].
  static Future<void> refund(
    String userId, {
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
  }) {
    return spend(userId,
        calories: -calories, protein: -protein, carbs: -carbs, fat: -fat);
  }
}
