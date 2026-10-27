import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/ui/skeleton.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/services/recipe_service.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/tutorials/tutorial_button.dart';
import 'package:namer_app/pages/add_recipe_page.dart';
import 'package:namer_app/ui/log_recipe_sheet.dart';
import 'package:namer_app/ui/calorie_symbol.dart';

/// A recipe a friend shared with you, ready to show. [recipe] is null when
/// it can't be shown: [gone] if the friend deleted it, otherwise it
/// couldn't be read (so it says so, rather than quietly vanishing).
class _SharedRecipe {
  final String recipeId;
  final Map<String, dynamic>? recipe;
  final String sharedBy;
  final Timestamp? sharedAt;
  final bool gone;

  const _SharedRecipe({
    required this.recipeId,
    required this.recipe,
    required this.sharedBy,
    this.sharedAt,
    this.gone = false,
  });
}

class RecipesPage extends StatefulWidget {
  const RecipesPage({super.key});

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
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

  /// Under the name: "Makes 1990 g" reads better than a bare "1990 g".
  static String _servingLabel(Map<String, dynamic> data) {
    final serving = _servingOf(data);
    return RegExp(r'^\d[\d.,]*\s*(g|kg|ml|l)$', caseSensitive: false)
            .hasMatch(serving)
        ? 'Makes $serving'
        : serving;
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

    // Friends who already have it: shown as shared, so it's never sent
    // twice (it would show up twice for them).
    final already = await _sharedWith(recipeId);
    if (!mounted) return;
    if (already.length >= friends.length) {
      _showMessage(friends.length == 1
          ? 'Already shared with ${friends.single.name}'
          : 'Already shared with all your friends');
      return;
    }

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
                      final shared = already.contains(friend.id);
                      return CheckboxListTile(
                        title: Text(friend.name),
                        subtitle: shared ? const Text('Already shared') : null,
                        value: shared || selectedFriends.contains(friend.id),
                        onChanged: sharing || shared
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

  /// The friends you've already shared [recipeId] with. Empty if it can't
  /// be checked (then sharing works as before).
  Future<Set<String>> _sharedWith(String recipeId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('shared_recipes')
          .where('shared_by_user_id', isEqualTo: uid)
          .where('recipe_id', isEqualTo: recipeId)
          .get();
      final friends = <String>{};
      final extras = <DocumentReference<Map<String, dynamic>>>[];
      for (final d in snap.docs) {
        final to = d.data()['shared_with_user_id'];
        if (to is! String) continue;
        // Shared more than once before this check existed: tidy up the
        // extra copies (best effort, they're hidden anyway).
        if (!friends.add(to)) extras.add(d.reference);
      }
      if (extras.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final r in extras) {
          batch.delete(r);
        }
        unawaited(batch.commit().catchError((_) {}));
      }
      return friends;
    } catch (_) {
      return const {};
    }
  }

  Future<void> _performShare(String recipeId, Set<String> friendIds) async {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    // Checked again here, in case it was shared from another device.
    final already = await _sharedWith(recipeId);

    for (final friendId in friendIds) {
      if (already.contains(friendId)) continue;
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

      _showMessage('Saved a copy to your recipes');
    } catch (_) {
      _showMessage("Couldn't save that recipe. Please try again.");
    } finally {
      if (mounted) setState(() => _copying.remove(recipeId));
    }
  }

  // --- Shared building blocks ----------------------------------------------

