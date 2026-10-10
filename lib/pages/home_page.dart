import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/pages/achievements_page.dart';
import 'package:namer_app/pages/add_food_page.dart';
import 'package:namer_app/pages/coach_page.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/services/achievement_service.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/card_design_service.dart';
import 'package:namer_app/services/direct_debit_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/services/leaderboard_service.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/coach_nudge.dart';
import 'package:namer_app/ui/home_inbox.dart';
import 'package:namer_app/ui/home_widgets.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/spotlight_tour.dart';
import 'package:namer_app/ui/tutorials/tutorial_button.dart';

class HomePage extends StatefulWidget {
  final bool readOnly;
  final String? userIdOverride;
  final String? bannerTitle;
  final bool showBanner;

  const HomePage(
      {Key? key,
      this.readOnly = false,
      this.userIdOverride,
      this.bannerTitle,
      this.showBanner = false})
      : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _SelectExistingRecipePage extends StatefulWidget {
  /// The meal the recipe will be logged to (for the button label).
  final String meal;

  const _SelectExistingRecipePage({required this.meal});

  @override
  State<_SelectExistingRecipePage> createState() =>
      _SelectExistingRecipePageState();
}

class _SelectExistingRecipePageState extends State<_SelectExistingRecipePage> {
  int? _editingRecipeIndex;
  final TextEditingController _portionController = TextEditingController();
  int _selectedTabIndex = 0; // 0 = My recipes, 1 = Shared with me

  // Created once, so typing a portion (which rebuilds the page) doesn't
  // re-subscribe and drop the text field's focus.
  late final Stream<QuerySnapshot> _myRecipes = FirebaseFirestore.instance
      .collection('recipes')
      .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
      .snapshots();
  late final Stream<QuerySnapshot> _sharedRecipes = FirebaseFirestore.instance
      .collection('shared_recipes')
      .where('shared_with_user_id',
          isEqualTo: FirebaseAuth.instance.currentUser!.uid)
      .snapshots();

  // Shared recipe details, cached for the current set of shared docs.
  Future<List<Map<String, dynamic>>>? _sharedDetails;
  String? _sharedDetailsKey;

