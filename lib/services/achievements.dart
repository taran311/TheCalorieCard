import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/spend_category.dart';
import 'package:namer_app/services/streak.dart';

/// Achievement tiers: harder ones are worth more points.
enum AchievementTier {
  bronze('Bronze', 10, Color(0xFFB87333)),
  silver('Silver', 25, Color(0xFF94A3B8)),
  gold('Gold', 50, Color(0xFFF59E0B)),
  platinum('Platinum', 100, Color(0xFF6366F1));

  final String label;
  final int points;
  final Color color;

  const AchievementTier(this.label, this.points, this.color);
}

enum AchievementCategory {
  gettingStarted('Getting started', '🚀'),
  consistency('Consistency', '🔥'),
  onBudget('On budget', '💳'),
  nutrition('Nutrition', '🥗'),
  social('Social', '🤝'),
  banking('Card & extras', '✨');

  final String label;
  final String emoji;

  const AchievementCategory(this.label, this.emoji);
}

class Achievement {
  final String id;
  final String title;
  final String description;
  final String emoji;
  final AchievementCategory category;
  final AchievementTier tier;

  /// Progress needed to unlock (1 for one-off achievements).
  final int target;

  /// Unit shown with progress, e.g. "days" in "12 / 30 days".
  final String unit;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    required this.category,
    required this.tier,
    this.target = 1,
    this.unit = '',
  });
}

/// Every achievement, in the order they're shown.
///
/// Deliberately nothing rewards eating very little: "on budget" days only
/// count when you've eaten at least half your goal (same rule as Pots), so
/// skipping meals can't farm achievements.
class Achievements {
  Achievements._();

