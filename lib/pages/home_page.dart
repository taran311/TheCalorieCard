import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/pages/add_food_page.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/services/achievement_service.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/card_design_service.dart';
import 'package:namer_app/services/direct_debit_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/leaderboard_service.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/home_inbox.dart';
import 'package:namer_app/ui/home_widgets.dart';
import 'package:namer_app/ui/responsive.dart';

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
  const _SelectExistingRecipePage();

  @override
  State<_SelectExistingRecipePage> createState() =>
      _SelectExistingRecipePageState();
}

class _SelectExistingRecipePageState extends State<_SelectExistingRecipePage> {
  int? _editingRecipeIndex;
  final TextEditingController _portionController = TextEditingController();
  int _selectedTabIndex = 0; // 0 = My Recipes, 1 = Shared with Me

  @override
  void dispose() {
    _portionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Recipe'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedTabIndex = 0;
                        _editingRecipeIndex = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _selectedTabIndex == 0
                                ? AppColors.primary
                                : AppColors.gray300,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        'My Recipes',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _selectedTabIndex == 0
                              ? AppColors.primary
                              : AppColors.gray600,
                          fontSize: 14,
                          fontWeight: _selectedTabIndex == 0
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedTabIndex = 1;
                        _editingRecipeIndex = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _selectedTabIndex == 1
                                ? AppColors.primary
                                : AppColors.gray300,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        'Shared with Me',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _selectedTabIndex == 1
                              ? AppColors.primary
                              : AppColors.gray600,
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
      stream: FirebaseFirestore.instance
          .collection('recipes')
          .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No recipes yet.'));
        }

        final recipes = snapshot.data!.docs;
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
                : 'Serving${originalServingValue != 1 ? 's' : ''}';

