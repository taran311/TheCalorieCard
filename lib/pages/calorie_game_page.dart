import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/calorie_game.dart';
import 'package:namer_app/services/calorie_sense.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/services/games_service.dart';
import 'package:namer_app/services/notification_service.dart';
import 'package:namer_app/ui/game_food_picker.dart';
import 'package:namer_app/ui/game_level.dart';
import 'package:namer_app/ui/responsive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Your name as friends see it: your display name if you set one.
Future<String> _myName() {
  final user = FirebaseAuth.instance.currentUser;
  return FriendsService.nameFor(user?.uid ?? '', email: user?.email);
}

/// A game being started, so a double tap doesn't start two.
bool _startingGame = false;

/// One line on each kind of game, the same everywhere it's offered.
String _modeBlurb(GameMode mode) => mode == GameMode.classic
    ? 'You both guess the same ${CalorieGameService.rounds} everyday foods.'
    : "You each pick ${CalorieGameService.rounds} things you've eaten. You "
        'guess theirs, they guess yours.';

/// Starts a game with a friend and opens it.
///
/// Always asks which kind of game first (a game can't start without one),
/// with [mode] preselected if given. [confirm] is kept so existing callers
/// (the Friends list) work unchanged: either way the choice sheet is the
/// confirmation. For "Guess what I ate" you pick your 5 foods before the
/// game is created, so backing out leaves no half-made game.
Future<void> startCalorieGame(
  BuildContext context, {
  required String friendId,
  required String friendName,
  bool confirm = false,
  GameMode? mode,
}) async {
  await _startGame(context,
      friendId: friendId, friendName: friendName, initial: mode);
}

/// [startCalorieGame], and Rematch ([replace] swaps the finished game's
/// page for the new one). True when a game was started.
Future<bool> _startGame(
  BuildContext context, {
  required String friendId,
  required String friendName,
  GameMode? initial,
  bool replace = false,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || _startingGame) return false;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  _startingGame = true;
  try {
    final mode = await showModalBottomSheet<GameMode>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ModeSheet(
        friendName: friendName,
        initial: initial ?? GameMode.classic,
      ),
    );
    if (mode == null) return false;
    List<GameFood>? picks;
    if (mode == GameMode.swap) {
      picks = await navigator.push(
        GameFoodPicker.route(uid: uid, friendName: friendName),
      );
      if (picks == null || picks.length != CalorieGameService.rounds) {
        return false;
      }
    }
    final id = await CalorieGameService.create(
      uid: uid,
      myName: await _myName(),
      friendId: friendId,
      friendName: friendName,
      mode: mode,
      picks: picks,
    );
    GamesService.countPlay('friends');
    final route =
        MaterialPageRoute<void>(builder: (_) => CalorieGamePage(gameId: id));
    if (replace) {
      navigator.pushReplacement(route);
    } else {
      navigator.push(route);
    }
    return true;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text("Couldn't start the game. Please try again.")));
    return false;
  } finally {
    _startingGame = false;
  }
}

/// "Guess the Calories with Sam": the two kinds of game, then Start.
class _ModeSheet extends StatefulWidget {
  final String friendName;
  final GameMode initial;

  const _ModeSheet({required this.friendName, required this.initial});

  @override
  State<_ModeSheet> createState() => _ModeSheetState();
}