  static const all = <Achievement>[
    // ---- Getting started ----
    Achievement(
      id: 'first_time_logger',
      title: 'First Swipe',
      description: 'Log your first food.',
      emoji: '💳',
      category: AchievementCategory.gettingStarted,
      tier: AchievementTier.bronze,
    ),
    Achievement(
      id: 'first_finish',
      title: 'First Statement',
      description: 'Finish your first day (swipe the card at the end of the day).',
      emoji: '🧾',
      category: AchievementCategory.gettingStarted,
      tier: AchievementTier.bronze,
    ),
    Achievement(
      id: 'first_recipe',
      title: 'Head Chef',
      description: 'Save your first recipe.',
      emoji: '👩‍🍳',
      category: AchievementCategory.gettingStarted,
      tier: AchievementTier.bronze,
    ),
    Achievement(
      id: 'first_friend',
      title: 'Plus One',
      description: 'Add your first friend.',
      emoji: '👋',
      category: AchievementCategory.gettingStarted,
      tier: AchievementTier.bronze,
    ),
    Achievement(
      id: 'card_custom',
      title: 'New Card, Who Dis?',
      description: 'Switch to a different card design.',
      emoji: '🎨',
      category: AchievementCategory.gettingStarted,
      tier: AchievementTier.bronze,
    ),

    // ---- Consistency ----
    Achievement(
      id: 'streak_starter',
      title: 'Streak Starter',
      description: 'Finish 3 days in a row.',
      emoji: '🔥',
      category: AchievementCategory.consistency,
      tier: AchievementTier.bronze,
      target: 3,
      unit: 'days',
    ),
    Achievement(
      id: 'streak_7',
      title: 'On a Roll',
      description: 'Finish 7 days in a row.',
      emoji: '🎳',
      category: AchievementCategory.consistency,
      tier: AchievementTier.silver,
      target: 7,
      unit: 'days',
    ),
    Achievement(
      id: 'streak_14',
      title: 'Fortnight Strong',
      description: 'Finish 14 days in a row.',
      emoji: '💪',
      category: AchievementCategory.consistency,
      tier: AchievementTier.gold,
      target: 14,
      unit: 'days',
    ),
    Achievement(
      id: 'streak_30',
      title: 'Habit Formed',
      description: 'Finish 30 days in a row. Unlocks the Metal card.',
      emoji: '🏅',
      category: AchievementCategory.consistency,
      tier: AchievementTier.gold,
      target: 30,
      unit: 'days',
    ),
    Achievement(
      id: 'streak_100',
      title: 'Centurion',
      description: 'Finish 100 days in a row.',
      emoji: '💯',
      category: AchievementCategory.consistency,
      tier: AchievementTier.platinum,
      target: 100,
      unit: 'days',
    ),
    Achievement(
      id: 'days_30',
      title: 'Regular Customer',
      description: 'Finish 30 days in total.',
      emoji: '📅',
      category: AchievementCategory.consistency,
      tier: AchievementTier.silver,
      target: 30,
      unit: 'days',
    ),
    Achievement(
      id: 'days_100',
      title: 'Loyal Cardholder',
      description: 'Finish 100 days in total.',
      emoji: '🪪',
      category: AchievementCategory.consistency,
      tier: AchievementTier.gold,
      target: 100,
      unit: 'days',
    ),
    Achievement(
      id: 'days_365',
      title: 'Platinum Member',
      description: 'Finish 365 days in total. A whole year of statements.',
      emoji: '👑',
      category: AchievementCategory.consistency,
      tier: AchievementTier.platinum,
      target: 365,
      unit: 'days',
    ),
    Achievement(
      id: 'breakfast_club',
      title: 'Breakfast Club',
      description: 'Log breakfast on 7 finished days.',
      emoji: '🥣',
      category: AchievementCategory.consistency,
      tier: AchievementTier.bronze,
      target: 7,
      unit: 'days',
    ),

    // ---- On budget ----
    Achievement(
      id: 'budget_1',
      title: 'In the Black',
      description: 'Finish a day in credit (on budget, having eaten at least '
          'half your goal).',
      emoji: '✅',
      category: AchievementCategory.onBudget,
      tier: AchievementTier.bronze,
    ),
    Achievement(
      id: 'bullseye',
      title: 'Bullseye',
      description: 'Finish a day with 0–50 kcal left on the card.',
      emoji: '🎯',
      category: AchievementCategory.onBudget,
      tier: AchievementTier.silver,
    ),
    Achievement(
      id: 'bullseye_5',
      title: 'Precision Banking',
      description: 'Hit a Bullseye on 5 days.',
      emoji: '🏹',
      category: AchievementCategory.onBudget,
      tier: AchievementTier.gold,
      target: 5,
      unit: 'days',
    ),
    Achievement(
      id: 'weekend_warrior',
      title: 'Weekend Warrior',
      description: 'Stay on budget on both Saturday and Sunday of a weekend.',
      emoji: '🛡️',
      category: AchievementCategory.onBudget,
      tier: AchievementTier.silver,
    ),
    Achievement(
      id: 'comeback',
      title: 'Comeback Kid',
      description: 'Finish on budget the day after going over.',
      emoji: '🔄',
      category: AchievementCategory.onBudget,
      tier: AchievementTier.bronze,
    ),
    Achievement(
      id: 'perfect_week',
      title: 'Perfect Week',
      description: 'On budget every day from Monday to Sunday.',
      emoji: '🌟',
      category: AchievementCategory.onBudget,
      tier: AchievementTier.gold,
    ),
    Achievement(
      id: 'budget_streak_14',
      title: 'Excellent Credit',
      description: 'On budget 14 days in a row.',
      emoji: '📈',
      category: AchievementCategory.onBudget,
      tier: AchievementTier.platinum,
      target: 14,
      unit: 'days',
    ),
    Achievement(
      id: 'budget_50',
      title: 'Balanced Books',
      description: 'Finish 50 days on budget.',
      emoji: '⚖️',
      category: AchievementCategory.onBudget,
      tier: AchievementTier.gold,
      target: 50,
      unit: 'days',
    ),

    // ---- Nutrition ----
    Achievement(
      id: 'macro_master',
      title: 'Macro Master',
      description: 'Finish a day with protein, carbs and fat all within 10% '
          'of your goals.',
      emoji: '🧪',
      category: AchievementCategory.nutrition,
      tier: AchievementTier.silver,
    ),
    Achievement(
      id: 'macro_master_5',
      title: 'Macro Maestro',
      description: 'Be a Macro Master on 5 days.',
      emoji: '🎼',
      category: AchievementCategory.nutrition,
      tier: AchievementTier.gold,
      target: 5,
      unit: 'days',
    ),
    Achievement(
      id: 'cultivating_mass',
      title: 'Cultivating Mass',
      description: 'Hit your protein goal 7 days in a row.',
      emoji: '🏋️',
      category: AchievementCategory.nutrition,
      tier: AchievementTier.silver,
      target: 7,
      unit: 'days',
    ),
    Achievement(
      id: 'protein_30',
      title: 'Protein Powerhouse',
      description: 'Hit your protein goal on 30 days.',
      emoji: '🥩',
      category: AchievementCategory.nutrition,
      tier: AchievementTier.gold,
      target: 30,
      unit: 'days',
    ),
    Achievement(
      id: 'five_a_day',
      title: 'Five a Day',
      description: 'Log 5 fruit & veg items in one day.',
      emoji: '🍎',
      category: AchievementCategory.nutrition,
      tier: AchievementTier.silver,
      target: 5,
      unit: 'items',
    ),
    Achievement(
      id: 'home_chef',
      title: 'Home Cooking',
      description: 'Log 10 of your own recipes.',
      emoji: '🍲',
      category: AchievementCategory.nutrition,
      tier: AchievementTier.silver,
      target: 10,
      unit: 'recipes',
    ),
    Achievement(
      id: 'takeaway_free',
      title: 'Spending Freeze',
      description: 'Finish 7 days in a row without a takeaway.',
      emoji: '🧊',
      category: AchievementCategory.nutrition,
      tier: AchievementTier.gold,
      target: 7,
      unit: 'days',
    ),
    Achievement(
      id: 'variety',
      title: 'Explorer',
      description: 'Log 50 different foods.',
      emoji: '🧭',
      category: AchievementCategory.nutrition,
      tier: AchievementTier.gold,
      target: 50,
      unit: 'foods',
    ),

    // ---- Social ----
    Achievement(
      id: 'friends_5',
      title: 'Squad Goals',
      description: 'Have 5 friends on The Calorie Card.',
      emoji: '👯',
      category: AchievementCategory.social,
      tier: AchievementTier.silver,
      target: 5,
      unit: 'friends',
    ),
    Achievement(
      id: 'split_1',
      title: 'Going Dutch',
      description: 'Split a bill with a friend.',
      emoji: '🍕',
      category: AchievementCategory.social,
      tier: AchievementTier.bronze,
    ),
    Achievement(
      id: 'challenge_join',
      title: 'Game On',
      description: 'Start or join a challenge.',
      emoji: '⚔️',
      category: AchievementCategory.social,
      tier: AchievementTier.bronze,
    ),
    Achievement(
      id: 'challenge_win',
      title: 'Champion',
      description: 'Win a head-to-head challenge outright.',
      emoji: '🏆',
      category: AchievementCategory.social,
      tier: AchievementTier.gold,
    ),
    Achievement(
      id: 'team_goal',
      title: 'Team Player',
      description: 'Be part of a team challenge that hits its goal.',
      emoji: '🤝',
      category: AchievementCategory.social,
      tier: AchievementTier.silver,
    ),
    Achievement(
      id: 'wrapped_share',
      title: 'Show-off',
      description: 'Share your Monthly Wrapped.',
      emoji: '📣',
      category: AchievementCategory.social,
      tier: AchievementTier.bronze,
    ),

    // ---- Card & extras ----
    Achievement(
      id: 'scanner',
      title: 'Contactless',
      description: 'Log 10 foods by scanning their barcode.',
      emoji: '📶',
      category: AchievementCategory.banking,
      tier: AchievementTier.silver,
      target: 10,
      unit: 'scans',
    ),
    Achievement(
      id: 'bang_on',
      title: 'Bang On',
      description: 'Guess a food\'s calories within 5% while it looks up.',
      emoji: '🔮',
      category: AchievementCategory.banking,
      tier: AchievementTier.silver,
    ),
    Achievement(
      id: 'sharp_eye',
      title: 'Sharp Eye',
      description: 'Average 85%+ Calorie Sense over 10 guesses in a month.',
      emoji: '🦅',
      category: AchievementCategory.banking,
      tier: AchievementTier.gold,
    ),
    Achievement(
      id: 'direct_debit',
      title: 'Set and Forget',
      description: 'Set up a direct debit (long-press a food on your card).',
      emoji: '🔁',
      category: AchievementCategory.banking,
      tier: AchievementTier.bronze,
    ),
    Achievement(
      id: 'pot_saver',
      title: 'Saver',
      description: 'Fill your pot to the 750 kcal weekly cap.',
      emoji: '🐷',
      category: AchievementCategory.banking,
      tier: AchievementTier.gold,
      target: 750,
      unit: 'kcal',
    ),
    Achievement(
      id: 'pot_treat',
      title: 'Treat Yourself',
      description: 'Move your pot onto your card.',
      emoji: '🍰',
      category: AchievementCategory.banking,
      tier: AchievementTier.bronze,
    ),
  ];

