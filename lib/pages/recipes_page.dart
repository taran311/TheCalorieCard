import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/recipe_service.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/pages/add_recipe_page.dart';
import 'package:namer_app/ui/log_recipe_sheet.dart';

class RecipesPage extends StatefulWidget {

  const RecipesPage({super.key});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
  bool _deleteMode = false;
  int _selectedTabIndex = 0; // 0 = My Recipes, 1 = Shared with Me
  String _recipeQuery = '';
  String _recipeSort = 'newest'; // newest | name | kcal_low | kcal_high
  final TextEditingController _recipeSearchController =
      TextEditingController();

  @override
  void dispose() {
    _recipeSearchController.dispose();
    super.dispose();
  }

  Future<void> _deleteRecipe(String recipeId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete recipe?'),
        content: const Text(
            "This removes the recipe. Food you've already logged from it stays in your history."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.red600),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      // Removes the recipe and its ingredient rows in one write. Food
      // already logged from it is kept, so balances don't change.
      await RecipeService.delete(
          FirebaseAuth.instance.currentUser!.uid, recipeId);

      if (mounted) {
        setState(() {
          _deleteMode = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recipe deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting recipe: $e')),
        );
      }
    }
  }

  Widget _buildMacroChip(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  // Share recipe with friends
  Future<void> _shareRecipe(String recipeId, String recipeName) async {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    // Fetch user's friends
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .get();

    final friends = (userDoc['friends'] as List? ?? []).cast<String>();

    if (friends.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No friends to share with. Add friends first.')),
        );
      }
      return;
    }

    // Fetch friend details
    final friendDocs = await Future.wait(friends.map((fId) =>
        FirebaseFirestore.instance.collection('users').doc(fId).get()));

    final Map<String, String> friendMap = {};
    for (var doc in friendDocs) {
      if (doc.exists) {
        friendMap[doc.id] = doc['email'] ?? 'Unknown';
      }
    }

    if (!mounted) return;

    // Show share dialog
    Set<String> selectedFriends = {};

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Share Recipe'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sharing: $recipeName',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.gray400,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select friends to share with:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: friendMap.length,
                    itemBuilder: (_, index) {
                      final friendId = friendMap.keys.toList()[index];
                      final friendEmail = friendMap[friendId]!;

                      return CheckboxListTile(
                        title: Text(friendEmail),
                        value: selectedFriends.contains(friendId),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              selectedFriends.add(friendId);
                            } else {
                              selectedFriends.remove(friendId);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedFriends.isEmpty
                  ? null
                  : () async {
                      await _performShare(recipeId, selectedFriends);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Recipe shared with ${selectedFriends.length} friend${selectedFriends.length > 1 ? 's' : ''}',
                            ),
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Share'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performShare(String recipeId, Set<String> friendIds) async {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    for (final friendId in friendIds) {
      await FirebaseFirestore.instance.collection('shared_recipes').add({
        'recipe_id': recipeId,
        'shared_by_user_id': currentUserId,
        'shared_with_user_id': friendId,
        'shared_at': FieldValue.serverTimestamp(),
      });
    }
  }

