import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/coach_actions.dart';
import 'package:namer_app/services/food_log.dart';
import 'package:namer_app/services/proxy_client.dart';
import 'package:namer_app/services/statement_service.dart';

/// One message in a Coach chat.
class CoachMessage {
  final bool fromUser;
  final String text;

  const CoachMessage.user(this.text) : fromUser = true;
  const CoachMessage.coach(this.text) : fromUser = false;

  Map<String, String> toJson() =>
      {'role': fromUser ? 'user' : 'assistant', 'content': text};
}

/// Something in today's diary Coach can point at (e.g. to remove it).
class CoachEntryRef {
  final String id;
  final String name;
  final String portion;
  final String meal;
  final double calories;

  const CoachEntryRef({
    required this.id,
    required this.name,
    required this.portion,
    required this.meal,
    required this.calories,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (portion.isNotEmpty) 'portion': portion,
        'meal': meal,
        'kcal': calories.round(),
      };
}

/// One of your saved recipes, so Coach can log or delete it.
class CoachRecipeRef {
  final String id;
  final String name;
  final String servingSize;
  final double calories;

  const CoachRecipeRef({
    required this.id,
    required this.name,
    required this.servingSize,
    required this.calories,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'serving_size': servingSize,
        'kcal_for_serving_size': calories.round(),
      };
}

/// Today's numbers, sent with each question so answers are about you.
class CoachContext {
  final double calorieGoal;
  final double caloriesLeft;
  final Macros goals;
  final Macros eaten;
  final List<String> todaysFoods;
  final int daysOverThisWeek;
  final int daysLoggedThisWeek;
  final double averageThisWeek;
  final int hour;
  final List<CoachEntryRef> entries;
  final List<CoachRecipeRef> recipes;

  const CoachContext({
    required this.calorieGoal,
    required this.caloriesLeft,
    required this.goals,
    required this.eaten,
    required this.todaysFoods,
    required this.daysOverThisWeek,
    required this.daysLoggedThisWeek,
    required this.averageThisWeek,
    required this.hour,
    this.entries = const [],
    this.recipes = const [],
  });

  bool get isOver => caloriesLeft < 0;
  bool get hasEaten => todaysFoods.isNotEmpty;
  double get proteinLeft => goals.protein - eaten.protein;

  Map<String, dynamic> toJson() => {
        'time_of_day': hour < 11
            ? 'morning'
            : hour < 17
                ? 'afternoon'
                : 'evening',
        'calorie_goal': calorieGoal.round(),
        'calories_left_today': caloriesLeft.round(),
        'eaten_today': {
          'calories': eaten.calories.round(),
          'protein_g': eaten.protein.round(),
          'carbs_g': eaten.carbs.round(),
          'fat_g': eaten.fat.round(),
        },
        'macro_goals': {
          'protein_g': goals.protein.round(),
          'carbs_g': goals.carbs.round(),
          'fat_g': goals.fat.round(),
        },
        'foods_today': todaysFoods.take(20).toList(),
        'last_7_days': {
          'days_logged': daysLoggedThisWeek,
          'days_over_budget': daysOverThisWeek,
          'average_calories': averageThisWeek.round(),
        },
        'entries_today': [for (final e in entries.take(30)) e.toJson()],
        'recipes': [for (final r in recipes.take(30)) r.toJson()],
      };

