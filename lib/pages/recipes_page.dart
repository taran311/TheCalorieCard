import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/services/recipe_service.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/pages/add_recipe_page.dart';
import 'package:namer_app/ui/log_recipe_sheet.dart';

/// A recipe a friend shared with you, ready to show.
class _SharedRecipe {
  final String recipeId;
  final Map<String, dynamic> recipe;
  final String sharedBy;

  const _SharedRecipe({
    required this.recipeId,
    required this.recipe,
    required this.sharedBy,
  });
}

class RecipesPage extends StatefulWidget {
  const RecipesPage({super.key});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
  int _selectedTabIndex = 0; // 0 = My recipes, 1 = Shared with me
  String _recipeQuery = '';
  String _recipeSort = 'newest'; // newest | name | kcal_low | kcal_high
  final TextEditingController _recipeSearchController =
      TextEditingController();

  // Streams are created once so typing in search or switching tabs doesn't
  // resubscribe (and flash a spinner) on every rebuild.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _myRecipesStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _sharedStream;

  // Shared recipe details, reloaded only when the set of shares changes.
  String? _sharedKey;
  Future<List<_SharedRecipe>>? _sharedFuture;

  // Shared recipes currently being saved to My recipes (double-tap guard).
  final Set<String> _copying = {};

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _myRecipesStream = FirebaseFirestore.instance
        .collection('recipes')
        .where('user_id', isEqualTo: uid)
        .snapshots();
    _sharedStream = FirebaseFirestore.instance
        .collection('shared_recipes')
        .where('shared_with_user_id', isEqualTo: uid)
        .snapshots();
  }

  @override
  void dispose() {
    _recipeSearchController.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  // --- Safe field reads -----------------------------------------------------

  static String _nameOf(Map<String, dynamic> data) {
    final name = (data['name'] ?? '').toString().trim();
    return name.isEmpty ? 'Recipe' : name;
  }

  static String _servingOf(Map<String, dynamic> data) {
    final serving = data['serving_size'];
    return serving is String ? serving.trim() : '';
  }

  static double _numOf(Map<String, dynamic> data, String key) =>
      BalanceService.number(data[key]) ?? 0;

  static Timestamp? _timeOf(Map<String, dynamic> data) {
    final t = data['created_at'];
    return t is Timestamp ? t : null;
  }

  /// Newest first. A missing time means the write is still pending, so it
  /// is the newest of all.
  static int _newestFirst(Timestamp? a, Timestamp? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    return b.compareTo(a);
  }

  // --- Actions --------------------------------------------------------------

  Future<void> _openEditor({String? recipeId}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddRecipePage(recipeId: recipeId)),
    );
    // A new recipe lands in My recipes, so show that tab.
    if (recipeId == null && mounted && _selectedTabIndex != 0) {
      setState(() => _selectedTabIndex = 0);
    }
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
      _showMessage('Recipe deleted');
    } catch (_) {
      _showMessage("Couldn't delete that recipe. Please try again.");
    }
  }

  // Share recipe with friends
  Future<void> _shareRecipe(String recipeId, String recipeName) async {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;

    List<Friend> friends;
    try {
      friends = await FriendsService.load(currentUserId);
    } catch (_) {
      _showMessage("Couldn't share that recipe. Please try again.");
      return;
    }

    if (friends.isEmpty) {
      _showMessage(
          "You haven't added any friends yet. Add some in Friends to share recipes.");
      return;
    }

    if (!mounted) return;

    final selectedFriends = <String>{};
    var sharing = false;

    final sharedCount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Share recipe'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipeName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Choose friends',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: friends.length,
                    itemBuilder: (_, index) {
                      final friend = friends[index];
                      return CheckboxListTile(
                        title: Text(friend.name),
                        value: selectedFriends.contains(friend.id),
                        onChanged: sharing
                            ? null
                            : (value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selectedFriends.add(friend.id);
                                  } else {
                                    selectedFriends.remove(friend.id);
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
              onPressed: sharing ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selectedFriends.isEmpty || sharing
                  ? null
                  : () async {
                      setDialogState(() => sharing = true);
                      try {
                        await _performShare(recipeId, selectedFriends);
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, selectedFriends.length);
                        }
                      } catch (_) {
                        if (dialogContext.mounted) {
                          setDialogState(() => sharing = false);
                        }
                        _showMessage(
                            "Couldn't share that recipe. Please try again.");
                      }
                    },
              child: sharing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppText.primaryDark,
                      ),
                    )
                  : const Text('Share'),
            ),
          ],
        ),
      ),
    );

    if (sharedCount != null && sharedCount > 0) {
      _showMessage(
          'Recipe shared with $sharedCount friend${sharedCount == 1 ? '' : 's'}');
    }
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

  // Save a friend's recipe as your own copy.
  Future<void> _copyRecipeFromFriend(String recipeId) async {
    if (_copying.contains(recipeId)) return;
    setState(() => _copying.add(recipeId));
    try {
      final firestore = FirebaseFirestore.instance;
      final uid = FirebaseAuth.instance.currentUser!.uid;

      final original =
          await firestore.collection('recipes').doc(recipeId).get();
      final data = original.data();
      if (!original.exists || data == null) {
        throw StateError('Recipe not found');
      }

      final ingredientDocs = await firestore
          .collection('user_food')
          .where('user_id', isEqualTo: data['user_id'])
          .where('recipe_id', isEqualTo: recipeId)
          .where('foodCategory', isEqualTo: BalanceService.recipeCategory)
          .get();

      final ingredients = <RecipeIngredient>[
        for (final doc in ingredientDocs.docs)
          RecipeIngredient(
            name: (doc.data()['food_description'] ?? 'Ingredient').toString(),
            macros: Macros.fromEntry(doc.data()),
            portion: (doc.data()['food_portion'] ?? '').toString(),
          ),
      ];

      final serving = _servingOf(data);
      await RecipeService.create(
        uid,
        name: '${_nameOf(data)} (copy)',
        servingSize: serving.isEmpty ? 'Per 1 Serving' : serving,
        ingredients: ingredients,
      );

      _showMessage('Saved to My recipes');
    } catch (_) {
      _showMessage("Couldn't save that recipe. Please try again.");
    } finally {
      if (mounted) setState(() => _copying.remove(recipeId));
    }
  }

  // --- Shared building blocks ----------------------------------------------

  Widget _buildMacroChip(String label, Color textColor, Color baseColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.1),
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

  Widget _buildStatTile({
    required IconData icon,
    required String value,
    required String label,
    required Color fill,
    required Color border,
    required Color valueColor,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: valueColor,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipeCard({
    required Map<String, dynamic> data,
    required IconData icon,
    required String subtitle,
    int? ingredientCount,
    Widget? menu,
    VoidCallback? onTap,
    required Widget actions,
  }) {
    final kcal = _numOf(data, 'total_calories');
    final protein = _numOf(data, 'total_protein');
    final carbs = _numOf(data, 'total_carbs');
    final fat = _numOf(data, 'total_fat');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppDecor.card,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDecor.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.indigo50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: AppText.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _nameOf(data),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              color: AppColors.ink,
                            ),
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (menu != null) menu else const SizedBox(width: 8),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatTile(
                              icon: Icons.local_fire_department,
                              value: kcal.toStringAsFixed(0),
                              label: 'kcal',
                              fill: AppColors.indigo50,
                              border: AppColors.indigo100,
                              valueColor: AppColors.primaryDark,
                              iconColor: AppText.primary,
                            ),
                          ),
                          if (ingredientCount != null) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatTile(
                                icon: Icons.fastfood,
                                value: '$ingredientCount',
                                label: ingredientCount == 1
                                    ? 'ingredient'
                                    : 'ingredients',
                                fill: AppColors.gray50,
                                border: AppColors.border,
                                valueColor: AppColors.gray700,
                                iconColor: AppColors.gray600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMacroChip(
                              'Protein ${protein.toStringAsFixed(0)}g',
                              AppColors.proteinText,
                              AppColors.protein,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMacroChip(
                              'Carbs ${carbs.toStringAsFixed(0)}g',
                              AppColors.carbsText,
                              AppColors.carbs,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMacroChip(
                              'Fat ${fat.toStringAsFixed(0)}g',
                              AppColors.fatText,
                              AppColors.fat,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      actions,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String body,
    Color? iconColor,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: iconColor ?? AppColors.gray300),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.gray700,
              ),
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- My recipes -----------------------------------------------------------

  Widget _buildMyRecipesTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _myRecipesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildMessage(
            icon: Icons.cloud_off,
            iconColor: AppColors.gray400,
            title: "Couldn't load your recipes",
            body: 'Check your connection and try again.',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.docs.isEmpty) {
          return _buildMessage(
            icon: Icons.restaurant,
            title: 'No recipes yet',
            body: 'Tap New recipe to save one you make often.',
          );
        }

        final recipes = [
          for (final doc in snapshot.data!.docs) MapEntry(doc.id, doc.data()),
        ];
        recipes.sort((a, b) => _newestFirst(_timeOf(a.value), _timeOf(b.value)));

        final q = _recipeQuery.trim().toLowerCase();
        final visible = recipes
            .where(
                (r) => q.isEmpty || _nameOf(r.value).toLowerCase().contains(q))
            .toList();
        switch (_recipeSort) {
          case 'name':
            visible.sort((a, b) => _nameOf(a.value)
                .toLowerCase()
                .compareTo(_nameOf(b.value).toLowerCase()));
          case 'kcal_low':
            visible.sort((a, b) => _numOf(a.value, 'total_calories')
                .compareTo(_numOf(b.value, 'total_calories')));
          case 'kcal_high':
            visible.sort((a, b) => _numOf(b.value, 'total_calories')
                .compareTo(_numOf(a.value, 'total_calories')));
        }

        return Column(
          children: [
            _buildRecipeSearchBar(),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No recipes match "${_recipeQuery.trim()}"',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.gray600),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final recipeId = visible[index].key;
                        final data = visible[index].value;
                        final ids = data['food_item_ids'];
                        return _buildRecipeCard(
                          data: data,
                          icon: Icons.restaurant,
                          subtitle: _servingOf(data),
                          ingredientCount: ids is List ? ids.length : 0,
                          onTap: () => _openEditor(recipeId: recipeId),
                          menu: PopupMenuButton<String>(
                            tooltip: 'More options',
                            icon: Icon(Icons.more_vert,
                                color: AppColors.muted),
                            onSelected: (value) {
                              switch (value) {
                                case 'edit':
                                  _openEditor(recipeId: recipeId);
                                case 'share':
                                  _shareRecipe(recipeId, _nameOf(data));
                                case 'delete':
                                  _deleteRecipe(recipeId);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              PopupMenuItem(
                                value: 'share',
                                child: Text('Share with friends'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  'Delete',
                                  style: TextStyle(color: AppText.red600),
                                ),
                              ),
                            ],
                          ),
                          actions: FilledButton.icon(
                            onPressed: () => showLogRecipeSheet(
                              context,
                              recipeId: recipeId,
                              recipe: data,
                            ),
                            icon: const Icon(Icons.credit_card, size: 18),
                            label: const Text('Log to today'),
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
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _recipeSearchController.clear();
                          _recipeQuery = '';
                        }),
                      ),
                filled: true,
                fillColor: AppColors.surface,
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
                color: AppColors.surface,
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

  // --- Shared with me -------------------------------------------------------

  Widget _buildSharedRecipesTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _sharedStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildMessage(
            icon: Icons.cloud_off,
            iconColor: AppColors.gray400,
            title: "Couldn't load your shared recipes",
            body: 'Check your connection and try again.',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final emptyState = _buildMessage(
          icon: Icons.card_giftcard,
          title: 'No shared recipes yet',
          body: 'Recipes friends share with you will show up here.',
        );
        if (snapshot.data!.docs.isEmpty) return emptyState;

        final sharedDocs = snapshot.data!.docs;
        final key = sharedDocs.map((d) => d.id).join(',');
        if (_sharedFuture == null || key != _sharedKey) {
          _sharedKey = key;
          _sharedFuture = _loadSharedRecipeDetails(sharedDocs);
        }

        return FutureBuilder<List<_SharedRecipe>>(
          future: _sharedFuture,
          builder: (context, detailSnapshot) {
            if (detailSnapshot.hasError) {
              return _buildMessage(
                icon: Icons.cloud_off,
                iconColor: AppColors.gray400,
                title: "Couldn't load your shared recipes",
                body: 'Check your connection and try again.',
              );
            }
            if (!detailSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final recipes = detailSnapshot.data!;
            if (recipes.isEmpty) return emptyState;

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: recipes.length,
              itemBuilder: (context, index) {
                final item = recipes[index];
                final copying = _copying.contains(item.recipeId);
                return _buildRecipeCard(
                  data: item.recipe,
                  icon: Icons.card_giftcard,
                  subtitle: 'Shared by ${item.sharedBy}',
                  actions: LayoutBuilder(
                    builder: (context, constraints) {
                      final save = OutlinedButton.icon(
                        onPressed: copying
                            ? null
                            : () => _copyRecipeFromFriend(item.recipeId),
                        icon: copying
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.bookmark_add_outlined, size: 18),
                        label: const Text('Save to mine'),
                      );
                      final log = FilledButton.icon(
                        onPressed: () => showLogRecipeSheet(
                          context,
                          recipeId: item.recipeId,
                          recipe: item.recipe,
                        ),
                        icon: const Icon(Icons.credit_card, size: 18),
                        label: const Text('Log to today'),
                      );
                      if (constraints.maxWidth < 300) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [save, const SizedBox(height: 8), log],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: save),
                          const SizedBox(width: 8),
                          Expanded(child: log),
                        ],
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // Loads the recipe and sharer's name for each share.
  Future<List<_SharedRecipe>> _loadSharedRecipeDetails(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sharedRecipeDocs,
  ) async {
    final firestore = FirebaseFirestore.instance;
    final results = <_SharedRecipe>[];

    // Newest shares first; pending ones (no time yet) count as newest.
    final docs = [...sharedRecipeDocs];
    docs.sort((a, b) {
      final ta = a.data()['shared_at'];
      final tb = b.data()['shared_at'];
      return _newestFirst(
          ta is Timestamp ? ta : null, tb is Timestamp ? tb : null);
    });

    for (final doc in docs) {
      final data = doc.data();
      final recipeId = data['recipe_id'];
      final sharedByUserId = data['shared_by_user_id'];
      if (recipeId is! String || recipeId.isEmpty) continue;

      try {
        final recipeDoc =
            await firestore.collection('recipes').doc(recipeId).get();
        final recipe = recipeDoc.data();
        if (!recipeDoc.exists || recipe == null) continue;

        String? email;
        if (sharedByUserId is String && sharedByUserId.isNotEmpty) {
          final userDoc =
              await firestore.collection('users').doc(sharedByUserId).get();
          final e = userDoc.data()?['email'];
          email = e is String ? e : null;
        }

        results.add(_SharedRecipe(
          recipeId: recipeId,
          recipe: recipe,
          sharedBy: FriendsService.displayName(email),
        ));
      } catch (_) {
        // Skip a share whose recipe or sharer can't be read.
        continue;
      }
    }

    return results;
  }

  // --- Page -----------------------------------------------------------------

  Widget _buildTab(String label, int index) {
    final selected = _selectedTabIndex == index;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          height: 48,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.3),
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Recipes'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Row(
            children: [
              Expanded(child: _buildTab('My recipes', 0)),
              Expanded(child: _buildTab('Shared with me', 1)),
            ],
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _selectedTabIndex == 0
            ? _buildMyRecipesTab()
            : _buildSharedRecipesTab(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'recipes-add',
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New recipe'),
      ),
    );
  }
}
