import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/calorie_game.dart';
import 'package:namer_app/services/calorie_sense.dart';
import 'package:namer_app/services/statement_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// Levels and XP
// ============================================================================

/// Where someone is on the Games ladder.
class GameLevel {
  /// 1 and up.
  final int level;

  /// XP earned since reaching [level], and XP needed for the next one.
  final int into;
  final int needed;

  /// All XP ever earned.
  final int total;

  const GameLevel(this.level, this.into, this.needed, this.total);

  /// 0 to 1, towards the next level.
  double get progress => needed <= 0 ? 0 : (into / needed).clamp(0.0, 1.0);

  int get toNext => needed - into;

  String get title => Levels.titleFor(level).title;
  String get emoji => Levels.titleFor(level).emoji;
}

class LevelTitle {
  final int from;
  final String emoji;
  final String title;
  const LevelTitle(this.from, this.emoji, this.title);
}

class Levels {
  Levels._();

  /// XP needed to go from [level] to the next: 100, 150, 200, …
  static int cost(int level) => 100 + 50 * (max(1, level) - 1);

  static GameLevel of(int xp) {
    final total = max(0, xp);
    var level = 1;
    var left = total;
    while (left >= cost(level)) {
      left -= cost(level);
      level++;
    }
    return GameLevel(level, left, cost(level), total);
  }

  static const titles = [
    LevelTitle(1, '🥄', 'Rookie'),
    LevelTitle(3, '🏷️', 'Label Reader'),
    LevelTitle(6, '🍽️', 'Portion Pro'),
    LevelTitle(10, '🔍', 'Calorie Detective'),
    LevelTitle(15, '🧠', 'Macro Master'),
    LevelTitle(20, '🔮', 'Calorie Oracle'),
  ];

  static LevelTitle titleFor(int level) {
    var t = titles.first;
    for (final candidate in titles) {
      if (level >= candidate.from) t = candidate;
    }
    return t;
  }
}

/// How XP is earned. XP rewards being close, never eating more.
class Xp {
  Xp._();

  /// 0-10 for one guess, from its 0-100 score.
  static int forScore(int score) => (score.clamp(0, 100) / 10).round();

  /// For finishing all of the Daily Calorie Quiz.
  static const dailyBonus = 10;

  /// A friend game: on top of the XP for your guesses.
  static const winBonus = 25;
  static const drawBonus = 10;

  /// Guess the Meal rounds a day that earn XP (more is just practice).
  static const mealRoundsPerDay = 3;

  /// Higher or Lower: XP for each right answer, and rounds a day that
  /// earn it.
  static const perHigherLower = 2;
  static const higherLowerRoundsPerDay = 3;

  /// Calorie Sense guesses (guessing before a lookup when you log food)
  /// a day that earn XP.
  static const senseGuessesPerDay = 10;

  /// XP for a finished friend game.
  static int forFriendGame(CalorieGame g, String uid) {
    var xp = 0;
    for (final s in g.roundScoresOf(uid)) {
      xp += forScore(s);
    }
    if (g.winner == uid) {
      xp += winBonus;
    } else if (g.isDraw && !g.expired) {
      xp += drawBonus;
    }
    return xp;
  }
}

/// XP before and after something was earned.
class XpResult {
  final int before;
  final int after;
  const XpResult(this.before, this.after);

  int get gained => after - before;
  GameLevel get level => Levels.of(after);
  bool get levelledUp => Levels.of(after).level > Levels.of(before).level;

  static const none = XpResult(0, 0);
}

// ============================================================================
// Guess the Meal
// ============================================================================

/// One thing in a meal, with its calories.
class MealItem {
  final String emoji;
  final String name;
  final int kcal;
  const MealItem(this.emoji, this.name, this.kcal);
}

enum MealKind { breakfast, lunch, dinner, snack, nightOut, day }

extension MealKindLabel on MealKind {
  String get label => switch (this) {
        MealKind.breakfast => 'Breakfast',
        MealKind.lunch => 'Lunch',
        MealKind.dinner => 'Dinner',
        MealKind.snack => 'Snacks',
        MealKind.nightOut => 'Night out',
        MealKind.day => 'Whole day',
      };
}

/// "How much did I eat?": a realistic meal, night out or whole day.
class GameMeal {
  final String id;
  final String emoji;
  final String title;
  final MealKind kind;
  final List<MealItem> items;

  /// Meals that only differ in one swap (lean vs 20% mince, slimline vs
  /// full-sugar tonic) share a pair, so a round never has both.
  final String? pair;

  const GameMeal(this.id, this.emoji, this.title, this.kind, this.items,
      {this.pair});

  int get total => items.fold(0, (a, b) => a + b.kcal);

  /// The items, biggest first (the reveal).
  List<MealItem> get biggestFirst =>
      [...items]..sort((a, b) => b.kcal.compareTo(a.kcal));
}