  // Copy recipe from friend
  Future<void> _copyRecipeFromFriend(String recipeId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Get the original recipe
      final originalRecipe =
          await firestore.collection('recipes').doc(recipeId).get();

      if (!originalRecipe.exists) {
        throw Exception('Recipe not found');
      }

      final data = originalRecipe.data()!;

      // Get all ingredients of the original recipe
      final ingredients = await firestore
          .collection('user_food')
          .where('user_id', isEqualTo: data['user_id'])
          .where('recipe_id', isEqualTo: recipeId)
          .where('foodCategory', isEqualTo: 'Recipe')
          .get();

      final batch = firestore.batch();
      final ingredientIds = <String>[];
      final newRecipeRef = firestore.collection('recipes').doc();

      // Create new ingredient documents for the current user
      for (final ing in ingredients.docs) {
        final docRef = firestore.collection('user_food').doc();
        ingredientIds.add(docRef.id);

        final ingData = ing.data();
        batch.set(docRef, {
          'user_id': uid,
          'food_description': ingData['food_description'],
          'food_calories': ingData['food_calories'],
          'food_protein': ingData['food_protein'],
          'food_carbs': ingData['food_carbs'],
          'food_fat': ingData['food_fat'],
          'food_portion': ingData['food_portion'] ?? '',
          'foodCategory': 'Recipe',
          'created_at': FieldValue.serverTimestamp(),
          'recipe_id': newRecipeRef.id,
        });
      }

      // Create new recipe document
      batch.set(newRecipeRef, {
        'user_id': uid,
        'name': '${data['name']} (Copy)',
        'serving_size': data['serving_size'],
        'food_item_ids': ingredientIds,
        'total_calories': data['total_calories'],
        'total_protein': data['total_protein'],
        'total_carbs': data['total_carbs'],
        'total_fat': data['total_fat'],
        'created_at': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recipe copied to your recipes!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error copying recipe: $e')),
        );
      }
    }
  }

  // Build "My Recipes" tab
  Widget _buildMyRecipesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('recipes')
          .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: AppColors.red300),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}',
                    style: TextStyle(color: AppColors.gray600)),
              ],
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.restaurant, size: 80, color: AppColors.gray300),
                const SizedBox(height: 16),
                Text(
                  'No recipes yet',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.gray600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap + to create your first recipe',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          );
        }

        final recipes = snapshot.data!.docs;
        recipes.sort((a, b) {
          final timeA = a['created_at'] as Timestamp?;
          final timeB = b['created_at'] as Timestamp?;
          if (timeA == null || timeB == null) return 0;
          return timeB.compareTo(timeA);
        });

        num kcalOf(QueryDocumentSnapshot r) =>
            ((r.data() as Map<String, dynamic>)['total_calories'] as num?) ??
            0;
        String nameOf(QueryDocumentSnapshot r) =>
            ((r.data() as Map<String, dynamic>)['name'] ?? '').toString();

        final q = _recipeQuery.trim().toLowerCase();
        final visible = recipes
            .where((r) => q.isEmpty || nameOf(r).toLowerCase().contains(q))
            .toList();
        switch (_recipeSort) {
          case 'name':
            visible.sort((a, b) =>
                nameOf(a).toLowerCase().compareTo(nameOf(b).toLowerCase()));
          case 'kcal_low':
            visible.sort((a, b) => kcalOf(a).compareTo(kcalOf(b)));
          case 'kcal_high':
            visible.sort((a, b) => kcalOf(b).compareTo(kcalOf(a)));
        }

        return Column(
          children: [
            _buildRecipeSearchBar(),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        'No recipes match "${_recipeQuery.trim()}"',
                        style: TextStyle(color: AppColors.gray600),
                      ),
                    )
                  : ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final recipe = visible[index];
            final totalCalories = (recipe['total_calories'] as num?) ?? 0;
            final protein = (recipe['total_protein'] as num?) ?? 0;
            final carbs = (recipe['total_carbs'] as num?) ?? 0;
            final fats = (recipe['total_fat'] as num?) ?? 0;
            final ingredientIds = (recipe['food_item_ids'] as List?) ?? [];

            final gradients = [
              [AppColors.violet400, AppColors.violet600],
              [AppColors.indigo400, AppColors.primaryDark],
              [AppColors.emerald400, AppColors.emerald600],
              [AppColors.amber400, AppColors.amber600],
              [AppColors.rose400, AppColors.rose600],
            ];
            final gradient = gradients[index % gradients.length];

            return GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddRecipePage(recipeId: recipe.id),
                  ),
                );
                if (mounted) {
                  setState(() {
                    _selectedTabIndex = 0;
                  });
                }
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradient,
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.restaurant,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  recipe['name'] ?? 'Recipe',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Colors.white,
                                  ),
                                ),
                                if (recipe['serving_size'] != null &&
                                    (recipe['serving_size'] as String)
                                        .isNotEmpty)
                                  Text(
                                    recipe['serving_size'],
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (_deleteMode)
                            IconButton(
                              onPressed: () async {
                                await _deleteRecipe(recipe.id);
                              },
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.white,
                                size: 24,
                              ),
                            )
                          else
                            IconButton(
                              onPressed: () =>
                                  _shareRecipe(recipe.id, recipe['name']),
                              icon: const Icon(
                                Icons.share_outlined,
                                color: Colors.white,
                                size: 24,
                              ),
                              tooltip: 'Share recipe',
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.amber50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.amber200,
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.local_fire_department,
                                        color: AppColors.amber600,
                                        size: 24,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        totalCalories.toStringAsFixed(0),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20,
                                          color: AppColors.amber700,
                                        ),
                                      ),
                                      Text(
                                        'kcal',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.gray600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.gray50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.border,
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.fastfood,
                                        color: AppColors.gray600,
                                        size: 24,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${ingredientIds.length}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 20,
                                          color: AppColors.gray700,
                                        ),
                                      ),
                                      Text(
                                        'items',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.gray600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildMacroChip(
                                  'Protein: ${protein.toStringAsFixed(0)}g',
                                  AppColors.primaryDark,
                                  AppColors.indigo50,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildMacroChip(
                                  'Carbs: ${carbs.toStringAsFixed(0)}g',
                                  AppColors.emerald600,
                                  AppColors.emerald50,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildMacroChip(
                                  'Fat: ${fats.toStringAsFixed(0)}g',
                                  AppColors.violet600,
                                  AppColors.violet50,
                                ),
                              ),
                            ],
                          ),
                          if (!_deleteMode) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => showLogRecipeSheet(
                                  context,
                                  recipeId: recipe.id,
                                  recipe:
                                      recipe.data() as Map<String, dynamic>,
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.credit_card, size: 18),
                                label: const Text(
                                  'Log to today',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecipeSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _recipeSearchController,
              onChanged: (v) => setState(() => _recipeQuery = v),
              decoration: InputDecoration(
                hintText: 'Search recipes',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _recipeQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _recipeSearchController.clear();
                          _recipeQuery = '';
                        }),
                      ),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.gray300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.gray300),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Sort',
            initialValue: _recipeSort,
            onSelected: (v) => setState(() => _recipeSort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'newest', child: Text('Newest first')),
              PopupMenuItem(value: 'name', child: Text('Name (A–Z)')),
              PopupMenuItem(value: 'kcal_low', child: Text('Lowest kcal')),
              PopupMenuItem(value: 'kcal_high', child: Text('Highest kcal')),
            ],
            child: Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.gray300),
              ),
              child: const Icon(Icons.sort),
            ),
          ),
        ],
      ),
    );
  }

  // Build "Shared with Me" tab
  Widget _buildSharedRecipesTab() {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shared_recipes')
          .where('shared_with_user_id', isEqualTo: currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: AppColors.red300),
                const SizedBox(height: 16),
                Text('Error: ${snapshot.error}',
                    style: TextStyle(color: AppColors.gray600)),
              ],
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.card_giftcard,
                    size: 80, color: AppColors.gray300),
                const SizedBox(height: 16),
                Text(
                  'No recipes shared yet',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.gray600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your friends will share recipes here',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          );
        }

        final sharedRecipes = snapshot.data!.docs;

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _loadSharedRecipeDetails(sharedRecipes),
          builder: (context, detailSnapshot) {
            if (detailSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!detailSnapshot.hasData || detailSnapshot.data!.isEmpty) {
              return Center(
                child: Text(
                  'No recipes available',
                  style: TextStyle(color: AppColors.gray600),
                ),
              );
            }

            final recipes = detailSnapshot.data!;

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: recipes.length,
              itemBuilder: (context, index) {
                final item = recipes[index];
                final recipe = item['recipe'] as Map<String, dynamic>;
                final sharedByEmail = item['sharedByEmail'] as String;
                final totalCalories = (recipe['total_calories'] as num?) ?? 0;
                final protein = (recipe['total_protein'] as num?) ?? 0;
                final carbs = (recipe['total_carbs'] as num?) ?? 0;
                final fats = (recipe['total_fat'] as num?) ?? 0;

                final gradients = [
                  [AppColors.violet400, AppColors.violet600],
                  [AppColors.indigo400, AppColors.primaryDark],
                  [AppColors.emerald400, AppColors.emerald600],
                  [AppColors.amber400, AppColors.amber600],
                  [AppColors.rose400, AppColors.rose600],
                ];
                final gradient = gradients[index % gradients.length];

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: gradient,
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.card_giftcard,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    recipe['name'] ?? 'Recipe',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    'Shared by $sharedByEmail',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.amber50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors.amber200,
                                        width: 1,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.local_fire_department,
                                          color: AppColors.amber600,
                                          size: 24,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          totalCalories.toStringAsFixed(0),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 20,
                                            color: AppColors.amber700,
                                          ),
                                        ),
                                        Text(
                                          'kcal',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.gray600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _copyRecipeFromFriend(
                                        item['recipe_id'] as String),
                                    child: Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.primary,
                                          width: 2,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.add_circle_outline,
                                            color: AppColors.primary,
                                            size: 24,
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'Copy',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildMacroChip(
                                    'Protein: ${protein.toStringAsFixed(0)}g',
                                    AppColors.primaryDark,
                                    AppColors.indigo50,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildMacroChip(
                                    'Carbs: ${carbs.toStringAsFixed(0)}g',
                                    AppColors.emerald600,
                                    AppColors.emerald50,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildMacroChip(
                                    'Fat: ${fats.toStringAsFixed(0)}g',
                                    AppColors.violet600,
                                    AppColors.violet50,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // Helper to load recipe details for shared recipes
  Future<List<Map<String, dynamic>>> _loadSharedRecipeDetails(
    List<QueryDocumentSnapshot> sharedRecipeDocs,
  ) async {
    final firestore = FirebaseFirestore.instance;
    final results = <Map<String, dynamic>>[];

    for (final doc in sharedRecipeDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final recipeId = data['recipe_id'] as String;
      final sharedByUserId = data['shared_by_user_id'] as String;

      try {
        // Get recipe details
        final recipeDoc =
            await firestore.collection('recipes').doc(recipeId).get();
        if (!recipeDoc.exists) continue;

        // Get shared by user email
        final userDoc =
            await firestore.collection('users').doc(sharedByUserId).get();
        final sharedByEmail = userDoc['email'] as String? ?? 'Unknown';

        results.add({
          'recipe_id': recipeId,
          'recipe': recipeDoc.data(),
          'sharedByEmail': sharedByEmail,
        });
      } catch (e) {
        // Skip if recipe or user not found
        continue;
      }
    }

    return results;
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.fromLTRB(16, topPadding + 16, 16, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.violet400,
                    AppColors.violet600,
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.violet.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.restaurant_menu,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recipes',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Create & share your recipes',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Tab buttons
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedTabIndex = 0;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: _selectedTabIndex == 0
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.3),
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Text(
                              'My Recipes',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: _selectedTabIndex == 0
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedTabIndex = 1;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: _selectedTabIndex == 1
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.3),
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Text(
                              'Shared with Me',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: _selectedTabIndex == 1
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _selectedTabIndex == 0
                  ? _buildMyRecipesTab()
                  : _buildSharedRecipesTab(),
            ),
          ],
        ),
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'recipes-add',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddRecipePage()),
              );
              if (mounted) {
                setState(() {
                  _selectedTabIndex = 0;
                });
              }
            },
            backgroundColor: AppColors.emerald400,
            child: const Icon(Icons.add),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'recipes-delete',
            onPressed: () {
              setState(() {
                _deleteMode = !_deleteMode;
              });
            },
            backgroundColor:
                _deleteMode ? AppColors.red600 : AppColors.red400,
            child: Icon(_deleteMode ? Icons.close : Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}
