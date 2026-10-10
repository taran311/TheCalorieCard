// Practice-mode copy of the app used by the tutorials.
//
// Everything here is pretend: plain Dart objects in memory and look-alike
// widgets. Nothing imports a service, touches Firestore or calls the proxy,
// so a tutorial can never change (or corrupt) anyone's real card, diary,
// recipes, friends or chats, even if the app is closed half way through.

import 'package:flutter/material.dart';
import 'package:namer_app/ui/calorie_card.dart';
import 'package:namer_app/ui/coach_glyph.dart';
import 'package:namer_app/ui/coach_nudge.dart';
import 'package:namer_app/ui/responsive.dart';

class MockFood {
  final String name;
  final String portion;
  final String meal;
  final int kcal;
  final double protein;
  final double carbs;
  final double fat;

  const MockFood(
    this.name,
    this.portion,
    this.meal,
    this.kcal, {
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
  });

  MockFood inMeal(String newMeal) =>
      MockFood(name, portion, newMeal, kcal,
          protein: protein, carbs: carbs, fat: fat);

  MockFood scaled(double by, String newPortion) => MockFood(
        name,
        newPortion,
        meal,
        (kcal * by).round(),
        protein: protein * by,
        carbs: carbs * by,
        fat: fat * by,
      );
}

class MockRecipe {
  final String name;
  final int servings;
  final List<MockFood> ingredients;

  const MockRecipe(this.name, this.servings, this.ingredients);

  int get kcal => ingredients.fold(0, (s, i) => s + i.kcal);
  double get protein => ingredients.fold(0.0, (s, i) => s + i.protein);
  double get carbs => ingredients.fold(0.0, (s, i) => s + i.carbs);
  double get fat => ingredients.fold(0.0, (s, i) => s + i.fat);

  /// One serving, as it lands in the diary.
  MockFood serving(String meal) => MockFood(
        'Recipe: $name',
        '1 serving',
        meal,
        (kcal / servings).round(),
        protein: protein / servings,
        carbs: carbs / servings,
        fat: fat / servings,
      );
}

class MockMessage {
  final bool mine;
  final String text;
  const MockMessage(this.mine, this.text);
}

class MockFriend {
  final String name;
  final String status;
  const MockFriend(this.name, this.status);
}

enum MockScreen {
  home,
  addFood,
  coach,
  recipes,
  recipeEditor,
  friends,
  messages,
  chat,
}

enum ProposalStatus { ready, done }

/// The whole pretend app, rebuilt from scratch for every step.
class TutorialState {
  MockScreen screen = MockScreen.home;
  String meal = 'Lunch';

  static const goalKcal = 2000;
  static const goalProtein = 150.0;
  static const goalCarbs = 200.0;
  static const goalFat = 65.0;

  final List<MockFood> foods = [
    const MockFood('Porridge with banana', '1 bowl', 'Brekkie', 412,
        protein: 14, carbs: 70, fat: 8),
    const MockFood('Flat white', '1 regular', 'Brekkie', 110,
        protein: 7, carbs: 9, fat: 5),
  ];

  bool cardFlipped = false;
  bool dayClosed = false;
  bool showCloseDialog = false;
  int pot = 0;
  String? toast;

  // Add food
  String typed = '';
  final List<MockFood> found = [];

  // Coach
  final List<MockMessage> coach = [];
  String coachTyped = '';
  bool coachThinking = false;
  List<MockFood> proposal = [];
  String proposalMeal = 'Brekkie';
  ProposalStatus? proposalStatus;

  // Recipes
  final List<MockRecipe> recipes = [
    const MockRecipe('Overnight oats', 1, [
      MockFood('Oats', '50g', 'Recipe', 190, protein: 7, carbs: 32, fat: 4),
      MockFood('Greek yoghurt', '100g', 'Recipe', 97,
          protein: 9, carbs: 4, fat: 5),
    ]),
  ];
  String draftName = '';
  String draftTyped = '';
  final List<MockFood> draftIngredients = [];
  bool showPicker = false;

  // Friends and chat
  final List<MockFriend> friends = [
    const MockFriend('Marcus', 'Finished the day ✅'),
  ];
  bool showAddFriend = false;
  String friendEmail = '';
  final List<String> requestsSent = [];
  final List<MockMessage> chat = [
    const MockMessage(false, 'How was the gym? 💪'),
  ];
  String chatTyped = '';