// Standard portions, from UK labels and UK / USDA reference values. The
// same item always has the same value everywhere in the game.
const _sausages2 = MealItem('🌭', '2 pork sausages, grilled', 236);
const _bacon2 = MealItem('🥓', '2 rashers back bacon, grilled', 130);
const _friedEgg = MealItem('🍳', '1 fried egg', 90);
const _beans = MealItem('🫘', 'Half a can of baked beans (207g)', 164);
const _toastButter =
    MealItem('🍞', '1 slice white toast, thinly buttered', 122);
const _oats40 = MealItem('🥣', 'Porridge oats (40g)', 150);
const _semi200 = MealItem('🥛', 'Semi-skimmed milk (200ml)', 100);
const _banana = MealItem('🍌', '1 banana', 105);
const _honey2 = MealItem('🍯', '2 teaspoons of honey', 42);
const _honey1 = MealItem('🍯', '1 teaspoon of honey', 21);
const _granola = MealItem('🥣', 'Granola (45g)', 200);
const _greekFull = MealItem('🥛', 'Full-fat Greek-style yogurt (150g)', 165);
const _blueberries = MealItem('🫐', 'Blueberries (80g)', 46);
const _sourdough = MealItem('🍞', 'Sourdough, 1 large slice (50g)', 120);
const _avocadoHalf = MealItem('🥑', 'Half an avocado', 114);
const _poached2 = MealItem('🥚', '2 poached eggs', 156);
const _latteWhole = MealItem('☕', 'Large latte, whole milk', 192);
const _latteSemi = MealItem('☕', 'Large latte, semi-skimmed', 150);
const _flatWhite = MealItem('☕', 'Flat white, whole milk', 96);
const _croissant = MealItem('🥐', 'Butter croissant', 231);
const _jam = MealItem('🍓', 'Jam (1 tablespoon)', 38);
const _butter10 = MealItem('🧈', 'Butter (10g)', 74);
const _cornflakes = MealItem('🥣', 'Cornflakes (45g)', 170);
const _semi150 = MealItem('🥛', 'Semi-skimmed milk (150ml)', 75);
const _oj = MealItem('🍊', 'Orange juice (200ml)', 90);
const _eggs2 = MealItem('🥚', '2 large eggs, scrambled', 156);
const _milkSplash = MealItem('🥛', 'Splash of semi-skimmed milk', 15);
const _wholemeal2 = MealItem('🍞', '2 slices wholemeal toast', 156);
const _white2 = MealItem('🍞', '2 slices white bread', 170);
const _cheddar30 = MealItem('🧀', 'Cheddar (30g)', 125);
const _cheddar40 = MealItem('🧀', 'Cheddar (40g)', 166);
const _ham = MealItem('🍖', '2 slices of ham', 33);
const _crisps = MealItem('🥔', 'Walkers Ready Salted (32.5g bag)', 171);
const _coke = MealItem('🥤', 'Coca-Cola (330ml can)', 139);
const _dietCoke = MealItem('🥤', 'Medium Diet Coke', 1);
const _jacket = MealItem('🥔', 'Jacket potato (200g)', 186);
const _tuna = MealItem('🐟', 'Tuna (60g, drained)', 66);
const _mayo = MealItem('🥄', 'Mayonnaise (1 tablespoon)', 108);
const _lightMayo = MealItem('🥄', 'Light mayonnaise (1 tablespoon)', 39);
const _chicken150 = MealItem('🍗', 'Grilled chicken breast (150g)', 248);
const _chicken100 = MealItem('🍗', 'Cooked chicken breast (100g)', 165);
const _croutons = MealItem('🍞', 'Croutons (20g)', 90);
const _parmesan = MealItem('🧀', 'Parmesan (10g)', 39);
const _caesar = MealItem('🥫', 'Caesar dressing (2 tablespoons)', 140);
const _romaine = MealItem('🥬', 'Romaine lettuce (80g)', 14);
const _wrap = MealItem('🌯', 'Large tortilla wrap', 190);
const _salad = MealItem('🍅', 'Lettuce and tomato', 20);
const _soup = MealItem('🍅', 'Cream of tomato soup (half a can)', 118);
const _pitta = MealItem('🫓', 'White pitta', 160);
const _hummus = MealItem('🫘', 'Hummus (2 tablespoons)', 90);
const _carrot = MealItem('🥕', 'Carrot sticks (1 carrot)', 25);
const _apple = MealItem('🍎', '1 apple', 95);
const _sausageRoll = MealItem('🥐', 'Greggs sausage roll', 327);
const _mars = MealItem('🍫', 'Mars bar', 228);
const _spaghetti = MealItem('🍝', 'Spaghetti (200g cooked)', 316);
const _mince5 = MealItem('🥩', 'Lean beef mince, 5% fat (125g)', 155);
const _mince20 = MealItem('🥩', 'Beef mince, 20% fat (125g)', 318);
const _sauce = MealItem('🍅', 'Tomato pasta sauce (125g)', 60);
const _oil = MealItem('🫒', 'Olive oil for cooking (1 tablespoon)', 119);
const _salmon = MealItem('🐟', 'Baked salmon fillet (120g)', 247);
const _rice = MealItem('🍚', 'White rice (150g cooked)', 195);
const _broccoli = MealItem('🥦', 'Broccoli (80g)', 27);
const _noodles = MealItem('🍜', 'Egg noodles (1 nest)', 220);
const _veg = MealItem('🥕', 'Stir-fry vegetables (150g)', 45);
const _soy = MealItem('🥢', 'Soy sauce (1 tablespoon)', 10);
const _bigMac = MealItem('🍔', "McDonald's Big Mac", 508);
const _fries = MealItem('🍟', "McDonald's medium fries", 337);
const _choccyDigestives3 = MealItem('🍪', '3 chocolate digestives', 249);
const _maltesers = MealItem('🍫', 'Maltesers (37g bag)', 187);
const _twix = MealItem('🍫', 'Twix (2 fingers)', 250);
const _wholeMilk150 = MealItem('🥛', 'Whole milk (150ml)', 96);
const _peanutButter = MealItem('🥜', 'Peanut butter (1 tablespoon)', 94);
const _oats30 = MealItem('🥣', 'Porridge oats (30g)', 112);
const _teas = MealItem('🫖', '2 cups of tea, milk and 1 sugar', 62);
const _digestives4 = MealItem('🍪', "4 McVitie's Digestives", 284);
const _almonds = MealItem('🌰', 'Almonds (30g)', 174);
const _lager3 = MealItem('🍺', '3 pints of lager (4%)', 546);
const _peanuts = MealItem('🥜', 'Salted peanuts (50g bag)', 305);
const _wine2 = MealItem('🍷', '2 large glasses of red wine (250ml)', 454);
const _gnt3 = MealItem('🍸', '3 single gin and tonics (full-sugar tonic)', 318);
const _gntSlim3 = MealItem('🍸', '3 single gin and slimline tonics', 171);
const _vodkaRb2 = MealItem('🥤', '2 vodka and Red Bulls (full can each)', 334);
const _prosecco3 = MealItem('🥂', '3 glasses of prosecco (125ml)', 258);
const _rumCoke3 = MealItem('🥃', '3 single rum and Cokes', 345);
const _guinness2 = MealItem('🍺', '2 pints of Guinness', 420);