class _ModeSheetState extends State<_ModeSheet> {
  late GameMode _mode = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Guess the Calories with ${widget.friendName}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pick a game. You each play whenever suits you, and the '
              'closest guesses win.',
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: AppColors.gray600,
              ),
            ),
            const SizedBox(height: 16),
            for (final m in GameMode.values) ...[
              _ModeCard(
                mode: m,
                selected: _mode == m,
                onTap: () => setState(() => _mode = m),
              ),
              const SizedBox(height: 10),
            ],
            if (_mode == GameMode.swap)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  "Next, you'll pick your ${CalorieGameService.rounds} "
                  'foods.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.gray600),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_mode),
                child: const Text(
                  'Start',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One big choice on the [_ModeSheet].
class _ModeCard extends StatelessWidget {
  final GameMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '${mode.title}. ${_modeBlurb(mode)}',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.indigo50 : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDecor.radius),
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              children: [
                Text(mode.emoji, style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _modeBlurb(mode),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: AppColors.gray700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? AppText.primary : AppColors.gray400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Ends Friday": when a game runs out if nobody moves.
String _endsLabel(DateTime end, DateTime now) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  // Hours, not inDays: a day with a clock change is 23 or 25 hours long.
  final days = (BalanceService.startOfDay(end)
              .difference(BalanceService.startOfDay(now))
              .inHours /
          24)
      .round();
  if (days <= 0) return 'Ends today';
  if (days == 1) return 'Ends tomorrow';
  final day = weekdays[end.weekday - 1];
  // A week away is the same weekday as today.
  return days >= 7 ? 'Ends next $day' : 'Ends $day';
}

/// The line a game that ran out of time ends with, from [uid]'s side.
String _endedLine(CalorieGame game, String uid) {
  final other = game.opponentOf(uid);
  final name = game.nameOf(other);
  final winner = game.isFinished
      ? game.winner
      : CalorieGameService.expiredWinnerOf(game);
  if (winner == uid) return "This game ended: $name didn't finish in time";
  if (winner == other) return "This game ended: you didn't finish in time";
  return 'This game ended before anyone finished';
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

  /// Stale games already asked to end, so each is only asked once.
  final Set<String> _expiring = {};

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

  /// Ends games nobody has moved in for a week (after this frame: no
  /// writes in the middle of a build). The list updates by itself.
  void _expireStale(List<CalorieGame> games, DateTime now) {
    final stale = [
      for (final g in games)
        if (g.isStaleAt(now) && _expiring.add(g.id)) g
    ];
    if (stale.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final g in stale) {
        CalorieGameService.expireIfStale(g, _uid);
      }
    });
  }

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
          final now = BalanceService.now();
          _expireStale(games, now);
          bool ended(CalorieGame g) => g.isFinished || g.isStaleAt(now);
          final yourTurn = [
            for (final g in games)
              if (!ended(g) && g.isTurnOf(_uid)) g
          ];
          final waiting = [
            for (final g in games)
              if (!ended(g) && !g.isTurnOf(_uid)) g
          ];
          final finished = [
            for (final g in games)
              if (ended(g)) g
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
    final body = TextStyle(
      color: Colors.white.withValues(alpha: 0.92),
      fontSize: 13,
      height: 1.35,
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(AppDecor.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                Text('Two ways to play with a friend:', style: body),
                const SizedBox(height: 4),
                for (final m in GameMode.values)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('${m.label}: ${_modeBlurb(m)}', style: body),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Play whenever suits you. The closer you are, the more '
                  'points (up to 100 a food). The winner is revealed once '
                  "you've both finished. A game ends 7 days after the last "
                  'move.',
                  style: body,
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
    final now = BalanceService.now();

    // The same wording as the banner on the game itself.
    final String subtitle;
    final Color accent;
    final IconData icon;
    if (game.expired || (!game.isFinished && game.isStaleAt(now))) {
      final winner = game.isFinished
          ? game.winner
          : CalorieGameService.expiredWinnerOf(game);
      if (winner == uid) {
        subtitle = "Ended · $name didn't finish";
        accent = AppText.emerald600;
      } else if (winner == other) {
        subtitle = "Ended · you didn't finish";
        accent = AppText.rose600;
      } else {
        subtitle = 'Ended · nobody finished';
        accent = AppColors.gray600;
      }
      icon = Icons.timer_off_outlined;
    } else if (game.isFinished) {
      final score = '${game.scoreOf(uid)}–${game.scoreOf(other)}';
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
    } else if (game.needsPickFrom(uid)) {
      subtitle = 'Your turn · pick your ${CalorieGameService.rounds} foods';
      accent = AppText.primary;
      icon = Icons.play_circle_fill;
    } else if (game.needsPickFrom(other)) {
      subtitle = 'Waiting for $name to pick';
      accent = AppText.amber700;
      icon = Icons.hourglass_top;
    } else if (!game.doneBy(uid)) {
      subtitle = 'Your turn · ${game.progressOf(uid)} of '
          '${game.totalFor(uid)} guessed';
      accent = AppText.primary;
      icon = Icons.play_circle_fill;
    } else {
      subtitle = 'Waiting for $name · ${game.progressOf(other)} of '
          '${game.totalFor(other)}';
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
                const SizedBox(width: 8),
                Tooltip(
                  message: game.mode.title,
                  child: Text(
                    game.mode.emoji,
                    semanticsLabel: game.mode.title,
                    style: const TextStyle(fontSize: 22),
                  ),
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

/// Playing one game: pick your foods (Guess what I ate), guess each food,
/// see how close you were, then wait for your friend. A banner at the top
/// always says whose turn it is. Updates live, so if you're both playing
/// at once you see each other's progress and the result the moment the
/// last guess lands.
///
/// Works opened cold from a link or a notification, for either player,
/// even if the game has since been cancelled.
class CalorieGamePage extends StatefulWidget {
  final String gameId;

  const CalorieGamePage({super.key, required this.gameId});

  @override
  State<CalorieGamePage> createState() => _CalorieGamePageState();
}

class _CalorieGamePageState extends State<CalorieGamePage> {
  /// Read each time: opened cold from a link, sign-in may finish after
  /// this page is created.
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
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
  bool _picking = false;
  bool _nudged = false;
  String? _error;

  /// A stale game is only asked to end once.
  bool _expireRequested = false;

  /// "Get a notification when it's your turn", while you wait.
  bool _offerAlerts = false;
  bool _alertsBusy = false;
  static const _alertsDismissedKey = 'calorie_game_alerts_offer_dismissed';

  @override
  void initState() {
    super.initState();
    _loadAlertsOffer();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Offer turn alerts if this device can have them, they aren't on, and
  /// the offer hasn't been dismissed here.
  Future<void> _loadAlertsOffer() async {
    if (!NotificationService.supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_alertsDismissedKey) == true) return;
      final settings = await NotificationService.load();
      if (!mounted || settings.gameAlerts) return;
      setState(() => _offerAlerts = true);
    } catch (_) {
      // No offer: the switch is still in the reminder settings.
    }
  }

  Future<void> _dismissAlerts() async {
    setState(() => _offerAlerts = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_alertsDismissedKey, true);
    } catch (_) {}
  }

  Future<void> _turnOnAlerts() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _alertsBusy = true);
    final error = await NotificationService.enableGameAlerts();
    if (!mounted) return;
    setState(() {
      _alertsBusy = false;
      if (error == null) _offerAlerts = false;
    });
    messenger.showSnackBar(SnackBar(
      content: Text(error ?? "Done. We'll let you know when it's your turn."),
    ));
  }

  /// Ends the game if nobody has moved in time (after this frame: no
  /// writes in the middle of a build). The stream then shows the result.
  void _maybeExpire(CalorieGame game) {
    if (_expireRequested || !game.isStaleAt(BalanceService.now())) return;
    _expireRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CalorieGameService.expireIfStale(game, _uid);
    });
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

  /// Opens the picker, saves your 5 foods, and the game moves straight on
  /// to guessing (or waiting, if your friend hasn't picked yet).
  Future<void> _pickFoods(CalorieGame game) async {
    if (_picking) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _picking = true);
    try {
      final picks = await navigator.push(GameFoodPicker.route(
        uid: _uid,
        friendName: game.nameOf(game.opponentOf(_uid)),
      ));
      if (picks == null || picks.length != CalorieGameService.rounds) return;
      await CalorieGameService.pick(game.id, _uid, picks);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't save your foods. Please try again.")));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
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

  /// Same friend, same kind of game (it can be changed on the sheet).
  Future<void> _rematch(CalorieGame game) async {
    final other = game.opponentOf(_uid);
    await _startGame(
      context,
      friendId: other,
      friendName: game.nameOf(other),
      initial: game.mode,
      replace: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CalorieGame?>(
      stream: _game,
      builder: (context, snap) {
        final raw = snap.data;
        // Someone else's game (an old link) reads as unavailable.
        final game =
            raw != null && raw.playerIds.contains(_uid) ? raw : null;
        if (game != null) _maybeExpire(game);
        final open = game != null &&
            !game.isFinished &&
            !game.isStaleAt(BalanceService.now());
        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(
            toolbarHeight: game == null ? null : 64,
            title: game == null
                ? const Text('Guess the Calories')
                : _AppBarTitle(game: game, uid: _uid),
            actions: [
              if (game != null && open)
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
      return const _Unavailable(
        message: "Couldn't load this game. It may have ended or been "
            "cancelled, or you're offline.",
      );
    }
    if (snap.connectionState == ConnectionState.waiting && snap.data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (game == null) {
      return const _Unavailable(
        message: 'This game has ended or was cancelled.',
      );
    }

    final now = BalanceService.now();
    final other = game.opponentOf(_uid);
    final foods = game.foodsFor(_uid);

    final Widget content;
    final String step;
    if (_revealing != null && _revealing! < foods.length) {
      content = _reveal(game, _revealing!);
      step = 'reveal-$_revealing';
    } else if (_saving && _answering != null && _answering! < foods.length) {
      content = _question(game, _answering!);
      step = 'question-$_answering';
    } else if (game.isFinished) {
      step = 'result';
      content = _Result(
        game: game,
        uid: _uid,
        onRematch: () => _rematch(game),
      );
    } else if (game.isStaleAt(now)) {
      // Being ended: the result follows in a moment.
      step = 'ending';
      content = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (game.needsPickFrom(_uid)) {
      step = 'pick';
      content = _pickIntro(game);
    } else if (game.needsPickFrom(other)) {
      step = 'waiting-pick';
      content = _waitingForPick(game);
    } else if (game.doneBy(_uid) || game.nextFoodFor(_uid) == null) {
      step = 'waiting';
      content = _waiting(game);
    } else {
      final index = game.nextFoodFor(_uid)!;
      step = 'question-$index';
      content = _question(game, index);
    }

    final banner = _banner(game, now);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (banner != null) ...[
                banner,
                const SizedBox(height: 14),
              ],
              if (!game.isFinished && !game.isStaleAt(now) && game.ready) ...[
                _Progress(game: game, uid: _uid),
                const SizedBox(height: 16),
              ],
              AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 250),
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

  /// Always one line saying whose turn it is and what to do next (none
  /// once the game has a normal result: the result says it all).
  Widget? _banner(CalorieGame game, DateTime now) {
    final other = game.opponentOf(_uid);
    final name = game.nameOf(other);
    if (game.isFinished) {
      if (!game.expired) return null;
      return _StatusBanner(tone: _Tone.ended, text: _endedLine(game, _uid));
    }
    if (game.isStaleAt(now)) {
      return _StatusBanner(tone: _Tone.ended, text: _endedLine(game, _uid));
    }
    if (game.needsPickFrom(_uid)) {
      return _StatusBanner(
        tone: _Tone.yourTurn,
        text: 'Your turn: pick ${CalorieGameService.rounds} foods for $name '
            'to guess',
        action: SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _picking ? null : () => _pickFoods(game),
            icon: const Icon(Icons.restaurant_menu),
            label: const Text('Pick my foods'),
          ),
        ),
      );
    }
    if (game.needsPickFrom(other)) {
      return _StatusBanner(
        tone: _Tone.waiting,
        text: 'Waiting for $name to pick their foods',
        action: _nudgeButton(game, name),
      );
    }
    if (!game.doneBy(_uid)) {
      final total = game.totalFor(_uid);
      return _StatusBanner(
        tone: _Tone.yourTurn,
        text: 'Your turn: ${total - game.progressOf(_uid)} of $total to '
            'guess',
      );
    }
    return _StatusBanner(
      tone: _Tone.waiting,
      text: 'Waiting for $name to finish (${game.progressOf(other)} of '
          '${game.totalFor(other)})',
      action: _nudgeButton(game, name),
    );
  }

  Widget _nudgeButton(CalorieGame game, String name) {
    return OutlinedButton.icon(
      onPressed: _nudged ? null : () => _nudge(game),
      icon: const Icon(Icons.notifications_active_outlined),
      label: Text(
        _nudged ? 'Nudge sent' : 'Nudge $name',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// "🔔 Get a notification when it's your turn", on the waiting screens.
  Widget _alertsCard() {
    if (!_offerAlerts) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        decoration: AppDecor.card,
        child: Row(
          children: [
            const ExcludeSemantics(
              child: Text('🔔', style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Get a notification when it's your turn",
                style: TextStyle(fontSize: 14, color: AppColors.ink),
              ),
            ),
            TextButton(
              onPressed: _alertsBusy ? null : _turnOnAlerts,
              child: const Text('Turn on'),
            ),
            IconButton(
              onPressed: _dismissAlerts,
              tooltip: 'Not now',
              icon: Icon(Icons.close, size: 20, color: AppColors.gray600),
            ),
          ],
        ),
      ),
    );
  }

  /// Your turn to pick: what this game is, in a couple of lines. The
  /// button is on the banner above.
  Widget _pickIntro(CalorieGame game) {
    final name = game.nameOf(game.opponentOf(_uid));
    final rounds = CalorieGameService.rounds;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecor.card,
      child: Column(
        children: [
          Text(GameMode.swap.emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          Text(
            GameMode.swap.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            game.hasPicked(game.opponentOf(_uid))
                ? "$name has picked $rounds foods they've eaten. Pick "
                    "$rounds of yours, then you'll guess the calories in "
                    "$name's while $name guesses yours. The higher total wins."
                : "Pick $rounds foods you've eaten. $name guesses their "
                    "calories, and you guess $name's. The higher total wins.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.gray600),
          ),
        ],
      ),
    );
  }

  /// You've picked; your friend hasn't yet.
  Widget _waitingForPick(CalorieGame game) {
    final name = game.nameOf(game.opponentOf(_uid));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "You'll start guessing as soon as $name has picked their foods.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.gray600),
        ),
        const SizedBox(height: 14),
        _GuessTable(
          title: 'Your foods for $name to guess',
          foods: game.picksOf(_uid),
        ),
        _alertsCard(),
      ],
    );
  }

  Widget _foodCard(CalorieGame game, GameFood food, int index) {
    final total = game.totalFor(_uid);
    final label = game.isSwap
        ? "${game.nameOf(game.opponentOf(_uid))}'s food ${index + 1} of $total"
        : 'Food ${index + 1} of $total';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: AppDecor.card,
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
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
          if (food.portion.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              food.portion,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: AppColors.gray600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _question(CalorieGame game, int index) {
    final food = game.foodsFor(_uid)[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _foodCard(game, food, index),
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
    final food = game.foodsFor(_uid)[index];
    final guesses = game.guessesOf(_uid);
    final guess =
        index < guesses.length ? guesses[index] : (_lastGuess ?? 0);
    final score = CalorieSense.score(guess.toDouble(), food.kcal.toDouble());
    final last = index >= game.totalFor(_uid) - 1;
    final color = score >= 85
        ? AppText.emerald600
        : score >= 50
            ? AppText.amber700
            : AppText.rose600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _foodCard(game, food, index),
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

  /// You've guessed all yours; your friend is still going.
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
                'You scored ${game.scoreOf(_uid)} out of ${game.maxScore}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "You'll find out who won as soon as $name finishes. Stay on "
                'this screen to see it happen, or come back later.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.gray600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (game.isSwap)
          _GuessTable(
            title: "$name's foods: your guesses",
            foods: game.foodsFor(_uid),
            guesses: game.guessesOf(_uid),
            scores: game.roundScoresOf(_uid),
            guesser: 'You',
            onlyGuessed: true,
          )
        else
          _AnswersTable(game: game, uid: _uid, showFriend: false),
        _alertsCard(),
      ],
    );
  }
}

/// A game that's gone (cancelled, or an old link): say so, and offer the
/// way to your other games, so a link is never a dead end.
class _Unavailable extends StatelessWidget {
  final String message;

  const _Unavailable({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎯', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppColors.ink),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                    builder: (_) => const CalorieGamesPage()),
              ),
              child: const Text('See your games'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "vs Sam", with the kind of game and when it ends underneath.
class _AppBarTitle extends StatelessWidget {
  final CalorieGame game;
  final String uid;

  const _AppBarTitle({required this.game, required this.uid});

  @override
  Widget build(BuildContext context) {
    final now = BalanceService.now();
    final end = game.endsAt;
    final ends = !game.isFinished && !game.isStaleAt(now) && end != null
        ? _endsLabel(end, now)
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'vs ${game.nameOf(game.opponentOf(uid))}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.indigo50,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  game.mode.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppText.primary,
                  ),
                ),
              ),
            ),
            if (ends != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  ends,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.gray600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

enum _Tone { yourTurn, waiting, ended }

/// The one line at the top of a game: whose turn it is, or how it ended.
class _StatusBanner extends StatelessWidget {
  final _Tone tone;
  final String text;
  final Widget? action;

  const _StatusBanner({required this.tone, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final IconData icon;
    if (tone == _Tone.yourTurn) {
      bg = AppColors.indigo50;
      fg = AppText.primary;
      icon = Icons.play_circle_fill;
    } else if (tone == _Tone.waiting) {
      bg = AppColors.amber50;
      fg = AppText.amber700;
      icon = Icons.hourglass_top;
    } else {
      bg = AppColors.gray100;
      fg = AppColors.gray700;
      icon = Icons.timer_off_outlined;
    }
    final act = action;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDecor.radius),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: fg, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                      color: tone == _Tone.ended ? AppColors.ink : fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (act != null) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: act),
          ],
        ],
      ),
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
    Widget lane(String label, int done, int total, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label  $done/$total',
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
                  value: total == 0 ? 0 : done / total,
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
        lane('You', game.progressOf(uid), game.totalFor(uid),
            AppColors.primary),
        const SizedBox(width: 16),
        lane(game.nameOf(other), game.progressOf(other), game.totalFor(other),
            AppColors.violet),
      ],
    );
  }
}

/// One player's foods with the real calories and, when [guesser] is set,
/// the guesses made for them and the points (out of 100 a food). With
/// [onlyGuessed], foods not guessed yet stay hidden.
class _GuessTable extends StatelessWidget {
  final String title;
  final List<GameFood> foods;
  final List<int> guesses;
  final List<int> scores;
  final String? guesser;
  final bool onlyGuessed;

  const _GuessTable({
    required this.title,
    required this.foods,
    this.guesses = const [],
    this.scores = const [],
    this.guesser,
    this.onlyGuessed = false,
  });

  @override
  Widget build(BuildContext context) {
    final who = guesser;
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
    final total = scores.fold<int>(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: AppDecor.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (who != null && scores.isNotEmpty)
                Text(
                  '$total pts',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppText.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
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
              if (who != null)
                Expanded(
                  flex: 4,
                  child: cell(who, bold: true, color: AppColors.gray600),
                ),
            ],
          ),
          const Divider(height: 16),
          for (var i = 0; i < foods.length; i++)
            if (!onlyGuessed || i < guesses.length)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        '${foods[i].emoji} ${foods[i].name}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: AppColors.ink),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: cell('${foods[i].kcal}', bold: true),
                    ),
                    if (who != null)
                      Expanded(
                        flex: 4,
                        child: i < guesses.length && i < scores.length
                            ? cell(
                                '${guesses[i]} (${scores[i]})',
                                bold: scores[i] >= 85,
                                color: scores[i] >= 85
                                    ? AppText.emerald600
                                    : null,
                              )
                            : cell('–', color: AppColors.gray400),
                      ),
                  ],
                ),
              ),
          if (who != null) ...[
            const SizedBox(height: 4),
            Text(
              'Points in brackets, out of 100 a food',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.gray600),
            ),
          ],
        ],
      ),
    );
  }
}