  int get eaten => foods.fold(0, (s, f) => s + f.kcal);
  int get left => goalKcal - eaten;
  double get proteinLeft =>
      goalProtein - foods.fold(0.0, (s, f) => s + f.protein);
  double get carbsLeft => goalCarbs - foods.fold(0.0, (s, f) => s + f.carbs);
  double get fatLeft => goalFat - foods.fold(0.0, (s, f) => s + f.fat);

  List<MockFood> foodsIn(String m) =>
      [for (final f in foods) if (f.meal == m) f];

  int kcalIn(String m) => foodsIn(m).fold(0, (s, f) => s + f.kcal);

  /// The bottom-bar tab that matches the screen.
  String get tab => switch (screen) {
        MockScreen.recipes || MockScreen.recipeEditor => 'recipes',
        MockScreen.coach => 'coach',
        MockScreen.friends || MockScreen.messages || MockScreen.chat =>
          'friends',
        _ => 'card',
      };
}

/// Looks up (or makes) the key a tutorial step points at.
typedef TargetKey = GlobalKey Function(String id);

/// Draws [s] as a slimmed-down, look-alike version of the app.
class MockApp extends StatelessWidget {
  final TutorialState s;
  final TargetKey k;
  final ScrollController scroll;

  const MockApp({
    super.key,
    required this.s,
    required this.k,
    required this.scroll,
  });

  Widget _mark(String id, Widget child) => KeyedSubtree(key: k(id), child: child);