const _fryUp = GameMeal('fry_up', '🍳', 'Saturday fry-up', MealKind.breakfast,
    [_sausages2, _bacon2, _friedEgg, _beans, _toastButter]);
const _porridge = GameMeal('porridge', '🥣', 'Porridge made with milk',
    MealKind.breakfast, [_oats40, _semi200, _banana, _honey2]);
const _granolaBowl = GameMeal('granola', '🥣', 'Granola and yogurt bowl',
    MealKind.breakfast, [_granola, _greekFull, _blueberries, _honey1]);
const _avoToast = GameMeal('avo_toast', '🥑', 'Brunch: avocado toast',
    MealKind.breakfast, [_sourdough, _avocadoHalf, _poached2, _latteWhole]);
const _coffeeShop = GameMeal('croissant', '🥐', 'Coffee-shop breakfast',
    MealKind.breakfast, [_croissant, _butter10, _jam, _flatWhite]);
const _cereal = GameMeal('cereal', '🥣', 'Bowl of cereal and a juice',
    MealKind.breakfast, [_cornflakes, _semi150, _oj]);
const _scrambled = GameMeal('scrambled', '🍳', 'Scrambled eggs on toast',
    MealKind.breakfast, [_eggs2, _butter10, _milkSplash, _wholemeal2]);

const _mealDeal = GameMeal(
    'meal_deal',
    '🥪',
    'Cheese and ham sandwich, crisps and a Coke',
    MealKind.lunch,
    [_white2, _butter10, _cheddar30, _ham, _crisps, _coke]);
const _jacketLunch = GameMeal(
    'jacket',
    '🥔',
    'Jacket potato with tuna mayo and cheese',
    MealKind.lunch,
    [_jacket, _butter10, _tuna, _mayo, _cheddar30]);
const _caesarSalad = GameMeal('caesar', '🥗', 'Chicken Caesar salad',
    MealKind.lunch, [_chicken150, _croutons, _parmesan, _caesar, _romaine]);
const _chickenWrap = GameMeal('wrap', '🌯', 'Chicken wrap', MealKind.lunch,
    [_wrap, _chicken100, _lightMayo, _salad]);
const _toastie = GameMeal('toastie_soup', '🧀',
    'Cheese toastie and tomato soup', MealKind.lunch,
    [_white2, _cheddar40, _butter10, _soup]);
const _beansToast = GameMeal('beans_toast', '🫘', 'Cheesy beans on toast',
    MealKind.lunch, [_wholemeal2, _butter10, _beans, _cheddar30]);
const _pittaLunch = GameMeal('pitta', '🫓', 'Pitta, hummus and carrots',
    MealKind.lunch, [_pitta, _hummus, _carrot, _apple]);
const _greggs = GameMeal('greggs', '🥐', 'Greggs run', MealKind.lunch,
    [_sausageRoll, _coke, _mars]);