  static Achievement? byId(String id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }

  static int get totalPoints => all.fold(0, (s, a) => s + a.tier.points);
}

/// One finished day, from its `daily_logs` document.
class AchievementDay {
  final DateTime date;
  final double eaten;
  final double? left; // calories left on the card at the end of the day
  final double calorieGoal;
  final double protein, carbs, fat;
  final double proteinGoal, carbsGoal, fatGoal;
  final List<Map<String, dynamic>> entries;

  const AchievementDay({
    required this.date,
    required this.eaten,
    required this.left,
    required this.calorieGoal,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.proteinGoal = 0,
    this.carbsGoal = 0,
    this.fatGoal = 0,
    this.entries = const [],
  });

  /// On budget, having eaten at least half the goal (so not eating isn't
  /// rewarded).
  bool get isGood =>
      calorieGoal > 0 && left != null && left! >= 0 && eaten >= calorieGoal * 0.5;

  bool get isOver => left != null && left! < 0;

  bool get isBullseye => isGood && left! <= 50;

  bool get hitProtein => proteinGoal > 0 && protein >= proteinGoal;

  bool get isMacroMaster {
    bool within(double v, double goal) =>
        goal > 0 && (v - goal).abs() <= goal * 0.1;
    return isGood &&
        within(protein, proteinGoal) &&
        within(carbs, carbsGoal) &&
        within(fat, fatGoal);
  }