            return Column(
              children: [
                ListTile(
                  title: Text((r['name'] ?? 'Recipe').toString()),
                  subtitle: Text(
                      '${calories.toStringAsFixed(0)} kcal ($servingSize)'),
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
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text('No recipes shared with you yet.'),
          );
        }

        final sharedRecipeDocs = snapshot.data!.docs;

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _loadSharedRecipeDetailsForHome(sharedRecipeDocs),
          builder: (context, detailSnapshot) {
            if (detailSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!detailSnapshot.hasData || detailSnapshot.data!.isEmpty) {
              return const Center(child: Text('No recipes available'));
            }

            final recipes = detailSnapshot.data!;

            return ListView.builder(
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
                    : 'Serving${originalServingValue != 1 ? 's' : ''}';

                return Column(
                  children: [
                    ListTile(
                      title: Text(recipe['name'] ?? 'Recipe'),
                      subtitle: Text(
                          '${calories.toStringAsFixed(0)} kcal ($servingSize)\n${item['sharedByEmail']}'),
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
                      _buildRecipeExpandedView(
                        recipeId,
                        recipe,
                        calories,
                        protein,
                        carbs,
                        fat,
                        servingSize,
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

  Widget _buildRecipeExpandedView(
    String recipeId,
    Map<String, dynamic> recipe,
    num calories,
    double protein,
    double carbs,
    double fat,
    String servingSize,
    double originalServingValue,
    bool isGrams,
    String unit,
  ) {
    return _buildExpandedPortionView(
      recipeId,
      recipe,
      calories,
      protein,
      carbs,
      fat,
      originalServingValue,
      isGrams,
      unit,
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
      decoration: BoxDecoration(
        color: AppColors.indigo50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.indigo300, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'per ',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _portionController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
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
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.amber400,
                          AppColors.amber600,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.amber.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.local_fire_department,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$adjustedCalories',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'kcal',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            color: AppColors.indigo100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.indigo300,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Protein',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.indigo800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${adjustedProtein.toStringAsFixed(1)}g',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.indigo900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            color: AppColors.emerald100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.emerald300,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Carbs',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.emerald800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${adjustedCarbs.toStringAsFixed(1)}g',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.emerald900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            color: AppColors.violet100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.violet300,
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Fat',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.violet800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${adjustedFat.toStringAsFixed(1)}g',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.violet900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
                      ElevatedButton(
                        onPressed: !validPortion
                            ? null
                            : () {
                          final multiplier = ratio;
                          Navigator.pop(context, {
                            'recipeId': recipeId,
                            'multiplier': multiplier,
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Add'),
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
  bool _deleteMode = false;
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
    }
  }

  Future<void> _changeDay(DateTime day) async {
    setState(() {
      _selectedLogDate = day;
      _deleteMode = false;
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
      if (_isDayFinished) {
        _deleteMode = false;
      }
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
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
              ),
              child: const Text('Yes'),
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
        title: 'Continue logging',
        message: 'Are you sure you wish to continue logging for today?',
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
      title: 'Finish logging',
      message: 'Are you sure you wish to finish logging for today?',
    );
    if (!confirm) return;

    setState(() {
      _isDayFinished = true;
      _deleteMode = false;
    });
    await _upsertDailyLogForDate(_selectedLogDate);
    await _setDailyLogFinished(_selectedLogDate, true);
    await _fetchDailyLogForDate(_selectedLogDate);
    await AchievementService.updateAchievementsForUser(_activeUserId);
    // Update your best streak now, so card designs unlock without having
    // to open Hiscores first.
    try {
      await LeaderboardService.refreshMine(_activeUserId);
    } catch (_) {}
  }

  /// Loads the selected day's food: the list for the selected meal, that
  /// meal's totals, and the whole day's totals (for past days' cards).
  Future<void> populateFoodItems() async {
    final token = ++_foodLoadToken;
    try {
      final meal =
          Provider.of<CategoryService>(context, listen: false).selectedCategory;
      final day = _selectedLogDate;

      final dayDocs = await BalanceService.entriesOn(_activeUserId, day);
      if (!mounted || token != _foodLoadToken) return;

      final mealDocs = dayDocs
          .where((d) => (d.data()['foodCategory'] ?? 'Brekkie') == meal)
          .toList()
        ..sort((a, b) {
          final ta = BalanceService.entryDate(a.data());
          final tb = BalanceService.entryDate(b.data());
          if (ta == null || tb == null) return 0;
          return ta.compareTo(tb);
        });
      final mealTotals = BalanceService.totalOf(mealDocs.map((d) => d.data()));

      setState(() {
        _foodDocs = mealDocs;
        _dayTotals = BalanceService.totalOf(dayDocs.map((d) => d.data()));
        _totalCalories = mealTotals.calories.round();
        _totalProtein = mealTotals.protein;
        _totalCarbs = mealTotals.carbs;
        _totalFat = mealTotals.fat;
        _foodMacrosVisibility
          ..clear()
          ..addEntries(mealDocs.map((d) => MapEntry(d.id, _showMacrosTotal)));
      });
      await _fetchReactionsForFoodItems();
    } catch (e) {
      if (!mounted || token != _foodLoadToken) return;
      setState(() {
        _foodDocs = [];
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
          SnackBar(content: Text('Error adding reaction: $e')),
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
  Future<void> _deleteFoodItem(String docId) async {
    if (_isDeletingItem || !_canEditSelectedDay) return;

    setState(() {
      _isDeletingItem = true;
    });

    try {
      // One write removes the food and refunds today's card.
      await FoodLog.remove(docId);
      // The change signal has already started a refresh; wait for it.
      await (_refreshing ?? _refreshAfterChange());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Food item removed')),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          color: Colors.white,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Container(
            color: AppColors.canvas,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (widget.showBanner) ...[
                  Container(
                    padding: EdgeInsets.fromLTRB(
                      8,
                      MediaQuery.of(context).padding.top + 8,
                      8,
                      8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            Navigator.of(context).maybePop();
                          },
                          icon: const Icon(Icons.arrow_back),
                          color: Colors.white,
                          splashRadius: 20,
                          tooltip: 'Back',
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              widget.bannerTitle ?? 'Card',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  const SizedBox(height: 16),
                ],
                Center(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _jiggleAnimationController!,
                      _cardDragResetController!,
                    ]),
                    builder: (context, child) {
                      final resetValue = _cardDragResetController?.value ?? 0.0;
                      final effectiveDx = _isResettingCard
                          ? _dragEndDx *
                              (1 - Curves.easeOut.transform(resetValue))
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
                        children: [
                          _isSelectedDateToday
                              ? CreditCard(
                                  key: ValueKey(_creditCardRefreshKey),
                                  userIdOverride: widget.userIdOverride,
                                  cardUserNameOverride: widget.bannerTitle,
                                  design: _cardDesign,
                                  validThruDate:
                                      '${_selectedLogDate.day}/${_selectedLogDate.month}/${_selectedLogDate.year}',
                                  onToggleMacros: (showMacros) {
                                    // Trigger jiggle when card is flipped
                                    _jiggleAnimationController?.forward(
                                        from: 0);
                                    setState(() {
                                      _showMacrosTotal = showMacros;
                                      for (var doc in _foodDocs) {
                                        _foodMacrosVisibility[doc.id] =
                                            showMacros;
                                      }
                                    });
                                  },
                                )
                              : CreditCard(
                                  key: ValueKey(
                                      '$_creditCardRefreshKey-${_selectedLogDate.toIso8601String()}'),
                                  skipFetch: true,
                                  caloriesOverride:
                                      _selectedDayBalance.calories.round(),
                                  proteinOverride: _selectedDayBalance.protein,
                                  carbsOverride: _selectedDayBalance.carbs,
                                  fatsOverride: _selectedDayBalance.fat,
                                  userIdOverride: widget.userIdOverride,
                                  cardUserNameOverride: widget.bannerTitle,
                                  design: _cardDesign,
                                  validThruDate:
                                      '${_selectedLogDate.day}/${_selectedLogDate.month}/${_selectedLogDate.year}',
                                  onToggleMacros: (showMacros) {
                                    _jiggleAnimationController?.forward(
                                        from: 0);
                                    setState(() {
                                      _showMacrosTotal = showMacros;
                                      for (var doc in _foodDocs) {
                                        _foodMacrosVisibility[doc.id] =
                                            showMacros;
                                      }
                                    });
                                  },
                                ),
                          if (_isDayFinished)
                            Positioned(
                              top: 10,
                              right: 12,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.check_circle,
                                  color: AppColors.green,
                                  size: 22,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DayStepper(
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
                const SizedBox(height: 12),
                // Meals
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Consumer<CategoryService>(
                    builder: (context, categoryService, _) => MealTabs(
                      meals: _tabs,
                      selected: categoryService.selectedCategory,
                      onSelected: (tab) {
                        categoryService.setSelectedCategory(tab);
                        populateFoodItems();
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.indigo700,
                              AppColors.indigo900,
                            ],
                          ),
                        ),
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  // Category Totals Header
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _showMacrosTotal = !_showMacrosTotal;
                                        // When card is tapped, flip all food items to match card state
                                        for (var doc in _foodDocs) {
                                          _foodMacrosVisibility[doc.id] =
                                              _showMacrosTotal;
                                        }
                                      });
                                    },
                                    child: Builder(
                                      builder: (context) {
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 12),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: Colors.white
                                                    .withValues(alpha: 0.3),
                                                width: 1,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                const Text(
                                                  'Total',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                Row(
                                                  children: [
                                                    if (!_showMacrosTotal)
                                                      Text(
                                                        '$_totalCalories kcal',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 14,
                                                        ),
                                                      )
                                                    else
                                                      Text(
                                                        'Protein: ${_roundMacro(_totalProtein)}g | Carbs: ${_roundMacro(_totalCarbs)}g | Fat: ${_roundMacro(_totalFat)}g',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    const SizedBox(width: 8),
                                                    Icon(
                                                      _showMacrosTotal
                                                          ? Icons.fastfood
                                                          : Icons.show_chart,
                                                      color: Colors.white,
                                                      size: 20,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  Expanded(
                                    child: Stack(
                                      children: [
                                        ListView.builder(
                                          itemCount: _foodDocs.length,
                                          itemBuilder: (context, index) {
                                            final doc = _foodDocs[index];
                                            final data = doc.data();
                                            final portion =
                                                (data['food_portion'] ?? '')
                                                    .toString();
                                            return Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 6),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                color: Colors.white,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.1),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: GestureDetector(
                                                onTap: () {
                                                  _handleFoodItemTap(doc.id);
                                                },
                                                onLongPress: _isOwnCard
                                                    ? () => _offerDirectDebit(
                                                        data)
                                                    : null,
                                                child: Column(
                                                  children: [
                                                    ListTile(
                                                      contentPadding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                        horizontal: 16,
                                                        vertical: 8,
                                                      ),
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      title: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                            (data['food_description'] ??
                                                                    'Food')
                                                                .toString(),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                              color: Colors
                                                                  .black87,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                          if (portion
                                                              .isNotEmpty)
                                                            Text(
                                                              '($portion)',
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .grey
                                                                    .shade600,
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w400,
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                      trailing: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .center,
                                                        children: [
                                                          if (_deleteMode &&
                                                              _canEditSelectedDay)
                                                            GestureDetector(
                                                              onTap: () async {
                                                                await _deleteFoodItem(
                                                                    doc.id);
                                                              },
                                                              child: Icon(
                                                                Icons
                                                                    .delete_outline,
                                                                color: Colors
                                                                    .red
                                                                    .shade400,
                                                                size: 24,
                                                              ),
                                                            )
                                                          else
                                                            Container(
                                                              padding: EdgeInsets
                                                                  .symmetric(
                                                                horizontal: 12,
                                                                vertical: (_foodMacrosVisibility[
                                                                            doc.id] ??
                                                                        _showMacrosTotal)
                                                                    ? 1
                                                                    : 4,
                                                              ),
                                                              decoration:
                                                                  BoxDecoration(
                                                                gradient:
                                                                    LinearGradient(
                                                                  colors: [
                                                                    Colors
                                                                        .orange
                                                                        .shade400,
                                                                    Colors
                                                                        .orange
                                                                        .shade600,
                                                                  ],
                                                                ),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            12),
                                                              ),
                                                              child: (_foodMacrosVisibility[
                                                                          doc.id] ??
                                                                      _showMacrosTotal)
                                                                  ? Column(
                                                                      mainAxisAlignment:
                                                                          MainAxisAlignment
                                                                              .center,
                                                                      mainAxisSize:
                                                                          MainAxisSize
                                                                              .min,
                                                                      children: [
                                                                        Text(
                                                                          '${_roundMacro(data['food_protein'])}g Protein',
                                                                          style:
                                                                              const TextStyle(
                                                                            color:
                                                                                Colors.white,
                                                                            fontWeight:
                                                                                FontWeight.bold,
                                                                            fontSize:
                                                                                10,
                                                                            height:
                                                                                1.2,
                                                                          ),
                                                                        ),
                                                                        Text(
                                                                          '${_roundMacro(data['food_carbs'])}g Carbs',
                                                                          style:
                                                                              const TextStyle(
                                                                            color:
                                                                                Colors.white,
                                                                            fontWeight:
                                                                                FontWeight.bold,
                                                                            fontSize:
                                                                                10,
                                                                            height:
                                                                                1.2,
                                                                          ),
                                                                        ),
                                                                        Text(
                                                                          '${_roundMacro(data['food_fat'])}g Fat',
                                                                          style:
                                                                              const TextStyle(
                                                                            color:
                                                                                Colors.white,
                                                                            fontWeight:
                                                                                FontWeight.bold,
                                                                            fontSize:
                                                                                10,
                                                                            height:
                                                                                1.2,
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    )
                                                                  : Text(
                                                                      '${_roundMacro(data['food_calories'])} kcal',
                                                                      style:
                                                                          const TextStyle(
                                                                        color: Colors
                                                                            .white,
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                        fontSize:
                                                                            12,
                                                                      ),
                                                                    ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                    // Show emoji picker when in readOnly mode
                                                    if (widget.readOnly &&
                                                        (_showEmojiPicker[
                                                                doc.id] ??
                                                            false))
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(12),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors
                                                              .grey.shade100,
                                                          borderRadius:
                                                              const BorderRadius
                                                                  .only(
                                                            bottomLeft:
                                                                Radius.circular(
                                                                    12),
                                                            bottomRight:
                                                                Radius.circular(
                                                                    12),
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceEvenly,
                                                          children: [
                                                            GestureDetector(
                                                              onTap: () =>
                                                                  _addReaction(
                                                                      doc.id,
                                                                      '🔥'),
                                                              child: const Text(
                                                                  '🔥',
                                                                  style: TextStyle(
                                                                      fontSize:
                                                                          32)),
                                                            ),
                                                            GestureDetector(
                                                              onTap: () =>
                                                                  _addReaction(
                                                                      doc.id,
                                                                      '😈'),
                                                              child: const Text(
                                                                  '😈',
                                                                  style: TextStyle(
                                                                      fontSize:
                                                                          32)),
                                                            ),
                                                            GestureDetector(
                                                              onTap: () =>
                                                                  _addReaction(
                                                                      doc.id,
                                                                      '💪'),
                                                              child: const Text(
                                                                  '💪',
                                                                  style: TextStyle(
                                                                      fontSize:
                                                                          32)),
                                                            ),
                                                            GestureDetector(
                                                              onTap: () =>
                                                                  _addReaction(
                                                                      doc.id,
                                                                      '❤️'),
                                                              child: const Text(
                                                                  '❤️',
                                                                  style: TextStyle(
                                                                      fontSize:
                                                                          32)),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    // Show reaction confirmation when in readOnly mode after adding emoji
                                                    if (widget.readOnly &&
                                                        _reactionConfirmationFoodId ==
                                                            doc.id &&
                                                        _reactionFadeAnimation !=
                                                            null)
                                                      FadeTransition(
                                                        opacity:
                                                            _reactionFadeAnimation!,
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 16,
                                                            vertical: 8,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors
                                                                .green.shade50,
                                                            borderRadius:
                                                                const BorderRadius
                                                                    .only(
                                                              bottomLeft: Radius
                                                                  .circular(12),
                                                              bottomRight:
                                                                  Radius
                                                                      .circular(
                                                                          12),
                                                            ),
                                                          ),
                                                          child: Row(
                                                            children: [
                                                              Expanded(
                                                                child: Text(
                                                                  _reactionConfirmationUsername ??
                                                                      '',
                                                                  style:
                                                                      TextStyle(
                                                                    color: Colors
                                                                        .grey
                                                                        .shade700,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w500,
                                                                  ),
                                                                ),
                                                              ),
                                                              Text(
                                                                _reactionConfirmationEmoji ??
                                                                    '',
                                                                style:
                                                                    const TextStyle(
                                                                        fontSize:
                                                                            24),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    // Show reactions when owner taps food item
                                                    if (!widget.readOnly &&
                                                        (_showReactions[
                                                                doc.id] ??
                                                            false) &&
                                                        _foodReactions[
                                                                doc.id] !=
                                                            null &&
                                                        _foodReactions[doc.id]!
                                                            .isNotEmpty)
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 16,
                                                          vertical: 8,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors
                                                              .blue.shade50,
                                                          borderRadius:
                                                              const BorderRadius
                                                                  .only(
                                                            bottomLeft:
                                                                Radius.circular(
                                                                    12),
                                                            bottomRight:
                                                                Radius.circular(
                                                                    12),
                                                          ),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: _foodReactions[
                                                                  doc.id]!
                                                              .map(
                                                                  (reaction) =>
                                                                      Padding(
                                                                        padding:
                                                                            const EdgeInsets.symmetric(
                                                                          vertical:
                                                                              2,
                                                                        ),
                                                                        child:
                                                                            Row(
                                                                          children: [
                                                                            Expanded(
                                                                              child: Text(
                                                                                reaction['username'] ?? 'Unknown',
                                                                                style: TextStyle(
                                                                                  color: AppColors.gray700,
                                                                                  fontWeight: FontWeight.w500,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            Text(
                                                                              reaction['emoji'] ?? '',
                                                                              style: const TextStyle(fontSize: 20),
                                                                            ),
                                                                          ],
                                                                        ),
                                                                      ))
                                                              .toList(),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        if (_isDeletingItem)
                                          Container(
                                            color:
                                                Colors.black.withValues(alpha: 0.3),
                                            child: const Center(
                                              child: CircularProgressIndicator(
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(Colors.white),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if (_isOwnCard && !_isSelectedDateToday)
                                    _PastDayNotice(
                                      onToday: () =>
                                          _changeDay(BalanceService.now()),
                                    )
                                  else if (_isOwnCard)
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: <Widget>[
                                        FloatingActionButton.extended(
                                          onPressed: !_canEditSelectedDay
                                              ? null
                                              : () async {
                                                  setState(() {
                                                    _deleteMode = false;
                                                  });
                                                  final saved =
                                                      await Navigator.push<
                                                          bool>(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          const AddFoodPage(),
                                                    ),
                                                  );
                                                  // Logging signals a refresh
                                                  // on its own; this covers
                                                  // the rest.
                                                  if (saved == true &&
                                                      mounted) {
                                                    await (_refreshing ??
                                                        _refreshAfterChange());
                                                  }
                                                },
                                          heroTag: 'addFood',
                                          backgroundColor: !_canEditSelectedDay
                                              ? AppColors.gray400
                                              : AppColors.emerald600,
                                          foregroundColor: Colors.white,
                                          icon: const Icon(Icons.add),
                                          label: const Text('Food'),
                                        ),
                                        FloatingActionButton.extended(
                                          onPressed: !_canEditSelectedDay
                                              ? null
                                              : () async {
                                                  setState(() {
                                                    _deleteMode = false;
                                                  });
                                                  final result =
                                                      await Navigator.push<
                                                          Map<String, dynamic>>(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          const _SelectExistingRecipePage(),
                                                    ),
                                                  );
                                                  if (result == null ||
                                                      !context.mounted) {
                                                    return;
                                                  }
                                                  final category = Provider.of<
                                                              CategoryService>(
                                                          context,
                                                          listen: false)
                                                      .selectedCategory;
                                                  await _addRecipeToHome(
                                                    result['recipeId']
                                                        as String,
                                                    category,
                                                    multiplier:
                                                        result['multiplier']
                                                            as double,
                                                  );
                                                },
                                          heroTag: 'addRecipe',
                                          backgroundColor: !_canEditSelectedDay
                                              ? AppColors.gray400
                                              : AppColors.violet600,
                                          foregroundColor: Colors.white,
                                          icon: const Icon(Icons.add),
                                          label: const Text('Recipe'),
                                        ),
                                        FloatingActionButton(
                                          onPressed: !_canEditSelectedDay ||
                                                  _foodDocs.isEmpty
                                              ? null
                                              : () {
                                                  setState(() {
                                                    _deleteMode = !_deleteMode;
                                                  });
                                                },
                                          heroTag: 'delete',
                                          tooltip: _deleteMode
                                              ? 'Done removing'
                                              : 'Remove food',
                                          backgroundColor: !_canEditSelectedDay ||
                                                  _foodDocs.isEmpty
                                              ? AppColors.gray400
                                              : _deleteMode
                                                  ? AppColors.red700
                                                  : AppColors.red600,
                                          foregroundColor: Colors.white,
                                          child: Icon(_deleteMode
                                              ? Icons.close
                                              : Icons.delete_outline),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the add/remove buttons on a past day.
class _PastDayNotice extends StatelessWidget {
  final VoidCallback onToday;

  const _PastDayNotice({required this.onToday});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock, color: Colors.white70, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Past days are read-only. Food you add goes on today.',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onToday,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
            ),
            child: const Text('Go to today'),
          ),
        ],
      ),
    );
  }
}