const _spagBol = GameMeal('spag_bol', '🍝', 'Spaghetti bolognese, lean mince',
    MealKind.dinner, [_spaghetti, _mince5, _sauce, _oil, _parmesan],
    pair: 'spag_bol');
const _spagBol20 = GameMeal('spag_bol_20', '🍝',
    'Spaghetti bolognese, 20% fat mince', MealKind.dinner,
    [_spaghetti, _mince20, _sauce, _oil, _parmesan],
    pair: 'spag_bol');
const _salmonDinner = GameMeal('salmon', '🐟',
    'Salmon, rice and buttery broccoli', MealKind.dinner,
    [_salmon, _rice, _broccoli, _butter10]);
const _stirFry = GameMeal('stir_fry', '🥢', 'Chicken noodle stir-fry',
    MealKind.dinner, [_chicken150, _noodles, _veg, _oil, _soy]);
const _maccies = GameMeal('maccies', '🍔', "McDonald's on the way home",
    MealKind.dinner, [_bigMac, _fries, _dietCoke]);
const _chickenJacket = GameMeal('chicken_jacket', '🍗',
    'Chicken, jacket potato and broccoli', MealKind.dinner,
    [_chicken150, _jacket, _butter10, _broccoli]);

const _office = GameMeal('office', '🏢', 'Afternoon at the office',
    MealKind.snack, [_choccyDigestives3, _latteSemi, _banana]);
const _filmNight = GameMeal('film', '🍿', 'Film night snacks',
    MealKind.snack, [_maltesers, _twix, _coke]);
const _smoothie = GameMeal('smoothie', '🥤', "Homemade 'healthy' smoothie",
    MealKind.snack, [_banana, _wholeMilk150, _peanutButter, _oats30, _honey1]);
const _teaBiscuits = GameMeal('tea_biscuits', '🫖', 'Tea and biscuits',
    MealKind.snack, [_teas, _digestives4]);
const _deskSnacks = GameMeal('desk_snacks', '🧀', 'Desk snacks',
    MealKind.snack, [_almonds, _apple, _cheddar30]);

const _pints = GameMeal('pints', '🍺', 'Three pints and some peanuts',
    MealKind.nightOut, [_lager3, _peanuts]);
const _wineNight = GameMeal('wine', '🍷', 'Wine and crisps',
    MealKind.nightOut, [_wine2, _crisps]);
const _gin = GameMeal('gin', '🍸', 'Gin night', MealKind.nightOut, [_gnt3],
    pair: 'gin');
const _ginSlim = GameMeal('gin_slim', '🍸', 'Gin night, slimline tonic',
    MealKind.nightOut, [_gntSlim3],
    pair: 'gin');
const _vodka = GameMeal('vodka_rb', '🥤', 'Pre-drinks', MealKind.nightOut,
    [_vodkaRb2]);
const _bottomless = GameMeal('prosecco', '🥂', 'Bottomless brunch',
    MealKind.nightOut, [_prosecco3, _croissant]);
const _rum = GameMeal('rum_coke', '🥃', 'Rum and Cokes', MealKind.nightOut,
    [_rumCoke3]);
const _pub = GameMeal('guinness', '🍺', 'Pub with friends',
    MealKind.nightOut, [_guinness2, _crisps]);

/// A meal as one line of a whole day, with its total.
MealItem _asItem(String text, GameMeal m) => MealItem(m.emoji, text, m.total);

/// Every meal the game deals from.
final List<GameMeal> kGameMeals = [
  _fryUp, _porridge, _granolaBowl, _avoToast, _coffeeShop, _cereal,
  _scrambled,
  _mealDeal, _jacketLunch, _caesarSalad, _chickenWrap, _toastie, _beansToast,
  _pittaLunch, _greggs,
  _spagBol, _spagBol20, _salmonDinner, _stirFry, _maccies, _chickenJacket,
  _office, _filmNight, _smoothie, _teaBiscuits, _deskSnacks,
  _pints, _wineNight, _gin, _ginSlim, _vodka, _bottomless, _rum, _pub,
  GameMeal('day_weekday', '📅', 'A normal weekday', MealKind.day, [
    _asItem('Breakfast: porridge with banana and honey', _porridge),
    _asItem('Lunch: cheese and ham sandwich, crisps and a Coke', _mealDeal),
    _asItem('Snack: 3 chocolate digestives, a latte and a banana', _office),
    _asItem('Dinner: spaghetti bolognese', _spagBol),
  ]),
  GameMeal('day_saturday', '📅', 'A big Saturday', MealKind.day, [
    _asItem('Breakfast: full fry-up', _fryUp),
    _asItem('Lunch: Greggs sausage roll, a Coke and a Mars', _greggs),
    _asItem('Evening: 3 pints of lager and peanuts', _pints),
    _asItem('Late: Big Mac, fries and a Diet Coke', _maccies),
  ]),
  GameMeal('day_clean', '📅', "A 'clean eating' day", MealKind.day, [
    _asItem('Breakfast: granola and yogurt bowl', _granolaBowl),
    _asItem('Lunch: chicken Caesar salad', _caesarSalad),
    _asItem('Snack: homemade smoothie', _smoothie),
    _asItem('Dinner: salmon, rice and buttery broccoli', _salmonDinner),
  ]),
];