  @override
  void dispose() {
    _portionController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _sharedDetailsFor(
      List<QueryDocumentSnapshot> docs) {
    final key = docs.map((d) => d.id).join(',');
    final cached = _sharedDetails;
    if (cached != null && key == _sharedDetailsKey) return cached;
    _sharedDetailsKey = key;
    final future = _loadSharedRecipeDetailsForHome(docs);
    _sharedDetails = future;
    return future;
  }

  Widget _tab(int index, String label) {
    final selected = _selectedTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTabIndex = index;
            _editingRecipeIndex = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.primary : AppColors.border,
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? AppColors.primaryDark : AppColors.gray600,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _message(String text, {IconData icon = Icons.menu_book_outlined}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.gray400),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.gray600, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorMessage() => _message(
        "Couldn't load your recipes. Please try again.",
        icon: Icons.cloud_off_outlined,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Add a recipe'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Material(
            color: Colors.white,
            child: Row(
              children: [
                _tab(0, 'My recipes'),
                _tab(1, 'Shared with me'),
              ],
            ),
          ),
        ),
      ),
      body: _selectedTabIndex == 0
          ? _buildMyRecipesTab()
          : _buildSharedRecipesTab(),
    );
  }

  Widget _buildMyRecipesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _myRecipes,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _errorMessage();
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _message(
              "No recipes yet. Save one on the Recipes tab and it'll show here.");
        }

        final recipes = List<QueryDocumentSnapshot>.from(snapshot.data!.docs);
        // Sort by created_at descending (client-side)
        recipes.sort((a, b) {
          // data()[...] rather than doc[...]: older recipes may be missing
          // fields, and doc[...] throws for those.
          final timeA = (a.data() as Map)['created_at'] as Timestamp?;
          final timeB = (b.data() as Map)['created_at'] as Timestamp?;
          if (timeA == null || timeB == null) return 0;
          return timeB.compareTo(timeA);
        });

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 48),
          itemCount: recipes.length,
          itemBuilder: (context, index) {
            final recipe = recipes[index];
            final r = recipe.data() as Map<String, dynamic>;
            final calories = BalanceService.number(r['total_calories']) ?? 0;
            final protein = BalanceService.number(r['total_protein']) ?? 0;
            final carbs = BalanceService.number(r['total_carbs']) ?? 0;
            final fat = BalanceService.number(r['total_fat']) ?? 0;
            final servingSize =
                (r['serving_size'] as String?) ?? 'Per 1 Serving';
            final isEditing = _editingRecipeIndex == index;

            // Parse serving size to determine unit and value
            final isGrams = servingSize.contains('g') &&
                !servingSize.toLowerCase().contains('serving');
            final originalServingValue = FoodLog.servingAmount(servingSize);
            final unit = isGrams
                ? 'g'
                : 'serving${originalServingValue != 1 ? 's' : ''}';

            return Column(
              children: [
                ListTile(
                  title: Text(
                    (r['name'] ?? 'Recipe').toString(),
                    style: const TextStyle(
                        color: AppColors.ink, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${calories.toStringAsFixed(0)} kcal ($servingSize)',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  trailing: const Icon(Icons.add_circle_outline,
                      color: AppColors.primary),
                  onTap: () {
                    setState(() {
                      _editingRecipeIndex = index;
                      _portionController.text =
                          FoodLog.formatAmount(originalServingValue);
                    });
                  },
                ),
                if (isEditing)
                  _buildExpandedPortionView(
                    recipe.id,
                    r,
                    calories,
                    protein,
                    carbs,
                    fat,
                    originalServingValue,
                    isGrams,
                    unit,
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSharedRecipesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _sharedRecipes,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _errorMessage();
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _message('Nothing shared with you yet.',
              icon: Icons.people_outline);
        }

        final sharedRecipeDocs = snapshot.data!.docs;

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _sharedDetailsFor(sharedRecipeDocs),
          builder: (context, detailSnapshot) {
            if (detailSnapshot.hasError) return _errorMessage();
            if (detailSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!detailSnapshot.hasData || detailSnapshot.data!.isEmpty) {
              return _message("Those recipes aren't available any more.",
                  icon: Icons.people_outline);
            }

            final recipes = detailSnapshot.data!;

            return ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 48),
              itemCount: recipes.length,
              itemBuilder: (context, index) {
                final item = recipes[index];
                final recipe = item['recipe'] as Map<String, dynamic>;
                final recipeId = item['recipe_id'] as String;
                final calories =
                    BalanceService.number(recipe['total_calories']) ?? 0;
                final protein =
                    BalanceService.number(recipe['total_protein']) ?? 0;
                final carbs = BalanceService.number(recipe['total_carbs']) ?? 0;
                final fat = BalanceService.number(recipe['total_fat']) ?? 0;
                final servingSize =
                    recipe['serving_size'] as String? ?? 'Per 1 Serving';
                final isEditing = _editingRecipeIndex == index;

                final isGrams = servingSize.contains('g') &&
                    !servingSize.toLowerCase().contains('serving');
                final originalServingValue =
                    FoodLog.servingAmount(servingSize);
                final unit = isGrams
                    ? 'g'
                    : 'serving${originalServingValue != 1 ? 's' : ''}';
                final sharedBy = FriendsService.displayName(
                    item['sharedByEmail'] as String?);

                return Column(
                  children: [
                    ListTile(
                      title: Text(
                        (recipe['name'] ?? 'Recipe').toString(),
                        style: const TextStyle(
                            color: AppColors.ink, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${calories.toStringAsFixed(0)} kcal ($servingSize)\nShared by $sharedBy',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.add_circle_outline,
                          color: AppColors.primary),
                      onTap: () {
                        setState(() {
                          _editingRecipeIndex = index;
                          _portionController.text =
                              FoodLog.formatAmount(originalServingValue);
                        });
                      },
                    ),
                    if (isEditing)
                      _buildExpandedPortionView(
                        recipeId,
                        recipe,
                        calories,
                        protein,
                        carbs,
                        fat,
                        originalServingValue,
                        isGrams,
                        unit,
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _macroBox(String name, Color color, double grams) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: AppDecor.inset,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${grams.toStringAsFixed(1)}g',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedPortionView(
    String recipeId,
    Map<String, dynamic> recipe,
    num calories,
    double protein,
    double carbs,
    double fat,
    double originalServingValue,
    bool isGrams,
    String unit,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: AppDecor.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Amount',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _portionController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => setState(() {}),
                  onTapOutside: (_) {
                    FocusScope.of(context).unfocus();
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(
                unit,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.gray700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Builder(
            builder: (context) {
              final typed = double.tryParse(_portionController.text.trim());
              // Only amounts above zero can be logged; anything else would
              // log nothing or credit the card.
              final validPortion =
                  typed != null && typed.isFinite && typed > 0;
              final newPortion = validPortion ? typed! : originalServingValue;
              final ratio = newPortion / originalServingValue;
              final adjustedCalories = (calories * ratio).round();
              final adjustedProtein = protein * ratio;
              final adjustedCarbs = carbs * ratio;
              final adjustedFat = fat * ratio;

              return Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.indigo50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$adjustedCalories',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'kcal',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _macroBox('Protein', AppColors.protein, adjustedProtein),
                      const SizedBox(width: 8),
                      _macroBox('Carbs', AppColors.carbs, adjustedCarbs),
                      const SizedBox(width: 8),
                      _macroBox('Fat', AppColors.fat, adjustedFat),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _editingRecipeIndex = null;
                          });
                        },
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FilledButton(
                          onPressed: !validPortion
                              ? null
                              : () {
                                  final multiplier = ratio;
                                  Navigator.pop(context, {
                                    'recipeId': recipeId,
                                    'multiplier': multiplier,
                                  });
                                },
                          child: Text(
                            'Add to ${widget.meal}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadSharedRecipeDetailsForHome(
    List<QueryDocumentSnapshot> sharedRecipeDocs,
  ) async {
    final firestore = FirebaseFirestore.instance;
    final results = <Map<String, dynamic>>[];

    for (final doc in sharedRecipeDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final recipeId = data['recipe_id'] as String;
      final sharedByUserId = data['shared_by_user_id'] as String;

      try {
        final recipeDoc =
            await firestore.collection('recipes').doc(recipeId).get();
        if (!recipeDoc.exists) continue;

        final userDoc =
            await firestore.collection('users').doc(sharedByUserId).get();
        final sharedByEmail =
            userDoc.data()?['email'] as String? ?? 'Unknown';

        results.add({
          'recipe_id': recipeId,
          'recipe': recipeDoc.data(),
          'sharedByEmail': sharedByEmail,
        });
      } catch (e) {
        continue;
      }
    }

    return results;
  }
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String get _activeUserId =>
      widget.userIdOverride ?? FirebaseAuth.instance.currentUser!.uid;

  /// Your own card (not a friend's): the only one we ever write to.
  bool get _isOwnCard => !widget.readOnly && widget.userIdOverride == null;

  /// Food can be added or removed only on today's card, and only until the
  /// day is finished. Past days are a statement: read-only.
  bool get _canEditSelectedDay =>
      _isOwnCard && _isSelectedDateToday && !_isDayFinished;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _foodDocs = [];

  /// Everything eaten on the selected day, all meals.
  Macros _dayTotals = Macros.zero;

  // Guards against slow, out-of-order loads (fast tab or day switching).
  int _foodLoadToken = 0;
  int _dailyLogLoadToken = 0;

  // Day rollover while the app stays open.
  DateTime _lastKnownToday = BalanceService.now();
  Timer? _midnightTimer;

  Future<void>? _refreshing;
  bool _refreshAgain = false;

  /// The card finish the card's owner picked (live).
  CardDesign _cardDesign = CardDesign.midnight;
  StreamSubscription<CardDesign>? _designSub;
  final List<String> _tabs = ['Brekkie', 'Lunch', 'Dinner', 'Snacks'];
  int _creditCardRefreshKey = 0;
  bool _isLoading = true;

  // First-time walkthrough of the Card screen.
  final _tourCard = GlobalKey(debugLabel: 'tour-home-card');
  final _tourDay = GlobalKey(debugLabel: 'tour-home-day');
  final _tourMeals = GlobalKey(debugLabel: 'tour-home-meals');
  final _tourAdd = GlobalKey(debugLabel: 'tour-home-add');
  final _tourTutorials = GlobalKey(debugLabel: 'tour-home-tutorials');
  bool _isDayFinished = false;
  bool _isUpdatingDailyLog = false;
  double _cardDragDx = 0;
  DateTime _selectedLogDate = DateTime.now();
  Map<String, dynamic>? _selectedDailyLog;

  // User goals for unlogged days
  int? _userCalorieGoal;
  double? _userProteinGoal;
  double? _userCarbsGoal;
  double? _userFatsGoal;

  // Category totals tracking
  bool _showMacrosTotal = false;
  int _totalCalories = 0;
  double _totalProtein = 0.0;
  double _totalCarbs = 0.0;
  double _totalFat = 0.0;

  /// Calories logged per meal on the selected day (for the meal tabs).
  Map<String, int> _mealKcal = const {};

  /// Today's live balance, as the card loaded it (null until it has).
  int? _liveBalance;

  /// Foods swiped away whose Undo snackbar is still showing. They're hidden
  /// now and only deleted once the snackbar closes without Undo.
  final Set<String> _pendingRemoval = {};
  Future<void> _removalChain = Future<void>.value();

  /// Yesterday's food (for "Copy yesterday's ..."), cached per day.
  List<Map<String, dynamic>> _yesterdayEntries = const [];
  String? _yesterdayKey;
  bool _copyingYesterday = false;

  // Individual food item macro visibility tracking
  Map<String, bool> _foodMacrosVisibility = {};

  // Food reaction tracking
  Map<String, List<Map<String, dynamic>>> _foodReactions = {};
  Map<String, bool> _showEmojiPicker = {};
  Map<String, bool> _showReactions = {};
  String? _reactionConfirmationFoodId;
  String? _reactionConfirmationEmoji;
  String? _reactionConfirmationUsername;
  AnimationController? _reactionFadeController;
  Animation<double>? _reactionFadeAnimation;

  // Card animations
  AnimationController? _jiggleAnimationController;
  Animation<double>? _jiggleAnimation;
  AnimationController? _cardDragResetController;
  double _dragEndDx = 0;
  bool _isResettingCard = false;
  bool _pendingSwipePrompt = false;
  bool _isDeletingItem = false;

  // Food input

  String _roundMacro(dynamic value) {
    final numVal =
        (value is num) ? value.toDouble() : double.tryParse('$value') ?? 0.0;
    return numVal.toStringAsFixed(1).endsWith('.5')
        ? numVal.ceil().toString()
        : numVal.round().toString();
  }

  @override
  void initState() {
    super.initState();
    _jiggleAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _reactionFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _reactionFadeAnimation = CurvedAnimation(
      parent: _reactionFadeController!,
      curve: Curves.easeInOut,
    );

    _jiggleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.05, end: -0.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.05, end: 0.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.05, end: -0.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.05, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _jiggleAnimationController!,
      curve: Curves.easeInOut,
    ));

    _cardDragResetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _initializeHome();
    FoodLog.changed.addListener(_onFoodLogChanged);
    _designSub = CardDesignService.watch(_activeUserId).listen(
      (d) {
        if (mounted && d.id != _cardDesign.id) {
          setState(() => _cardDesign = d);
        }
      },
      onError: (_) {},
    );
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnightCheck();
  }

  /// Food was logged or removed (here or on another screen): refresh.
  void _onFoodLogChanged() {
    if (!mounted || !_isOwnCard) return;
    _refreshAfterChange();
  }

  /// Reloads the food list, totals, the day's history snapshot and the
  /// card. Calls that arrive while a refresh is running are merged into
  /// one follow-up refresh.
  Future<void> _refreshAfterChange() {
    final running = _refreshing;
    if (running != null) {
      _refreshAgain = true;
      return running;
    }
    final future = _doRefresh().whenComplete(() {
      _refreshing = null;
      if (_refreshAgain && mounted) {
        _refreshAgain = false;
        _refreshAfterChange();
      }
    });
    _refreshing = future;
    return future;
  }

  Future<void> _doRefresh() async {
    await populateFoodItems();
    if (!mounted) return;
    if (_isOwnCard && _isSelectedDateToday) {
      // Keep today's history snapshot current, so this day shows the right
      // balance once it's in the past.
      await _upsertDailyLogForDate(_selectedLogDate);
      await _fetchDailyLogForDate(_selectedLogDate);
    }
    if (!mounted) return;
    setState(() {
      _creditCardRefreshKey++;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkForNewDay();
  }

  void _scheduleMidnightCheck() {
    _midnightTimer?.cancel();
    final now = BalanceService.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(
      nextMidnight.difference(now) + const Duration(seconds: 2),
      () {
        _checkForNewDay();
        _scheduleMidnightCheck();
      },
    );
  }

  /// The date changed while the app was open: if you were looking at
  /// "today", move to the new today and start the new day's balance.
  Future<void> _checkForNewDay() async {
    if (!mounted) return;
    final now = BalanceService.now();
    if (BalanceService.sameDay(now, _lastKnownToday)) return;
    final wasOnToday = _isSameDay(_selectedLogDate, _lastKnownToday);
    _lastKnownToday = now;
    if (_isOwnCard) {
      try {
        await BalanceService.ensureDailyReset(_activeUserId);
      } catch (_) {}
    }
    if (!mounted) return;
    if (wasOnToday) {
      await _changeDay(now);
    } else {
      setState(() => _creditCardRefreshKey++);
    }
  }

  @override
  void dispose() {
    FoodLog.changed.removeListener(_onFoodLogChanged);
    _designSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    _jiggleAnimationController?.dispose();
    _cardDragResetController?.dispose();
    _reactionFadeController?.dispose();
    super.dispose();
  }

  Future<void> _resetCardPosition({required bool promptAfterReset}) async {
    if (_cardDragResetController == null) return;
    _pendingSwipePrompt = promptAfterReset;
    _dragEndDx = _cardDragDx;
    _isResettingCard = true;
    _cardDragResetController!.reset();
    await _cardDragResetController!.forward();
    if (!mounted) return;
    setState(() {
      _isResettingCard = false;
      _cardDragDx = 0;
    });
    if (_pendingSwipePrompt) {
      _pendingSwipePrompt = false;
      await _handleCardSwipe();
    }
  }

  Future<void> _initializeHome() async {
    // New day? Put the card back to today's goals before showing it.
    // Only for your own card — never write to a friend's data.
    if (!widget.readOnly && widget.userIdOverride == null) {
      try {
        // One-off: give old entries a time_added so date-range reads see them.
        await BalanceService.backfillEntryTimes(_activeUserId);
      } catch (_) {
        // Tried again next launch.
      }
      try {
        final didReset = await BalanceService.ensureDailyReset(_activeUserId);
        if (didReset && mounted) {
          setState(() {
            _creditCardRefreshKey++;
          });
        }
      } catch (_) {
        // Card still shows the stored balance; next load will retry.
      }
    }
    await _fetchUserGoals();
    await populateFoodItems();
    await _fetchDailyLogForDate(_selectedLogDate);
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      _startHomeTour();
    }
  }

  /// Shows new users round the Card screen once (after the page has drawn).
  void _startHomeTour() {
    if (!_isOwnCard || widget.showBanner) return;
    // Only while the Card tab is on screen with nothing on top of it.
    bool onScreen() =>
        mounted &&
        (ShellTourScope.maybeOf(context)?.cardTabShowing ?? true) &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        !Navigator.of(context, rootNavigator: true).canPop();

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!onScreen()) return;
      final shell = ShellTourScope.maybeOf(context);
      SpotlightTour.showOnce(context, id: 'home_intro', canStart: onScreen,
          steps: [
        TourStep(
          target: _tourCard,
          title: 'Your card',
          body: 'Tap it to flip it over and see your macros. When you\'re '
              'done for the day, swipe it sideways to close the day.',
          padding: 6,
          radius: 24,
        ),
        TourStep(
          target: _tourDay,
          title: 'Your days',
          body: 'Step back to look at earlier days and how you did.',
        ),
        TourStep(
          target: _tourMeals,
          title: 'Your meals',
          body: 'Your day is split into meals. Tap a meal to switch between '
              'calories and macros.',
        ),
        TourStep(
          target: _tourAdd,
          title: 'Add food',
          body: 'Each meal has its own Add button. You can also log a saved '
              'recipe, and swipe a food left to remove it.',
          radius: 16,
        ),
        TourStep(
          target: _tourTutorials,
          title: 'Tutorials',
          body: 'Tap the headphones any time to watch how things work on a '
              "practice card. It never touches your real data.",
          padding: 4,
          radius: 28,
        ),
        if (shell != null)
          TourStep(
            target: shell.coach,
          title: 'Calorie Coach',
          body: 'Ask for a meal that fits what you\'ve got left, a pep talk, '
              'or help if you\'ve gone over.',
          padding: 4,
          radius: 40,
        ),
        if (shell != null)
          TourStep(
            target: shell.recipes,
          title: 'Recipes',
          body: 'Save meals you make often and log them in one tap.',
        ),
        if (shell != null)
          TourStep(
            target: shell.friends,
          title: 'Friends',
          body: 'Add friends, see the hiscores, take on challenges and chat. '
              'Messages are at the top.',
        ),
        if (shell != null)
          TourStep(
            target: shell.profile,
          title: 'Profile',
          body: 'Your statement, achievements, pots, card designs and '
              'settings all live here.',
        ),
      ]);
    });
  }

  Future<void> _changeDay(DateTime day) async {
    setState(() {
      _selectedLogDate = day;
    });
    await Future.wait([
      populateFoodItems(),
      _fetchDailyLogForDate(day),
    ]);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool get _isSelectedDateToday =>
      _isSameDay(_selectedLogDate, BalanceService.now());

  Future<void> _fetchDailyLogForDate(DateTime date) async {
    final token = ++_dailyLogLoadToken;
    try {
      final userId = _activeUserId;
      final key = _dateKey(date);
      final docRef = FirebaseFirestore.instance
          .collection('daily_logs')
          .doc('${userId}_$key');
      final doc = await docRef.get();
      if (!mounted || token != _dailyLogLoadToken) return;
      final data = doc.data();

      setState(() {
        _selectedDailyLog = data;
      });
      await _loadDailyLogStatusForSelectedDate(data);
    } catch (_) {
      if (!mounted || token != _dailyLogLoadToken) return;
      setState(() {
        _selectedDailyLog = null;
        _isDayFinished = false;
      });
    }
  }

  /// The goals that applied on the selected day: from that day's saved
  /// history when there is one, otherwise today's goals.
  Macros get _goalsForSelectedDay {
    final log = _selectedDailyLog;
    final goals = (log?['goals'] as Map?) ?? const {};
    final balances = (log?['balances'] as Map?) ?? const {};
    final totals = (log?['totals'] as Map?) ?? const {};
    double? n(dynamic v) => BalanceService.number(v);

    var calories = n(goals['calorie_goal']);
    if (calories == null) {
      // Older history: balance left + amount eaten = the day's goal.
      final left = n(balances['calories']);
      final eaten = n(totals['calories']);
      if (left != null && eaten != null) calories = left + eaten;
    }
    return Macros(
      calories: calories ?? (_userCalorieGoal ?? 0).toDouble(),
      protein: n(goals['protein_goal']) ?? _userProteinGoal ?? 0,
      carbs: n(goals['carbs_goal']) ?? _userCarbsGoal ?? 0,
      fat: n(goals['fats_goal']) ?? _userFatsGoal ?? 0,
    );
  }

  /// What was left on the card at the end of the selected (past) day,
  /// worked out from the food actually logged that day.
  Macros get _selectedDayBalance => _goalsForSelectedDay - _dayTotals;

  String _dateKey(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _fetchUserGoals() async {
    try {
      final userId = _activeUserId;
      final userDataSnapshot = await FirebaseFirestore.instance
          .collection('user_data')
          .where('user_id', isEqualTo: userId)
          .limit(1)
          .get();

      if (userDataSnapshot.docs.isNotEmpty) {
        final userData = userDataSnapshot.docs.first.data();
        if (mounted) {
          setState(() {
            _userCalorieGoal =
                BalanceService.calorieGoalFrom(userData)?.round();
            _userProteinGoal = BalanceService.number(userData['protein_goal']);
            _userCarbsGoal = BalanceService.number(userData['carbs_goal']);
            _userFatsGoal = BalanceService.number(userData['fats_goal']);
          });
        }
      }
    } catch (_) {
      // Error fetching user goals
    }
  }

  Future<void> _loadDailyLogStatusForSelectedDate(
      Map<String, dynamic>? data) async {
    final finished = data?['finished'] as bool? ?? false;
    if (!mounted) return;
    setState(() {
      _isDayFinished = finished;
    });
  }

  Future<void> _setDailyLogFinished(DateTime date, bool finished) async {
    try {
      final userId = _activeUserId;
      final key = _dateKey(date);
      final docRef = FirebaseFirestore.instance
          .collection('daily_logs')
          .doc('${userId}_$key');
      await docRef.set({
        'user_id': userId,
        'date_key': key,
        'date': Timestamp.fromDate(date),
        'finished': finished,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // ignore
    }
  }

  Future<void> _upsertDailyLogForDate(DateTime date) async {
    if (!_isOwnCard || _isUpdatingDailyLog) return;
    setState(() {
      _isUpdatingDailyLog = true;
    });

    try {
      final userId = _activeUserId;
      final firestore = FirebaseFirestore.instance;
      final key = _dateKey(date);

      final docs = await BalanceService.entriesOn(userId, date);
      final foodEntries = [
        for (final doc in docs) {'id': doc.id, ...doc.data()}
      ];
      final totals = BalanceService.totalOf(docs.map((d) => d.data()));

      final userDoc = await BalanceService.userDataDoc(userId);
      final userData = userDoc?.data() ?? <String, dynamic>{};
      double? n(String k) => BalanceService.number(userData[k]);

      final docRef = firestore.collection('daily_logs').doc('${userId}_$key');
      final existingDoc = await docRef.get();
      final existingFinished =
          (existingDoc.data()?['finished'] as bool?) ?? false;
      await docRef.set({
        'user_id': userId,
        'date_key': key,
        'date': Timestamp.fromDate(date),
        'food_entries': foodEntries,
        'totals': {
          'calories': totals.calories,
          'protein': totals.protein,
          'carbs': totals.carbs,
          'fat': totals.fat,
        },
        'balances': {
          'calories': n('calories'),
          'protein_balance': n('protein_balance'),
          'carbs_balance': n('carbs_balance'),
          'fats_balance': n('fats_balance'),
        },
        'goals': {
          'calorie_goal': BalanceService.calorieGoalFrom(userData),
          'protein_goal': n('protein_goal'),
          'carbs_goal': n('carbs_goal'),
          'fats_goal': n('fats_goal'),
        },
        'finished': existingFinished,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // History is rebuilt on the next change.
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingDailyLog = false;
        });
      }
    }
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    String cancelLabel = 'Cancel',
    String confirmLabel = 'OK',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(cancelLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _handleCardSwipe() async {
    if (_isUpdatingDailyLog) return;
    if (!_isSelectedDateToday || !_isOwnCard) return;
    if (_isDayFinished) {
      final confirm = await _showConfirmDialog(
        title: 'Reopen today?',
        message: "You can add or remove food again. Close it when you're done.",
        cancelLabel: 'Cancel',
        confirmLabel: 'Reopen',
      );
      if (!confirm) return;
      setState(() {
        _isDayFinished = false;
      });
      await _setDailyLogFinished(_selectedLogDate, false);
      await _fetchDailyLogForDate(_selectedLogDate);
      return;
    }

    final confirm = await _showConfirmDialog(
      title: 'Close today?',
      message: "This locks today's card and counts it towards your streak. "
          'You can reopen it if you need to.',
      cancelLabel: 'Not yet',
      confirmLabel: 'Close day',
    );
    if (!confirm) return;

    setState(() {
      _isDayFinished = true;
    });
    await _upsertDailyLogForDate(_selectedLogDate);
    await _setDailyLogFinished(_selectedLogDate, true);
    await _fetchDailyLogForDate(_selectedLogDate);
    try {
      final unlocked =
          await AchievementService.updateAchievementsForUser(_activeUserId);
      if (unlocked.isNotEmpty && mounted) {
        final first = unlocked.first;
        final more = unlocked.length > 1 ? ' (+${unlocked.length - 1} more)' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${first.emoji} Achievement unlocked: ${first.title}$more'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AchievementsPage()),
              ),
            ),
          ),
        );
      }
    } catch (_) {
      // Achievements are re-checked next time.
    }
    // Update your best streak now, so card designs unlock without having
    // to open Hiscores first.
    try {
      await LeaderboardService.refreshMine(_activeUserId);
    } catch (_) {}
  }

  /// Loads the selected day's food (every meal, oldest first), per-meal
  /// totals, and the whole day's totals (for past days' cards).
  Future<void> populateFoodItems() async {
    final token = ++_foodLoadToken;
    try {
      final day = _selectedLogDate;

      final dayDocs = await BalanceService.entriesOn(_activeUserId, day);
      if (!mounted || token != _foodLoadToken) return;

      final mealDocs = dayDocs.toList()
        ..sort((a, b) {
          final ta = BalanceService.entryDate(a.data());
          final tb = BalanceService.entryDate(b.data());
          if (ta == null || tb == null) return 0;
          return ta.compareTo(tb);
        });
      final mealTotals = BalanceService.totalOf(mealDocs.map((d) => d.data()));

      final mealKcal = <String, int>{};
      for (final m in _tabs) {
        mealKcal[m] = BalanceService.totalOf(dayDocs
                .where((d) => (d.data()['foodCategory'] ?? 'Brekkie') == m)
                .map((d) => d.data()))
            .calories
            .round();
      }

      setState(() {
        _foodDocs = mealDocs;
        _mealKcal = mealKcal;
        _dayTotals = BalanceService.totalOf(dayDocs.map((d) => d.data()));
        _totalCalories = mealTotals.calories.round();
        _totalProtein = mealTotals.protein;
        _totalCarbs = mealTotals.carbs;
        _totalFat = mealTotals.fat;
        _foodMacrosVisibility
          ..clear()
          ..addEntries(mealDocs.map((d) => MapEntry(d.id, _showMacrosTotal)));
      });
      _loadYesterday();
      await _fetchReactionsForFoodItems();
    } catch (e) {
      if (!mounted || token != _foodLoadToken) return;
      setState(() {
        _foodDocs = [];
        _mealKcal = const {};
        _dayTotals = Macros.zero;
        _totalCalories = 0;
        _totalProtein = 0;
        _totalCarbs = 0;
        _totalFat = 0;
        _foodMacrosVisibility.clear();
      });
    }
  }

  Future<void> _fetchReactionsForFoodItems() async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      for (var doc in _foodDocs) {
        final reactionsSnapshot = await FirebaseFirestore.instance
            .collection('food_reactions')
            .where('food_item_id', isEqualTo: doc.id)
            .get();

        final reactions =
            await Future.wait(reactionsSnapshot.docs.map((reactionDoc) async {
          final userId = reactionDoc['user_id'];
          // Fetch user email/username
          String username = 'Unknown';
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .get();
            username = userDoc.data()?['email']?.split('@')[0] ?? 'Unknown';
          } catch (e) {
            // Error fetching user data
          }

          return {
            'id': reactionDoc.id,
            'emoji': reactionDoc['emoji'],
            'user_id': userId,
            'username': username,
          };
        }));

        if (mounted) {
          setState(() {
            _foodReactions[doc.id] = reactions;
          });
        }
      }
    } catch (e) {
      // Error fetching reactions
    }
  }

  Future<void> _addReaction(String foodItemId, String emoji) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      // Get current user's email for display
      final currentUserEmail = FirebaseAuth.instance.currentUser?.email ?? '';
      final username = currentUserEmail.split('@')[0];

      // Check if user already reacted to this food item
      final existingReaction = await FirebaseFirestore.instance
          .collection('food_reactions')
          .where('food_item_id', isEqualTo: foodItemId)
          .where('user_id', isEqualTo: currentUserId)
          .limit(1)
          .get();

      if (existingReaction.docs.isNotEmpty) {
        // Update existing reaction
        await existingReaction.docs.first.reference.update({
          'emoji': emoji,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new reaction
        await FirebaseFirestore.instance.collection('food_reactions').add({
          'food_item_id': foodItemId,
          'owner_id': _activeUserId,
          'user_id': currentUserId,
          'emoji': emoji,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      // Refresh reactions
      await _fetchReactionsForFoodItems();

      if (mounted) {
        setState(() {
          _showEmojiPicker[foodItemId] = false;
          // Show confirmation animation
          _reactionConfirmationFoodId = foodItemId;
          _reactionConfirmationEmoji = emoji;
          _reactionConfirmationUsername = username;
        });

        // Fade in animation
        _reactionFadeController?.forward(from: 0.0);

        // Wait 2 seconds then fade out
        await Future.delayed(const Duration(seconds: 2));
        await _reactionFadeController?.reverse();

        if (mounted) {
          setState(() {
            _reactionConfirmationFoodId = null;
            _reactionConfirmationEmoji = null;
            _reactionConfirmationUsername = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Couldn't add your reaction. Please try again.")),
        );
      }
    }
  }

  void _handleFoodItemTap(String foodItemId) {
    if (widget.readOnly) {
      // Show emoji picker
      setState(() {
        _showEmojiPicker[foodItemId] = !(_showEmojiPicker[foodItemId] ?? false);
      });
    } else {
      // Toggle reactions display
      setState(() {
        _showReactions[foodItemId] = !(_showReactions[foodItemId] ?? false);
      });
    }
  }
  /// Removes a logged food (and refunds the card). [swiped] removals were
  /// checked when the row was swiped and confirmed by the Undo snackbar
  /// closing, so they skip the editable-day check and the extra snackbar.
  Future<void> _deleteFoodItem(String docId, {bool swiped = false}) async {
    if (_isDeletingItem) return;
    if (!swiped && !_canEditSelectedDay) return;

    if (mounted) {
      setState(() {
        _isDeletingItem = true;
      });
    }

    try {
      // One write removes the food and refunds today's card.
      await FoodLog.remove(docId);
      // The change signal has already started a refresh; wait for it.
      if (mounted) await (_refreshing ?? _refreshAfterChange());
      if (mounted && !swiped) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Food removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Couldn't remove that food. Please try again.")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingItem = false;
        });
      }
    }
  }

  /// A food was swiped away: hide it now, offer Undo, and only delete it
  /// once the snackbar has closed without Undo (so Undo never re-logs).
  void _onFoodSwiped(String docId, String name) {
    if (!_canEditSelectedDay) return;
    setState(() => _pendingRemoval.add(docId));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text('Removed $name'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: 'Undo', onPressed: () {}),
      ),
    );
    // Snackbars with an action can stay up in newer Flutter; this one must
    // close on its own so the removal goes through.
    var closed = false;
    Timer(const Duration(seconds: 5), () {
      if (!closed) messenger.hideCurrentSnackBar();
    });
    controller.closed.then((reason) {
      closed = true;
      if (reason == SnackBarClosedReason.action) {
        if (mounted) setState(() => _pendingRemoval.remove(docId));
        return;
      }
      // One removal at a time, in the order they were swiped.
      _removalChain = _removalChain.then((_) async {
        await _deleteFoodItem(docId, swiped: true);
        if (mounted) setState(() => _pendingRemoval.remove(docId));
      });
    });
  }

  /// Loads yesterday's food once per day, for the "Copy yesterday's"
  /// shortcut on an empty meal.
  Future<void> _loadYesterday() async {
    if (!_isOwnCard || !_isSelectedDateToday) return;
    final yesterday = BalanceService.addDays(BalanceService.now(), -1);
    final key = _dateKey(yesterday);
    if (_yesterdayKey == key) return;
    _yesterdayKey = key;
    try {
      final docs = await BalanceService.entriesOn(_activeUserId, yesterday);
      if (!mounted || _yesterdayKey != key) return;
      setState(() {
        _yesterdayEntries = [for (final d in docs) d.data()];
      });
    } catch (_) {
      // Just a shortcut; try again next time.
      if (_yesterdayKey == key) _yesterdayKey = null;
    }
  }

  List<Map<String, dynamic>> _yesterdayFor(String meal) => [
        for (final e in _yesterdayEntries)
          if ((e['foodCategory'] ?? 'Brekkie') == meal) e
      ];

  Future<void> _copyYesterday(
      String meal, List<Map<String, dynamic>> entries) async {
    if (_copyingYesterday || !_canEditSelectedDay || entries.isEmpty) return;
    setState(() => _copyingYesterday = true);
    try {
      await FoodLog.logFoods(
        items: [
          for (final e in entries)
            {
              'name': (e['food_description'] ?? 'Food').toString(),
              'portion': (e['food_portion'] ?? '').toString(),
              'calories': BalanceService.number(e['food_calories']) ?? 0,
              'protein': BalanceService.number(e['food_protein']) ?? 0,
              'carbs': BalanceService.number(e['food_carbs']) ?? 0,
              'fat': BalanceService.number(e['food_fat']) ?? 0,
            }
        ],
        meal: meal,
      );
      if (mounted) await (_refreshing ?? _refreshAfterChange());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Added yesterday's $meal")),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Couldn't copy that. Please try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _copyingYesterday = false);
    }
  }

  /// True on a phone-sized window. Uses the real window width: on desktop
  /// MediaQuery.size is narrowed to the page column.
  bool get _isPhone {
    final view = View.of(context);
    return view.physicalSize.width / view.devicePixelRatio <
        Breakpoints.tablet;
  }

  /// Makes [meal] the one Add food / recipes log to.
  void _useMeal(String meal) {
    Provider.of<CategoryService>(context, listen: false)
        .setSelectedCategory(meal);
  }

  Future<void> _openAddFood(String meal) async {
    if (!_canEditSelectedDay) return;
    _useMeal(meal);
    // On phones, open above the bottom bar so the Coach button doesn't
    // cover the page's buttons.
    final saved = await Navigator.of(context, rootNavigator: _isPhone)
        .push<bool>(
      MaterialPageRoute(builder: (_) => const AddFoodPage()),
    );
    // Logging signals a refresh on its own; this covers the rest.
    if (saved == true && mounted) {
      await (_refreshing ?? _refreshAfterChange());
    }
  }

  Future<void> _openRecipePicker(String meal) async {
    if (!_canEditSelectedDay) return;
    _useMeal(meal);
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => _SelectExistingRecipePage(meal: meal),
      ),
    );
    if (result == null || !mounted) return;
    final category =
        Provider.of<CategoryService>(context, listen: false).selectedCategory;
    await _addRecipeToHome(
      result['recipeId'] as String,
      category,
      multiplier: result['multiplier'] as double,
    );
  }

  /// Long-press a food: have it every day? Set up a direct debit.
  Future<void> _offerDirectDebit(Map<String, dynamic> entry) async {
    final name = (entry['food_description'] ?? 'this').toString();
    final yes = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Have this every day?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'Set up a direct debit for $name. Each morning it waits on '
                'your Card screen for a one-tap Pay (or Skip).',
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  icon: const Icon(Icons.autorenew),
                  label: const Text('Set up direct debit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await DirectDebitService.createFromEntry(_activeUserId, entry);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Direct debit set up for $name')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Couldn't set that up. Please try again.")),
        );
      }
    }
  }

  Future<void> _addRecipeToHome(String recipeId, String category,
      {double multiplier = 1.0}) async {
    try {
      final recipeDoc = await FirebaseFirestore.instance
          .collection('recipes')
          .doc(recipeId)
          .get();
      final data = recipeDoc.data();
      if (data == null) {
        throw StateError('That recipe no longer exists.');
      }
      // Logs it and charges the card in one write; the change signal then
      // refreshes this screen.
      await FoodLog.logRecipe(
        recipeId: recipeId,
        recipe: data,
        meal: category,
        multiplier: multiplier,
      );
      await (_refreshing ?? _refreshAfterChange());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is StateError
                ? e.message
                : "Couldn't add that recipe. Please try again."),
          ),
        );
      }
    }
  }

  /// The card was flipped: jiggle it and match every food row to it.
  void _onCardFlipped(bool showMacros) {
    _jiggleAnimationController?.forward(from: 0);
    setState(() {
      _showMacrosTotal = showMacros;
      for (var doc in _foodDocs) {
        _foodMacrosVisibility[doc.id] = showMacros;
      }
    });
  }

  /// The meal header was tapped: switch between kcal and macros.
  void _toggleMacros() {
    setState(() {
      _showMacrosTotal = !_showMacrosTotal;
      // Flip all food items to match.
      for (var doc in _foodDocs) {
        _foodMacrosVisibility[doc.id] = _showMacrosTotal;
      }
    });
  }

  Widget _buildBanner(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        8,
        MediaQuery.of(context).padding.top + 8,
        8,
        8,
      ),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.arrow_back),
            color: Colors.white,
            tooltip: 'Back',
          ),
          Expanded(
            child: Center(
              child: Text(
                widget.bannerTitle ?? 'Card',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildCard() {
    final validThru =
        '${_selectedLogDate.day}/${_selectedLogDate.month}/${_selectedLogDate.year}';
    return Center(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _jiggleAnimationController!,
          _cardDragResetController!,
        ]),
        builder: (context, child) {
          final resetValue = _cardDragResetController?.value ?? 0.0;
          final effectiveDx = _isResettingCard
              ? _dragEndDx * (1 - Curves.easeOut.transform(resetValue))
              : _cardDragDx;
          return Transform.translate(
            offset: Offset(effectiveDx, 0),
            child: Transform.rotate(
              angle: _jiggleAnimation?.value ?? 0.0,
              child: child,
            ),
          );
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) {
            _cardDragDx = 0;
            _cardDragResetController?.stop();
            _isResettingCard = false;
          },
          onHorizontalDragUpdate: (details) {
            setState(() {
              _cardDragDx += details.delta.dx;
            });
          },
          onHorizontalDragEnd: (_) {
            final shouldPrompt = _cardDragDx.abs() > 40;
            _resetCardPosition(promptAfterReset: shouldPrompt);
          },
          child: Stack(
            key: _tourCard,
            children: [
              _isSelectedDateToday
                  ? CreditCard(
                      key: ValueKey(_creditCardRefreshKey),
                      userIdOverride: widget.userIdOverride,
                      cardUserNameOverride: widget.bannerTitle,
                      design: _cardDesign,
                      validThruDate: validThru,
                      onToggleMacros: _onCardFlipped,
                      onBalance: (calories) {
                        if (mounted && calories != _liveBalance) {
                          setState(() => _liveBalance = calories);
                        }
                      },
                    )
                  : CreditCard(
                      key: ValueKey(
                          '$_creditCardRefreshKey-${_selectedLogDate.toIso8601String()}'),
                      skipFetch: true,
                      caloriesOverride: _selectedDayBalance.calories.round(),
                      proteinOverride: _selectedDayBalance.protein,
                      carbsOverride: _selectedDayBalance.carbs,
                      fatsOverride: _selectedDayBalance.fat,
                      userIdOverride: widget.userIdOverride,
                      cardUserNameOverride: widget.bannerTitle,
                      design: _cardDesign,
                      validThruDate: validThru,
                      onToggleMacros: _onCardFlipped,
                    ),
            ],
          ),
        ),
      ),
    );
  }

  /// The food in [meal] that's on screen (not mid-swipe).
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _visibleIn(String meal) => [
        for (final d in _foodDocs)
          if (!_pendingRemoval.contains(d.id) &&
              (d.data()['foodCategory'] ?? 'Brekkie') == meal)
            d
      ];

  Widget _buildMealHeader(
      String meal, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final totals = BalanceService.totalOf(docs.map((d) => d.data()));
    final kcal = totals.calories.round();
    final macros = '${_roundMacro(totals.protein)}g protein · '
        '${_roundMacro(totals.carbs)}g carbs · ${_roundMacro(totals.fat)}g fat';

    return Material(
      color: AppColors.gray50,
      child: InkWell(
        onTap: docs.isEmpty ? null : _toggleMacros,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Icon(_mealIcon(meal), size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                meal,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                fit: FlexFit.tight,
                child: Text(
                  docs.isEmpty
                      ? ''
                      : _showMacrosTotal
                          ? macros
                          : '$kcal kcal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: AppColors.gray700,
                    fontWeight: FontWeight.w600,
                    fontSize: _showMacrosTotal ? 12 : 14,
                  ),
                ),
              ),
              if (docs.isNotEmpty) ...[
                const SizedBox(width: 8),
                Icon(
                  _showMacrosTotal
                      ? Icons.local_fire_department_outlined
                      : Icons.show_chart,
                  color: AppColors.muted,
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static IconData _mealIcon(String meal) {
    switch (meal.toLowerCase()) {
      case 'brekkie':
      case 'breakfast':
        return Icons.free_breakfast_outlined;
      case 'lunch':
        return Icons.lunch_dining_outlined;
      case 'dinner':
        return Icons.dinner_dining_outlined;
      default:
        return Icons.cookie_outlined;
    }
  }

  /// One line above the meals: what's been eaten and what's left.
  Widget? _buildDaySummary() {
    final left = _liveBalance;
    if (!_isOwnCard || !_isSelectedDateToday || left == null) return null;
    final goal = _goalsForSelectedDay.calories;
    final Color leftColor = left < 0
        ? AppColors.red600
        : (goal > 0 && left <= goal * 0.1)
            ? AppColors.amber700
            : AppColors.emerald700;
    final eaten = _dayTotals.calories.round();
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Eaten today: ${formatCardKcal(eaten)} kcal · '),
          TextSpan(
            text: left < 0
                ? '${formatCardKcal(-left)} kcal over'
                : '${formatCardKcal(left)} kcal left',
            style: TextStyle(color: leftColor, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, color: AppColors.muted),
    );
  }

  /// Empty meals stay small so the whole day fits on screen.
  Widget _buildEmptyMeal(String meal) {
    final String text;
    if (!_isSelectedDateToday) {
      text = 'Nothing logged that day.';
    } else if (!_isOwnCard) {
      text = 'Nothing logged yet.';
    } else {
      text = 'Nothing yet. Add what you had and it comes off your card.';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.muted, fontSize: 13),
      ),
    );
  }

  Widget _reactionEmoji(String foodId, String emoji) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _addReaction(foodId, emoji),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Text(emoji, style: const TextStyle(fontSize: 32)),
      ),
    );
  }

  Widget _buildFoodRow(
      QueryDocumentSnapshot<Map<String, dynamic>> doc, bool canEdit) {
    final data = doc.data();
    final name = (data['food_description'] ?? 'Food').toString();
    final portion = (data['food_portion'] ?? '').toString();
    final showMacros = _foodMacrosVisibility[doc.id] ?? _showMacrosTotal;
    final reactions = _foodReactions[doc.id];

    final row = Material(
      color: Colors.white,
      child: InkWell(
        onTap: () {
          _handleFoodItemTap(doc.id);
        },
        onLongPress: _isOwnCard ? () => _offerDirectDebit(data) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                        if (portion.isNotEmpty)
                          Text(
                            portion,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: showMacros ? 3 : 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.indigo50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: showMacros
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${_roundMacro(data['food_protein'])}g protein',
                                style: const TextStyle(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10.5,
                                  height: 1.25,
                                ),
                              ),
                              Text(
                                '${_roundMacro(data['food_carbs'])}g carbs',
                                style: const TextStyle(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10.5,
                                  height: 1.25,
                                ),
                              ),
                              Text(
                                '${_roundMacro(data['food_fat'])}g fat',
                                style: const TextStyle(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10.5,
                                  height: 1.25,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            '${_roundMacro(data['food_calories'])} kcal',
                            style: const TextStyle(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            // Friends viewing your card: pick a reaction.
            if (widget.readOnly && (_showEmojiPicker[doc.id] ?? false))
              Container(
                padding: const EdgeInsets.all(8),
                color: AppColors.gray100,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _reactionEmoji(doc.id, '🔥'),
                    _reactionEmoji(doc.id, '😈'),
                    _reactionEmoji(doc.id, '💪'),
                    _reactionEmoji(doc.id, '❤️'),
                  ],
                ),
              ),
            // Reaction just added (friend's view).
            if (widget.readOnly &&
                _reactionConfirmationFoodId == doc.id &&
                _reactionFadeAnimation != null)
              FadeTransition(
                opacity: _reactionFadeAnimation!,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppColors.emerald50,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _reactionConfirmationUsername ?? '',
                          style: const TextStyle(
                            color: AppColors.gray700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        _reactionConfirmationEmoji ?? '',
                        style: const TextStyle(fontSize: 24),
                      ),
                    ],
                  ),
                ),
              ),
            // Owner tapped a food: who reacted to it.
            if (!widget.readOnly &&
                (_showReactions[doc.id] ?? false) &&
                reactions != null &&
                reactions.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppColors.indigo50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final reaction in reactions)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                (reaction['username'] ?? 'Unknown').toString(),
                                style: const TextStyle(
                                  color: AppColors.gray700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Text(
                              (reaction['emoji'] ?? '').toString(),
                              style: const TextStyle(fontSize: 20),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    if (!canEdit) return row;
    return Dismissible(
      key: ValueKey('food-${doc.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.red600,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _onFoodSwiped(doc.id, name),
      child: row,
    );
  }

  Widget _buildAddActions(String meal, bool showCopy, {bool tour = false}) {
    final canEdit = _canEditSelectedDay;
    final yesterday =
        showCopy ? _yesterdayFor(meal) : const <Map<String, dynamic>>[];
    final yesterdayKcal =
        BalanceService.totalOf(yesterday).calories.round();
    return Column(
      key: tour ? _tourAdd : null,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: canEdit ? () => _openAddFood(meal) : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                icon: const Icon(Icons.add),
                label: Text(
                  'Add to $meal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: canEdit ? () => _openRecipePicker(meal) : null,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Recipe'),
            ),
          ],
        ),
        if (canEdit && yesterday.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _copyingYesterday
                ? null
                : () => _copyYesterday(meal, yesterday),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
            ),
            icon: const Icon(Icons.history),
            label: Text(
              "Copy yesterday's $meal ($yesterdayKcal kcal)",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFoodPanel(String meal, {bool first = false}) {
    final visible = _visibleIn(meal);
    final canEdit = _canEditSelectedDay;
    final footer = _isOwnCard && _isSelectedDateToday
        ? _buildAddActions(meal, visible.isEmpty, tour: first)
        : null;

    return Container(
      key: first ? _tourMeals : null,
      decoration: AppDecor.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMealHeader(meal, visible),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          if (visible.isEmpty)
            _buildEmptyMeal(meal)
          else
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, thickness: 1, color: AppColors.border),
              _buildFoodRow(visible[i], canEdit),
            ],
          if (footer != null) ...[
            if (visible.isNotEmpty)
              const Divider(height: 1, thickness: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.all(12),
              child: footer,
            ),
          ] else
            const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topGap = widget.showBanner
        ? 12.0
        : 16.0 + MediaQuery.paddingOf(context).top;

    if (_isLoading) {
      // Same size as the real card, so nothing jumps when it loads.
      final screenWidth = MediaQuery.sizeOf(context).width;
      final cardWidth = math.min(screenWidth - 32, 380.0);
      final cardHeight = math.max(cardWidth / 1.7, 190.0);
      return Scaffold(
        backgroundColor: AppColors.canvas,
        body: Column(
          children: [
            if (widget.showBanner) _buildBanner(context),
            SizedBox(height: topGap),
            Center(
              child: SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: CalorieCardSkeleton(design: _cardDesign),
              ),
            ),
          ],
        ),
      );
    }

    final summary = _buildDaySummary();

    final ownHome = _isOwnCard && !widget.showBanner;
    final overBy = _liveBalance == null ? 0 : -_liveBalance!;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      // Tutorials, bottom-left so it never sits under the Coach button.
      floatingActionButton: ownHome
          ? KeyedSubtree(key: _tourTutorials, child: const TutorialButton())
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: Column(
        children: [
          if (widget.showBanner) _buildBanner(context),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshAfterChange,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: topGap, bottom: ownHome ? 96 : 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCard(),
                    if (_isOwnCard && _isSelectedDateToday && _isDayFinished)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _ClosedDayStrip(onReopen: _handleCardSwipe),
                      ),
                    // Over budget: a kind note with a plan to even it out.
                    if (_isOwnCard &&
                        _isSelectedDateToday &&
                        !_isDayFinished &&
                        overBy > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: CoachNudge(
                          overBy: overBy,
                          goal: _goalsForSelectedDay.calories,
                          today: BalanceService.now(),
                          onAsk: (question) => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  CoachPage(initialQuestion: question),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DayStepper(
                        key: _tourDay,
                        selected: _selectedLogDate,
                        onChanged: _changeDay,
                      ),
                    ),
                    if (_isOwnCard && _isSelectedDateToday)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: HomeInbox(
                          userId: _activeUserId,
                          isDayFinished: _isDayFinished,
                          hasFoodToday: _dayTotals.calories > 0,
                          onFinishDay: _handleCardSwipe,
                          onBalanceChanged: _refreshAfterChange,
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (summary != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: summary,
                      ),
                    if (_isOwnCard && !_isSelectedDateToday)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: _PastDayNotice(
                          onToday: () => _changeDay(BalanceService.now()),
                        ),
                      ),
                    if (_isDeletingItem || _copyingYesterday)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    // Every meal, one after another.
                    for (var i = 0; i < _tabs.length; i++)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: _buildFoodPanel(_tabs[i], first: i == 0),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Under the card once today is closed, with a way to reopen it.
class _ClosedDayStrip extends StatelessWidget {
  final VoidCallback onReopen;

  const _ClosedDayStrip({required this.onReopen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      decoration: BoxDecoration(
        color: AppColors.emerald50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.emerald300),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.emerald600, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "Today's closed. Nice work.",
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          TextButton(
            onPressed: onReopen,
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the add buttons on a past day.
class _PastDayNotice extends StatelessWidget {
  final VoidCallback onToday;

  const _PastDayNotice({required this.onToday});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.indigo50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Past days are read-only. Food you add goes on today.',
              style: TextStyle(color: AppColors.ink, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onToday,
            child: const Text('Go to today'),
          ),
        ],
      ),
    );
  }
}