  Widget _buildRecipeCard({
    required Map<String, dynamic> data,
    required IconData icon,
    required String subtitle,
    int? ingredientCount,
    String? tag,
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
                          if (tag != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.indigo50,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  tag,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppText.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
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
                      const SizedBox(height: 10),
                      // One compact line (it was two rows of tiles, so
                      // only one or two recipes fitted on a screen).
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          // What a serving costs, like a price tag.
                          Text(
                            cals(kcal),
                            semanticsLabel:
                                '${kcal.toStringAsFixed(0)} calories',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: AppText.primaryDark,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(
                                    text: 'P ${protein.toStringAsFixed(0)}',
                                    style:
                                        TextStyle(color: AppColors.proteinText)),
                                const TextSpan(text: ' · '),
                                TextSpan(
                                    text: 'C ${carbs.toStringAsFixed(0)}',
                                    style: TextStyle(color: AppColors.carbsText)),
                                const TextSpan(text: ' · '),
                                TextSpan(
                                    text: 'F ${fat.toStringAsFixed(0)}',
                                    style: TextStyle(color: AppColors.fatText)),
                                if (ingredientCount != null)
                                  TextSpan(
                                    text: '  ·  $ingredientCount '
                                        '${ingredientCount == 1 ? 'ingredient' : 'ingredients'}',
                                    style: TextStyle(color: AppColors.muted),
                                  ),
                              ]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.muted,
                              ),
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
              PopupMenuItem(value: 'kcal_low', child: Text('Lowest calories')),
              PopupMenuItem(value: 'kcal_high', child: Text('Highest calories')),
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

  /// Your recipes and the ones friends shared with you, in one list:
  /// shared ones carry a "Shared by …" tag rather than hiding behind a tab.
  Widget _buildRecipes() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _myRecipesStream,
      builder: (context, mine) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _sharedStream,
          builder: (context, shared) {
            final sharedDocs = shared.data?.docs ?? const [];
            final key = sharedDocs.map((d) => d.id).join(',');
            if (shared.hasData && (_sharedFuture == null || key != _sharedKey)) {
              _sharedKey = key;
              _sharedFuture = _loadSharedRecipeDetails(sharedDocs);
            }
            return FutureBuilder<List<_SharedRecipe>>(
              future: _sharedFuture,
              builder: (context, details) =>
                  _buildRecipeList(mine, shared, details),
            );
          },
        );
      },
    );
  }

  Widget _buildRecipeList(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> mine,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> shared,
    AsyncSnapshot<List<_SharedRecipe>> details,
  ) {
    if (mine.hasError) {
      return _buildMessage(
        icon: Icons.cloud_off,
        iconColor: AppColors.gray400,
        title: "Couldn't load your recipes",
        body: 'Check your connection and try again.',
      );
    }
    if (!mine.hasData) return const SkeletonList();

    // Shared ones are still loading (or failed): show yours meanwhile.
    final sharedList = details.data ?? const <_SharedRecipe>[];
    final rows = <({String id, Map<String, dynamic>? data, _SharedRecipe? shared})>[
      for (final doc in mine.data!.docs) (id: doc.id, data: doc.data(), shared: null),
      for (final sr in sharedList) (id: sr.recipeId, data: sr.recipe, shared: sr),
    ];
    if (rows.isEmpty) {
      return _buildMessage(
        icon: Icons.restaurant,
        title: 'No recipes yet',
        body: 'Tap New recipe to save one you make often. Recipes friends '
            'share with you show up here too.',
      );
    }

    Timestamp? timeOf(({String id, Map<String, dynamic>? data, _SharedRecipe? shared}) r) =>
        r.shared != null
            ? (r.shared!.sharedAt ?? (r.data == null ? null : _timeOf(r.data!)))
            : _timeOf(r.data!);
    String nameOf(({String id, Map<String, dynamic>? data, _SharedRecipe? shared}) r) =>
        r.data == null ? '' : _nameOf(r.data!);
    double kcalOf(({String id, Map<String, dynamic>? data, _SharedRecipe? shared}) r) =>
        r.data == null ? 0 : _numOf(r.data!, 'total_calories');

    rows.sort((a, b) => _newestFirst(timeOf(a), timeOf(b)));
    final q = _recipeQuery.trim().toLowerCase();
    final visible = rows
        .where((r) =>
            q.isEmpty ||
            nameOf(r).toLowerCase().contains(q) ||
            (r.shared?.sharedBy.toLowerCase().contains(q) ?? false))
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
        if (shared.hasError || details.hasError)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              "Couldn't load recipes friends shared with you. Check your "
              'connection and try again.',
              style: TextStyle(color: AppColors.gray600, fontSize: 13),
            ),
          ),
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
                    final r = visible[index];
                    final sr = r.shared;
                    if (sr == null) return _ownRecipeCard(r.id, r.data!);
                    if (sr.recipe == null) return _unavailableCard(sr);
                    return _sharedRecipeCard(sr);
                  },
                ),
        ),
      ],
    );
  }

  Widget _ownRecipeCard(String recipeId, Map<String, dynamic> data) {
    final ids = data['food_item_ids'];
    return _buildRecipeCard(
      data: data,
      icon: Icons.restaurant,
      subtitle: _servingLabel(data),
      ingredientCount: ids is List ? ids.length : 0,
      onTap: () => _openEditor(recipeId: recipeId),
      menu: PopupMenuButton<String>(
        tooltip: 'More options',
        icon: Icon(Icons.more_vert, color: AppColors.muted),
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
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(
              value: 'share', child: Text('Share with friends')),
          PopupMenuItem(
            value: 'delete',
            child: Text('Delete', style: TextStyle(color: AppText.red600)),
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
        label: const Text('Add to today'),
      ),
    );
  }

  /// A friend's recipe: log it, or save your own copy to change.
  Widget _sharedRecipeCard(_SharedRecipe item) {
    final copying = _copying.contains(item.recipeId);
    return _buildRecipeCard(
      data: item.recipe!,
      icon: Icons.card_giftcard,
      subtitle: _servingLabel(item.recipe!),
      tag: 'Shared by ${item.sharedBy}',
      menu: PopupMenuButton<String>(
        tooltip: 'More options',
        icon: Icon(Icons.more_vert, color: AppColors.muted),
        enabled: !copying,
        onSelected: (value) {
          if (value == 'copy') _copyRecipeFromFriend(item.recipeId);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'copy',
            child: Text('Save a copy to edit'),
          ),
        ],
      ),
      actions: FilledButton.icon(
        onPressed: () => showLogRecipeSheet(
          context,
          recipeId: item.recipeId,
          recipe: item.recipe!,
        ),
        icon: const Icon(Icons.credit_card, size: 18),
        label: const Text('Add to today'),
      ),
    );
  }

  /// A share whose recipe can't be shown: says why instead of vanishing.
  Widget _unavailableCard(_SharedRecipe item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AppDecor.card,
      child: Row(
        children: [
          Icon(Icons.card_giftcard, color: AppColors.gray400),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.gone
                  ? '${item.sharedBy} shared a recipe that has since been '
                      'deleted.'
                  : "Couldn't open a recipe ${item.sharedBy} shared with "
                      'you. Try again later.',
              style: TextStyle(color: AppColors.gray700),
            ),
          ),
        ],
      ),
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

    // The same recipe shared more than once shows once (the newest).
    final seen = <String>{};
    final names = <String, String>{};
    for (final doc in docs) {
      final data = doc.data();
      final recipeId = data['recipe_id'];
      final sharedByUserId = data['shared_by_user_id'];
      final at = data['shared_at'];
      if (recipeId is! String || recipeId.isEmpty) continue;
      if (!seen.add(recipeId)) continue;

      var sharedBy = 'a friend';
      if (sharedByUserId is String && sharedByUserId.isNotEmpty) {
        try {
          sharedBy = names[sharedByUserId] ??= FriendsService.nameFromUser(
              (await firestore.collection('users').doc(sharedByUserId).get())
                  .data());
        } catch (_) {}
      }
      try {
        final recipeDoc =
            await firestore.collection('recipes').doc(recipeId).get();
        results.add(_SharedRecipe(
          recipeId: recipeId,
          recipe: recipeDoc.exists ? recipeDoc.data() : null,
          sharedBy: sharedBy,
          sharedAt: at is Timestamp ? at : null,
          gone: !recipeDoc.exists,
        ));
      } catch (_) {
        // Couldn't read it (permissions or connection): show that.
        results.add(_SharedRecipe(
          recipeId: recipeId,
          recipe: null,
          sharedBy: sharedBy,
          sharedAt: at is Timestamp ? at : null,
        ));
      }
    }
    return results;
  }

  // --- Page -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Recipes'),
        actions: const [ScreenHelpButton(tutorialIds: ['recipe', 'recipe_import'])],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: FirstVisitHint(
                screen: 'recipes',
                label: 'recipes',
                tutorialIds: const ['recipe', 'recipe_import'],
                onShow: () =>
                    showScreenHelp(context, tutorialIds: const ['recipe', 'recipe_import']),
              ),
            ),
            Expanded(child: _buildRecipes()),
          ],
        ),
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