// ============================================================================
// Your games progress, from users/{uid}.games
// ============================================================================

/// What's stored on `users/{uid}`:
///   games: {
///     xp: 1240,                     all-time XP
///     month: '2026-10', month_xp: 310     (High scores)
///     daily: {day: '2026-10-11', guesses: [250, 90], score: 171}
///                                   (the Daily Calorie Quiz)
///     meal_day: '2026-10-11', meal_rounds: 2    (rounds that earned XP)
///     hl_day: '2026-10-11', hl_rounds: 1, hl_best: 9   (Higher or Lower)
///     own_day: '2026-10-11'         (Guess your own day earned XP today)
///   }
class GamesProgress {
  final int xp;
  final int monthXp;
  final String? dailyDay;
  final List<int> dailyGuesses;
  final int dailyScore;
  final String? mealDay;
  final int mealRounds;
  final String? hlDay;
  final int hlRounds;
  final int hlBest;
  final String? ownDay;

  const GamesProgress({
    this.xp = 0,
    this.monthXp = 0,
    this.dailyDay,
    this.dailyGuesses = const [],
    this.dailyScore = 0,
    this.mealDay,
    this.mealRounds = 0,
    this.hlDay,
    this.hlRounds = 0,
    this.hlBest = 0,
    this.ownDay,
  });

  static int _int(Object? v) => (BalanceService.number(v) ?? 0).round();

  factory GamesProgress.fromUser(Map<String, dynamic>? user, {DateTime? now}) {
    final g = user?['games'];
    if (g is! Map) return const GamesProgress();
    final month = CalorieSense.monthKey(now ?? BalanceService.now());
    final daily = g['daily'];
    final guesses = daily is Map && daily['guesses'] is List
        ? [for (final v in daily['guesses'] as List) _int(v)]
        : const <int>[];
    return GamesProgress(
      xp: _int(g['xp']),
      monthXp: g['month'] == month ? _int(g['month_xp']) : 0,
      dailyDay: daily is Map ? daily['day']?.toString() : null,
      dailyGuesses: guesses,
      dailyScore: daily is Map ? _int(daily['score']) : 0,
      mealDay: g['meal_day']?.toString(),
      mealRounds: _int(g['meal_rounds']),
      hlDay: g['hl_day']?.toString(),
      hlRounds: _int(g['hl_rounds']),
      hlBest: _int(g['hl_best']),
      ownDay: g['own_day']?.toString(),
    );
  }

  /// The same progress with [xp] and this month's XP moved on by [gained].
  GamesProgress withXp(int xp, int gained) => GamesProgress(
        xp: xp,
        monthXp: monthXp + gained,
        dailyDay: dailyDay,
        dailyGuesses: dailyGuesses,
        dailyScore: dailyScore,
        mealDay: mealDay,
        mealRounds: mealRounds,
        hlDay: hlDay,
        hlRounds: hlRounds,
        hlBest: hlBest,
        ownDay: ownDay,
      );

  GameLevel get level => Levels.of(xp);

  /// Today's Calorie Quiz guesses (empty if not started today).
  List<int> dailyGuessesOn(String day) =>
      dailyDay == day ? dailyGuesses : const [];

  bool dailyDoneOn(String day) =>
      dailyGuessesOn(day).length >= GamesService.dailyRounds;

  int dailyScoreOn(String day) => dailyDay == day ? dailyScore : 0;

  /// Guess the Meal rounds left today that still earn XP.
  int mealXpRoundsLeft(String day) =>
      max(0, Xp.mealRoundsPerDay - (mealDay == day ? mealRounds : 0));

  /// Higher or Lower rounds left today that still earn XP.
  int higherLowerXpRoundsLeft(String day) => max(
      0, Xp.higherLowerRoundsPerDay - (hlDay == day ? hlRounds : 0));

  /// Guess your own day still earns XP today.
  bool ownXpLeft(String day) => ownDay != day;
}

// ============================================================================
// Higher or Lower
// ============================================================================

/// One side of a Higher or Lower pair.
class HlFood {
  final String emoji;
  final String name;

  /// The portion, when it isn't already in the name.
  final String detail;
  final int kcal;
  const HlFood(this.emoji, this.name, this.detail, this.kcal);
}

/// Two foods: which has more calories?
class HlPair {
  final HlFood a;
  final HlFood b;
  const HlPair(this.a, this.b);

  HlFood get higher => a.kcal >= b.kcal ? a : b;
  int get difference => (a.kcal - b.kcal).abs();
}

// ============================================================================
// Guess your own day
// ============================================================================

/// A day from your own log to guess the total of.
class OwnDay {
  final DateTime day;
  final List<MealItem> items;
  const OwnDay(this.day, this.items);

  int get total => items.fold(0, (a, b) => a + b.kcal);
}

class GamesService {
  GamesService._();