/// Food by food: the real calories and each guess. [showFriend] is only
/// true once the game is over. Mystery foods only, where both players
/// guess the same [CalorieGame.foods] (swap games use [_GuessTable]).
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
  void initState() {
    super.initState();
    // Your Games XP for this game, once (nothing happens if it's had).
    if (!widget.game.xpClaimed.contains(widget.uid)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final r = await GamesService.claimFriendGame(widget.game, widget.uid);
          if (r != null && mounted) await celebrateLevelUp(context, r);
        } catch (_) {}
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final uid = widget.uid;
    final other = game.opponentOf(uid);
    final name = game.nameOf(other);
    final won = game.winner == uid;

    final String emoji;
    final String headline;
    // Games that ran out of time say why they ended.
    String? note;
    if (game.expired) {
      if (game.isDraw) {
        emoji = '⏱️';
        headline = 'Out of time';
        note = 'Neither of you finished in time.';
      } else if (won) {
        emoji = '🏆';
        headline = 'You win!';
        note = "$name didn't finish in time, so you win.";
      } else {
        emoji = '⏱️';
        headline = '$name wins';
        note = "You didn't finish in time, so $name wins.";
      }
    } else if (game.isDraw) {
      emoji = '🤝';
      headline = "It's a draw!";
    } else if (won) {
      emoji = '🏆';
      headline = 'You win!';
    } else {
      emoji = '🥈';
      headline = '$name wins';
    }
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final emojiText = Text(emoji, style: const TextStyle(fontSize: 64));

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
              if (reduceMotion)
                emojiText
              else
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.4, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (context, s, child) =>
                      Transform.scale(scale: s, child: child),
                  child: emojiText,
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
              if (note != null) ...[
                const SizedBox(height: 4),
                Text(
                  note,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
              const SizedBox(height: 12),
              XpPill(Xp.forFriendGame(game, uid)),
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
        if (game.isSwap) ...[
          // Each player's own foods, with the other's guesses.
          _swapSection(
            title: 'Your foods — $name guessed',
            foods: game.picksOf(uid),
            guesses: game.guessesOf(other),
            scores: game.roundScoresOf(other),
            guesser: name,
            missing: "$name didn't get to guess any of your foods.",
            empty: "You didn't pick any foods.",
          ),
          const SizedBox(height: 12),
          _swapSection(
            title: "$name's foods — you guessed",
            foods: game.picksOf(other),
            guesses: game.guessesOf(uid),
            scores: game.roundScoresOf(uid),
            guesser: 'You',
            missing: "You didn't get to guess any of $name's foods.",
            empty: "$name didn't pick any foods.",
          ),
        ] else
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  /// One player's foods in a swap game. A game that ran out of time may
  /// have no foods ([empty]) or no guesses ([missing]) to show.
  Widget _swapSection({
    required String title,
    required List<GameFood> foods,
    required List<int> guesses,
    required List<int> scores,
    required String guesser,
    required String missing,
    required String empty,
  }) {
    if (foods.isEmpty || guesses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: AppDecor.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              foods.isEmpty ? empty : missing,
              style: TextStyle(fontSize: 13, color: AppColors.gray600),
            ),
          ],
        ),
      );
    }
    return _GuessTable(
      title: title,
      foods: foods,
      guesses: guesses,
      scores: scores,
      guesser: guesser,
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
