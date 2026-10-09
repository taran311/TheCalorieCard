import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

/// Shared set-up for the balance tests: an in-memory Firestore, a fixed
/// clock, and a user whose goals are 2000 kcal / 150P / 200C / 60F.
class TestWorld {
  static const uid = 'user-1';
  static const otherUid = 'user-2';

  static const goals = Macros(calories: 2000, protein: 150, carbs: 200, fat: 60);

  final FakeFirebaseFirestore db = FakeFirebaseFirestore();
  DateTime now;

  TestWorld({DateTime? now}) : now = now ?? DateTime(2026, 10, 9, 12, 0);

  /// Points the app's services at this world.
  void install() {
    BalanceService.firestore = db;
    BalanceService.clock = () => now;
  }

  static void uninstall() {
    BalanceService.firestore = null;
    BalanceService.clock = DateTime.now;
  }

  String get today => BalanceService.dateKey(now);

  /// Creates the user's profile with a full card for today, or a stale
  /// card from [balanceDate] holding [calories] left.
  Future<void> addProfile({
    String uid = TestWorld.uid,
    String? balanceDate,
    double? calories,
    Macros goals = TestWorld.goals,
  }) async {
    await db.collection('user_data').add({
      'user_id': uid,
      'calorie_goal': goals.calories,
      'protein_goal': goals.protein,
      'carbs_goal': goals.carbs,
      'fats_goal': goals.fat,
      'calories': calories ?? goals.calories,
      'protein_balance': goals.protein,
      'carbs_balance': goals.carbs,
      'fats_balance': goals.fat,
      'balance_date': balanceDate ?? today,
    });
  }

  /// Writes a food entry directly (as if logged by an older version or
  /// another device), without touching the card.
  Future<String> addEntry({
    String uid = TestWorld.uid,
    required DateTime at,
    double calories = 100,
    double protein = 10,
    double carbs = 10,
    double fat = 2,
    String meal = 'Lunch',
    String description = 'Test food',
  }) async {
    final ref = await db.collection('user_food').add({
      'user_id': uid,
      'food_description': description,
      'food_calories': calories,
      'food_protein': protein,
      'food_carbs': carbs,
      'food_fat': fat,
      'foodCategory': meal,
      'time_added': Timestamp.fromDate(at),
    });
    return ref.id;
  }

  /// The user's card: calories, protein_balance, carbs_balance,
  /// fats_balance, goals and balance_date.
  Future<Map<String, dynamic>> card({String uid = TestWorld.uid}) async {
    final doc = await BalanceService.userDataDoc(uid);
    return doc!.data()!;
  }

  Future<List<Map<String, dynamic>>> foodRows({String? meal}) async {
    final snap = await db.collection('user_food').get();
    return [
      for (final d in snap.docs)
        if (meal == null || d.data()['foodCategory'] == meal)
          {'id': d.id, ...d.data()}
    ];
  }
}