  /// Loads today's numbers. Missing pieces just come through as zero.
  static Future<CoachContext> load(String uid) async {
    // Started together; the statement is optional (a week summary).
    final profileFuture = BalanceService.userDataDoc(uid);
    final entriesFuture = BalanceService.entriesOn(uid, BalanceService.now());
    final statementFuture = StatementService.load(uid, days: 7)
        .then<Statement?>((s) => s)
        .catchError((_) => null);
    final recipesFuture = BalanceService.db
        .collection('recipes')
        .where('user_id', isEqualTo: uid)
        .limit(60)
        .get()
        .then((snap) => [
              for (final d in snap.docs)
                CoachRecipeRef(
                  id: d.id,
                  name: '${d.data()['name'] ?? ''}',
                  servingSize:
                      '${d.data()['serving_size'] ?? 'Per 1 Serving'}',
                  calories:
                      BalanceService.number(d.data()['total_calories']) ?? 0,
                )
            ])
        .catchError((_) => <CoachRecipeRef>[]);

    final profile = (await profileFuture)?.data() ?? const <String, dynamic>{};
    final entries = await entriesFuture;
    final statement = await statementFuture;
    final recipes = await recipesFuture;

    final goals = BalanceService.goalsFrom(profile) ?? Macros.zero;
    final eaten = BalanceService.totalOf(entries.map((e) => e.data()));
    final foods = [
      for (final e in entries) '${e.data()['food_description'] ?? ''}'.trim()
    ]..removeWhere((s) => s.isEmpty);

    final budget = statement?.dailyBudget ?? goals.calories;
    final pastDays = statement?.days
            .where((d) => !BalanceService.isToday(d.day))
            .where((d) => d.transactions.isNotEmpty)
            .toList() ??
        const [];

    return CoachContext(
      calorieGoal: goals.calories,
      // The card's real balance (includes any pot moved onto it today);
      // worked out from the goal if today's balance hasn't started yet.
      caloriesLeft: (profile['balance_date'] ==
                  BalanceService.dateKey(BalanceService.now())
              ? BalanceService.number(profile['calories'])
              : null) ??
          goals.calories - eaten.calories,
      goals: goals,
      eaten: eaten,
      todaysFoods: foods,
      daysOverThisWeek:
          pastDays.where((d) => budget > 0 && d.calories > budget).length,
      daysLoggedThisWeek: pastDays.length,
      averageThisWeek: pastDays.isEmpty
          ? 0
          : pastDays.fold<double>(0, (s, d) => s + d.calories) /
              pastDays.length,
      hour: BalanceService.now().hour,
      entries: [
        for (final e in entries)
          CoachEntryRef(
            id: e.id,
            name: '${e.data()['food_description'] ?? ''}',
            portion: '${e.data()['food_portion'] ?? ''}',
            meal: FoodLog.displayMeal('${e.data()['foodCategory'] ?? ''}'),
            calories: Macros.fromEntry(e.data()).calories,
          )
      ],
      recipes: recipes,
    );
  }
}

/// A gentle way to even out going over: a little less each day for the
/// rest of this week, or across next week when today is Sunday. Never more
/// than 10% of the daily goal (or 200 kcal) a day, matching Coach's rules.
class OffsetPlan {
  final int overBy;
  final int days;
  final int perDay;
  final bool nextWeek;

  /// True when the daily cap means the plan doesn't cover all of it (and
  /// that's fine: one day over doesn't undo anything).
  final bool partial;

  const OffsetPlan({
    required this.overBy,
    required this.days,
    required this.perDay,
    required this.nextWeek,
    required this.partial,
  });

  factory OffsetPlan.compute({
    required int overBy,
    required double goal,
    required DateTime today,
  }) {
    final daysLeft = DateTime.sunday - today.weekday; // Monday-start weeks
    final nextWeek = daysLeft <= 0;
    final days = nextWeek ? 7 : daysLeft;
    final tenPercent = goal > 0 ? (goal * 0.10).floor() : 200;
    final cap = tenPercent < 200 ? (tenPercent < 25 ? 25 : tenPercent) : 200;
    final needed = overBy <= 0 ? 0 : (overBy / days).ceil();
    final partial = needed > cap;
    return OffsetPlan(
      overBy: overBy < 0 ? 0 : overBy,
      days: days,
      perDay: partial ? cap : needed,
      nextWeek: nextWeek,
      partial: partial,
    );
  }

  String get when => nextWeek
      ? 'across next week'
      : days == 1
          ? 'tomorrow'
          : 'for the rest of this week';

  /// One line for the card under the balance.
  String get summary => perDay <= 0
      ? 'One day never undoes your progress.'
      : 'About $perDay kcal less a day $when evens it out'
          '${partial ? ' (most of it)' : ''}.';

  /// What we ask Coach when they tap it.
  String get question =>
      "I've gone over my calories today by $overBy kcal and feel a bit rubbish "
      'about it. Can you help me feel better and even it out gently? I was '
      'thinking about $perDay kcal less a day $when'
      '${nextWeek || days == 1 ? '' : ' ($days days)'}'
      '${partial ? ", and not worrying about the rest" : ''}. '
      'What easy swaps would do that?';
}

/// Coach's answer: the text, plus any changes it's proposing.
class CoachReply {
  final String text;
  final List<CoachAction> actions;

  /// Free accounts: Coach messages left today (null when unlimited).
  final int? freeLeft;

  /// Free accounts: changes Coach would have offered (a Premium feature).
  final int lockedActions;

