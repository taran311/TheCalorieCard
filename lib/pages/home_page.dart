import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import 'package:namer_app/services/pacing.dart';
import 'package:namer_app/services/usuals.dart';
import 'package:namer_app/ui/coach_nudge.dart';
import 'package:namer_app/ui/entry_sheet.dart';
import 'package:namer_app/ui/log_recipe_sheet.dart';
import 'package:namer_app/ui/streak_pill.dart';
import 'package:namer_app/ui/premium_sheet.dart';
import 'package:namer_app/services/premium_service.dart';
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

/// Pick a saved recipe to log. Tapping one opens the shared recipe sheet
/// (meal, servings, Spend), which shows its own "Logged … · Undo" note.
class _RecipePickerPage extends StatefulWidget {
  const _RecipePickerPage();

  @override
  State<_RecipePickerPage> createState() => _RecipePickerPageState();
}

class _RecipePickerPageState extends State<_RecipePickerPage> {
  int _selectedTabIndex = 0; // 0 = My recipes, 1 = Shared with me

  // Created once, so rebuilding the page doesn't re-subscribe.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _myRecipes =
      BalanceService.db
          .collection('recipes')
          .where('user_id', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _sharedRecipes =
      BalanceService.db
          .collection('shared_recipes')
          .where('shared_with_user_id',
              isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .snapshots();

  // Shared recipe details, cached for the current set of shared docs.
  Future<List<Map<String, dynamic>>>? _sharedDetails;
  String? _sharedDetailsKey;

  Future<List<Map<String, dynamic>>> _sharedDetailsFor(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final key = docs.map((d) => d.id).join(',');
    final cached = _sharedDetails;
    if (cached != null && key == _sharedDetailsKey) return cached;
    _sharedDetailsKey = key;
    final future = _loadSharedRecipeDetails(docs);
    _sharedDetails = future;
    return future;
  }

  /// Opens the recipe sheet; once something's logged, back to the Card.
  Future<void> _log(String recipeId, Map<String, dynamic> recipe) async {
    // Typed loosely so this works whether the sheet returns what it
    // logged or nothing.
    final logged = await showLogRecipeSheet(
      context,
      recipeId: recipeId,
      recipe: recipe,
    ).then<Object?>((Object? r) => r);
    if (logged is LoggedFoods && mounted) Navigator.pop(context, logged);
  }

  Widget _tab(int index, String label) {
    final selected = _selectedTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTabIndex = index),
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
              color: selected ? AppText.primaryDark : AppColors.gray600,
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
              style: TextStyle(color: AppColors.gray600, fontSize: 15),
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

  Widget _recipeTile(
    String recipeId,
    Map<String, dynamic> recipe, {
    String? sharedBy,
  }) {
    final calories = BalanceService.number(recipe['total_calories']) ?? 0;
    final servingSize = (recipe['serving_size'] as String?) ?? 'Per 1 Serving';
    return ListTile(
      minVerticalPadding: 10,
      title: Text(
        (recipe['name'] ?? 'Recipe').toString(),
        style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        sharedBy == null
            ? '${calories.toStringAsFixed(0)} kcal ($servingSize)'
            : '${calories.toStringAsFixed(0)} kcal ($servingSize)\n'
                'Shared by $sharedBy',
        style: TextStyle(color: AppColors.muted),
      ),
      isThreeLine: sharedBy != null,
      trailing: Icon(Icons.add_circle_outline, color: AppText.primary),
      onTap: () => _log(recipeId, recipe),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Add a recipe'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Material(
            color: AppColors.surface,
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
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

        final recipes = snapshot.data!.docs.toList()
          // Newest first. data()[...] rather than doc[...]: older recipes
          // may be missing fields, and doc[...] throws for those.
          ..sort((a, b) {
            final timeA = a.data()['created_at'];
            final timeB = b.data()['created_at'];
            if (timeA is! Timestamp || timeB is! Timestamp) return 0;
            return timeB.compareTo(timeA);
          });

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 48),
          itemCount: recipes.length,
          itemBuilder: (context, index) =>
              _recipeTile(recipes[index].id, recipes[index].data()),
        );
      },
    );
  }

  Widget _buildSharedRecipesTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _sharedDetailsFor(snapshot.data!.docs),
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
                return _recipeTile(
                  item['recipe_id'] as String,
                  item['recipe'] as Map<String, dynamic>,
                  sharedBy: item['sharedBy'] as String,
                );
              },
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadSharedRecipeDetails(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sharedRecipeDocs,
  ) async {
    final firestore = BalanceService.db;
    final found = await Future.wait(sharedRecipeDocs.map((doc) async {
      final data = doc.data();
      final recipeId = data['recipe_id'];
      final sharedByUserId = data['shared_by_user_id'];
      if (recipeId is! String) return null;
      try {
        final recipeDoc =
            await firestore.collection('recipes').doc(recipeId).get();
        final recipe = recipeDoc.data();
        if (recipe == null) return null;
        final sharedBy = sharedByUserId is String
            ? await FriendsService.nameFor(sharedByUserId)
            : 'Unknown';
        return <String, dynamic>{
          'recipe_id': recipeId,
          'recipe': recipe,
          'sharedBy': sharedBy,
        };
      } catch (_) {
        return null;
      }
    }));
    return [for (final r in found) if (r != null) r];
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
  final List<String> _tabs = FoodLog.meals;
  int _creditCardRefreshKey = 0;
  bool _isLoading = true;

  // First-time walkthrough of the Card screen.
  final _tourCard = GlobalKey(debugLabel: 'tour-home-card');
  final _tourAdd = GlobalKey(debugLabel: 'tour-home-add');
  final _tourClose = GlobalKey(debugLabel: 'tour-home-close');
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

  /// The day's food couldn't be loaded: show Retry, not "Nothing yet".
  bool _foodLoadFailed = false;

  /// The meal picked on the Add food button's menu, and the time-of-day
  /// meal it replaced. Once the clock moves on to the next meal, the
  /// button goes back to guessing.
  String? _mealOverride;
  String? _mealOverrideFor;

  /// Foods often logged at [_usualsMeal] (one-tap chips under Add food).
  List<UsualFood> _usuals = const [];
  String? _usualsMeal;
  bool _loggingUsual = false;

  /// Names of people who reacted, looked up once each.
  final Map<String, String> _reactionNames = {};

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

  // Food reaction tracking (food id → reactions), loaded after the food.
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
    // What you just logged can become one of your usuals.
    _usualsMeal = null;
    _loadUsuals();
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
    _loadUsuals();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForNewDay();
      // The meal the Add food button guesses may have moved on.
      if (mounted) setState(() {});
      _loadUsuals();
    }
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
    // Reduce motion: snap back instead of sliding.
    if (!MediaQuery.of(context).disableAnimations) {
      _isResettingCard = true;
      _cardDragResetController!.reset();
      await _cardDragResetController!.forward();
    }
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
      // One-off: give old entries a time_added so date-range reads see
      // them. Not awaited: it's a no-op for almost everyone, and shouldn't
      // hold up the card. If it fails it's tried again next launch.
      unawaited(BalanceService.backfillEntryTimes(_activeUserId)
          .then<void>((fixed) {
        if (fixed > 0 && mounted) _refreshAfterChange();
      }, onError: (_) {}));
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
    // Independent reads: run them side by side.
    await Future.wait([
      _fetchUserGoals(),
      populateFoodItems(),
      _fetchDailyLogForDate(_selectedLogDate),
    ]);
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      _startHomeTour();
      _loadUsuals();
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
      // Kept short: the four things you need on day one. Same id as
      // before, so anyone who's seen it doesn't get it again.
      SpotlightTour.showOnce(context, id: 'home_intro', canStart: onScreen,
          steps: [
        TourStep(
          target: _tourCard,
          title: 'Your card',
          body: "The big number is what you've got left to spend today. "
              'Food you log comes off it. Tap the card to see your macros.',
          padding: 6,
          radius: 24,
        ),
        TourStep(
          target: _tourAdd,
          title: 'Add food',
          body: 'One tap to log what you had. It picks the meal from the '
              'time of day; tap the meal next to it to change it.',
          radius: 16,
        ),
        TourStep(
          target: _tourClose,
          title: 'Close today',
          body: "When you're done eating, close the day. Closed days count "
              'towards your streak, and you can reopen if you need to.',
          radius: 16,
        ),
        if (shell != null)
          TourStep(
            target: shell.coach,
            title: 'Calorie Coach',
            body: "Ask for a meal that fits what you've got left, a pep "
                "talk, or help if you've gone over.",
            padding: 4,
            radius: 40,
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

  /// The card was swiped: close today, or reopen it if it's closed.
  Future<void> _handleCardSwipe() async {
    if (_isDayFinished) {
      await _reopenDay();
    } else {
      await _closeDay();
    }
  }

  Future<void> _reopenDay() async {
    if (_isUpdatingDailyLog) return;
    if (!_isSelectedDateToday || !_isOwnCard || !_isDayFinished) return;
    final confirm = await _showConfirmDialog(
      title: 'Reopen today?',
      message: "You can add or remove food again. Close it when you're done.",
      cancelLabel: 'Cancel',
      confirmLabel: 'Reopen',
    );
    if (!confirm || !mounted) return;
    setState(() {
      _isDayFinished = false;
    });
    await _setDailyLogFinished(_selectedLogDate, false);
    await _fetchDailyLogForDate(_selectedLogDate);
    MyStreak.load(_activeUserId, force: true);
  }

  /// Closes today (from the Close today button, a card swipe, the inbox
  /// or the card's "Close day" accessibility action).
  Future<void> _closeDay() async {
    if (_isUpdatingDailyLog) return;
    if (!_isSelectedDateToday || !_isOwnCard || _isDayFinished) return;

    // An empty day is usually a mistake, so say so first.
    final nothingLogged = _foodDocs.isEmpty;
    final confirm = nothingLogged
        ? await _showConfirmDialog(
            title: 'Close today?',
            message: 'Nothing logged today. Close anyway? You can reopen '
                'it if you need to.',
            cancelLabel: 'Not yet',
            confirmLabel: 'Close anyway',
          )
        : await _showConfirmDialog(
            title: 'Close today?',
            message: "This locks today's card and counts it towards your "
                'streak. You can reopen it if you need to.',
            cancelLabel: 'Not yet',
            confirmLabel: 'Close day',
          );
    if (!confirm || !mounted) return;

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

  /// Loads the selected day's food (every meal, oldest first) and the
  /// whole day's totals (for past days' cards). Reactions follow after the
  /// food is on screen, so they never hold it up.
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

      setState(() {
        _foodLoadFailed = false;
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
      _loadYesterday();
      unawaited(_fetchReactionsForFoodItems());
    } catch (e) {
      if (!mounted || token != _foodLoadToken) return;
      setState(() {
        _foodLoadFailed = true;
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

  /// Reactions to the food on screen: one query per 30 foods (Firestore's
  /// whereIn limit), all at once, with each person's name looked up once.
  Future<void> _fetchReactionsForFoodItems() async {
    final token = _foodLoadToken;
    final ids = [for (final d in _foodDocs) d.id];
    if (ids.isEmpty) {
      if (mounted && _foodReactions.isNotEmpty) {
        setState(() => _foodReactions = {});
      }
      return;
    }
    try {
      final db = BalanceService.db;
      final snaps = await Future.wait([
        for (var i = 0; i < ids.length; i += 30)
          db
              .collection('food_reactions')
              .where('food_item_id',
                  whereIn: ids.sublist(i, math.min(i + 30, ids.length)))
              .get(),
      ]);
      final docs = [for (final snap in snaps) ...snap.docs];

      final unknown = {
        for (final d in docs)
          if (d.data()['user_id'] is String &&
              !_reactionNames.containsKey(d.data()['user_id']))
            d.data()['user_id'] as String
      };
      await Future.wait(unknown.map((uid) async {
        _reactionNames[uid] = await FriendsService.nameFor(uid);
      }));
      if (!mounted || token != _foodLoadToken) return;

      final byFood = <String, List<Map<String, dynamic>>>{};
      for (final d in docs) {
        final data = d.data();
        final userId = data['user_id'];
        byFood.putIfAbsent('${data['food_item_id']}', () => []).add({
          'id': d.id,
          'emoji': data['emoji'],
          'user_id': userId,
          'username': userId is String
              ? (_reactionNames[userId] ?? 'Someone')
              : 'Someone',
        });
      }
      setState(() => _foodReactions = byFood);
    } catch (e) {
      // Reactions are a nice extra; the food is already showing.
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

  void _handleFoodItemTap(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final foodItemId = doc.id;
    if (widget.readOnly) {
      // Show emoji picker
      setState(() {
        _showEmojiPicker[foodItemId] = !(_showEmojiPicker[foodItemId] ?? false);
      });
    } else if (_isOwnCard) {
      _openEntrySheet(doc);
    } else {
      // Toggle reactions display
      setState(() {
        _showReactions[foodItemId] = !(_showReactions[foodItemId] ?? false);
      });
    }
  }

  /// One of your foods was tapped (or long-pressed): see it, change the
  /// portion or meal, fix the calories, delete, log again or set up a
  /// direct debit.
  Future<void> _openEntrySheet(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    if (!_isOwnCard) return;
    final entry = doc.data();
    final name = (entry['food_description'] ?? 'Food').toString();
    final result = await showEntrySheet(
      context,
      entryId: doc.id,
      entry: entry,
      canEdit: _canEditSelectedDay,
      reactions: _foodReactions[doc.id] ?? const [],
    );
    if (result == null || !mounted) return;
    switch (result.action) {
      case EntrySheetAction.saved:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved $name')),
        );
        await (_refreshing ?? _refreshAfterChange());
      case EntrySheetAction.delete:
        await _deleteFoodItem(doc.id);
      case EntrySheetAction.loggedAgain:
        final logged = result.logged;
        if (logged != null) {
          await (_refreshing ?? _refreshAfterChange());
          if (mounted) _showLoggedUndo(logged);
        }
      case EntrySheetAction.directDebit:
        await _offerDirectDebit(entry);
    }
  }

  /// "Added 412 kcal to Lunch · Undo" after logging from here.
  void _showLoggedUndo(LoggedFoods logged, {String? message}) {
    if (logged.count == 0 || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(message ??
            'Added ${formatCardKcal(logged.calories)} kcal to ${logged.meal}'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              await FoodLog.undo(logged);
            } catch (_) {
              messenger.showSnackBar(const SnackBar(
                  content: Text("Couldn't undo that. Swipe the food away "
                      'to remove it.')));
            }
          },
        ),
      ),
    );
    // Snackbars with an action can stay up in newer Flutter; close it.
    var closed = false;
    controller.closed.then((_) => closed = true);
    Timer(const Duration(seconds: 6), () {
      if (!closed) messenger.hideCurrentSnackBar();
    });
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
          if (FoodLog.mealOf(e['foodCategory']) == meal) e
      ];

  Future<void> _copyYesterday(
      String meal, List<Map<String, dynamic>> entries) async {
    if (_copyingYesterday || !_canEditSelectedDay || entries.isEmpty) return;
    setState(() => _copyingYesterday = true);
    try {
      final logged = await FoodLog.logFoods(
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
        _showLoggedUndo(logged,
            message: "Added yesterday's $meal "
                '(${formatCardKcal(logged.calories)} kcal)');
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

  /// The meal the Add food button logs to: your pick on its menu, or a
  /// guess from the time of day.
  String get _addMeal {
    final guess = Pacing.mealAt(BalanceService.now());
    final picked = _mealOverride;
    return picked != null && _mealOverrideFor == guess ? picked : guess;
  }

  void _pickAddMeal(String meal) {
    setState(() {
      _mealOverride = meal;
      _mealOverrideFor = Pacing.mealAt(BalanceService.now());
    });
    _loadUsuals();
  }

  Future<void> _openAddFood(String meal) async {
    if (!_canEditSelectedDay) return;
    _useMeal(meal);
    // On phones, open above the bottom bar so the Coach button doesn't
    // cover the page's buttons.
    final saved = await Navigator.of(context, rootNavigator: _isPhone)
        .push<Object?>(
      MaterialPageRoute(builder: (_) => const AddFoodPage()),
    );
    if (!mounted) return;
    // Logging signals a refresh on its own; this covers the rest. Older
    // versions of the page popped `true`; now it says what was logged.
    if (saved is LoggedFoods) {
      await (_refreshing ?? _refreshAfterChange());
      if (mounted) _showLoggedUndo(saved);
    } else if (saved == true) {
      await (_refreshing ?? _refreshAfterChange());
    }
  }

  /// Log a saved recipe. The picker opens above the bottom bar on phones
  /// (so the Coach button can't cover it), and the recipe sheet shows its
  /// own "Logged … · Undo" note.
  Future<void> _openRecipePicker(String meal) async {
    if (!_canEditSelectedDay) return;
    _useMeal(meal);
    await Navigator.of(context, rootNavigator: _isPhone).push<Object?>(
      MaterialPageRoute(builder: (_) => const _RecipePickerPage()),
    );
    if (mounted) await (_refreshing ?? _refreshAfterChange());
  }

  /// Loads the "usuals" chips for the Add food meal, off the critical
  /// path (only when the meal they're for has changed).
  Future<void> _loadUsuals() async {
    if (!_isOwnCard || widget.showBanner) return;
    final meal = _addMeal;
    if (_usualsMeal == meal) return;
    _usualsMeal = meal;
    try {
      final usuals = await Usuals.load(_activeUserId, meal);
      if (!mounted || _usualsMeal != meal) return;
      setState(() => _usuals = usuals);
    } catch (_) {
      // Just a shortcut; try again next time.
      if (_usualsMeal == meal) _usualsMeal = null;
    }
  }

  /// One tap on a usual: log it to the Add food meal, with Undo.
  Future<void> _logUsual(UsualFood usual) async {
    if (_loggingUsual || !_canEditSelectedDay) return;
    final meal = _addMeal;
    setState(() => _loggingUsual = true);
    try {
      final logged =
          await FoodLog.logFoods(items: [usual.toLogItem()], meal: meal);
      if (mounted) await (_refreshing ?? _refreshAfterChange());
      if (mounted) _showLoggedUndo(logged);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Couldn't log that. Please try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _loggingUsual = false);
    }
  }

  /// From the food sheet: have it every day? Set up a direct debit.
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
                style: TextStyle(color: AppColors.muted),
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

  /// The card was flipped: jiggle it and match every food row to it.
  void _onCardFlipped(bool showMacros) {
    // Reduce motion: no jiggle.
    if (!MediaQuery.of(context).disableAnimations) {
      _jiggleAnimationController?.forward(from: 0);
    }
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
          child: Semantics(
            // Swiping isn't available to everyone: same actions here.
            customSemanticsActions: !_isOwnCard || !_isSelectedDateToday
                ? null
                : {
                    if (_isDayFinished)
                      CustomSemanticsAction(label: 'Reopen day'):
                          _reopenDay
                    else
                      CustomSemanticsAction(label: 'Close day'):
                          _closeDay,
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
      ),
    );
  }

  /// The food in [meal] that's on screen (not mid-swipe).
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _visibleIn(String meal) => [
        for (final d in _foodDocs)
          if (!_pendingRemoval.contains(d.id) &&
              FoodLog.mealOf(d.data()['foodCategory']) == meal)
            d
      ];

  Widget _buildMealHeader(
      String meal, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final totals = BalanceService.totalOf(docs.map((d) => d.data()));
    final kcal = totals.calories.round();
    final macros = '${_roundMacro(totals.protein)}g protein · '
        '${_roundMacro(totals.carbs)}g carbs · ${_roundMacro(totals.fat)}g fat';
    // Small "+" and recipe buttons; the big Add food button is under the
    // card, so these stay light and never truncate on a 320 px phone.
    final canAdd = _canEditSelectedDay;
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 420;
    // On the smallest phones the meal icon makes way for the totals.
    final showIcon = !canAdd || width >= 360;

    return Material(
      color: AppColors.gray50,
      child: InkWell(
        onTap: docs.isEmpty ? null : _toggleMacros,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, canAdd ? 2 : 12, canAdd ? 4 : 12,
              canAdd ? 2 : 12),
          child: Row(
            children: [
              if (showIcon) ...[
                Icon(_mealIcon(meal), size: 20, color: AppText.primary),
                const SizedBox(width: 8),
              ],
              Text(
                meal,
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 8),
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
              if (docs.isNotEmpty && !(canAdd && narrow)) ...[
                const SizedBox(width: 8),
                Icon(
                  _showMacrosTotal
                      ? Icons.local_fire_department_outlined
                      : Icons.show_chart,
                  color: AppColors.muted,
                  size: 18,
                ),
              ],
              if (canAdd) ...[
                const SizedBox(width: 4),
                if (narrow)
                  IconButton(
                    tooltip: 'Add a recipe to $meal',
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    padding: EdgeInsets.zero,
                    color: AppText.primary,
                    onPressed: () => _openRecipePicker(meal),
                    icon: const Icon(Icons.menu_book_outlined, size: 20),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _openRecipePicker(meal),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('Recipe'),
                  ),
                IconButton(
                  tooltip: 'Add to $meal',
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  padding: EdgeInsets.zero,
                  color: AppText.primary,
                  onPressed: () => _openAddFood(meal),
                  icon: const Icon(Icons.add_circle_outline, size: 24),
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
        ? AppText.red600
        : (goal > 0 && left <= goal * 0.1)
            ? AppText.amber700
            : AppText.emerald700;
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
      style: TextStyle(fontSize: 13, color: AppColors.muted),
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
      text = 'Nothing yet.';
    }
    final yesterday = _canEditSelectedDay
        ? _yesterdayFor(meal)
        : const <Map<String, dynamic>>[];
    final yesterdayKcal = BalanceService.totalOf(yesterday).calories.round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          if (yesterday.isNotEmpty)
            Flexible(
              flex: 3,
              child: TextButton.icon(
                onPressed: _copyingYesterday
                    ? null
                    : () => _copyYesterday(meal, yesterday),
                style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                icon: const Icon(Icons.history, size: 18),
                label: Text(
                  'Same as yesterday · ${formatCardKcal(yesterdayKcal)} kcal',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Shown instead of the meals when the day's food couldn't be loaded,
  /// so an error never looks like an empty day.
  Widget _buildFoodLoadError() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.red50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.red100),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: AppText.red600, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Couldn't load your food.",
              style: TextStyle(color: AppColors.ink, fontSize: 14),
            ),
          ),
          TextButton(
            onPressed: _refreshAfterChange,
            style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Retry'),
          ),
        ],
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
    final estimate = data['food_estimate'] == true;

    final row = Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: () => _handleFoodItemTap(doc),
        // Same sheet as a tap (it has Make it a direct debit too).
        onLongPress: _isOwnCard ? () => _openEntrySheet(doc) : null,
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
                          style: TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                        if (portion.isNotEmpty ||
                            (_isOwnCard &&
                                reactions != null &&
                                reactions.isNotEmpty))
                          Text(
                            [
                              if (portion.isNotEmpty) portion,
                              // Your own card: a hint that friends reacted
                              // (tap to see who).
                              if (_isOwnCard &&
                                  reactions != null &&
                                  reactions.isNotEmpty)
                                reactions
                                    .map((r) => '${r['emoji'] ?? ''}')
                                    .join(),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (estimate) ...[
                    const SizedBox(width: 6),
                    const EstimateMark(),
                  ],
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.indigo50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: showMacros
                        ? MacroText(
                            protein:
                                BalanceService.number(data['food_protein']) ??
                                    0,
                            carbs:
                                BalanceService.number(data['food_carbs']) ?? 0,
                            fat: BalanceService.number(data['food_fat']) ?? 0,
                          )
                        : Text(
                            '${_roundMacro(data['food_calories'])} kcal',
                            style: TextStyle(
                              color: AppText.primaryDark,
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
                          style: TextStyle(
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
                                style: TextStyle(
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

  /// The one obvious way to log: a big Add food button for the meal it's
  /// about time for, with a small menu to pick another meal.
  Widget _buildAddFoodBar() {
    final meal = _addMeal;
    return Row(
      key: _tourAdd,
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: () => _openAddFood(meal),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add food',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'Change meal',
          initialValue: meal,
          onSelected: _pickAddMeal,
          itemBuilder: (context) => [
            for (final m in FoodLog.meals)
              PopupMenuItem<String>(
                value: m,
                child: Row(
                  children: [
                    Icon(_mealIcon(m), size: 20, color: AppText.primary),
                    const SizedBox(width: 10),
                    Text(m),
                  ],
                ),
              ),
          ],
          child: Semantics(
            button: true,
            label: 'Meal: $meal. Change meal',
            excludeSemantics: true,
            child: Container(
              height: 52,
              padding: const EdgeInsets.only(left: 12, right: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_mealIcon(meal), size: 18, color: AppText.primary),
                  const SizedBox(width: 6),
                  Text(
                    meal,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Icon(Icons.arrow_drop_down, color: AppColors.muted),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One-tap chips for what you usually have at this meal.
  Widget? _buildUsuals() {
    if (_usuals.isEmpty || _usualsMeal != _addMeal) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your usual ${_addMeal.toLowerCase()}',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _usuals.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final usual = _usuals[i];
              return Center(
                child: ActionChip(
                  avatar: Icon(Icons.add, size: 16, color: AppText.primary),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      usual.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  tooltip: 'Log ${usual.name} '
                      '(${usual.calories.round()} kcal) to $_addMeal',
                  onPressed: _loggingUsual ? null : () => _logUsual(usual),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// "About 650 kcal for dinner": how to pace what's left today.
  Widget? _buildPacing() {
    final left = _liveBalance;
    if (left == null || left <= 0) return null;
    final plan = Pacing.plan(
      left: left,
      now: BalanceService.now(),
      mealsWithFood: {
        for (final d in _foodDocs)
          if (!_pendingRemoval.contains(d.id))
            FoodLog.mealOf(d.data()['foodCategory'])
      },
    );
    if (plan == null) return null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.restaurant_outlined, size: 16, color: AppText.emerald700),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            plan.message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.gray700,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFoodPanel(String meal) {
    final visible = _visibleIn(meal);
    final canEdit = _canEditSelectedDay;

    return Container(
      decoration: AppDecor.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMealHeader(meal, visible),
          Divider(height: 1, thickness: 1, color: AppColors.border),
          if (visible.isEmpty)
            _buildEmptyMeal(meal)
          else
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0)
                Divider(height: 1, thickness: 1, color: AppColors.border),
              _buildFoodRow(visible[i], canEdit),
            ],
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
    final canAdd = _canEditSelectedDay;
    final pacing = canAdd ? _buildPacing() : null;
    final usuals = canAdd ? _buildUsuals() : null;
    final visibleFood = _foodDocs.any((d) => !_pendingRemoval.contains(d.id));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      // Tutorials, bottom-left so it never sits under the Coach button.
      // It hides itself once you've watched a couple.
      floatingActionButton: ownHome ? const TutorialButton() : null,
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
                    if (pacing != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: pacing,
                      ),
                    // Logging is one obvious tap, right under the card.
                    if (canAdd)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _buildAddFoodBar(),
                      ),
                    if (usuals != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: usuals,
                      ),
                    // Closed: one quiet row instead of any add buttons.
                    if (_isOwnCard && _isSelectedDateToday && _isDayFinished)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _ClosedDayStrip(onReopen: _reopenDay),
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
                          onAsk: (question) {
                            if (!Premium.isPremium) {
                              showPremiumSheet(
                                context,
                                title: '"Even it out" plans are Premium',
                                message: 'Coach spreads what you went over '
                                    'across the rest of the week, a little '
                                    'each day, so one big day never knocks '
                                    'you off track.',
                              );
                              return;
                            }
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    CoachPage(initialQuestion: question),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: DayStepper(
                              selected: _selectedLogDate,
                              onChanged: _changeDay,
                            ),
                          ),
                          if (_isOwnCard) ...[
                            const SizedBox(width: 8),
                            StreakPill(userId: _activeUserId),
                          ],
                        ],
                      ),
                    ),
                    if (_isOwnCard && _isSelectedDateToday)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: HomeInbox(
                          userId: _activeUserId,
                          isDayFinished: _isDayFinished,
                          hasFoodToday: _dayTotals.calories > 0,
                          onFinishDay: _closeDay,
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
                    if (_isDeletingItem || _copyingYesterday || _loggingUsual)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (_foodLoadFailed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: _buildFoodLoadError(),
                      )
                    else
                      // Every meal, one after another.
                      for (final meal in _tabs)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: _buildFoodPanel(meal),
                        ),
                    // Done for the day? Close it here (or swipe the card).
                    if (canAdd && visibleFood)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: OutlinedButton.icon(
                          key: _tourClose,
                          onPressed: _isUpdatingDailyLog ? null : _closeDay,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          icon: const Icon(Icons.task_alt_rounded),
                          label: const Text('Close today'),
                        ),
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

/// Under the card once today is closed: one quiet row (in place of the
/// add buttons) with a way to reopen it.
class _ClosedDayStrip extends StatelessWidget {
  final VoidCallback onReopen;

  const _ClosedDayStrip({required this.onReopen});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.gray50,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onReopen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline_rounded,
                  color: AppColors.muted, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Day closed · Reopen to add more',
                  style: TextStyle(
                    color: AppColors.gray700,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              TextButton(
                onPressed: onReopen,
                style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                child: const Text('Reopen'),
              ),
            ],
          ),
        ),
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
          Icon(Icons.lock_clock, color: AppText.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
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