  @override
  Widget build(BuildContext context) {
    final body = switch (s.screen) {
      MockScreen.home => _home(context),
      MockScreen.addFood => _addFood(),
      MockScreen.coach => _coach(),
      MockScreen.recipes => _recipes(),
      MockScreen.recipeEditor => _recipeEditor(),
      MockScreen.friends => _friends(),
      MockScreen.messages => _messages(),
      MockScreen.chat => _chat(),
    };
    final showBar = s.screen == MockScreen.home ||
        s.screen == MockScreen.recipes ||
        s.screen == MockScreen.friends ||
        s.screen == MockScreen.coach;

    return Container(
      color: AppColors.canvas,
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  // Only the new screen stays in the tree (it fades in), so
                  // its pointer targets are never in use twice.
                  layoutBuilder: (current, previous) =>
                      current ?? const SizedBox.shrink(),
                  child: KeyedSubtree(key: ValueKey(s.screen), child: body),
                ),
              ),
              if (showBar) _bottomBar(),
            ],
          ),
          if (s.showPicker) _picker(),
          if (s.showAddFriend) _addFriendSheet(),
          if (s.showCloseDialog) _closeDialog(),
          if (s.toast != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: showBar ? 82 : 16,
              child: _Toast(text: s.toast!),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- chrome

  Widget _header(String title, {bool back = false, List<Widget> actions = const []}) {
    return Container(
      height: 52,
      color: AppColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: back
                ? const Icon(Icons.arrow_back, color: Colors.white, size: 22)
                : null,
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    Widget item(String id, IconData icon, String label) {
      final on = s.tab == id;
      final color = on ? AppColors.primary : AppColors.muted;
      return Expanded(
        child: _mark(
          'nav_$id',
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 26,
                decoration: BoxDecoration(
                  color: on
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          item('card', Icons.credit_card, 'Card'),
          item('recipes', Icons.restaurant, 'Recipes'),
          SizedBox(
            width: 64,
            child: Center(
              child: _mark(
                'orb',
                Container(
                  width: 46,
                  height: 46,
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(colors: [
                      Color(0xFF6366F1),
                      Color(0xFFA855F7),
                      Color(0xFFEC4899),
                      Color(0xFF22D3EE),
                      Color(0xFF6366F1),
                    ]),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.brandGradient,
                    ),
                    child: CoachGlyph(
                      size: 22,
                      thinking: s.coachThinking,
                    ),
                  ),
                ),
              ),
            ),
          ),
          item('friends', Icons.people, 'Friends'),
          item('profile', Icons.person, 'Profile'),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ home

  List<CardMacro> get _macros => [
        CardMacro(
            name: 'Protein',
            remaining: s.proteinLeft,
            goal: TutorialState.goalProtein,
            color: CalorieCardColors.protein),
        CardMacro(
            name: 'Carbs',
            remaining: s.carbsLeft,
            goal: TutorialState.goalCarbs,
            color: CalorieCardColors.carbs),
        CardMacro(
            name: 'Fat',
            remaining: s.fatLeft,
            goal: TutorialState.goalFat,
            color: CalorieCardColors.fat),
      ];

  Widget _home(BuildContext context) {
    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}';
    final meals = const ['Brekkie', 'Lunch', 'Dinner', 'Snacks'];

    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 32).clamp(200.0, 380.0).toDouble();
      final h = w / 1.7 < 180 ? 180.0 : w / 1.7;
      return SingleChildScrollView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _mark(
                'card',
                SizedBox(
                  width: w,
                  height: h,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    transitionBuilder: (child, a) => ScaleTransition(
                      scale: Tween(begin: 0.96, end: 1.0).animate(a),
                      child: FadeTransition(opacity: a, child: child),
                    ),
                    child: s.cardFlipped
                        ? CalorieCardBack(
                            key: const ValueKey('back'),
                            macros: _macros,
                            footnote: 'Today',
                          )
                        : _AnimatedFront(
                            key: const ValueKey('front'),
                            amount: s.left,
                            macros: _macros,
                            validThru: date,
                          ),
                  ),
                ),
              ),
            ),
            if (s.dayClosed) ...[
              const SizedBox(height: 12),
              _mark(
                'closed',
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: AppColors.emerald50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.emerald300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle,
                          color: AppText.emerald600, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.pot > 0
                              ? "Today's closed. ${s.pot} kcal went in your Pot."
                              : "Today's closed. Nice work.",
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppText.emerald800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (!s.dayClosed && s.left < 0) ...[
              const SizedBox(height: 12),
              _mark(
                'nudge',
                CoachNudgeCard(overBy: -s.left, onTap: () {}),
              ),
            ],
            const SizedBox(height: 14),
            _mark(
              'day',
              Container(
                height: 44,
                decoration: AppDecor.card,
                child: Row(
                  children: [
                    SizedBox(width: 12),
                    Icon(Icons.chevron_left, color: AppColors.muted),
                    Expanded(
                      child: Text('Today',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Icon(Icons.chevron_right, color: AppColors.gray300),
                    SizedBox(width: 12),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                s.left < 0
                    ? 'Eaten today: ${s.eaten} kcal · ${-s.left} kcal over'
                    : 'Eaten today: ${s.eaten} kcal · ${s.left} kcal left',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 10),
            for (final m in meals) ...[
              _mealSection(m),
              const SizedBox(height: 12),
            ],
          ],
        ),
      );
    });
  }

  Widget _mealSection(String meal) {
    final items = s.foodsIn(meal);
    return _mark(
      'section_$meal',
      Container(
        decoration: AppDecor.card,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppColors.gray50,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  Text(meal,
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: AppColors.ink)),
                  const Spacer(),
                  if (items.isNotEmpty)
                    Text('${s.kcalIn(meal)} kcal',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink)),
                ],
              ),
            ),
            if (items.isEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Text('Nothing yet.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
              )
            else
              for (final f in items)
                _mark(
                  'food_${f.name}',
                  Container(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.name,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.ink)),
                              Text(f.portion,
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        _kcalPill(f.kcal),
                      ],
                    ),
                  ),
                ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: _mark(
                      'add_$meal',
                      _fakeButton(
                        icon: Icons.add,
                        label: 'Add to $meal',
                        filled: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _mark(
                    'recipeBtn_$meal',
                    _fakeButton(
                      icon: Icons.menu_book_outlined,
                      label: 'Recipe',
                      filled: false,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- add food

  Widget _addFood() {
    final total = s.found.fold(0, (sum, f) => sum + f.kcal);
    final lookUp = s.typed.isNotEmpty && s.found.isEmpty;
    return Column(
      children: [
        _header('Add to ${s.meal}', back: true),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text("Type everything you had. We'll work out the calories.",
                  style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              _mark('input', _fakeField(s.typed, 'e.g. 2 eggs, toast, coffee')),
              const SizedBox(height: 16),
              if (s.found.isNotEmpty) ...[
                Text('Ready to add',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 8),
                for (final f in s.found)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: AppDecor.card,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              Text(
                                  '${f.portion} · ${f.protein.round()}g protein',
                                  style: TextStyle(
                                      fontSize: 12, color: AppColors.muted)),
                            ],
                          ),
                        ),
                        _kcalPill(f.kcal),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              _mark(
                'mainBtn',
                _fakeButton(
                  icon: lookUp ? Icons.search : Icons.check,
                  label: lookUp
                      ? 'Look up ${s.typed.split(',').where((x) => x.trim().isNotEmpty).length} items'
                      : s.found.isEmpty
                          ? 'Add to ${s.meal}'
                          : 'Add $total kcal to ${s.meal}',
                  filled: true,
                  wide: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- coach

  Widget _coach() {
    return Column(
      children: [
        Container(
          height: 52,
          color: AppColors.primary,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.brandGradient),
                child: CoachGlyph(size: 18, thinking: s.coachThinking),
              ),
              const SizedBox(width: 8),
              const Text('Calorie Coach',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            s.left < 0 ? '${-s.left} kcal over' : '${s.left} kcal left',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _bubble(false,
                  "Hi! You've got ${s.left < 0 ? 0 : s.left} kcal left today. How can I help?"),
              for (final m in s.coach) _bubble(m.mine, m.text),
              if (s.coachThinking)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CoachGlyph(
                            size: 24, thinking: true, color: AppColors.primary),
                        SizedBox(width: 6),
                        Text('Thinking…',
                            style: TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              if (s.proposalStatus != null) _proposalCard(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: _mark('coachInput',
                    _fakeField(s.coachTyped, 'Ask anything, or "add 2 eggs"')),
              ),
              const SizedBox(width: 8),
              _mark('coachSend', _roundSend()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _proposalCard() {
    final total = s.proposal.fold(0, (sum, f) => sum + f.kcal);
    final done = s.proposalStatus == ProposalStatus.done;
    return Container(
      margin: const EdgeInsets.only(top: 6, right: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done
              ? AppColors.emerald600.withValues(alpha: 0.5)
              : AppColors.indigo100,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🍽️ Add to ${s.proposalMeal}',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 6),
          for (final f in s.proposal)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• ${f.name} · ${f.portion} · ${f.kcal} kcal',
                  style: const TextStyle(fontSize: 13)),
            ),
          const Divider(height: 14),
          Text('+$total kcal',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (done)
            Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: AppText.emerald600),
                SizedBox(width: 6),
                Text('Added to your card',
                    style: TextStyle(
                        color: AppText.emerald600,
                        fontWeight: FontWeight.w600)),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _fakeButton(
                      icon: null, label: 'Reject', filled: false),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _mark(
                    'proposalAdd',
                    _fakeButton(
                      icon: null,
                      label: 'Add',
                      filled: true,
                      color: AppColors.emerald600,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- recipes

  Widget _recipes() {
    return Stack(
      children: [
        Column(
          children: [
            _header('Recipes'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                children: [
                  for (final r in s.recipes)
                    _mark(
                      'recipe_${r.name}',
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: AppDecor.card,
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.indigo50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.restaurant,
                                  color: AppText.primary, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.name,
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.ink)),
                                  Text(
                                      'Makes ${r.servings} · ${(r.kcal / r.servings).round()} kcal each',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.muted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: _mark(
            'newRecipe',
            _fakeButton(icon: Icons.add, label: 'New recipe', filled: true),
          ),
        ),
      ],
    );
  }

  Widget _recipeEditor() {
    final whole = s.draftIngredients.fold(0, (sum, f) => sum + f.kcal);
    return Column(
      children: [
        _header('New recipe', back: true),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Recipe name',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              _mark('recipeName', _fakeField(s.draftName, 'e.g. Chicken curry')),
              const SizedBox(height: 12),
              Text('This recipe makes 2 servings',
                  style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              _mark('ingInput',
                  _fakeField(s.draftTyped, 'e.g. 200g chicken, 1 onion')),
              const SizedBox(height: 10),
              for (final f in s.draftIngredients)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: AppDecor.card,
                  child: Row(
                    children: [
                      Expanded(child: Text('${f.name} · ${f.portion}')),
                      Text('${f.kcal} kcal',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              if (s.draftIngredients.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: AppDecor.inset,
                  child: Text(
                      'Whole recipe: $whole kcal · per serving: ${(whole / 2).round()} kcal',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
              const SizedBox(height: 12),
              _mark(
                'recipeMain',
                _fakeButton(
                  icon: s.draftIngredients.isEmpty
                      ? Icons.auto_awesome
                      : Icons.check,
                  label: s.draftIngredients.isEmpty
                      ? 'Work out calories'
                      : 'Save recipe',
                  filled: true,
                  wide: true,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _picker() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.35),
        alignment: Alignment.bottomCenter,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.gray300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text('Add a recipe',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final r in s.recipes)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: AppDecor.card,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                            '${r.name}\n1 serving · ${(r.kcal / r.servings).round()} kcal',
                            style: const TextStyle(fontSize: 13)),
                      ),
                      if (r == s.recipes.last)
                        _mark(
                          'pickAdd',
                          _fakeButton(
                              icon: null,
                              label: 'Add to ${s.meal}',
                              filled: true),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- friends

  Widget _friends() {
    return Stack(
      children: [
        Column(
          children: [
            _header('Friends', actions: [
              _mark(
                'chatIcon',
                const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.chat_bubble_outline,
                      color: Colors.white, size: 22),
                ),
              ),
            ]),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                children: [
                  _mark(
                    'hiscores',
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.leaderboard, color: Colors.white),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text('Hiscores\nSee how you rank against friends',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (s.requestsSent.isNotEmpty) ...[
                    Text('Sent requests',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, color: AppColors.ink)),
                    const SizedBox(height: 8),
                    for (final r in s.requestsSent)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: AppDecor.card,
                        child: Text('$r · Waiting for them to accept',
                            style: TextStyle(color: AppColors.muted)),
                      ),
                    const SizedBox(height: 8),
                  ],
                  Text('Your friends',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: AppColors.ink)),
                  const SizedBox(height: 8),
                  for (final f in s.friends)
                    _mark(
                      'friend_${f.name}',
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: AppDecor.card,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.indigo50,
                              child: Text(f.name[0],
                                  style: TextStyle(
                                      color: AppText.primary,
                                      fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(f.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  Text(f.status,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.muted)),
                                ],
                              ),
                            ),
                            Icon(Icons.chat_bubble_outline,
                                size: 20, color: AppText.primary),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: _mark(
            'addFriend',
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.person_add, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _addFriendSheet() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.35),
        alignment: Alignment.bottomCenter,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Add a friend',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              _mark('friendEmail', _fakeField(s.friendEmail, "Friend's email")),
              const SizedBox(height: 12),
              _mark(
                'sendRequest',
                _fakeButton(
                    icon: null, label: 'Send request', filled: true, wide: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messages() {
    return Column(
      children: [
        _header('Messages', back: true),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _mark(
                'conv_Marcus',
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: AppDecor.card,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.indigo50,
                        child: Text('M',
                            style: TextStyle(
                                color: AppText.primary,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Marcus',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            Text('How was the gym? 💪',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('1',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chat() {
    return Column(
      children: [
        _header('Marcus', back: true),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [for (final m in s.chat) _bubble(m.mine, m.text)],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Row(
            children: [
              Expanded(
                  child: _mark('chatInput', _fakeField(s.chatTyped, 'Message'))),
              const SizedBox(width: 8),
              _mark('chatSend', _roundSend()),
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- dialogs

  Widget _closeDialog() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.35),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Close today?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                  "This locks today's card and counts it towards your streak. You can reopen it if you need to.",
                  style: TextStyle(color: AppColors.gray600)),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _fakeButton(icon: null, label: 'Not yet', filled: false),
                  _mark('closeDay',
                      _fakeButton(icon: null, label: 'Close day', filled: true)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- pieces

  static Widget _kcalPill(int kcal) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.indigo50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('$kcal kcal',
            style: TextStyle(
                color: AppText.primaryDark,
                fontWeight: FontWeight.w700,
                fontSize: 12)),
      );

  static Widget _fakeField(String text, String hint) => Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: text.isEmpty ? AppColors.border : AppColors.primary),
        ),
        child: Text(
          text.isEmpty ? hint : '$text▏',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: text.isEmpty ? AppColors.gray400 : AppColors.ink),
        ),
      );

  static Widget _fakeButton({
    required IconData? icon,
    required String label,
    required bool filled,
    bool wide = false,
    Color? color,
  }) {
    final bg = filled ? (color ?? AppColors.primaryDark) : AppColors.surface;
    final fg = filled ? Colors.white : AppText.primaryDark;
    return Container(
      height: 44,
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: filled ? null : Border.all(color: AppColors.gray300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  static Widget _roundSend() => Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: AppColors.primaryDark,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
      );

  static Widget _bubble(bool mine, String text) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 260),
          decoration: BoxDecoration(
            color: mine ? AppColors.primaryDark : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: mine ? null : Border.all(color: AppColors.border),
          ),
          child: Text(text,
              style: TextStyle(
                  color: mine ? Colors.white : AppColors.ink, fontSize: 14)),
        ),
      );
}

/// The card front with the balance counting smoothly to its new value.
class _AnimatedFront extends StatelessWidget {
  final int amount;
  final List<CardMacro> macros;
  final String validThru;

  const _AnimatedFront({
    super.key,
    required this.amount,
    required this.macros,
    required this.validThru,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: amount.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => CalorieCardFront(
        amount: value.round(),
        macros: macros,
        holder: 'You',
        validThru: validThru,
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  final String text;
  const _Toast({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white, fontSize: 13.5)),
    );
  }
}
