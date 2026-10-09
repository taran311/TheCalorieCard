import 'dart:convert';

import 'package:namer_app/services/balance_service.dart';
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
      };

  /// Loads today's numbers. Missing pieces just come through as zero.
  static Future<CoachContext> load(String uid) async {
    // Started together; the statement is optional (a week summary).
    final profileFuture = BalanceService.userDataDoc(uid);
    final entriesFuture = BalanceService.entriesOn(uid, BalanceService.now());
    final statementFuture = StatementService.load(uid, days: 7)
        .then<Statement?>((s) => s)
        .catchError((_) => null);

    final profile = (await profileFuture)?.data() ?? const <String, dynamic>{};
    final entries = await entriesFuture;
    final statement = await statementFuture;

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
    );
  }
}

/// A ready-made question shown as a tappable chip.
class CoachPrompt {
  final String emoji;
  final String label;

  /// What's actually sent (can be more specific than the label).
  final String question;

  const CoachPrompt(this.emoji, this.label, this.question);
}

class CoachService {
  CoachService._();

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
      CoachPrompt('📊', 'How did I do today?',
          "Look at what I've eaten today and tell me how I'm doing, kindly and honestly."),
      CoachPrompt('📅', 'How was my week?',
          'How has my last week gone? What went well and one thing to try next week?'),
      CoachPrompt('🍕', 'Eating out tonight',
          "I'm eating out tonight. How do I enjoy it and still stay roughly on track?"),
      CoachPrompt('🍬', "I'm craving something sweet",
          "I'm craving something sweet. What could I have that fits?"),
      CoachPrompt('🔁', 'Healthier swaps',
          "Suggest a few easy swaps for the foods I've had today."),
      CoachPrompt('🍷', 'Drinks this weekend',
          "I've got drinks this weekend. How do I fit that in sensibly?"),
      CoachPrompt('🧮', 'Explain my macros',
          'Explain my macro goals simply. Why do protein, carbs and fat matter?'),
      CoachPrompt('🚀', 'Motivate me', 'Give me a quick motivation boost for today.'),
      CoachPrompt('🐷', 'How do Pots work?',
          'How do Pots work in The Calorie Card, and how could I use them?'),
    ]);
    return prompts;
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

  /// Sends the conversation and returns Coach's reply. Throws a readable
  /// message on failure.
  static Future<String> ask({
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
          (body?['error'] as String?) ?? "Coach couldn't answer just now.");
    }
    final reply = (body?['reply'] as String?)?.trim() ?? '';
    if (reply.isEmpty) throw const CoachException('Coach is lost for words.');
    return reply;
  }
}

class CoachException implements Exception {
  final String message;
  const CoachException(this.message);

  @override
  String toString() => message;
}
