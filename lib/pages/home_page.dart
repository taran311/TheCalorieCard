import 'dart:async';
import 'dart:math' as math;

import 'package:namer_app/services/analytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/ui/snack.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:namer_app/components/credit_card.dart';
import 'package:namer_app/pages/achievements_page.dart';
import 'package:namer_app/pages/add_food_page.dart';
import 'package:namer_app/pages/statement_page.dart';
import 'package:namer_app/pages/coach_page.dart';
import 'package:namer_app/services/category_service.dart';
import 'package:namer_app/services/achievement_service.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/card_design_service.dart';
import 'package:namer_app/services/even_out.dart';
import 'package:namer_app/services/direct_debit_service.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/portion_amount.dart';
import 'package:namer_app/services/late_close.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/services/chat_service.dart';
import 'package:namer_app/services/leaderboard_service.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/services/pacing.dart';
import 'package:namer_app/services/rest_days.dart';
import 'package:namer_app/services/usuals.dart';
import 'package:namer_app/ui/coach_nudge.dart';
import 'package:namer_app/ui/entry_sheet.dart';
import 'package:namer_app/ui/log_recipe_sheet.dart';
import 'package:namer_app/ui/streak_pill.dart';
import 'package:namer_app/ui/confetti.dart';
import 'package:namer_app/ui/premium_sheet.dart';
import 'package:namer_app/services/premium_service.dart';
import 'package:namer_app/ui/home_inbox.dart';
import 'package:namer_app/ui/home_widgets.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:namer_app/ui/spotlight_tour.dart';
import 'package:namer_app/ui/tutorials/tutorial_button.dart';
import 'package:namer_app/ui/calorie_symbol.dart';

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
            ? '$calSym${calories.toStringAsFixed(0)} ($servingSize)'
            : '$calSym${calories.toStringAsFixed(0)} ($servingSize)\n'
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
    // The same recipe shared more than once shows once.
    final seen = <String>{};
    final unique = [
      for (final d in sharedRecipeDocs)
        if (d.data()['recipe_id'] is String &&
            seen.add(d.data()['recipe_id'] as String))
          d
    ];
    final found = await Future.wait(unique.map((doc) async {
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

  /// Food can be added or removed on today's card until the day is
  /// finished, and on yesterday's until midnight (forgot something? It
  /// stays closed if it was). Older days are a statement: read-only. A rest
  /// day ("frozen" card) is read-only too, until it's unfrozen.
  bool get _canEditSelectedDay =>
      _isOwnCard &&
      !_isRestDay &&
      ((_isSelectedDateToday && !_isDayFinished) || _isSelectedDateYesterday);

  /// Food can be removed from any of your own days, closed or not (a
  /// mistake is a mistake). That day's saved totals follow; today's card is
  /// only refunded for today's food.
  bool get _canRemoveOnSelectedDay => _isOwnCard;

  /// Today's extras (usuals, pacing, copy from yesterday, close / rest
  /// day) only make sense on today's card.
  bool get _canEditToday => _canEditSelectedDay && _isSelectedDateToday;

  /// The selected day is a rest day (`daily_logs.rest_day`): the card is
  /// "frozen", nothing is tracked and the streak is paused.
  bool get _isRestDay => RestDays.isRest(_selectedDailyLog);

  /// Starting or ending a rest day is in progress.
  bool _restBusy = false;

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

  /// "Spread it over the week" (EvenOut): the plan, if one is set.
  late final Stream<EvenOutPlan?> _evenOut = EvenOut.watch(_activeUserId);
  bool _evenOutBusy = false;

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

  // Card animations
  AnimationController? _jiggleAnimationController;
  Animation<double>? _jiggleAnimation;
  AnimationController? _cardDragResetController;
  double _dragEndDx = 0;
  bool _isResettingCard = false;
  /// Changing day: the card slides out one side and the new day's card in
  /// from the other (added to the drag offset).
  AnimationController? _slideController;
  final ValueNotifier<double> _slideDx = ValueNotifier(0);
  bool _sliding = false;
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
    _slideController = AnimationController(vsync: this);

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
    } else if (_isOwnCard) {
      // Changed an earlier day (added to yesterday, or removed something):
      // its saved totals and closing balance follow (today's card isn't
      // touched).
      try {
        await LateClose.syncDay(_activeUserId, _selectedLogDate);
      } catch (_) {}
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
    _slideController?.dispose();
    _slideDx.dispose();
    super.dispose();
  }

  Future<void> _resetCardPosition() async {
    if (_cardDragResetController == null) return;
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
  }

  /// Moves [_slideDx] from [from] to [to].
  Future<void> _slideBetween(
      double from, double to, int ms, Curve curve) async {
    final c = _slideController;
    if (c == null) return;
    c.duration = Duration(milliseconds: ms);
    final anim =
        Tween(begin: from, end: to).chain(CurveTween(curve: curve)).animate(c);
    void tick() => _slideDx.value = anim.value;
    c.addListener(tick);
    try {
      await c.forward(from: 0).orCancel;
    } catch (_) {
      // Stopped (the page closed): nothing to finish.
    } finally {
      c.removeListener(tick);
    }
  }

  /// Back ([days] -1) or forward (1) a day, like turning a page: the card
  /// leaves on one side and the new day's arrives from the other.
  /// (Forward from today springs back: there's nothing after it.)
  Future<void> _slideToDay(int days) async {
    if (_sliding) return;
    final next = BalanceService.addDays(_selectedLogDate, days);
    if (days > 0 && next.isAfter(BalanceService.now())) {
      await _resetCardPosition();
      return;
    }
    HapticFeedback.selectionClick();
    if (MediaQuery.of(context).disableAnimations) {
      setState(() => _cardDragDx = 0);
      await _changeDay(next);
      return;
    }
    _sliding = true;
    try {
      final width = MediaQuery.sizeOf(context).width;
      // Yesterday lives to the left, so going back the card leaves right.
      final out = days < 0 ? width : -width;
      // Carry on from wherever the finger let go.
      final start = _cardDragDx;
      setState(() => _cardDragDx = 0);
      await _slideBetween(start, out, 140, Curves.easeIn);
      if (!mounted) return;
      final loading = _changeDay(next);
      await _slideBetween(-out, 0, 220, Curves.easeOutCubic);
      await loading;
    } finally {
      _slideDx.value = 0;
      _sliding = false;
    }
  }

  /// The ‹ › arrows: one day either way slides like a swipe; a date picked
  /// from the calendar just switches.
  Future<void> _stepToDay(DateTime day) async {
    final from = DateTime(
        _selectedLogDate.year, _selectedLogDate.month, _selectedLogDate.day);
    final to = DateTime(day.year, day.month, day.day);
    // Rounded, so a clocks-change day (23 or 25 hours) still counts as one.
    final delta = (to.difference(from).inHours / 24).round();
    if (delta == 1 || delta == -1) {
      await _slideToDay(delta);
    } else {
      await _changeDay(day);
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
      if (!mounted || !onScreen()) return;
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

  bool get _isSelectedDateYesterday =>
      LateClose.isYesterday(_selectedLogDate);

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

  /// Closes today (from the Close today button, the inbox
  /// or the card's "Close day" accessibility action).
  Future<void> _closeDay() async {
    if (_isUpdatingDailyLog) return;
    if (!_isSelectedDateToday || !_isOwnCard || _isDayFinished) return;
    if (_isRestDay) return;

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
    HapticFeedback.mediumImpact();
    showStamp(context, 'CLOSED ✓');
    Analytics.track('day_closed');
    await _upsertDailyLogForDate(_selectedLogDate);
    await _setDailyLogFinished(_selectedLogDate, true);
    await _fetchDailyLogForDate(_selectedLogDate);
    try {
      final unlocked =
          await AchievementService.updateAchievementsForUser(_activeUserId);
      if (unlocked.isNotEmpty && mounted) {
        final first = unlocked.first;
        final more = unlocked.length > 1 ? ' (+${unlocked.length - 1} more)' : '';
        ScaffoldMessenger.of(context).showTimedSnackBar(
          SnackBar(
            content: Text(
                '${first.emoji} Achievement unlocked: ${first.title}$more'),
            duration: const Duration(seconds: 5),
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
    // to open High scores first.
    try {
      await LeaderboardService.refreshMine(_activeUserId);
    } catch (_) {}
    await MyStreak.load(_activeUserId, force: true);
    final streak = MyStreak.notifier.value?.current ?? 0;
    if (mounted && const {7, 30, 100, 365}.contains(streak)) {
      showConfetti(context);
      _snack('🔥 $streak days in a row. Brilliant.');
    }
  }

  /// "Spread it over the week": the next few days start a little lower.
  Future<void> _spreadOverWeek(int overBy) async {
    if (_evenOutBusy) return;
    setState(() => _evenOutBusy = true);
    try {
      final plan = await EvenOut.start(_activeUserId,
          overBy: overBy, goal: _goalsForSelectedDay.calories);
      if (plan != null) {
        _snack('Done. Your next ${plan.days} '
            'day${plan.days == 1 ? '' : 's'} start $calSym${plan.perDay} lower. '
            'Stop any time.');
      }
    } catch (_) {
      _snack("Couldn't set that up. Please try again.");
    } finally {
      if (mounted) setState(() => _evenOutBusy = false);
    }
  }

  Future<void> _stopEvenOut() async {
    if (_evenOutBusy) return;
    setState(() => _evenOutBusy = true);
    try {
      final back = await EvenOut.stop(_activeUserId);
      if (back > 0 && mounted) await _refreshAfterChange();
      _snack(back > 0
          ? "Stopped. Today's $calSym$back is back on your card."
          : 'Stopped evening out.');
    } catch (_) {
      _snack("Couldn't stop it. Please try again.");
    } finally {
      if (mounted) setState(() => _evenOutBusy = false);
    }
  }

  /// Under the "you're over" note: the button, or the plan just set.
  Widget _evenOutFooter(int overBy) {
    return StreamBuilder<EvenOutPlan?>(
      stream: _evenOut,
      builder: (context, snap) {
        final plan = snap.data;
        final now = BalanceService.now();
        final today = BalanceService.dateKey(now);
        if (plan != null && plan.setOn == today) {
          return Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: AppText.emerald600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Spreading it: $calSym${plan.perDay} less a day for '
                  '${plan.days} day${plan.days == 1 ? '' : 's'}, from '
                  'tomorrow.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.gray700),
                ),
              ),
              TextButton(
                onPressed: _evenOutBusy ? null : _stopEvenOut,
                child: const Text('Undo'),
              ),
            ],
          );
        }
        final goal = _goalsForSelectedDay.calories;
        if (EvenOut.perDayFor(overBy, goal, now) <= 0) {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _evenOutBusy ? null : () => _spreadOverWeek(overBy),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 40),
            ),
            icon: const Icon(Icons.calendar_view_week_outlined, size: 18),
            label: const Text('Spread it over the week'),
          ),
        );
      },
    );
  }

  /// Under the spent line on days a plan covers: "Evening out: −80 kcal
  /// today · 3 more days · Stop".
  Widget _evenOutLine() {
    return StreamBuilder<EvenOutPlan?>(
      stream: _evenOut,
      builder: (context, snap) {
        final plan = snap.data;
        final today = BalanceService.dateKey(BalanceService.now());
        if (plan == null || !plan.activeOn(today)) {
          return const SizedBox.shrink();
        }
        final more = plan.daysAfter(today);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.autorenew, size: 15, color: AppColors.muted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Evening out: −$calSym${plan.perDay} today'
                  '${more > 0 ? ' · $more more day${more == 1 ? '' : 's'}' : ' · last day'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
              ),
              TextButton(
                onPressed: _evenOutBusy ? null : _stopEvenOut,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Stop'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Today (not closed) or yesterday (until midnight) can be made a rest
  /// day, or have one ended.
  bool get _canChangeRestDay =>
      _isOwnCard &&
      ((_isSelectedDateToday && !_isDayFinished) || _isSelectedDateYesterday);

  /// After a rest day starts or ends: streaks and, for yesterday, the
  /// leaderboard (its streak and "on budget" change with it).
  void _afterRestDayChange({required bool yesterday}) {
    MyStreak.load(_activeUserId, force: true);
    if (yesterday) {
      LeaderboardService.refreshMine(_activeUserId).catchError((_) {});
    }
  }

  /// "🏖️ Rest day" (like freezing a bank card): explains it, then marks
  /// the day as a rest day: today, or yesterday if you forgot. Four a
  /// calendar month; once they're used up the sheet says so instead.
  Future<void> _startRestDay() async {
    if (_restBusy || !_canChangeRestDay || _isRestDay) return;
    final day = _selectedLogDate;
    final yesterday = _isSelectedDateYesterday;
    setState(() => _restBusy = true);
    int? left;
    try {
      left = await RestDays.leftThisMonth(_activeUserId, day: day);
    } catch (_) {
      left = null;
    }
    if (!mounted) return;
    if (left == null) {
      setState(() => _restBusy = false);
      _snack("Couldn't check your rest days. Please try again.");
      return;
    }
    setState(() => _restBusy = false);
    final yes = await _showRestDaySheet(left, yesterday: yesterday);
    if (yes != true || !mounted) return;

    setState(() => _restBusy = true);
    try {
      await RestDays.start(_activeUserId, day: day);
      if (!mounted) return;
      // Freeze straight away; the reload below confirms it.
      if (_isSameDay(_selectedLogDate, day)) {
        setState(() {
          _selectedDailyLog = <String, dynamic>{
            ...?_selectedDailyLog,
            'rest_day': true,
          };
        });
        await _fetchDailyLogForDate(_selectedLogDate);
      }
      _afterRestDayChange(yesterday: yesterday);
      _snack(yesterday
          ? "Yesterday's now a rest day. Your streak is paused, not broken."
          : 'Rest day on. Your streak is paused, not broken.');
    } on RestDayLimitReached {
      _snack("You've used all ${RestDays.maxPerMonth} rest days this "
          'month. They come back on the 1st.');
    } on RestDayTooLate {
      _snack("It's too late to change that day now.");
    } catch (_) {
      _snack("Couldn't start your rest day. Please try again.");
    } finally {
      if (mounted) setState(() => _restBusy = false);
    }
  }

  /// "Unfreeze": the day is a normal day again (today, or yesterday until
  /// midnight).
  Future<void> _endRestDay() async {
    final restYesterday = _isOwnCard && _isSelectedDateYesterday;
    if (_restBusy || !_isRestDay) return;
    if (!restYesterday && !(_isOwnCard && _isSelectedDateToday)) return;
    final day = _selectedLogDate;
    setState(() => _restBusy = true);
    try {
      await RestDays.end(_activeUserId, day: day);
      if (!mounted) return;
      if (_isSameDay(_selectedLogDate, day)) {
        setState(() {
          _selectedDailyLog = <String, dynamic>{
            ...?_selectedDailyLog,
            'rest_day': false,
          };
        });
        await _fetchDailyLogForDate(_selectedLogDate);
      }
      _afterRestDayChange(yesterday: restYesterday);
      _snack(restYesterday
          ? 'Yesterday is a normal day again.'
          : 'Rest day ended. Add food as normal.');
    } on RestDayTooLate {
      _snack("It's too late to change that day now.");
    } catch (_) {
      _snack("Couldn't end your rest day. Please try again.");
    } finally {
      if (mounted) setState(() => _restBusy = false);
    }
  }

  /// Explains a rest day before starting one ([left] this month), for
  /// today or [yesterday]. Returns true to go ahead.
  Future<bool?> _showRestDaySheet(int left, {bool yesterday = false}) {
    final usedUp = left <= 0;
    return showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                usedUp
                    ? '🏖️ No rest days left this month'
                    : yesterday
                        ? '🏖️ Make yesterday a rest day?'
                        : '🏖️ Take a rest day?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                usedUp
                    ? "You've taken all ${RestDays.maxPerMonth} of this "
                        "month's rest days. They come back on the 1st. Until "
                        'then, track as normal.'
                    : 'Rest days are for holidays, celebrations or a planned '
                        "refeed. ${yesterday ? "Yesterday won't count" : "You won't track today"}"
                        ', and your streak is paused, not broken. '
                        'You can take ${RestDays.maxPerMonth} a month, '
                        'together or spread out.',
                style: TextStyle(
                    fontSize: 15, color: AppColors.gray700, height: 1.4),
              ),
              if (!usedUp) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.sky50,
                    borderRadius: BorderRadius.circular(AppDecor.radius),
                    border: Border.all(color: AppColors.sky100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$left of ${RestDays.maxPerMonth} left this month',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.sky700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        yesterday
                            ? 'Food you logged yesterday stays in your diary. '
                                'Changed your mind? Tap End rest day before '
                                'midnight.'
                            : "Food you've already logged today stays in your "
                                'diary. Changed your mind? Tap End rest day '
                                'any time today.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.gray700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (usedUp)
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52)),
                  child: const Text('OK'),
                )
              else ...[
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52)),
                  child: Text(
                    yesterday ? 'Make it a rest day' : 'Start rest day',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  style: TextButton.styleFrom(
                      minimumSize: const Size(0, 48)),
                  child: const Text('Not now'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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

      setState(() {
        _foodLoadFailed = false;
        _foodDocs = mealDocs;
        _dayTotals = BalanceService.totalOf(dayDocs.map((d) => d.data()));
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

  /// A friend's food (or a whole meal of theirs): straight into Add food
  /// on your own card, for today, where the amounts, calories and meal can
  /// be changed before adding. Starts on the same meal as theirs.
  Future<void> _copyFromFriend(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      String meal) async {
    if (docs.isEmpty || FirebaseAuth.instance.currentUser == null) return;
    final from = widget.bannerTitle;
    final items = [
      for (final d in docs) FoodLog.copyItem(d.data(), from: from),
    ];
    setState(() => _showEmojiPicker.clear());
    Provider.of<CategoryService>(context, listen: false)
        .setSelectedCategory(meal);
    FoodLog.logDay = null; // always your today
    final saved = await Navigator.of(context, rootNavigator: true).push<Object?>(
      MaterialPageRoute(builder: (_) => AddFoodPage(initialItems: items)),
    );
    if (!mounted || saved is! LoggedFoods) return;
    final n = saved.ids.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Added ${n == 1 ? 'it' : '$n foods'} to your '
          '${FoodLog.displayMeal(saved.meal)}'),
    ));
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
      canDelete: _canRemoveOnSelectedDay,
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
            'Spent $calSym${formatCardKcal(logged.calories)} on ${logged.meal}'),
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
    unawaited(_maybeSuggestDirectDebit(logged));
  }

  /// Had the same food at the same meal five days running? Offer to make
  /// it a direct debit (once per food), instead of hoping people find the
  /// Direct debits page.
  Future<void> _maybeSuggestDirectDebit(LoggedFoods logged) async {
    if (!_isOwnCard || logged.count == 0 || logged.count > 3) return;
    try {
      String key(Object? v) => '${v ?? ''}'.trim().toLowerCase();
      // After the Undo message has had its moment.
      await Future<void>.delayed(const Duration(seconds: 7));
      if (!mounted) return;
      final docs = [
        for (final d in _foodDocs)
          if (logged.ids.contains(d.id)) d
      ];
      if (docs.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final asked = prefs.getStringList('dd_suggested') ?? const <String>[];
      final today = BalanceService.startOfDay(BalanceService.now());
      final past = await Future.wait([
        for (var i = 1; i <= 4; i++)
          BalanceService.entriesOn(
              _activeUserId, BalanceService.addDays(today, -i)),
      ]);
      final debits = await DirectDebitService.forUser(_activeUserId).first;
      for (final doc in docs) {
        final data = doc.data();
        final name = key(data['food_description']);
        final meal = FoodLog.mealOf(data['foodCategory']);
        final id = '$meal|$name';
        if (name.isEmpty || asked.contains(id)) continue;
        if (debits.any((d) => key(d.name) == name && d.meal == meal)) continue;
        final everyDay = past.every((day) => day.any((e) =>
            key(e.data()['food_description']) == name &&
            FoodLog.mealOf(e.data()['foodCategory']) == meal));
        if (!everyDay) continue;
        await prefs.setStringList('dd_suggested', [...asked, id]);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 8),
          content: Text("You've had ${data['food_description']} 5 days "
              'running. Log it automatically each day?'),
          action: SnackBarAction(
            label: 'Set up',
            onPressed: () => _offerDirectDebit(data),
          ),
        ));
        return; // one at a time
      }
    } catch (_) {
      // Only a suggestion.
    }
  }
  /// Removes a logged food (and refunds the card). [swiped] removals were
  /// checked when the row was swiped and confirmed by the Undo snackbar
  /// closing, so they skip the editable-day check and the extra snackbar.
  Future<void> _deleteFoodItem(String docId, {bool swiped = false}) async {
    if (_isDeletingItem) return;
    if (!swiped && !_canRemoveOnSelectedDay) return;

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

  /// A food was swiped away. It's removed straight away (so a refresh a
  /// moment later can't bring it back) and Undo puts the very same entry
  /// back, charging the card again.
  void _onFoodSwiped(String docId, String name) {
    if (!_canRemoveOnSelectedDay) return;
    setState(() => _pendingRemoval.add(docId));
    final messenger = ScaffoldMessenger.of(context);
    // One removal at a time, in the order they were swiped.
    final removal = _removalChain.then((_) async {
      try {
        return await FoodLog.removeForUndo(docId);
      } catch (_) {
        if (mounted) {
          setState(() => _pendingRemoval.remove(docId));
          messenger.showSnackBar(const SnackBar(
              content: Text("Couldn't remove that food. Please try again.")));
        }
        return null;
      }
    });
    _removalChain = removal.then((_) {});

    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text('Removed $name'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: 'Undo', onPressed: () {}),
      ),
    );
    // Snackbars with an action can stay up in newer Flutter; close it.
    var closed = false;
    Timer(const Duration(seconds: 5), () {
      if (!closed) messenger.hideCurrentSnackBar();
    });
    controller.closed.then((reason) async {
      closed = true;
      final removed = await removal;
      if (reason == SnackBarClosedReason.action && removed != null) {
        try {
          await FoodLog.restore(docId, removed);
        } catch (_) {
          messenger.showSnackBar(SnackBar(
              content: Text("Couldn't put $name back. Add it again from "
                  'your recents.')));
        }
      }
      if (!mounted) return;
      // Show the list as it now is before un-hiding the row.
      await (_refreshing ?? _refreshAfterChange());
      if (mounted) setState(() => _pendingRemoval.remove(docId));
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
    if (_copyingYesterday || !_canEditToday || entries.isEmpty) return;
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
                '($calSym${formatCardKcal(logged.calories)})');
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
    // Adding something forgotten yesterday: it goes on yesterday.
    FoodLog.logDay = _isSelectedDateToday ? null : _selectedLogDate;
    // On phones, open above the bottom bar so the Coach button doesn't
    // cover the page's buttons.
    final Object? saved;
    try {
      saved = await Navigator.of(context, rootNavigator: _isPhone)
          .push<Object?>(
        MaterialPageRoute(builder: (_) => const AddFoodPage()),
      );
    } finally {
      FoodLog.logDay = null;
    }
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
    FoodLog.logDay = _isSelectedDateToday ? null : _selectedLogDate;
    try {
      await Navigator.of(context, rootNavigator: _isPhone).push<Object?>(
        MaterialPageRoute(builder: (_) => const _RecipePickerPage()),
      );
    } finally {
      FoodLog.logDay = null;
    }
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
    if (_loggingUsual || !_canEditToday) return;
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
          _slideDx,
        ]),
        builder: (context, child) {
          final resetValue = _cardDragResetController?.value ?? 0.0;
          final effectiveDx = (_isResettingCard
                  ? _dragEndDx * (1 - Curves.easeOut.transform(resetValue))
                  : _cardDragDx) +
              _slideDx.value;
          // While changing day the card is clipped to its own space, so
          // on a wide screen it doesn't slide across the side panels.
          return ClipRect(
            clipBehavior: _sliding ? Clip.hardEdge : Clip.none,
            child: Transform.translate(
              offset: Offset(effectiveDx, 0),
              child: Transform.rotate(
                angle: _jiggleAnimation?.value ?? 0.0,
                child: child,
              ),
            ),
          );
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) {
            if (_sliding) return;
            _cardDragDx = 0;
            _cardDragResetController?.stop();
            _isResettingCard = false;
          },
          onHorizontalDragUpdate: (details) {
            if (_sliding) return;
            setState(() {
              _cardDragDx += details.delta.dx;
            });
          },
          // Swipe like turning a page: right for the day before, left
          // for the day after (as the arrows above). A quick flick counts.
          onHorizontalDragEnd: (details) {
            if (_sliding) return;
            final v = details.primaryVelocity ?? 0;
            final far = _cardDragDx.abs() > 60 || v.abs() > 600;
            final dir = (_cardDragDx.abs() > 8 ? _cardDragDx : v).sign;
            if (far && dir != 0) {
              _slideToDay(-dir.toInt());
            } else {
              _resetCardPosition();
            }
          },
          child: Semantics(
            // Close and reopen right from the card for screen readers.
            customSemanticsActions: !_isOwnCard || !_isSelectedDateToday
                ? null
                : {
                    if (_isRestDay)
                      CustomSemanticsAction(label: 'End rest day'):
                          _endRestDay
                    else if (_isDayFinished)
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
                        restDay: _isRestDay,
                        closed: _isDayFinished,
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
                        restDay: _isRestDay,
                        closed: _isDayFinished,
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
    // Small "+" and recipe buttons; the big Add food button is under the
    // card, so these stay light and never truncate on a 320 px phone.
    final canAdd = _canEditSelectedDay;
    // A friend's card: copy the whole meal to your own day.
    final canCopy = widget.readOnly && docs.isNotEmpty;
    final compact = canAdd || canCopy;
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 420;
    // On the smallest phones the meal icon makes way for the totals.
    final showIcon = !canAdd || width >= 360;

    return Material(
      color: AppColors.gray50,
      child: Padding(
          padding: EdgeInsets.fromLTRB(16, compact ? 2 : 12, compact ? 4 : 12,
              compact ? 2 : 12),
          child: Row(
            children: [
              if (showIcon) ...[
                Icon(_mealIcon(meal), size: 20, color: AppText.primary),
                const SizedBox(width: 8),
              ],
              // The meal, with its protein · carbs · fat underneath (always
              // shown, so you never have to know to tap for them).
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meal,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  if (docs.isNotEmpty)
                    MacroText(
                      protein: totals.protein,
                      carbs: totals.carbs,
                      fat: totals.fat,
                    ),
                ],
              ),
              const SizedBox(width: 8),
              Flexible(
                fit: FlexFit.tight,
                // Plain numbers, like a banking app's list: the card's
                // ⊂ already says what they are.
                child: Text(
                  docs.isEmpty ? '' : formatCardKcal(kcal),
                  semanticsLabel: docs.isEmpty ? '' : '$kcal calories',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: AppColors.gray700,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
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
              if (canCopy) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Copy $meal to my day',
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  padding: EdgeInsets.zero,
                  color: AppText.primary,
                  onPressed: () => _copyFromFriend(docs, meal),
                  icon: const Icon(Icons.copy_all_outlined, size: 22),
                ),
              ],
            ],
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

  /// One small line directly under the card, like a bank app's "£X spent
  /// today" under the balance: "420 kcal spent today · 1,580 left". The
  /// card itself has no caption, so this is also what says what its big
  /// number is. Past days: "1,850 kcal spent · 150 left".
  Widget? _buildSpentLine() {
    if (_foodLoadFailed) return null;
    final today = _isSelectedDateToday;
    final spent = _dayTotals.calories.round();
    final int? left =
        today ? _liveBalance : _selectedDayBalance.calories.round();
    final goal = _goalsForSelectedDay.calories;
    final Color leftColor = left == null || left < 0
        ? AppText.red600
        : (goal > 0 && left <= goal * 0.1)
            ? AppText.amber700
            : AppText.emerald700;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$calSym${formatCardKcal(spent)} spent'
                '${today ? ' today' : ''}',
          ),
          if (left != null) ...[
            const TextSpan(text: ' · '),
            TextSpan(
              text: left < 0
                  ? '$calSym${formatCardKcal(-left)} over'
                  : '$calSym${formatCardKcal(left)} left',
              style: TextStyle(color: leftColor, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, color: AppColors.muted),
    );
  }

  /// Empty meals stay small so the whole day fits on screen. On your own
  /// today, just the header (its + is the way in, and "Again" under Add
  /// food has yesterday's meal).
  /// "Same as yesterday · 612 kcal" inside an empty meal.
  Widget _yesterdayLink(String meal, List<Map<String, dynamic>> entries) {
    final kcal = BalanceService.totalOf(entries).calories.round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed:
              _copyingYesterday ? null : () => _copyYesterday(meal, entries),
          style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: const Icon(Icons.history, size: 18),
          label: Text('Same as yesterday · $calSym${formatCardKcal(kcal)}'),
        ),
      ),
    );
  }

  Widget _buildEmptyMeal(String meal) {
    if (_isOwnCard && _isSelectedDateToday) return const SizedBox(height: 4);
    final text = !_isSelectedDateToday
        ? 'Nothing logged that day.'
        : 'Nothing logged yet.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Text(
        text,
        style: TextStyle(color: AppColors.muted, fontSize: 13),
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

  Widget _buildFoodRow(
      QueryDocumentSnapshot<Map<String, dynamic>> doc, bool canEdit) {
    final data = doc.data();
    final name = (data['food_description'] ?? 'Food').toString();
    final rawPortion = (data['food_portion'] ?? '').toString();
    // "200ml Alpro soya milk" over "200 ml" says it twice: the amount
    // underneath only shows when the name doesn't already say it.
    final nameSize = PortionAmount.amountsIn(name) == 1
        ? PortionAmount.sizeOf(name)
        : null;
    final portion = nameSize != null &&
            nameSize == PortionAmount.sizeOf(rawPortion)
        ? ''
        : rawPortion;
    final reactions = _foodReactions[doc.id];
    final estimate = data['food_estimate'] == true;
    // Only you see that there's a note (tap the food to read it).
    final hasNote = _isOwnCard && FoodLog.noteOf(data).isNotEmpty;

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
                        // Its protein · carbs · fat, always visible.
                        MacroText(
                          protein:
                              BalanceService.number(data['food_protein']) ?? 0,
                          carbs: BalanceService.number(data['food_carbs']) ?? 0,
                          fat: BalanceService.number(data['food_fat']) ?? 0,
                        ),
                      ],
                    ),
                  ),
                  if (estimate) ...[
                    const SizedBox(width: 6),
                    const EstimateMark(),
                  ],
                  if (hasNote) ...[
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Has a note',
                      child: Semantics(
                        label: 'Has a note',
                        child: const ExcludeSemantics(
                          child: Text('📝', style: TextStyle(fontSize: 14)),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  // What it cost, as a plain number like a bank's list
                  // (5.49, not £5.49).
                  Text(
                    '${_roundMacro(data['food_calories'])}',
                    semanticsLabel:
                        '${_roundMacro(data['food_calories'])} calories',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            // Friends viewing your card: pick a reaction.
            // A friend's food tapped: had the same? Add it to your day.
            // (Cheers are for their whole day, under the card, not for
            // single foods.)
            if (widget.readOnly && (_showEmojiPicker[doc.id] ?? false))
              Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                color: AppColors.gray100,
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Had this too?',
                          style: TextStyle(
                              color: AppColors.gray700, fontSize: 14)),
                    ),
                    TextButton.icon(
                      onPressed: () => _copyFromFriend(
                          [doc], FoodLog.mealOf(data['foodCategory'])),
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('Add to mine'),
                    ),
                  ],
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

    // Swipe to remove works on any of your days.
    if (!_canRemoveOnSelectedDay) return row;
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
              label: Text(
                _isSelectedDateToday ? 'Add food' : 'Add to yesterday',
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

  /// "Again for {meal}": one-tap chips for what you usually have at the
  /// meal you're adding to. (Yesterday's whole meal is in each empty meal.)
  Widget? _buildUsuals() {
    // Already had it for this meal today? Don't suggest it again.
    String key(Object? name) => '${name ?? ''}'.trim().toLowerCase();
    final inMeal = [
      for (final d in _foodDocs)
        if (!_pendingRemoval.contains(d.id) &&
            FoodLog.mealOf(d.data()['foodCategory']) == _addMeal)
          d
    ];
    final had = {for (final d in inMeal) key(d.data()['food_description'])};
    final usuals = _usualsMeal != _addMeal
        ? const <UsualFood>[]
        : [
            for (final u in _usuals)
              if (!had.contains(key(u.name))) u
          ];
    // "Same as yesterday" lives in each empty meal below, not here.
    if (usuals.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Again for ${_addMeal.toLowerCase()}',
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
            itemCount: usuals.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final usual = usuals[index];
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
                      '($calSym${usual.calories.round()}) to $_addMeal',
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
    // "About 910 kcal for dinner" when 910 is all that's left just says
    // "910 left" again: only shown when it splits things up.
    if (plan.meals.length == 1 &&
        plan.snackReserve == 0 &&
        (plan.perMeal - left).abs() <= 10) {
      return null;
    }
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

  Future<void> _confirmClearToday() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Clear today's food?"),
        content: const Text(
            "This removes everything you've logged today and puts your card "
            'back to your full daily goal. Saved recipes are kept. '
            "You can't undo this."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red600,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear today'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final count = await BalanceService.clearToday(_activeUserId);
      FoodLog.notifyChanged();
      if (!mounted) return;
      await _refreshAfterChange();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(count == 0
              ? 'Nothing logged today'
              : 'Cleared $count food item${count == 1 ? '' : 's'} from today')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Couldn't clear today's food. Please try again.")));
      }
    }
  }

  /// The bottom of today: "Close today" (once there's food) and, beside
  /// it, the quieter "🏖️ Rest day" (freeze the card for today).
  Widget _buildDayActions(bool hasFood) {
    final rest = Tooltip(
      message: "A day off: no tracking, and your streak's paused",
      child: OutlinedButton(
        onPressed: _restBusy ? null : _startRestDay,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(
          hasFood ? '🏖️ Rest day' : '🏖️ Take a rest day',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    if (!hasFood) return rest;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: OutlinedButton.icon(
            key: _tourClose,
            onPressed: _isUpdatingDailyLog ? null : _closeDay,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.task_alt_rounded),
            label: const Text(
              'Close today',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(flex: 2, child: rest),
      ],
    );
  }

  Widget _buildFoodPanel(String meal) {
    final visible = _visibleIn(meal);
    final canEdit = _canEditSelectedDay;
    // An empty meal on your own today is just its header, or, if you had
    // it yesterday, one "Same as yesterday" link: the same for every meal.
    final emptyToday =
        visible.isEmpty && _isOwnCard && _isSelectedDateToday;
    final copy = emptyToday && _canEditToday
        ? _yesterdayFor(meal)
        : const <Map<String, dynamic>>[];

    return Container(
      decoration: AppDecor.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMealHeader(meal, visible),
          if (!emptyToday || copy.isNotEmpty)
            Divider(height: 1, thickness: 1, color: AppColors.border),
          if (emptyToday)
            if (copy.isNotEmpty) _yesterdayLink(meal, copy)
            else
              const SizedBox.shrink()
          else if (visible.isEmpty)
            _buildEmptyMeal(meal)
          else
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0)
                Divider(height: 1, thickness: 1, color: AppColors.border),
              _buildFoodRow(visible[i], canEdit),
            ],
          if (!emptyToday) const SizedBox(height: 8),
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

    final spentLine = _buildSpentLine();

    final ownHome = _isOwnCard && !widget.showBanner;
    final overBy = _liveBalance == null ? 0 : -_liveBalance!;
    final canAdd = _canEditSelectedDay;
    final pacing = _canEditToday ? _buildPacing() : null;
    final usuals = _canEditToday ? _buildUsuals() : null;
    final visibleFood = _foodDocs.any((d) => !_pendingRemoval.contains(d.id));

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Column(
        children: [
          if (widget.showBanner) _buildBanner(context),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshAfterChange,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: topGap, bottom: ownHome ? 72 : 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCard(),
                    if (spentLine != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        // Tap what you've spent for the statement, like
                        // tapping a bank balance.
                        child: _isOwnCard
                            ? InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => const StatementPage()),
                                ),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(child: spentLine),
                                      Icon(Icons.chevron_right,
                                          size: 18, color: AppColors.muted),
                                    ],
                                  ),
                                ),
                              )
                            : Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: spentLine,
                              ),
                      ),
                    if (_isOwnCard && _isSelectedDateToday) _evenOutLine(),
                    // Macros are on the card (what's left; tap it for eaten
                    // against goals), so they aren't repeated here. Wide
                    // screens have the Today panel too.
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
                    // A friend's card today: cheer their day.
                    if (widget.readOnly &&
                        widget.userIdOverride != null &&
                        _isSelectedDateToday)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _DayCheer(
                          friendId: widget.userIdOverride!,
                          name: widget.bannerTitle ?? 'your friend',
                        ),
                      ),
                    if (usuals != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: usuals,
                      ),
                    // Rest day: food is paused until it's unfrozen (today,
                    // or yesterday until midnight).
                    if (_isOwnCard &&
                        (_isSelectedDateToday || _isSelectedDateYesterday) &&
                        _isRestDay)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _RestDayStrip(
                          yesterday: _isSelectedDateYesterday,
                          onUnfreeze: _restBusy ? null : _endRestDay,
                        ),
                      )
                    // Closed: one quiet row instead of any add buttons.
                    else if (_isOwnCard &&
                        _isSelectedDateToday &&
                        _isDayFinished)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _ClosedDayStrip(onReopen: _reopenDay),
                      ),
                    // Over budget: a kind note with a plan to even it out.
                    if (_isOwnCard &&
                        _isSelectedDateToday &&
                        !_isDayFinished &&
                        !_isRestDay &&
                        overBy > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: CoachNudge(
                          overBy: overBy,
                          goal: _goalsForSelectedDay.calories,
                          today: BalanceService.now(),
                          footer: _evenOutFooter(overBy),
                          onAsk: (question) {
                            if (!Premium.isPremium) {
                              showPremiumSheet(
                                context,
                                title: 'Coach\'s swap ideas are Premium',
                                message: 'Coach suggests easy swaps for the '
                                    'next few days, so one big day never '
                                    'knocks you off track. "Spread it over '
                                    'the week" is free for everyone.',
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
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: DayStepper(
                              selected: _selectedLogDate,
                              onChanged: _stepToDay,
                            ),
                          ),
                          if (_isOwnCard) ...[
                            const SizedBox(width: 8),
                            StreakPill(userId: _activeUserId),
                          ],
                          // Tutorials sit here rather than floating over the
                          // food list; gone once a couple have been watched.
                          if (ownHome)
                            const TutorialButton(
                                padding: EdgeInsets.only(left: 8)),
                        ],
                      ),
                    ),
                    if (_isOwnCard && _isSelectedDateToday)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: HomeInbox(
                          userId: _activeUserId,
                          // Nothing to finish on a rest day.
                          isDayFinished: _isDayFinished || _isRestDay,
                          hasFoodToday: _dayTotals.calories > 0,
                          onFinishDay: _closeDay,
                          onBalanceChanged: _refreshAfterChange,
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (_isOwnCard &&
                        !_isSelectedDateToday &&
                        !(_isSelectedDateYesterday && _isRestDay))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: _PastDayNotice(
                          yesterday: _isSelectedDateYesterday,
                          onToday: () => _changeDay(BalanceService.now()),
                          onRestDay: _isSelectedDateYesterday && !_restBusy
                              ? _startRestDay
                              : null,
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
                    // Or freeze it: a rest day.
                    if (_canEditToday)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        child: _buildDayActions(visibleFood),
                      ),
                    // Start today over (was in Goals and profile).
                    if (_canEditToday && visibleFood)
                      Center(
                        child: TextButton.icon(
                          onPressed: _confirmClearToday,
                          style: TextButton.styleFrom(
                            foregroundColor: AppText.red600,
                          ),
                          icon: const Icon(Icons.delete_sweep_outlined,
                              size: 18),
                          label: const Text("Clear today's food…"),
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

/// Under the card on a rest day (in place of Add food): the card is
/// frozen, with one clear way to unfreeze it.
class _RestDayStrip extends StatelessWidget {
  final VoidCallback? onUnfreeze;

  /// Yesterday's rest day (can be ended until midnight).
  final bool yesterday;

  const _RestDayStrip({required this.onUnfreeze, this.yesterday = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      decoration: BoxDecoration(
        color: AppColors.sky50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.sky100),
      ),
      child: Row(
        children: [
          const ExcludeSemantics(
            child: Text('🏖️', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              yesterday
                  ? 'Yesterday was a rest day · End it to change it'
                  : 'Rest day · End it to add food',
              style: TextStyle(
                color: AppColors.gray700,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          TextButton(
            onPressed: onUnfreeze,
            style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('End rest day'),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of the add buttons on a past day.
class _PastDayNotice extends StatelessWidget {
  final VoidCallback onToday;

  /// Yesterday can still be fixed (until midnight).
  final bool yesterday;

  /// Make yesterday a rest day (forgot to take it). Null hides it.
  final VoidCallback? onRestDay;

  const _PastDayNotice({
    required this.onToday,
    this.yesterday = false,
    this.onRestDay,
  });

  @override
  Widget build(BuildContext context) {
    final notice = Row(
        children: [
          Icon(yesterday ? Icons.edit_calendar_outlined : Icons.lock_clock,
              color: AppText.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              yesterday
                  ? 'Forgot something? You can add to or fix yesterday '
                      "until midnight. Today's card isn't changed."
                  : 'You can remove food from past days (swipe it away). '
                      'Food you add goes on today.',
              style: TextStyle(color: AppColors.ink, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: onToday,
            child: const Text('Go to today'),
          ),
        ],
      );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.indigo50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: !yesterday
          ? notice
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                notice,
                // Forgot to take a rest day (a holiday, a refeed)?
                TextButton(
                  onPressed: onRestDay,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                  ),
                  child: const Text('🏖️ Make yesterday a rest day'),
                ),
              ],
            ),
    );
  }
}

/// "Cheer Sam's day": one tap sends a friendly line into your chat with
/// them, so they actually see it (it arrives like any message). For their
/// whole day, never a single food: nobody's food is up for judging.
class _DayCheer extends StatefulWidget {
  final String friendId;
  final String name;

  const _DayCheer({required this.friendId, required this.name});

  static const cheers = [
    ('🔥', "🔥 Your day's looking great!"),
    ('💪', '💪 Strong day, keep going!'),
    ('👏', '👏 Keep it up!'),
    ('❤️', '❤️ Proud of you today!'),
  ];

  @override
  State<_DayCheer> createState() => _DayCheerState();
}

class _DayCheerState extends State<_DayCheer> {
  String? _sent;
  bool _sending = false;

  Future<void> _send(String emoji, String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _sending || _sent != null) return;
    setState(() => _sending = true);
    try {
      await ChatService.sendToFriend(
        uid: user.uid,
        myName: await FriendsService.nameFor(user.uid, email: user.email),
        friendId: widget.friendId,
        friendName: widget.name,
        text: text,
      );
      if (mounted) setState(() => _sent = emoji);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cheer not sent. Check your connection.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sent;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: AppDecor.card,
      child: sent != null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Sent $sent to ${widget.name}, in your chat',
                style: TextStyle(
                    color: AppText.emerald600, fontWeight: FontWeight.w700),
              ),
            )
          : Row(
              children: [
                Expanded(
                  child: Text(
                    "Cheer ${widget.name}'s day",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.ink, fontWeight: FontWeight.w700),
                  ),
                ),
                for (final c in _DayCheer.cheers)
                  Tooltip(
                    message: c.$2,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: _sending ? null : () => _send(c.$1, c.$2),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(c.$1, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
