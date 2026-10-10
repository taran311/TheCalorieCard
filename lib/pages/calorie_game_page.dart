import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/calorie_game.dart';
import 'package:namer_app/services/calorie_sense.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/ui/responsive.dart';

String _myName() =>
    FriendsService.displayName(FirebaseAuth.instance.currentUser?.email);

/// A game being started, so a double tap doesn't start two.
bool _startingGame = false;

/// Starts a game with a friend and opens it. With [confirm], asks first
/// (used by the one-tap button in the Friends list).
Future<void> startCalorieGame(
  BuildContext context, {
  required String friendId,
  required String friendName,
  bool confirm = false,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  if (_startingGame) return;
  if (confirm) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guess the Calories 🎯'),
        content: Text(
          'Challenge $friendName? You both guess the calories in the same '
          "${CalorieGameService.rounds} foods, and we'll tell $friendName "
          "it's their turn.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Let's play"),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  _startingGame = true;
  try {
    final id = await CalorieGameService.create(
      uid: uid,
      myName: _myName(),
      friendId: friendId,
      friendName: friendName,
    );
    navigator.push(
      MaterialPageRoute(builder: (_) => CalorieGamePage(gameId: id)),
    );
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text("Couldn't start the game. Please try again.")));
  } finally {
    _startingGame = false;
  }
}

// ============================================================================
// Your games
// ============================================================================

/// All your Guess the Calories games: whose turn it is, and results.
class CalorieGamesPage extends StatefulWidget {
  const CalorieGamesPage({super.key});

  @override
  State<CalorieGamesPage> createState() => _CalorieGamesPageState();
}