  const CoachReply(this.text,
      [this.actions = const [], this.freeLeft, this.lockedActions = 0]);
}

/// Going-out help: the chip opens a short picker before asking.
enum CoachOuting { diningOut, drinksOut }

/// A ready-made question shown as a tappable chip.
class CoachPrompt {
  final String emoji;
  final String label;

  /// What's actually sent (can be more specific than the label).
  final String question;

  /// Set for Dining out / Drinks night out, which ask a couple of things
  /// first and then send [CoachService.diningOutQuestion] or
  /// [CoachService.drinksOutQuestion].
  final CoachOuting? outing;

  const CoachPrompt(this.emoji, this.label, this.question, [this.outing]);
}

class CoachService {
  CoachService._();

  /// True while Coach is working on an answer (the Coach button animates).
  /// Use [startThinking] / [stopThinking]: two Coach screens can be open.
  static final thinking = ValueNotifier<bool>(false);
  static int _busy = 0;

  static void startThinking() {
    _busy++;
    thinking.value = true;
  }

  static void stopThinking() {
    if (_busy > 0) _busy--;
    thinking.value = _busy > 0;
  }

  /// Ready-made questions, the most useful for right now first.
  static List<CoachPrompt> promptsFor(CoachContext? c) {
    final left = c?.caloriesLeft.round() ?? 0;
    final hour = c?.hour ?? BalanceService.now().hour;
    final prompts = <CoachPrompt>[];

    if (c != null && c.isOver) {
      prompts.addAll([
        CoachPrompt('🫶', 'I went over today',
            "I've gone over my calories today by ${-left} kcal and feel a bit rubbish about it."),
        const CoachPrompt('⚖️', 'Help me balance it out',
            'How can I gently balance out going over today across the next few days?'),
        const CoachPrompt('🌙', 'Light options for later',
            "I'm already over today. What are some light, filling options if I'm still hungry?"),
      ]);
    } else {
      prompts.addAll([
        CoachPrompt('🍽️', 'Meal ideas for my $left kcal',
            'Suggest a meal I could have with my $left kcal left today.'),
        CoachPrompt(
            '🍫',
            'A snack that fits',
            "Suggest a satisfying snack that fits in what I've got left today."),
      ]);
    }

    prompts.addAll(const [
      CoachPrompt('🍽️', 'Dining out', '', CoachOuting.diningOut),
      CoachPrompt('🍻', 'Drinks night out', '', CoachOuting.drinksOut),
    ]);

    if ((c?.proteinLeft ?? 0) > 15) {
      prompts.add(CoachPrompt('💪', 'Help me hit my protein',
          'I still need about ${c!.proteinLeft.round()}g of protein today. What could I eat?'));
    }

    if (hour >= 15 && !(c?.isOver ?? false)) {
      prompts.add(const CoachPrompt(
          '🥘', 'Plan my dinner', 'Plan a dinner that fits my numbers for today.'));
    }
    if (hour < 11) {
      prompts.add(const CoachPrompt('🥣', 'Breakfast ideas',
          'Give me a few breakfast ideas that set me up well for today.'));
    }

    prompts.addAll(const [
      CoachPrompt('✍️', 'Add food for me',
          "I'd like you to add some food to my diary for me."),
      CoachPrompt('📖', 'Save a recipe',
          "Help me save one of my usual meals as a recipe."),
    ]);
    if (c != null && c.entries.isNotEmpty) {
      prompts.add(const CoachPrompt('🗑️', 'Remove something',
          "I logged something by mistake today. Can you help me remove it?"));
    }

    prompts.addAll(const [
      CoachPrompt('📊', 'How did I do today?',
          "Look at what I've eaten today and tell me how I'm doing, kindly and honestly."),
      CoachPrompt('📅', 'How was my week?',
          'How has my last week gone? What went well and one thing to try next week?'),
      CoachPrompt('🍬', "I'm craving something sweet",
          "I'm craving something sweet. What could I have that fits?"),
      CoachPrompt('🔁', 'Healthier swaps',
          "Suggest a few easy swaps for the foods I've had today."),
      CoachPrompt('🧮', 'Explain my macros',
          'Explain my macro goals simply. Why do protein, carbs and fat matter?'),
      CoachPrompt('🚀', 'Motivate me', 'Give me a quick motivation boost for today.'),
      CoachPrompt('🐷', 'How do Pots work?',
          'How do Pots work in The Calorie Card, and how could I use them?'),
    ]);
    return prompts;
  }