  Iterable<SpendCategory> get categories => entries.map(SpendCategory.of);

  bool get hadBreakfast =>
      entries.any((e) => (e['foodCategory'] ?? '') == 'Brekkie');

  bool get hadTakeaway => categories.contains(SpendCategory.takeaway);

  int get fruitVegCount =>
      categories.where((c) => c == SpendCategory.fruitVeg).length;

  int get recipeCount => entries
      .where((e) =>
          e['is_recipe'] == true ||
          '${e['food_description'] ?? ''}'.startsWith('Recipe:'))
      .length;

  /// Builds a day from a `daily_logs` document's data.
  static AchievementDay? fromLog(Map<String, dynamic> d,
      {Map<String, dynamic>? fallbackGoals}) {
    final raw = d['date'];
    DateTime? date = raw is Timestamp
        ? raw.toDate()
        : raw is DateTime
            ? raw
            : null;
    date ??= _parseKey(d['date_key']);
    if (date == null) return null;

    double? n(dynamic v) => BalanceService.number(v);
    final totals = (d['totals'] as Map?) ?? const {};
    final balances = (d['balances'] as Map?) ?? const {};
    final goals = (d['goals'] as Map?) ?? const {};
    final fb = fallbackGoals ?? const {};

    final eaten = n(totals['calories']) ?? 0;
    final left = n(balances['calories']);
    var calorieGoal = n(goals['calorie_goal']);
    if (calorieGoal == null && left != null) calorieGoal = left + eaten;
    calorieGoal ??= n(fb['calorie_goal']) ?? 0;

    return AchievementDay(
      date: BalanceService.startOfDay(date),
      eaten: eaten,
      left: left,
      calorieGoal: calorieGoal,
      protein: n(totals['protein']) ?? 0,
      carbs: n(totals['carbs']) ?? 0,
      fat: n(totals['fat']) ?? 0,
      proteinGoal: n(goals['protein_goal']) ?? n(fb['protein_goal']) ?? 0,
      carbsGoal: n(goals['carbs_goal']) ?? n(fb['carbs_goal']) ?? 0,
      fatGoal: n(goals['fats_goal']) ?? n(fb['fats_goal']) ?? 0,
      entries: [
        for (final e in (d['food_entries'] as List? ?? const []))
          if (e is Map) Map<String, dynamic>.from(e)
      ],
    );
  }

  static DateTime? _parseKey(dynamic key) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch('${key ?? ''}');
    if (m == null) return null;
    return DateTime(
        int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }
}

/// Everything achievements are worked out from.
class AchievementInputs {
  /// Finished days (any order).
  final List<AchievementDay> days;

  /// Running counters kept on `user_achievements.stats`.
  final Map<String, num> counters;

  final int friendCount;
  final bool customCard;
  final double calorieSenseAverage;
  final int calorieSenseCount;
  final bool hasDirectDebit;
  final double pot;
  final bool inChallenge;
  final bool wonChallenge;
  final bool teamGoalHit;
  final int recipesSaved;

  const AchievementInputs({
    this.days = const [],
    this.counters = const {},
    this.friendCount = 0,
    this.customCard = false,
    this.calorieSenseAverage = 0,
    this.calorieSenseCount = 0,
    this.hasDirectDebit = false,
    this.pot = 0,
    this.inChallenge = false,
    this.wonChallenge = false,
    this.teamGoalHit = false,
    this.recipesSaved = 0,
  });
}

/// Works out progress towards every achievement. Pure, so it's easy to test.
class AchievementEngine {
  AchievementEngine._();