  static const dailyRounds = 5;
  static const mealsPerRound = 3;
  static const higherLowerPairs = 10;

  /// Guess your own day needs at least this many foods in a day.
  static const ownDayMinFoods = 3;

  static DocumentReference<Map<String, dynamic>> _user(String uid) =>
      BalanceService.db.collection('users').doc(uid);

  /// "2026-10-11", in the phone's own time zone (everyone's quiz changes
  /// at their midnight).
  static String dayKey([DateTime? d]) {
    final t = d ?? BalanceService.now();
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
  }

  /// A small, stable hash (the same on every device and browser).
  static int _hash(String s) {
    var h = 7;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) % 2147483647;
    }
    return h;
  }

  /// Today's Calorie Quiz: the same 5 foods for everyone on [day].
  static List<GameFood> dailyFoods(String day) {
    final ranked = [...kGameFoods]..sort((a, b) {
        final ha = _hash('$day|${a.name}|${a.portion}');
        final hb = _hash('$day|${b.name}|${b.portion}');
        return ha != hb ? ha.compareTo(hb) : a.name.compareTo(b.name);
      });
    return ranked.take(dailyRounds).toList();
  }

  /// Deals a Guess the Meal round: [mealsPerRound] meals, at most one whole
  /// day, never both of a pair, and not ones in [avoid] if there are
  /// enough others.
  static List<GameMeal> dealMeals({Random? random, Set<String> avoid = const {}}) {
    final r = random ?? Random();
    final fresh = [
      for (final m in kGameMeals)
        if (!avoid.contains(m.id)) m
    ]..shuffle(r);
    final rest = [
      for (final m in kGameMeals)
        if (avoid.contains(m.id)) m
    ]..shuffle(r);
    final picked = <GameMeal>[];
    for (final m in [...fresh, ...rest]) {
      if (picked.length == mealsPerRound) break;
      if (m.kind == MealKind.day &&
          picked.any((p) => p.kind == MealKind.day)) {
        continue;
      }
      if (m.pair != null && picked.any((p) => p.pair == m.pair)) continue;
      picked.add(m);
    }
    return picked;
  }

  static Stream<GamesProgress> watch(String uid) => _user(uid)
      .snapshots()
      .map((s) => GamesProgress.fromUser(s.data()));

  /// The `games` fields that add [xp] to [current].
  static Map<String, dynamic> _xpFields(Map? current, int xp) {
    final month = CalorieSense.monthKey(BalanceService.now());
    final total = (BalanceService.number(current?['xp']) ?? 0).round();
    final monthXp = current?['month'] == month
        ? (BalanceService.number(current?['month_xp']) ?? 0).round()
        : 0;
    return {
      'xp': total + xp,
      'month': month,
      'month_xp': monthXp + xp,
    };
  }

  /// The `games` fields that add [xp] (for other services' transactions).
  static Map<String, dynamic> xpFields(Map? games, int xp) =>
      _xpFields(games, xp);

  static int _xpOf(Map? games) =>
      (BalanceService.number(games?['xp']) ?? 0).round();

  /// Saves a Daily Calorie Quiz guess for food number [index] on [day] and
  /// adds its XP (plus the bonus for the last one). A guess for a food
  /// already guessed (a double tap, another device) is ignored.
  static Future<XpResult> saveDailyGuess({
    required String uid,
    required String day,
    required int index,
    required int guess,
    required int score,
  }) async {
    final ref = _user(uid);
    var result = XpResult.none;
    await BalanceService.db.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      final games = snap.data()?['games'];
      final g = games is Map ? games : const {};
      final rawDaily = g['daily'];
      final Map? daily =
          rawDaily is Map && rawDaily['day'] == day ? rawDaily : null;
      final saved = daily?['guesses'];
      final guesses = saved is List ? [for (final v in saved) v] : <dynamic>[];
      final before = _xpOf(g);
      if (guesses.length != index || index >= dailyRounds) {
        result = XpResult(before, before);
        return;
      }
      guesses.add(max(0, guess));
      final total =
          (BalanceService.number(daily?['score']) ?? 0).round() + score;
      final xp =
          Xp.forScore(score) + (guesses.length == dailyRounds ? Xp.dailyBonus : 0);
      tx.set(
        ref,
        {
          'games': {
            ..._xpFields(g, xp),
            'daily': {'day': day, 'guesses': guesses, 'score': total},
          },
        },
        SetOptions(merge: true),
      );
      result = XpResult(before, before + xp);
    });
    return result;
  }

  /// Starts a Guess the Meal round. True when it earns XP (the first
  /// [Xp.mealRoundsPerDay] of the day); counted as it starts, so quitting
  /// half way still uses it up.
  static Future<bool> startMealRound(String uid) => _startRound(uid,
      dayField: 'meal_day',
      countField: 'meal_rounds',
      left: (p, day) => p.mealXpRoundsLeft(day));

  /// Starts a Higher or Lower round (see [startMealRound]).
  static Future<bool> startHigherLowerRound(String uid) => _startRound(uid,
      dayField: 'hl_day',
      countField: 'hl_rounds',
      left: (p, day) => p.higherLowerXpRoundsLeft(day));

  static Future<bool> _startRound(
    String uid, {
    required String dayField,
    required String countField,
    required int Function(GamesProgress p, String day) left,
  }) async {
    final ref = _user(uid);
    final day = dayKey();
    var earns = false;
    await BalanceService.db.runTransaction<void>((tx) async {
      // A retried transaction starts again from scratch.
      earns = false;
      final snap = await tx.get(ref);
      final games = snap.data()?['games'];
      final p = GamesProgress.fromUser(snap.data());
      if (left(p, day) <= 0) return;
      earns = true;
      final sameDay = games is Map && games[dayField] == day;
      final count = sameDay
          ? (BalanceService.number((games as Map)[countField]) ?? 0).round()
          : 0;
      tx.set(
        ref,
        {
          'games': {dayField: day, countField: count + 1},
        },
        SetOptions(merge: true),
      );
    });
    return earns;
  }

  /// Saves a finished Higher or Lower round: its XP (when [earns]) and
  /// your best score.
  static Future<XpResult> finishHigherLower(
      String uid, {required int correct, required bool earns}) async {
    final ref = _user(uid);
    var result = XpResult.none;
    await BalanceService.db.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      final games = snap.data()?['games'];
      final g = games is Map ? games : const {};
      final before = _xpOf(g);
      final xp = earns ? correct * Xp.perHigherLower : 0;
      final best = (BalanceService.number(g['hl_best']) ?? 0).round();
      result = XpResult(before, before + xp);
      if (xp <= 0 && correct <= best) return;
      tx.set(
        ref,
        {
          'games': {
            if (xp > 0) ..._xpFields(g, xp),
            if (correct > best) 'hl_best': correct,
          },
        },
        SetOptions(merge: true),
      );
    });
    return result;
  }

  /// Saves a Guess your own day guess: [xp] the first time today, nothing
  /// after that (practice).
  static Future<XpResult> saveOwnDay(String uid, int xp) async {
    final ref = _user(uid);
    final day = dayKey();
    var result = XpResult.none;
    await BalanceService.db.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      final games = snap.data()?['games'];
      final g = games is Map ? games : const {};
      final before = _xpOf(g);
      if (g['own_day'] == day) {
        result = XpResult(before, before);
        return;
      }
      result = XpResult(before, before + max(0, xp));
      tx.set(
        ref,
        {
          'games': {..._xpFields(g, max(0, xp)), 'own_day': day},
        },
        SetOptions(merge: true),
      );
    });
    return result;
  }

  /// Adds [xp] (e.g. one Guess the Meal answer).
  static Future<XpResult> addXp(String uid, int xp) async {
    final ref = _user(uid);
    var result = XpResult.none;
    await BalanceService.db.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      final games = snap.data()?['games'];
      final g = games is Map ? games : const {};
      final before = _xpOf(g);
      result = XpResult(before, before + max(0, xp));
      if (xp <= 0) return;
      tx.set(ref, {'games': _xpFields(g, xp)}, SetOptions(merge: true));
    });
    return result;
  }

  /// Gives [uid] the XP for a finished friend game, once (the game keeps
  /// `xp_claimed: [uids]`). Null when there's nothing (more) to give.
  static Future<XpResult?> claimFriendGame(CalorieGame game, String uid) async {
    if (!game.isFinished || !game.playerIds.contains(uid)) return null;
    final gameRef = BalanceService.db.collection('calorie_games').doc(game.id);
    final userRef = _user(uid);
    XpResult? result;
    await BalanceService.db.runTransaction<void>((tx) async {
      // A retried transaction starts again from scratch.
      result = null;
      final gameSnap = await tx.get(gameRef);
      final userSnap = await tx.get(userRef);
      if (!gameSnap.exists) return;
      final claimed = gameSnap.data()?['xp_claimed'];
      if (claimed is List && claimed.contains(uid)) return;
      final fresh = CalorieGame.fromDoc(gameSnap);
      if (!fresh.isFinished) return;
      final xp = Xp.forFriendGame(fresh, uid);
      final games = userSnap.data()?['games'];
      final g = games is Map ? games : const {};
      final before = _xpOf(g);
      tx.update(gameRef, {
        'xp_claimed': FieldValue.arrayUnion([uid]),
      });
      if (xp > 0) {
        tx.set(userRef, {'games': _xpFields(g, xp)}, SetOptions(merge: true));
      }
      result = XpResult(before, before + xp);
    });
    return result;
  }

  /// Friends' Calorie Quiz scores for [day] (only those who finished).
  static Future<List<({String uid, Map<String, dynamic>? user, int score})>>
      friendsDaily(List<String> friendIds, String day) async {
    final docs = await Future.wait(friendIds.map((id) async {
      try {
        return await _user(id).get();
      } catch (_) {
        return null;
      }
    }));
    final out = <({String uid, Map<String, dynamic>? user, int score})>[];
    for (final d in docs) {
      if (d == null) continue;
      final p = GamesProgress.fromUser(d.data());
      if (p.dailyDoneOn(day)) {
        out.add((uid: d.id, user: d.data(), score: p.dailyScoreOn(day)));
      }
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  /// Everything Higher or Lower deals from: the quiz foods and the meal
  /// items, each once.
  static List<HlFood> higherLowerPool() {
    final seen = <String>{};
    final out = <HlFood>[];
    for (final f in kGameFoods) {
      if (f.kcal <= 0 || !seen.add(f.name.toLowerCase())) continue;
      out.add(HlFood(f.emoji, f.name, f.portion, f.kcal));
    }
    for (final m in kGameMeals) {
      if (m.kind == MealKind.day) continue;
      for (final i in m.items) {
        if (i.kcal <= 0 || !seen.add(i.name.toLowerCase())) continue;
        out.add(HlFood(i.emoji, i.name, '', i.kcal));
      }
    }
    return out;
  }

  /// A round of Higher or Lower: [higherLowerPairs] pairs, no food twice,
  /// and never two foods so close it's a coin toss (at least 15% apart).
  static List<HlPair> dealHigherLower({Random? random}) {
    final r = random ?? Random();
    final pool = higherLowerPool()..shuffle(r);
    final used = <int>{};
    final pairs = <HlPair>[];
    for (var i = 0; i < pool.length && pairs.length < higherLowerPairs; i++) {
      if (used.contains(i)) continue;
      for (var j = i + 1; j < pool.length; j++) {
        if (used.contains(j)) continue;
        final a = pool[i].kcal, b = pool[j].kcal;
        if ((a - b).abs() < max(a, b) * 0.15) continue;
        used..add(i)..add(j);
        pairs.add(HlPair(pool[i], pool[j]));
        break;
      }
    }
    return pairs;
  }

  /// The most recent day before [today] (within a week) with at least
  /// [ownDayMinFoods] foods logged, for Guess your own day. Null if there
  /// isn't one.
  static OwnDay? ownDayFrom(Statement statement, DateTime today) {
    const recipePrefix = 'Recipe:';
    final todayKey = dayKey(today);
    const order = {'breakfast': 0, 'lunch': 1, 'dinner': 2, 'snacks': 3};
    for (final d in statement.days.reversed) {
      if (dayKey(d.day) == todayKey || d.day.isAfter(today)) continue;
      final foods = [
        for (final t in d.transactions)
          if (t.calories.round() > 0) t
      ];
      if (foods.length < ownDayMinFoods) continue;
      int rank(CardTransaction t) =>
          order[t.category.trim().toLowerCase()] ?? 4;
      foods.sort((a, b) {
        final m = rank(a).compareTo(rank(b));
        return m != 0 ? m : a.time.compareTo(b.time);
      });
      return OwnDay(d.day, [
        for (final t in foods)
          MealItem(
            CalorieGameService.mealEmoji(t.category),
            () {
              final raw = t.description.trim();
              final name = raw.startsWith(recipePrefix)
                  ? raw.substring(recipePrefix.length).trim()
                  : raw;
              final portion = t.portion.trim();
              return portion.isEmpty ? name : '$name ($portion)';
            }(),
            t.calories.round(),
          ),
      ]);
    }
    return null;
  }

  /// Loads the day for Guess your own day.
  static Future<OwnDay?> loadOwnDay(String uid) async {
    final statement =
        await StatementService.load(uid, days: 8, withLogs: false);
    return ownDayFrom(statement, BalanceService.now());
  }

  /// Counts a play in `game_stats/{day}` so you can see what's played:
  ///   plays: {quiz: 41, meal: 17, ...}   every game started
  ///   players: {quiz: 30, ...}           first play on each device a day
  /// No names or ids are stored. Never throws.
  static Future<void> countPlay(String game) async {
    try {
      final day = dayKey();
      var first = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = 'games_counted_$game';
        first = prefs.getString(key) != day;
        if (first) await prefs.setString(key, day);
      } catch (_) {}
      await BalanceService.db.collection('game_stats').doc(day).set({
        'plays': {game: FieldValue.increment(1)},
        if (first) 'players': {game: FieldValue.increment(1)},
      }, SetOptions(merge: true));
    } catch (_) {
      // Only for your own curiosity: never get in the way of a game.
    }
  }

  /// "🎯 Daily Calorie Quiz · 11 Oct · 412/500" then "🟩🟩🟨🟩🟥".
  static String shareLine(String day, List<int> scores) {
    final total = scores.fold(0, (a, b) => a + b);
    final squares = scores
        .map((s) => s >= 90
            ? '🟩'
            : s >= 70
                ? '🟨'
                : s >= 50
                    ? '🟧'
                    : '🟥')
        .join();
    final parts = day.split('-');
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final label = parts.length == 3
        ? '${int.tryParse(parts[2]) ?? parts[2]} '
            '${months[((int.tryParse(parts[1]) ?? 1) - 1).clamp(0, 11)]}'
        : day;
    return '🎯 Daily Calorie Quiz · $label · '
        '$total/${dailyRounds * 100}\n$squares';
  }
}