class _CalorieGamesPageState extends State<CalorieGamesPage> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  /// Created once: building it in build() would re-subscribe every rebuild.
  late final Stream<List<CalorieGame>> _games =
      CalorieGameService.forUser(_uid);

  Future<void> _newGame() async {
    final friend = await showModalBottomSheet<Friend>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PickFriendSheet(uid: _uid),
    );
    if (friend == null || !mounted) return;
    await startCalorieGame(context,
        friendId: friend.id, friendName: friend.name);
  }

  void _open(CalorieGame g) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CalorieGamePage(gameId: g.id)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('Guess the Calories')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'calorie-game-new',
        onPressed: _newGame,
        icon: const Icon(Icons.add),
        label: const Text('New game'),
      ),
      body: StreamBuilder<List<CalorieGame>>(
        stream: _games,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text("Couldn't load your games."));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final games = snap.data!;
          final yourTurn = [
            for (final g in games)
              if (!g.isFinished && !g.doneBy(_uid)) g
          ];
          final waiting = [
            for (final g in games)
              if (!g.isFinished && g.doneBy(_uid)) g
          ];
          final finished = [
            for (final g in games)
              if (g.isFinished) g
          ].take(20).toList();

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
                children: [
                  const _HowToPlay(),
                  if (games.isEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'No games yet. Tap New game to challenge a friend.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.gray600),
                    ),
                  ],
                  if (yourTurn.isNotEmpty) ...[
                    const _Heading('Your turn'),
                    for (final g in yourTurn)
                      _GameTile(game: g, uid: _uid, onTap: () => _open(g)),
                  ],
                  if (waiting.isNotEmpty) ...[
                    const _Heading('Waiting for your friend'),
                    for (final g in waiting)
                      _GameTile(game: g, uid: _uid, onTap: () => _open(g)),
                  ],
                  if (finished.isNotEmpty) ...[
                    const _Heading('Finished'),
                    for (final g in finished)
                      _GameTile(game: g, uid: _uid, onTap: () => _open(g)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HowToPlay extends StatelessWidget {
  const _HowToPlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppDecor.radius),
      ),
      child: Row(
        children: [
          const Text('🎯', style: TextStyle(fontSize: 34)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How it works',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "You and a friend both guess the calories in the same "
                  "${CalorieGameService.rounds} foods, whenever suits you. "
                  "The closer you are, the more points (up to 100 a food). "
                  "The winner's revealed once you've both finished.",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
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
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  final CalorieGame game;
  final String uid;
  final VoidCallback onTap;

  const _GameTile({required this.game, required this.uid, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final other = game.opponentOf(uid);
    final name = game.nameOf(other);
    final total = game.foods.length;

    final String subtitle;
    final Color accent;
    final IconData icon;
    if (game.isFinished) {
      final score = '${game.scoreOf(uid)} – ${game.scoreOf(other)}';
      if (game.isDraw) {
        subtitle = 'Draw · $score';
        accent = AppColors.gray600;
        icon = Icons.handshake_outlined;
      } else if (game.winner == uid) {
        subtitle = 'You won · $score';
        accent = AppText.emerald600;
        icon = Icons.emoji_events;
      } else {
        subtitle = '$name won · $score';
        accent = AppText.rose600;
        icon = Icons.emoji_events_outlined;
      }
    } else if (!game.doneBy(uid)) {
      subtitle = 'Your turn · ${game.progressOf(uid)}/$total guessed';
      accent = AppText.primary;
      icon = Icons.play_circle_fill;
    } else {
      subtitle = '$name is on ${game.progressOf(other)}/$total';
      accent = AppText.amber700;
      icon = Icons.hourglass_top;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDecor.radius),
          side: BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Icon(icon, color: accent, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'vs $name',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  game.foods.map((f) => f.emoji).join(),
                  style: const TextStyle(fontSize: 14),
                ),
                Icon(Icons.chevron_right, color: AppColors.gray400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickFriendSheet extends StatefulWidget {
  final String uid;
  const _PickFriendSheet({required this.uid});

  @override
  State<_PickFriendSheet> createState() => _PickFriendSheetState();
}

class _PickFriendSheetState extends State<_PickFriendSheet> {
  late Future<List<Friend>> _friends = FriendsService.load(widget.uid);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: FutureBuilder<List<Friend>>(
          future: _friends,
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Couldn't load your friends."),
                    TextButton(
                      onPressed: () => setState(() {
                        _friends = FriendsService.load(widget.uid);
                      }),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final friends = snap.data!;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Who do you want to play?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                if (friends.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Add a friend first, then challenge them here.',
                      style: TextStyle(color: AppColors.gray600),
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        for (final f in friends)
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.indigo50,
                              child: Text(
                                f.name.isEmpty ? '?' : f.name[0].toUpperCase(),
                                style: TextStyle(
                                  color: AppText.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(f.name),
                            trailing: const Text('🎯'),
                            onTap: () => Navigator.of(context).pop(f),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// One game
// ============================================================================

/// Playing one game: guess each food, see how close you were, then wait for
/// your friend. Updates live, so if you're both playing at once you see each
/// other's progress and the result the moment the last guess lands.
class CalorieGamePage extends StatefulWidget {
  final String gameId;

  const CalorieGamePage({super.key, required this.gameId});

  @override
  State<CalorieGamePage> createState() => _CalorieGamePageState();
}

class _CalorieGamePageState extends State<CalorieGamePage> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _input = TextEditingController();
  final _focus = FocusNode();

  late final Stream<CalorieGame?> _game =
      CalorieGameService.watch(widget.gameId);

  /// The food you've just guessed, shown with its answer until you tap Next.
  int? _revealing;

  /// The food being saved, and the guess you gave for it. The live game can
  /// move on before the save returns, so these keep the screen steady.
  int? _answering;
  int? _lastGuess;
  bool _saving = false;
  bool _nudged = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit(CalorieGame game) async {
    if (_saving) return;
    final index = game.nextFoodFor(_uid);
    if (index == null) return;
    final value = int.tryParse(_input.text.trim());
    if (value == null || value < 0 || value > 5000) {
      setState(() => _error = 'Enter a number of calories (0 to 5000).');
      return;
    }
    setState(() {
      _saving = true;
      _answering = index;
      _lastGuess = value;
      _error = null;
    });
    try {
      await CalorieGameService.guess(
          gameId: game.id, uid: _uid, kcal: value);
      if (!mounted) return;
      _input.clear();
      setState(() => _revealing = index);
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't save your guess. Try again.");
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _next() {
    setState(() => _revealing = null);
    _focus.requestFocus();
  }

  Future<void> _nudge(CalorieGame game) async {
    setState(() => _nudged = true);
    await CalorieGameService.nudge(game, _uid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sent ${game.nameOf(game.opponentOf(_uid))} a nudge')));
  }

  Future<void> _cancel(CalorieGame game) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this game?'),
        content: const Text("It'll disappear for both of you."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep playing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel game'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    try {
      await CalorieGameService.cancel(game);
      navigator.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Couldn't cancel the game. Try again.")));
      }
    }
  }

  Future<void> _rematch(CalorieGame game) async {
    final other = game.opponentOf(_uid);
    final navigator = Navigator.of(context);
    try {
      final id = await CalorieGameService.create(
        uid: _uid,
        myName: _myName(),
        friendId: other,
        friendName: game.nameOf(other),
      );
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => CalorieGamePage(gameId: id)),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Couldn't start a rematch. Try again.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CalorieGame?>(
      stream: _game,
      builder: (context, snap) {
        final game = snap.data;
        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(
            title: Text(game == null
                ? 'Guess the Calories'
                : 'vs ${game.nameOf(game.opponentOf(_uid))}'),
            actions: [
              if (game != null && !game.isFinished)
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (_) => _cancel(game),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'cancel', child: Text('Cancel game')),
                  ],
                ),
            ],
          ),
          body: _body(snap, game),
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<CalorieGame?> snap, CalorieGame? game) {
    if (snap.hasError) {
      return const Center(child: Text("Couldn't load this game."));
    }
    if (snap.connectionState == ConnectionState.waiting && game == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (game == null) {
      return const Center(child: Text('This game was cancelled.'));
    }

    final Widget content;
    final String step;
    if (_revealing != null && _revealing! < game.foods.length) {
      content = _reveal(game, _revealing!);
      step = 'reveal-$_revealing';
    } else if (_saving &&
        _answering != null &&
        _answering! < game.foods.length) {
      content = _question(game, _answering!);
      step = 'question-$_answering';
    } else if (game.isFinished) {
      step = 'result';
      content = _Result(
        game: game,
        uid: _uid,
        onRematch: () => _rematch(game),
      );
    } else if (game.doneBy(_uid)) {
      step = 'waiting';
      content = _waiting(game);
    } else {
      final index = game.nextFoodFor(_uid)!;
      step = 'question-$index';
      content = _question(game, index);
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!game.isFinished) ...[
                _Progress(game: game, uid: _uid),
                const SizedBox(height: 16),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: KeyedSubtree(
                  key: ValueKey(step),
                  child: content,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _foodCard(GameFood food, int index, int total) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: AppDecor.card,
      child: Column(
        children: [
          Text(
            'Food ${index + 1} of $total',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.gray600,
            ),
          ),
          const SizedBox(height: 10),
          Text(food.emoji, style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 8),
          Text(
            food.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            food.portion,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: AppColors.gray600),
          ),
        ],
      ),
    );
  }

  Widget _question(CalorieGame game, int index) {
    final food = game.foods[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _foodCard(food, index, game.foods.length),
        const SizedBox(height: 18),
        Text(
          'How many calories?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: SizedBox(
            width: 200,
            child: TextField(
              controller: _input,
              focusNode: _focus,
              autofocus: true,
              enabled: !_saving,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              decoration: InputDecoration(
                hintText: '0',
                suffixText: 'kcal',
                errorText: _error,
                errorMaxLines: 2,
              ),
              onSubmitted: (_) => _submit(game),
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _saving ? null : () => _submit(game),
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text(
                    'Lock it in',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "${game.nameOf(game.opponentOf(_uid))} won't see your guesses "
          'until you have both finished.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.gray600),
        ),
      ],
    );
  }

  Widget _reveal(CalorieGame game, int index) {
    final food = game.foods[index];
    final guesses = game.guessesOf(_uid);
    final guess =
        index < guesses.length ? guesses[index] : (_lastGuess ?? 0);
    final score = CalorieSense.score(guess.toDouble(), food.kcal.toDouble());
    final last = index >= game.foods.length - 1;
    final color = score >= 85
        ? AppText.emerald600
        : score >= 50
            ? AppText.amber700
            : AppText.rose600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _foodCard(food, index, game.foods.length),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: AppDecor.card,
          child: Column(
            children: [
              Text(
                CalorieSense.verdict(score),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Figure(label: 'Actually', value: '${food.kcal}'),
                  ),
                  Expanded(
                    child: _Figure(label: 'You said', value: '$guess'),
                  ),
                  Expanded(
                    child: _Figure(
                      label: 'Points',
                      value: '+$score',
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: FilledButton(
            autofocus: true,
            onPressed: _next,
            child: Text(
              last ? 'Finish' : 'Next food',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  Widget _waiting(CalorieGame game) {
    final other = game.opponentOf(_uid);
    final name = game.nameOf(other);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: AppDecor.card,
          child: Column(
            children: [
              const Text('⏳', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              Text(
                'Waiting for $name',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "You scored ${game.scoreOf(_uid)} out of ${game.maxScore}. "
                "You'll find out who won as soon as $name finishes. "
                'Stay on this screen to see it happen.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.gray600),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _nudged ? null : () => _nudge(game),
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(_nudged ? 'Nudge sent' : 'Nudge $name'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _AnswersTable(game: game, uid: _uid, showFriend: false),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _Figure({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.gray600)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color ?? AppColors.ink,
          ),
        ),
      ],
    );
  }
}

/// You and your friend's progress, updating live.
class _Progress extends StatelessWidget {
  final CalorieGame game;
  final String uid;

  const _Progress({required this.game, required this.uid});

  @override
  Widget build(BuildContext context) {
    final other = game.opponentOf(uid);
    Widget lane(String label, int done, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label  $done/${game.foods.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.gray700,
                ),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: game.foods.isEmpty ? 0 : done / game.foods.length,
                  minHeight: 6,
                  color: color,
                  backgroundColor: AppColors.gray100,
                ),
              ),
            ],
          ),
        );
    return Row(
      children: [
        lane('You', game.progressOf(uid), AppColors.primary),
        const SizedBox(width: 16),
        lane(game.nameOf(other), game.progressOf(other), AppColors.violet),
      ],
    );
  }
}

/// Food by food: the real calories and each guess. [showFriend] is only
/// true once the game is over.
class _AnswersTable extends StatelessWidget {
  final CalorieGame game;
  final String uid;
  final bool showFriend;

  const _AnswersTable({
    required this.game,
    required this.uid,
    required this.showFriend,
  });

  @override
  Widget build(BuildContext context) {
    final other = game.opponentOf(uid);
    final mine = game.guessesOf(uid);
    final theirs = game.guessesOf(other);
    final myScores = game.roundScoresOf(uid);
    final theirScores = game.roundScoresOf(other);

    Widget cell(String text,
            {bool bold = false, Color? color, TextAlign? align}) =>
        Text(
          text,
          textAlign: align ?? TextAlign.right,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            color: color ?? AppColors.ink,
          ),
        );

    Widget guessCell(List<int> g, List<int> s, int i, bool best) {
      if (i >= g.length) return cell('–', color: AppColors.gray400);
      return cell(
        '${g[i]} (${s[i]})',
        bold: best,
        color: best ? AppText.emerald600 : null,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: AppDecor.card,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 5,
                child: cell('Food',
                    bold: true, color: AppColors.gray600, align: TextAlign.left),
              ),
              Expanded(
                flex: 3,
                child: cell('Actual', bold: true, color: AppColors.gray600),
              ),
              Expanded(
                flex: 4,
                child: cell('You', bold: true, color: AppColors.gray600),
              ),
              if (showFriend)
                Expanded(
                  flex: 4,
                  child: cell(game.nameOf(other),
                      bold: true, color: AppColors.gray600),
                ),
            ],
          ),
          const Divider(height: 16),
          for (var i = 0; i < game.foods.length; i++)
            if (i < mine.length || showFriend)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        '${game.foods[i].emoji} ${game.foods[i].name}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: AppColors.ink),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: cell('${game.foods[i].kcal}', bold: true),
                    ),
                    Expanded(
                      flex: 4,
                      child: guessCell(
                        mine,
                        myScores,
                        i,
                        showFriend &&
                            i < myScores.length &&
                            (i >= theirScores.length ||
                                myScores[i] > theirScores[i]),
                      ),
                    ),
                    if (showFriend)
                      Expanded(
                        flex: 4,
                        child: guessCell(
                          theirs,
                          theirScores,
                          i,
                          i < theirScores.length &&
                              (i >= myScores.length ||
                                  theirScores[i] > myScores[i]),
                        ),
                      ),
                  ],
                ),
              ),
          const SizedBox(height: 4),
          Text(
            'Points in brackets, out of 100 a food',
            style: TextStyle(fontSize: 11, color: AppColors.gray600),
          ),
        ],
      ),
    );
  }
}

/// The big reveal: who won, the scores, everyone's guesses, your record.
class _Result extends StatefulWidget {
  final CalorieGame game;
  final String uid;
  final Future<void> Function() onRematch;

  const _Result({
    required this.game,
    required this.uid,
    required this.onRematch,
  });

  @override
  State<_Result> createState() => _ResultState();
}

class _ResultState extends State<_Result> {
  late final Stream<List<CalorieGame>> _all =
      CalorieGameService.forUser(widget.uid);
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final uid = widget.uid;
    final other = game.opponentOf(uid);
    final name = game.nameOf(other);
    final won = game.winner == uid;

    final String emoji;
    final String headline;
    if (game.isDraw) {
      emoji = '🤝';
      headline = "It's a draw!";
    } else if (won) {
      emoji = '🏆';
      headline = 'You win!';
    } else {
      emoji = '🥈';
      headline = '$name wins';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(AppDecor.radius),
          ),
          child: Column(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.4, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (context, s, child) =>
                    Transform.scale(scale: s, child: child),
                child: Text(emoji, style: const TextStyle(fontSize: 64)),
              ),
              const SizedBox(height: 6),
              Text(
                headline,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _ScoreBlock(
                      label: 'You',
                      score: game.scoreOf(uid),
                      max: game.maxScore,
                      highlight: won || game.isDraw,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ScoreBlock(
                      label: name,
                      score: game.scoreOf(other),
                      max: game.maxScore,
                      highlight: !won,
                    ),
                  ),
                ],
              ),
              StreamBuilder<List<CalorieGame>>(
                stream: _all,
                builder: (context, snap) {
                  if (!snap.hasData) return const SizedBox.shrink();
                  final r =
                      CalorieGameService.recordAgainst(uid, other, snap.data!);
                  if (r.played < 2) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Text(
                      'Your record vs $name: ${r.wins} won · ${r.losses} lost'
                      '${r.draws > 0 ? ' · ${r.draws} drawn' : ''}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _AnswersTable(game: game, uid: uid, showFriend: true),
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _starting
                ? null
                : () async {
                    setState(() => _starting = true);
                    await widget.onRematch();
                    // Still here means it didn't start: allow another go.
                    if (mounted) setState(() => _starting = false);
                  },
            icon: const Icon(Icons.replay),
            label: Text(
              'Rematch $name',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScoreBlock extends StatelessWidget {
  final String label;
  final int score;
  final int max;
  final bool highlight;

  const _ScoreBlock({
    required this.label,
    required this.score,
    required this.max,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: highlight ? 0.24 : 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '$score',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'out of $max',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