  /// Longest run of consecutive calendar days in [days] matching [test].
  static int longestRun(
      List<AchievementDay> days, bool Function(AchievementDay) test) {
    final keys = {
      for (final d in days)
        if (test(d)) BalanceService.dateKey(d.date)
    };
    var best = 0;
    for (final d in days) {
      if (!test(d)) continue;
      // Only start counting at the first day of a run.
      final before = BalanceService.addDays(d.date, -1);
      if (keys.contains(BalanceService.dateKey(before))) continue;
      var run = 0;
      var cursor = d.date;
      while (keys.contains(BalanceService.dateKey(cursor))) {
        run++;
        cursor = BalanceService.addDays(cursor, 1);
      }
      if (run > best) best = run;
    }
    return best;
  }

  static int _count(
          List<AchievementDay> days, bool Function(AchievementDay) test) =>
      days.where(test).length;

  /// Progress for each achievement id (compare with its target).
  static Map<String, int> progress(AchievementInputs input) {
    // One entry per calendar day (the latest wins if there are duplicates).
    final byKey = <String, AchievementDay>{
      for (final d in input.days) BalanceService.dateKey(d.date): d
    };
    final days = byKey.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    AchievementDay? on(DateTime d) => byKey[BalanceService.dateKey(d)];
    int c(String key) => (input.counters[key] ?? 0).round();
    int flag(bool v) => v ? 1 : 0;

    final finished = days.length;
    // Streak Freezes count here too, so a frozen day doesn't break it.
    final streak = days.isEmpty
        ? 0
        : Streaks.compute(byKey.keys.toSet(),
                from: days.first.date, today: days.last.date)
            .longest;
    final goodDays = _count(days, (d) => d.isGood);
    final bullseyes = _count(days, (d) => d.isBullseye);
    final macroDays = _count(days, (d) => d.isMacroMaster);

    final weekend = days.any((d) =>
        d.date.weekday == DateTime.saturday &&
        d.isGood &&
        (on(BalanceService.addDays(d.date, 1))?.isGood ?? false));
    final comeback = days.any((d) =>
        d.isGood && (on(BalanceService.addDays(d.date, -1))?.isOver ?? false));
    final perfectWeek = days.any((d) =>
        d.date.weekday == DateTime.monday &&
        List.generate(7, (i) => on(BalanceService.addDays(d.date, i)))
            .every((x) => x?.isGood ?? false));

    final foods = <String>{
      for (final d in days)
        for (final e in d.entries)
          '${e['food_description'] ?? ''}'.trim().toLowerCase()
    }..remove('');

    return {
      'first_time_logger':
          flag(c('foods_logged') > 0 || days.any((d) => d.entries.isNotEmpty)),
      'first_finish': finished,
      'first_recipe': input.recipesSaved > 0 ? 1 : c('recipes_created'),
      'first_friend': input.friendCount,
      'card_custom': flag(input.customCard),
      'streak_starter': streak,
      'streak_7': streak,
      'streak_14': streak,
      'streak_30': streak,
      'streak_100': streak,
      'days_30': finished,
      'days_100': finished,
      'days_365': finished,
      'breakfast_club': _count(days, (d) => d.hadBreakfast),
      'budget_1': goodDays,
      'bullseye': bullseyes,
      'bullseye_5': bullseyes,
      'weekend_warrior': flag(weekend),
      'comeback': flag(comeback),
      'perfect_week': flag(perfectWeek),
      'budget_streak_14': longestRun(days, (d) => d.isGood),
      'budget_50': goodDays,
      'macro_master': macroDays,
      'macro_master_5': macroDays,
      'cultivating_mass': longestRun(days, (d) => d.hitProtein),
      'protein_30': _count(days, (d) => d.hitProtein),
      'five_a_day': days.fold(
          0, (best, d) => d.fruitVegCount > best ? d.fruitVegCount : best),
      'home_chef': days.fold(0, (s, d) => s + d.recipeCount),
      'takeaway_free':
          longestRun(days, (d) => d.entries.isNotEmpty && !d.hadTakeaway),
      'variety': foods.length,
      'friends_5': input.friendCount,
      'split_1': c('splits'),
      'challenge_join': flag(input.inChallenge),
      'challenge_win': flag(input.wonChallenge),
      'team_goal': flag(input.teamGoalHit),
      'wrapped_share': c('wrapped_shares'),
      'scanner': c('scans'),
      'bang_on': c('bang_on'),
      'sharp_eye': flag(
          input.calorieSenseCount >= 10 && input.calorieSenseAverage >= 85),
      'direct_debit': flag(input.hasDirectDebit),
      'pot_saver': input.pot.round(),
      'pot_treat': c('pot_spends'),
    };
  }

  /// Ids of achievements whose progress has reached their target.
  static Set<String> unlocked(Map<String, int> progress) => {
        for (final a in Achievements.all)
          if ((progress[a.id] ?? 0) >= a.target) a.id
      };
}