  /// "1,240 kcal left today" / "already 150 kcal over today".
  static String _budget(CoachContext? c) {
    if (c == null) return '';
    final left = c.caloriesLeft.round();
    if (left < 0) return "I'm already ${-left} kcal over today.";
    final protein = c.proteinLeft.round();
    return "I've got $left kcal left today"
        "${protein > 0 ? ' (and about ${protein}g of protein to go)' : ''}.";
  }

  /// Sent by Dining out: where they're going, and their numbers.
  static String diningOutQuestion(
    CoachContext? c, {
    String? kind,
    String? place,
    bool drinking = false,
  }) {
    final named = place?.trim() ?? '';
    final where = named.isNotEmpty
        ? (kind == null || kind == 'Other' ? named : '$named ($kind)')
        : kind == null || kind == 'Other'
            ? 'a restaurant'
            : kind == 'Pub'
                ? 'a pub'
                : 'a $kind place';
    final over = c?.isOver ?? false;
    return [
      "I'm eating out at $where.",
      _budget(c),
      if (drinking) "I'll probably have a drink or two as well.",
      over
          ? "What are the lighter options that still feel like a treat?"
          : 'What should I order so I enjoy it and stay roughly on track?',
    ].where((s) => s.isNotEmpty).join(' ');
  }

  /// Sent by Drinks night out: what they're drinking and how big a night.
  static String drinksOutQuestion(
    CoachContext? c, {
    required List<String> drinks,
    required String size,
    bool eating = false,
  }) {
    final what = drinks.isEmpty
        ? "I'm not sure what I'll drink yet"
        : 'Probably ${_list(drinks.map((d) => d.toLowerCase()).toList())}';
    return [
      "I'm going out for drinks later, $size.",
      '$what.',
      if (eating) "I'll be eating out too.",
      _budget(c),
      'How many drinks roughly fit, what are the lower-calorie choices, and '
          'what should I eat beforehand?',
    ].where((s) => s.isNotEmpty).join(' ');
  }

  static String _list(List<String> items) {
    if (items.length <= 1) return items.join();
    return '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
  }

  /// A warm opening line based on the day so far.
  static String greeting(CoachContext? c, {String? name}) {
    final hi = name == null || name.isEmpty ? 'Hi!' : 'Hi $name!';
    if (c == null) {
      return "$hi I'm your Calorie Coach. Ask me anything about food or your day, "
          'or tap a question below.';
    }
    final left = c.caloriesLeft.round();
    if (c.isOver) {
      return '$hi You\'re ${-left} kcal over today, and that\'s okay. One day '
          'never undoes your progress. Want some ideas for the rest of today, '
          'or a gentle plan for the next few days?';
    }
    if (!c.hasEaten) {
      return "$hi You've got $left kcal on your card today. "
          'Want some ideas to get started?';
    }
    return "$hi You've got $left kcal left today. "
        'How can I help?';
  }

  /// Sends the conversation and returns Coach's reply (and any proposed
  /// changes). Throws a readable message on failure.
  static Future<CoachReply> ask({
    required List<CoachMessage> history,
    CoachContext? context,
  }) async {
    final response = await ProxyClient.post('/coach', {
      'messages': [for (final m in history) m.toJson()],
      'context': context?.toJson() ?? const {},
    }).timeout(const Duration(seconds: 45));

    Map<String, dynamic>? body;
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    if (response.statusCode != 200) {
      throw CoachException(
          (body?['error'] as String?) ?? "Coach couldn't answer just now.",
          code: body?['code'] as String?);
    }
    final reply = (body?['reply'] as String?)?.trim() ?? '';
    if (reply.isEmpty) throw const CoachException('Coach is lost for words.');
    final raw = body?['actions'];
    final actions = [
      for (final a in (raw is List ? raw : const []))
        if (CoachAction.fromJson(a) case final CoachAction action) action
    ];
    final freeLeft = body?['free_left'];
    final locked = body?['locked_actions'];
    return CoachReply(
      reply,
      actions,
      freeLeft is num ? freeLeft.toInt() : null,
      locked is num ? locked.toInt() : 0,
    );
  }
}

class CoachException implements Exception {
  final String message;

  /// e.g. 'coach_limit' when today's free messages are used up.
  final String? code;

  const CoachException(this.message, {this.code});

  @override
  String toString() => message;
}
