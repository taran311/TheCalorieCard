import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

/// One ingredient line in a recipe.
class RecipeIngredient {
  final String name;
  final Macros macros;
  final String portion;

  const RecipeIngredient({
    required this.name,
    required this.macros,
    this.portion = '',
  });
}

/// Creating, editing and deleting recipes.
///
/// A recipe is a `recipes` document plus one `user_food` row per ingredient
/// (with `foodCategory: 'Recipe'`). Ingredient rows are building blocks, not
/// food eaten, so they never touch the card balance. Food already logged
/// from a recipe is a separate entry with its own numbers, so editing or
/// deleting the recipe never changes past days or today's balance.
class RecipeService {
  RecipeService._();

  static FirebaseFirestore get _db => BalanceService.db;

  static Map<String, dynamic> totalsOf(List<RecipeIngredient> ingredients) {
    final total = ingredients.fold<Macros>(
        Macros.zero, (sum, ing) => sum + ing.macros);
    return {
      'total_calories': total.calories,
      'total_protein': total.protein,
      'total_carbs': total.carbs,
      'total_fat': total.fat,
    };
  }

  static void _check(String name, List<RecipeIngredient> ingredients) {
    if (name.trim().isEmpty) throw ArgumentError('Recipe needs a name');
    if (ingredients.isEmpty) {
      throw ArgumentError('Recipe needs at least one ingredient');
    }
    for (final ing in ingredients) {
      if (!ing.macros.isValid) {
        throw ArgumentError('Ingredient amounts must be zero or more');
      }
    }
  }

  static Map<String, dynamic> _ingredientFields(
          RecipeIngredient ing, String uid, String recipeId) =>
      {
        'user_id': uid,
        'food_description': ing.name,
        ...ing.macros.toEntryFields(),
        'food_portion': ing.portion,
        'foodCategory': BalanceService.recipeCategory,
        'created_at': FieldValue.serverTimestamp(),
        'recipe_id': recipeId,
      };

  /// Saves a new recipe and returns its id.
  static Future<String> create(
    String uid, {
    required String name,
    required String servingSize,
    required List<RecipeIngredient> ingredients,
  }) async {
    _check(name, ingredients);
    final batch = _db.batch();
    final recipeRef = _db.collection('recipes').doc();

    final ingredientIds = <String>[];
    for (final ing in ingredients) {
      final ref = _db.collection('user_food').doc();
      ingredientIds.add(ref.id);
      batch.set(ref, _ingredientFields(ing, uid, recipeRef.id));
    }

    batch.set(recipeRef, {
      'user_id': uid,
      'name': name.trim(),
      'serving_size': servingSize,
      'created_at': FieldValue.serverTimestamp(),
      'food_item_ids': ingredientIds,
      ...totalsOf(ingredients),
    });

    await batch.commit();
    return recipeRef.id;
  }

  /// Replaces a recipe's name, serving size and ingredients.
  static Future<void> update(
    String uid,
    String recipeId, {
    required String name,
    required String servingSize,
    required List<RecipeIngredient> ingredients,
  }) async {
    _check(name, ingredients);
    final recipeRef = _db.collection('recipes').doc(recipeId);
    final recipe = await recipeRef.get();
    if (!recipe.exists) throw StateError('That recipe no longer exists');
    if (recipe.data()?['user_id'] != uid) {
      throw StateError("Can't edit someone else's recipe");
    }

    final batch = _db.batch();
    for (final doc in await _ingredientDocs(uid, recipeId)) {
      batch.delete(doc.reference);
    }

    final ingredientIds = <String>[];
    for (final ing in ingredients) {
      final ref = _db.collection('user_food').doc();
      ingredientIds.add(ref.id);
      batch.set(ref, _ingredientFields(ing, uid, recipeId));
    }

    batch.update(recipeRef, {
      'name': name.trim(),
      'serving_size': servingSize,
      'food_item_ids': ingredientIds,
      ...totalsOf(ingredients),
    });
    await batch.commit();
  }

  /// Deletes a recipe and its ingredient rows. Food already logged from it
  /// stays in your history (and on today's card).
  static Future<void> delete(String uid, String recipeId) async {
    final recipeRef = _db.collection('recipes').doc(recipeId);
    final recipe = await recipeRef.get();
    if (recipe.exists && recipe.data()?['user_id'] != uid) {
      throw StateError("Can't delete someone else's recipe");
    }

    final batch = _db.batch();
    batch.delete(recipeRef);
    for (final doc in await _ingredientDocs(uid, recipeId)) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    // Stop showing it to friends it was shared with. Not critical: shared
    // lists already skip recipes that no longer exist.
    try {
      final shares = await _db
          .collection('shared_recipes')
          .where('shared_by_user_id', isEqualTo: uid)
          .where('recipe_id', isEqualTo: recipeId)
          .get();
      if (shares.docs.isNotEmpty) {
        final cleanup = _db.batch();
        for (final d in shares.docs) {
          cleanup.delete(d.reference);
        }
        await cleanup.commit();
      }
    } catch (_) {}
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _ingredientDocs(String uid, String recipeId) async {
    final snap = await _db
        .collection('user_food')
        .where('user_id', isEqualTo: uid)
        .where('recipe_id', isEqualTo: recipeId)
        .where('foodCategory', isEqualTo: BalanceService.recipeCategory)
        .get();
    return snap.docs;
  }
}
