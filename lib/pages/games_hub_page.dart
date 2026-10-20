import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/ui/count_up.dart';
import 'package:namer_app/pages/calorie_game_page.dart';
import 'package:namer_app/pages/higher_lower_page.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/calorie_game.dart';
import 'package:namer_app/services/calorie_sense.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/services/games_service.dart';
import 'package:namer_app/services/web_platform.dart' as web;
import 'package:namer_app/ui/game_level.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Games: your level, today's solo games and games with friends. Everything
/// here is about getting better at judging calories.
class GamesHubPage extends StatefulWidget {
  const GamesHubPage({super.key});

  @override
  State<GamesHubPage> createState() => _GamesHubPageState();
}

class _GamesHubPageState extends State<GamesHubPage> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final Stream<GamesProgress> _progress = GamesService.watch(_uid);
  late final Stream<List<CalorieGame>> _games =
      CalorieGameService.forUser(_uid);

  /// Finished friend games already asked for XP this visit.
  final Set<String> _claiming = {};

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  /// Friend games that finished while you were away earn their XP here.
  void _claimFinished(List<CalorieGame> games) {
    final todo = [
      for (final g in games)
        if (g.isFinished &&
            !g.xpClaimed.contains(_uid) &&
            _claiming.add(g.id))
          g
    ];
    if (todo.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      XpResult? last;
      int? first;
      for (final g in todo) {
        try {
          final r = await GamesService.claimFriendGame(g, _uid);
          if (r != null) {
            first ??= r.before;
            last = r;
          }
        } catch (_) {}
      }
      if (last != null && first != null && mounted) {
        await celebrateLevelUp(context, XpResult(first, last.after));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final day = GamesService.dayKey();
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('Games'),
        actions: [
          IconButton(
            tooltip: 'How XP works',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showXpRules(context),
          ),
        ],
      ),
      body: StreamBuilder<GamesProgress>(
        stream: _progress,
        builder: (context, snap) {
          final p = snap.data ?? const GamesProgress();
          final dailyDone = p.dailyDoneOn(day);
          final dailyStarted = p.dailyGuessesOn(day).isNotEmpty;
          final mealsLeft = p.mealXpRoundsLeft(day);
          final hlLeft = p.higherLowerXpRoundsLeft(day);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
                children: [
                  LevelCard(progress: p),
                  const _Heading('Play solo'),
                  _GameCard(
                    hero: true,
                    emoji: '📅',
                    title: 'Daily Calorie Quiz',
                    subtitle: dailyDone
                        ? 'Done today: ${p.dailyScoreOn(day)} of '
                            '${GamesService.dailyRounds * 100}. New foods '
                            'tomorrow.'
                        : dailyStarted
                            ? '${p.dailyGuessesOn(day).length} of '
                                '${GamesService.dailyRounds} guessed. Pick up '
                                'where you left off.'
                            : '${GamesService.dailyRounds} foods, the same for '
                                'everyone today. One go.',
                    action: dailyDone
                        ? 'Results'
                        : dailyStarted
                            ? 'Continue'
                            : 'Play',
                    done: dailyDone,
                    onTap: () =>
                        _open(const SoloGamePage(kind: SoloKind.daily)),
                  ),
                  _GameCard(
                    emoji: '🍽️',
                    title: 'Guess the Meal',
                    subtitle: 'How much did they eat? Real meals, nights out '
                        'and whole days. ${mealsLeft > 0 ? '$mealsLeft of ${Xp.mealRoundsPerDay} XP rounds left today.' : 'Practice only until tomorrow.'}',
                    action: 'Play',
                    onTap: () =>
                        _open(const SoloGamePage(kind: SoloKind.meals)),
                  ),
                  _GameCard(
                    emoji: '⚖️',
                    title: 'Higher or Lower',
                    subtitle: 'Which has more calories? '
                        '${GamesService.higherLowerPairs} quick pairs, with a '
                        'few surprises.'
                        '${p.hlBest > 0 ? ' Your best: ${p.hlBest}.' : ''} '
                        '${hlLeft > 0 ? '$hlLeft of ${Xp.higherLowerRoundsPerDay} XP rounds left today.' : 'Practice only until tomorrow.'}',
                    action: 'Play',
                    onTap: () => _open(const HigherLowerPage()),
                  ),
                  const _Heading('With friends'),
                  StreamBuilder<List<CalorieGame>>(
                    stream: _games,
                    builder: (context, gs) {
                      final games = gs.data ?? const <CalorieGame>[];
                      if (gs.hasData) _claimFinished(games);
                      final waiting =
                          CalorieGameService.waitingOn(_uid, games);
                      return _GameCard(
                        emoji: '🎯',
                        title: 'Challenge a friend',
                        subtitle: waiting > 0
                            ? '$waiting game${waiting == 1 ? '' : 's'} '
                                'waiting for you.'
                            : 'Mystery foods or Higher or Lower, played '
                                'whenever suits you. The winner earns bonus '
                                'XP.',
                        action: waiting > 0 ? 'Your turn' : 'Open',
                        highlight: waiting > 0,
                        onTap: () => _open(const CalorieGamesPage()),
                      );
                    },
                  ),
                  if (dailyDone) _FriendsToday(uid: _uid, day: day),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback onTap;
  final bool done;
  final bool highlight;

  /// The daily habit (the Daily Calorie Quiz): bigger, first.
  final bool hero;

  const _GameCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
    this.done = false,
    this.highlight = false,
    this.hero = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDecor.radius),
          side: BorderSide(
            color: highlight || hero ? AppColors.primary : AppColors.border,
            width: highlight || hero ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: hero
                ? const EdgeInsets.fromLTRB(16, 18, 14, 18)
                : const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: hero ? 60 : 48,
                  height: hero ? 60 : 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: hero ? null : AppColors.indigo50,
                    gradient: hero ? AppColors.brandGradient : null,
                    borderRadius: BorderRadius.circular(hero ? 18 : 14),
                  ),
                  child: Text(emoji,
                      style: TextStyle(fontSize: hero ? 32 : 26)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: hero ? 18 : 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: AppColors.gray600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                done
                    ? Icon(Icons.check_circle,
                        color: AppText.emerald600, size: 28)
                    : FilledButton(
                        onPressed: onTap,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryDark,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(action),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Friends who've done today's Calorie Quiz, best first. Only shown once you've
/// done it too, so nobody's put off (or spoiled).
class _FriendsToday extends StatefulWidget {
  final String uid;
  final String day;
  const _FriendsToday({required this.uid, required this.day});

  @override
  State<_FriendsToday> createState() => _FriendsTodayState();
}

class _FriendsTodayState extends State<_FriendsToday> {
  late final Future<List<({String uid, Map<String, dynamic>? user, int score})>>
      _rows = _load();

  Future<List<({String uid, Map<String, dynamic>? user, int score})>>
      _load() async {
    final ids = await FriendsService.friendIds(widget.uid);
    return GamesService.friendsDaily([...ids, widget.uid], widget.day);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _rows,
      builder: (context, snap) {
        final rows = snap.data;
        // Just you: nothing to compare yet.
        if (rows == null || rows.length < 2) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Heading("Today's Calorie Quiz with friends"),
            Container(
              decoration: AppDecor.card,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    ListTile(
                      dense: true,
                      leading: Text(
                        i == 0
                            ? '🥇'
                            : i == 1
                                ? '🥈'
                                : i == 2
                                    ? '🥉'
                                    : '${i + 1}',
                        style: const TextStyle(fontSize: 20),
                      ),
                      title: Text(
                        rows[i].uid == widget.uid
                            ? 'You'
                            : FriendsService.nameFromUser(rows[i].user),
                        style: TextStyle(
                          fontWeight: rows[i].uid == widget.uid
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      trailing: Text(
                        '${rows[i].score}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// Solo play: Daily Calorie Quiz, Guess the Meal and Guess your own day
// ============================================================================

/// [daily] is the Daily Calorie Quiz.
enum SoloKind { daily, meals, own }

/// One thing to guess.
class _Question {
  final String emoji;
  final String title;

  /// The portion (a food), or what kind of meal it is.
  final String subtitle;

  /// What was in it (a meal), shown without calories until the reveal.
  final List<MealItem> items;
  final int answer;

  const _Question({
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.items = const [],
    required this.answer,
  });

  bool get isMeal => items.isNotEmpty;
}

class SoloGamePage extends StatefulWidget {
  final SoloKind kind;
  const SoloGamePage({super.key, required this.kind});

  @override
  State<SoloGamePage> createState() => _SoloGamePageState();
}

class _SoloGamePageState extends State<SoloGamePage> {
  static const _seenKey = 'games_meals_seen';

  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _input = TextEditingController();
  final _focus = FocusNode();

  /// Puts the cursor in the guess box, once it's back on screen (it's
  /// swapped out while the answer shows), so on a computer you can just
  /// type the next guess and press Enter.
  void _focusGuess() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  /// The quiz's day, fixed when the page opens (it doesn't change under
  /// you at midnight).
  final String _day = GamesService.dayKey();

  List<_Question> _questions = const [];
  final List<int> _guesses = [];
  final List<int> _scores = [];
  final List<int> _xp = [];

  bool _loading = true;
  bool _saving = false;
  bool _revealed = false;

  /// This Guess the Meal round earns XP (the first few of the day).
  bool _earnsXp = false;

  GamesProgress _progress = const GamesProgress();
  String? _error;

  bool get _daily => widget.kind == SoloKind.daily;
  bool get _own => widget.kind == SoloKind.own;

  /// Whether a guess here earns XP (the quiz always does, once).
  bool get _showXp => _daily || _earnsXp;
  bool get _finished =>
      _questions.isNotEmpty && _guesses.length >= _questions.length && !_revealed;
  int get _index => _revealed ? _guesses.length - 1 : _guesses.length;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (_daily) {
        final foods = GamesService.dailyFoods(_day);
        _questions = [
          for (final f in foods)
            _Question(
                emoji: f.emoji,
                title: f.name,
                subtitle: f.portion,
                answer: f.kcal)
        ];
        _progress = await GamesService.watch(_uid).first;
        // Carry on from where you left off (or see today's results).
        for (final g in _progress.dailyGuessesOn(_day)) {
          if (_guesses.length >= _questions.length) break;
          final s = CalorieSense.score(
              g.toDouble(), _questions[_guesses.length].answer.toDouble());
          _guesses.add(g);
          _scores.add(s);
          _xp.add(Xp.forScore(s));
        }
        // The last guess also earned the bonus for finishing.
        if (_xp.length >= GamesService.dailyRounds) {
          _xp[_xp.length - 1] += Xp.dailyBonus;
        }
      } else if (_own) {
        await _loadOwnDay();
      } else {
        await _dealMeals();
      }
    } catch (_) {
      _error = "Couldn't load the game. Check your connection and try again.";
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (!_finished) _focusGuess();
  }

  Future<void> _loadOwnDay() async {
    final results = await Future.wait<Object?>([
      GamesService.loadOwnDay(_uid),
      GamesService.watch(_uid).first,
    ]);
    final own = results[0] as OwnDay?;
    _progress = results[1] as GamesProgress;
    _earnsXp = _progress.ownXpLeft(_day);
    if (own == null) {
      _error = 'Nothing to guess yet. Log at least '
          '${GamesService.ownDayMinFoods} foods in a day, then come back '
          'the next day to guess what it all came to.';
      return;
    }
    _questions = [
      _Question(
        emoji: '🪞',
        title: _dayName(own.day),
        subtitle: '${own.items.length} foods you logged. How many calories '
            'altogether?',
        items: own.items,
        answer: own.total,
      ),
    ];
  }

  /// "Yesterday", or "Thursday 8 Oct".
  String _dayName(DateTime d) {
    final today = DateTime(BalanceService.now().year,
        BalanceService.now().month, BalanceService.now().day);
    final that = DateTime(d.year, d.month, d.day);
    if (today.difference(that).inHours.round() <= 30) return 'Yesterday';
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', //
      'Saturday', 'Sunday',
    ];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  Future<void> _dealMeals() async {
    Set<String> seen = {};
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      seen = (prefs.getStringList(_seenKey) ?? const []).toSet();
    } catch (_) {}
    final meals = GamesService.dealMeals(avoid: seen);
    _questions = [
      for (final m in meals)
        _Question(
          emoji: m.emoji,
          title: m.title,
          subtitle: m.kind.label,
          items: m.items,
          answer: m.total,
        )
    ];
    // Remember the last few, so rounds don't repeat too soon.
    try {
      final recent = [
        ...meals.map((m) => m.id),
        ...(prefs?.getStringList(_seenKey) ?? const <String>[]),
      ].take(18).toList();
      await prefs?.setStringList(_seenKey, recent);
    } catch (_) {}
    // Practice until the server says this round counts.
    _earnsXp = false;
    _earnsXp = await GamesService.startMealRound(_uid);
    _progress = await GamesService.watch(_uid).first;
    GamesService.countPlay('meal');
  }

  Future<void> _playAgain() async {
    setState(() {
      _loading = true;
      _guesses.clear();
      _scores.clear();
      _xp.clear();
      _revealed = false;
      _error = null;
    });
    try {
      await _dealMeals();
    } catch (_) {
      _error = "Couldn't deal a new round. Try again.";
    }
    if (!mounted) return;
    setState(() => _loading = false);
    _focusGuess();
  }

  Future<void> _lockIn() async {
    if (_saving || _revealed || _finished) return;
    final guess = int.tryParse(_input.text.trim());
    if (guess == null) {
      setState(() => _error = 'Type your guess in calories first.');
      return;
    }
    final q = _questions[_guesses.length];
    final score = CalorieSense.score(guess.toDouble(), q.answer.toDouble());
    setState(() {
      _saving = true;
      _error = null;
    });
    XpResult result = XpResult.none;
    var xp = 0;
    try {
      if (_daily) {
        result = await GamesService.saveDailyGuess(
          uid: _uid,
          day: _day,
          index: _guesses.length,
          guess: guess,
          score: score,
        );
        xp = result.gained;
        if (_guesses.isEmpty) GamesService.countPlay('quiz');
        // The quiz is where your calorie sense score is earned now (it
        // used to be guesses in Add food).
        CalorieSense.record(_uid, score, giveXp: false)
            .catchError((_) {});
      } else if (_own) {
        result = await GamesService.saveOwnDay(
            _uid, _earnsXp ? Xp.forScore(score) : 0);
        xp = result.gained;
        GamesService.countPlay('own');
      } else if (_earnsXp) {
        xp = Xp.forScore(score);
        result = await GamesService.addXp(_uid, xp);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = "Couldn't save that guess. Check your connection and try "
            'again.';
      });
      return;
    }
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() {
      _guesses.add(guess);
      _scores.add(score);
      _xp.add(xp);
      _revealed = true;
      _saving = false;
      if (result.after > 0) {
        _progress = _progress.withXp(result.after, result.gained);
      }
    });
    _input.clear();
    await celebrateLevelUp(context, result);
  }

  void _next() {
    setState(() => _revealed = false);
    if (!_finished) _focusGuess();
  }

  Future<void> _share() async {
    final text = GamesService.shareLine(_day, _scores);
    const link = 'https://thecaloriecard.com/';
    final messenger = ScaffoldMessenger.of(context);
    var shared = false;
    try {
      shared = await web.shareText('Daily Calorie Quiz', text, link);
    } catch (_) {}
    if (shared) return;
    try {
      await Clipboard.setData(ClipboardData(text: '$text\n$link'));
      messenger.showSnackBar(
          const SnackBar(content: Text('Copied. Paste it to your friends.')));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final title = _daily
        ? 'Daily Calorie Quiz'
        : _own
            ? 'Guess your own day'
            : 'Guess the Meal';
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error ?? "Couldn't load the game.",
                        textAlign: TextAlign.center),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
                      children: _finished ? _summary() : _round(),
                    ),
                  ),
                ),
    );
  }

  List<Widget> _round() {
    final q = _questions[_index];
    final n = _questions.length;
    return [
      Row(
        children: [
          Text(
            '${_index + 1} of $n',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.gray700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (_guesses.length) / n,
                minHeight: 6,
                color: AppColors.primary,
                backgroundColor: AppColors.gray100,
              ),
            ),
          ),
        ],
      ),
      if (!_showXp) ...[
        const SizedBox(height: 8),
        Text(
          _own
              ? "Practice: you've had today's XP for this one."
              : "Practice round: you've had today's XP rounds.",
          style: TextStyle(fontSize: 12.5, color: AppColors.muted),
        ),
      ],
      const SizedBox(height: 14),
      _QuestionCard(question: q, revealed: _revealed),
      const SizedBox(height: 14),
      if (_revealed)
        _Reveal(
          question: q,
          guess: _guesses.last,
          score: _scores.last,
          xp: _xp.last,
          showXp: _showXp,
          // The quiz's finishing bonus comes with the last answer.
          bonus: _daily && _guesses.length >= n ? Xp.dailyBonus : 0,
          last: _guesses.length >= n,
          onNext: _next,
        )
      else ...[
        TextField(
          // A fresh box for each question, so nothing typed for the last
          // one can carry over (the browser keeps its own copy of the text).
          key: ValueKey('guess_${_guesses.length}'),
          controller: _input,
          focusNode: _focus,
          enabled: !_saving,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          decoration: InputDecoration(
            labelText: _own
                ? 'Your guess for the whole day'
                : q.isMeal
                    ? 'Your guess for all of it'
                    : 'Your guess',
            suffixText: 'kcal',
            border: const OutlineInputBorder(),
            errorText: _error,
          ),
          onSubmitted: (_) => _lockIn(),
          onEditingComplete: () {},
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _saving ? null : _lockIn,
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark),
            // Shows the number that will be locked in, so what's scored
            // is always what you see.
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _input,
              builder: (context, value, _) {
                final n = int.tryParse(value.text.trim());
                return Text(
                  _saving
                      ? 'Saving…'
                      : n == null
                          ? 'Lock it in'
                          : 'Lock in $n kcal',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                );
              },
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _summary() {
    final total = _scores.fold(0, (a, b) => a + b);
    final max = _questions.length * 100;
    final xp = _xp.fold(0, (a, b) => a + b);
    final average = _scores.isEmpty ? 0 : total ~/ _scores.length;
    final emoji = average >= 90
        ? '🏆'
        : average >= 75
            ? '🎯'
            : average >= 55
                ? '👍'
                : '🧐';
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: AppDecor.card,
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 6),
            Text(
              '$total / $max',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              CalorieSense.verdict(average),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.gray700,
              ),
            ),
            if (_showXp) ...[
              const SizedBox(height: 10),
              XpPill(xp),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      LevelCard(progress: _progress, compact: true),
      const SizedBox(height: 14),
      Container(
        decoration: AppDecor.card,
        child: Column(
          children: [
            for (var i = 0; i < _questions.length; i++)
              ListTile(
                leading: Text(_questions[i].emoji,
                    style: const TextStyle(fontSize: 24)),
                title: Text(
                  _questions[i].title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                subtitle: Text(
                  'You said ${_guesses[i]} · actually ${_questions[i].answer} kcal',
                  style: TextStyle(color: AppColors.gray600),
                ),
                trailing: Text(
                  '${_scores[i]}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: _scoreColor(_scores[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      if (_daily) ...[
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _share,
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark),
            icon: const Icon(Icons.ios_share),
            label: const Text('Share my score',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'New foods tomorrow. Try Guess the Meal in the meantime.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
      ] else if (_own)
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark),
            child: const Text('Back to Games',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        )
      else
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _playAgain,
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark),
            icon: const Icon(Icons.replay),
            label: const Text('Another round',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
    ];
  }
}

Color _scoreColor(int score) => score >= 90
    ? AppText.emerald600
    : score >= 70
        ? AppText.amber700
        : AppText.rose600;

class _QuestionCard extends StatelessWidget {
  final _Question question;
  final bool revealed;
  const _QuestionCard({required this.question, required this.revealed});

  @override
  Widget build(BuildContext context) {
    final q = question;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: AppDecor.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(q.emoji,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 8),
          Text(
            q.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            q.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.gray600),
          ),
          // A meal lists what was in it; the calories come at the reveal.
          if (q.isMeal && !revealed) ...[
            const SizedBox(height: 14),
            for (final item in q.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 30,
                      child: Text(item.emoji,
                          style: const TextStyle(fontSize: 18)),
                    ),
                    Expanded(
                      child: Text(
                        item.name,
                        style: TextStyle(fontSize: 14.5, color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Reveal extends StatelessWidget {
  final _Question question;
  final int guess;
  final int score;
  final int xp;
  final bool showXp;

  /// Part of [xp] that's a bonus (finishing the quiz), not for this guess.
  final int bonus;
  final bool last;
  final VoidCallback onNext;

  const _Reveal({
    required this.question,
    required this.guess,
    required this.score,
    required this.xp,
    required this.showXp,
    this.bonus = 0,
    required this.last,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final q = question;
    final diff = guess - q.answer;
    final items = q.isMeal
        ? ([...q.items]..sort((a, b) => b.kcal.compareTo(a.kcal)))
        : const <MealItem>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: AppDecor.card,
            child: Column(
              children: [
                // Counts from your guess to the real number.
                CountUp(
                  key: ValueKey(q),
                  from: guess,
                  value: q.answer,
                  format: (n) => '$n kcal',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  diff == 0
                      ? 'You said $guess. Exactly right!'
                      : 'You said $guess, ${diff.abs()} '
                          '${diff > 0 ? 'over' : 'under'}.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14.5, color: AppColors.gray700),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$score/100 · ${CalorieSense.verdict(score)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _scoreColor(score),
                      ),
                    ),
                    if (showXp) ...[
                      const SizedBox(width: 10),
                      XpPill(xp),
                    ],
                  ],
                ),
                // Say where XP came from, so "Way off" with XP makes sense.
                if (showXp && bonus > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    xp - bonus > 0
                        ? 'Includes +$bonus XP for finishing the quiz'
                        : '+$bonus XP for finishing the quiz',
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: AppDecor.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Where the calories were',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < items.length; i++)
                  _BreakdownRow(
                    item: items[i],
                    share: q.answer == 0 ? 0 : items[i].kcal / q.answer,
                    biggest: i == 0 && items.length > 1,
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: onNext,
            autofocus: true,
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.primaryDark),
            child: Text(
              last ? 'See results' : 'Next',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final MealItem item;
  final double share;
  final bool biggest;
  const _BreakdownRow(
      {required this.item, required this.share, required this.biggest});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Text(item.emoji, style: const TextStyle(fontSize: 17)),
              ),
              Expanded(
                child: Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: biggest ? FontWeight.w800 : FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${item.kcal}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: biggest ? AppText.rose600 : AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share.clamp(0.0, 1.0),
                minHeight: 5,
                color: biggest ? AppColors.rose400 : AppColors.indigo300,
                backgroundColor: AppColors.gray100,
              ),
            ),
          ),
          if (biggest)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 3),
              child: Text(
                'The biggest part: ${(share * 100).round()}% of the total',
                style: TextStyle(fontSize: 12, color: AppText.rose600),
              ),
            ),
        ],
      ),
    );
  }
}
