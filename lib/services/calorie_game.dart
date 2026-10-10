import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/calorie_sense.dart';
import 'package:namer_app/services/chat_service.dart';

/// One food in Guess the Calories, with its real calories.
///
/// Values are from the brand's UK label, or USDA / UK reference data for
/// unbranded food, rounded to the nearest calorie.
class GameFood {
  final String emoji;
  final String name;
  final String portion;
  final int kcal;

  const GameFood(this.emoji, this.name, this.portion, this.kcal);

  Map<String, dynamic> toMap() =>
      {'emoji': emoji, 'name': name, 'portion': portion, 'kcal': kcal};

  static GameFood fromMap(dynamic m) {
    final map = m is Map ? m : const {};
    return GameFood(
      '${map['emoji'] ?? '🍽️'}',
      '${map['name'] ?? 'Mystery food'}',
      '${map['portion'] ?? ''}',
      (BalanceService.number(map['kcal']) ?? 0).round(),
    );
  }
}

/// The foods games are dealt from.
const List<GameFood> kGameFoods = [
  // Fruit and veg
  GameFood('🍌', 'Banana', '1 medium (118g)', 105),
  GameFood('🍎', 'Apple', '1 medium (182g)', 95),
  GameFood('🍐', 'Pear', '1 medium (178g)', 101),
  GameFood('🍊', 'Orange', '1 medium (131g)', 62),
  GameFood('🍇', 'Grapes', 'A handful (80g)', 53),
  GameFood('🍓', 'Strawberries', 'A handful (80g)', 26),
  GameFood('🥑', 'Avocado', 'Half (68g)', 114),
  GameFood('🥕', 'Carrot', '1 medium (61g)', 25),
  GameFood('🥦', 'Broccoli', '80g', 27),
  // Breakfast
  GameFood('🥚', 'Boiled egg', '1 large', 78),
  GameFood('🍳', 'Fried egg', '1 large', 90),
  GameFood('🥣', 'Porridge oats', '40g, made with water', 150),
  GameFood('🥣', 'Weetabix', '2 biscuits', 136),
  GameFood('🥣', 'Cornflakes', '30g, no milk', 113),
  GameFood('🍞', 'White bread', '1 medium slice (36g)', 85),
  GameFood('🥐', 'Butter croissant', '1 (57g)', 231),
  GameFood('🍯', 'Honey', '1 teaspoon (7g)', 21),
  // Staples
  GameFood('🍚', 'White rice', '150g cooked', 195),
  GameFood('🍝', 'Spaghetti', '200g cooked', 316),
  GameFood('🥔', 'Baked potato', '200g, plain', 186),
  GameFood('🍗', 'Grilled chicken breast', '150g', 248),
  GameFood('🐟', 'Baked salmon fillet', '120g', 247),
  // Dairy, fats and nuts
  GameFood('🧀', 'Cheddar', '30g (a matchbox)', 125),
  GameFood('🧈', 'Butter', '10g (a thin spread)', 74),
  GameFood('🫒', 'Olive oil', '1 tablespoon', 119),
  GameFood('🥜', 'Peanut butter', '1 tablespoon (16g)', 94),
  GameFood('🌰', 'Almonds', '30g', 174),
  GameFood('🥛', 'Semi-skimmed milk', '200ml', 100),
  GameFood('🥛', 'Whole milk', '200ml', 128),
  // Snacks and sweets
  GameFood('🍫', 'Mars bar', '1 bar (51g)', 228),
  GameFood('🍫', 'Snickers', '1 bar (48g)', 245),
  GameFood('🍫', 'Twix', '2 fingers (50g)', 250),
  GameFood('🍫', 'Cadbury Dairy Milk', '1 bar (45g)', 240),
  GameFood('🍫', 'Maltesers', '1 bag (37g)', 187),
  GameFood('🍪', 'McVitie\'s Digestive', '1 biscuit', 71),
  GameFood('🍪', 'Chocolate digestive', '1 biscuit', 83),
  GameFood('🍪', 'Oreo', '1 biscuit', 53),
  GameFood('🍊', 'Jaffa Cake', '1 cake', 46),
  // Out and about
  GameFood('🍔', 'McDonald\'s Big Mac', '1 burger', 508),
  GameFood('🍟', 'McDonald\'s fries', '1 medium portion', 337),
  GameFood('🥐', 'Greggs sausage roll', '1 roll', 327),
  GameFood('🌱', 'Greggs vegan sausage roll', '1 roll', 312),
  // Drinks
  GameFood('🥤', 'Coca-Cola', '1 can (330ml)', 139),
  GameFood('🥤', 'Diet Coke', '1 can (330ml)', 1),
  GameFood('🍺', 'Lager (4%)', '1 pint', 182),
  GameFood('🍺', 'Guinness', '1 pint', 210),
  GameFood('🍷', 'Red wine', '1 medium glass (175ml)', 159),
  GameFood('🥂', 'Prosecco', '1 glass (125ml)', 86),
];

enum GameStatus { active, finished }

/// A game of Guess the Calories between two friends, stored in
/// `calorie_games/{id}`:
///   player_ids: [a, b]        names: {a: 'sam', b: 'taz'}
///   foods: [{emoji, name, portion, kcal}, ...]
///   guesses: {a: [250, 90], b: []}     (one per food, in order)
///   status: 'active' | 'finished'      winner: uid | 'draw' | null
class CalorieGame {
  final String id;
  final List<String> playerIds;
  final Map<String, String> names;
  final String createdBy;
  final List<GameFood> foods;
  final Map<String, List<int>> guesses;
  final GameStatus status;
  final String? winner;
  final DateTime? updatedAt;

  const CalorieGame({
    required this.id,
    required this.playerIds,
    required this.names,
    required this.createdBy,
    required this.foods,
    required this.guesses,
    required this.status,
    required this.winner,
    required this.updatedAt,
  });

  bool get isFinished => status == GameStatus.finished;
  bool get isDraw => winner == CalorieGameService.draw;

  String opponentOf(String uid) =>
      playerIds.firstWhere((p) => p != uid, orElse: () => '');

  String nameOf(String uid) => names[uid] ?? 'Your friend';

  List<int> guessesOf(String uid) => guesses[uid] ?? const [];

  /// How many foods [uid] has guessed.
  int progressOf(String uid) => min(guessesOf(uid).length, foods.length);

  bool doneBy(String uid) => progressOf(uid) >= foods.length;

  /// The next food [uid] has to guess, or null when they're done.
  int? nextFoodFor(String uid) => doneBy(uid) ? null : progressOf(uid);

  /// 0-100 for each food [uid] has guessed so far.
  List<int> roundScoresOf(String uid) {
    final g = guessesOf(uid);
    return [
      for (var i = 0; i < min(g.length, foods.length); i++)
        CalorieSense.score(g[i].toDouble(), foods[i].kcal.toDouble())
    ];
  }

  int scoreOf(String uid) => roundScoresOf(uid).fold(0, (a, b) => a + b);

  int get maxScore => foods.length * 100;

  factory CalorieGame.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final rawNames = d['names'];
    final rawGuesses = d['guesses'];
    final updated = d['updated_at'];
    return CalorieGame(
      id: doc.id,
      playerIds: [for (final p in (d['player_ids'] as List? ?? const [])) '$p'],
      names: {
        if (rawNames is Map)
          for (final e in rawNames.entries) '${e.key}': '${e.value}'
      },
      createdBy: '${d['created_by'] ?? ''}',
      foods: [
        for (final f in (d['foods'] as List? ?? const [])) GameFood.fromMap(f)
      ],
      guesses: {
        if (rawGuesses is Map)
          for (final e in rawGuesses.entries)
            '${e.key}': [
              for (final g in (e.value is List ? e.value as List : const []))
                (BalanceService.number(g) ?? 0).round()
            ]
      },
      status: d['status'] == 'finished' ? GameStatus.finished : GameStatus.active,
      winner: d['winner'] as String?,
      updatedAt: updated is Timestamp ? updated.toDate() : null,
    );
  }
}

/// Your head-to-head record against one friend.
class GameRecord {
  final int wins;
  final int losses;
  final int draws;

  const GameRecord(this.wins, this.losses, this.draws);

  int get played => wins + losses + draws;
}

class CalorieGameService {
  CalorieGameService._();

  static const rounds = 5;
  static const draw = 'draw';

  static CollectionReference<Map<String, dynamic>> get _col =>
      BalanceService.db.collection('calorie_games');

  /// [rounds] different foods, at random.
  static List<GameFood> deal([Random? random]) {
    final pool = [...kGameFoods]..shuffle(random ?? Random());
    return pool.take(rounds).toList();
  }

  /// Starts a game with [friendId] and lets them know in your chat.
  static Future<String> create({
    required String uid,
    required String myName,
    required String friendId,
    required String friendName,
    Random? random,
    bool notify = true,
  }) async {
    if (friendId.isEmpty || friendId == uid) {
      throw ArgumentError('Pick a friend to play');
    }
    final ref = await _col.add({
      'player_ids': [uid, friendId],
      'names': {uid: myName, friendId: friendName},
      'created_by': uid,
      'foods': [for (final f in deal(random)) f.toMap()],
      'guesses': {uid: <int>[], friendId: <int>[]},
      'status': 'active',
      'winner': null,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    if (notify) {
      await _tell(uid, myName, friendId, friendName,
          "🎯 I've challenged you to Guess the Calories! Find it in Friends.");
    }
    return ref.id;
  }

  /// Live updates for one game.
  static Stream<CalorieGame?> watch(String id) => _col
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? CalorieGame.fromDoc(d) : null);

  /// Your games: ones waiting for you first, then ones waiting for your
  /// friend, then finished ones (newest first).
  static Stream<List<CalorieGame>> forUser(String uid) => _col
      .where('player_ids', arrayContains: uid)
      .snapshots()
      .map((snap) => sortForUser(
          uid, [for (final d in snap.docs) CalorieGame.fromDoc(d)]));

  static List<CalorieGame> sortForUser(String uid, List<CalorieGame> games) {
    int group(CalorieGame g) => g.isFinished ? 2 : (g.doneBy(uid) ? 1 : 0);
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return [...games]..sort((a, b) {
        final byGroup = group(a).compareTo(group(b));
        if (byGroup != 0) return byGroup;
        return (b.updatedAt ?? epoch).compareTo(a.updatedAt ?? epoch);
      });
  }

  /// Games still waiting for [uid] to guess.
  static int waitingOn(String uid, List<CalorieGame> games) =>
      games.where((g) => !g.isFinished && !g.doneBy(uid)).length;

  /// Saves [uid]'s guess for their next food. When that's the last guess
  /// from both players, the game finishes and the winner is set.
  /// Returns the updated game.
  static Future<CalorieGame> guess({
    required String gameId,
    required String uid,
    required int kcal,
    bool notify = true,
  }) async {
    final ref = _col.doc(gameId);
    late CalorieGame after;
    var finishedNow = false;
    await BalanceService.db.runTransaction<void>((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('This game has been deleted');
      final game = CalorieGame.fromDoc(snap);
      if (!game.playerIds.contains(uid)) throw StateError('Not your game');
      if (game.isFinished || game.doneBy(uid)) {
        after = game;
        finishedNow = false;
        return;
      }
      final mine = [...game.guessesOf(uid), max(0, kcal)];
      final guesses = {...game.guesses, uid: mine};
      after = CalorieGame(
        id: game.id,
        playerIds: game.playerIds,
        names: game.names,
        createdBy: game.createdBy,
        foods: game.foods,
        guesses: guesses,
        status: game.status,
        winner: game.winner,
        updatedAt: game.updatedAt,
      );
      final everyoneDone = game.playerIds.every(after.doneBy);
      final winner = everyoneDone ? winnerOf(after) : null;
      finishedNow = everyoneDone;
      if (everyoneDone) {
        after = CalorieGame(
          id: game.id,
          playerIds: game.playerIds,
          names: game.names,
          createdBy: game.createdBy,
          foods: game.foods,
          guesses: guesses,
          status: GameStatus.finished,
          winner: winner,
          updatedAt: game.updatedAt,
        );
      }
      tx.update(ref, {
        'guesses.$uid': mine,
        'updated_at': FieldValue.serverTimestamp(),
        if (everyoneDone) ...{
          'status': 'finished',
          'winner': winner,
          'finished_at': FieldValue.serverTimestamp(),
        },
      });
    });

    // You finished it: tell your friend how it went.
    if (notify && finishedNow) {
      final other = after.opponentOf(uid);
      final me = after.scoreOf(uid), them = after.scoreOf(other);
      final line = after.isDraw
          ? "🎯 Guess the Calories: it's a draw, $me each!"
          : after.winner == uid
              ? '🏆 I won Guess the Calories, $me to $them!'
              : '🏆 You won Guess the Calories, $them to $me!';
      await _tell(uid, after.nameOf(uid), other, after.nameOf(other), line);
    }
    return after;
  }

  /// The player with the higher total, or [draw].
  static String winnerOf(CalorieGame g) {
    if (g.playerIds.length < 2) return draw;
    final a = g.playerIds[0], b = g.playerIds[1];
    final sa = g.scoreOf(a), sb = g.scoreOf(b);
    if (sa == sb) return draw;
    return sa > sb ? a : b;
  }

  /// Your wins, losses and draws against [friendId] in [games].
  static GameRecord recordAgainst(
      String uid, String friendId, List<CalorieGame> games) {
    var w = 0, l = 0, d = 0;
    for (final g in games) {
      if (!g.isFinished || !g.playerIds.contains(friendId)) continue;
      if (!g.playerIds.contains(uid)) continue;
      if (g.isDraw) {
        d++;
      } else if (g.winner == uid) {
        w++;
      } else {
        l++;
      }
    }
    return GameRecord(w, l, d);
  }

  /// A friendly "your turn" in your chat with the other player.
  static Future<void> nudge(CalorieGame g, String uid) {
    final other = g.opponentOf(uid);
    return _tell(uid, g.nameOf(uid), other, g.nameOf(other),
        '🎯 Your turn in Guess the Calories!');
  }

  /// Removes a game that hasn't finished (finished ones stay in the record).
  static Future<void> cancel(CalorieGame g) async {
    if (g.isFinished) return;
    await _col.doc(g.id).delete();
  }

  /// Chat messages are a nice extra: the game works without them.
  static Future<void> _tell(String uid, String myName, String friendId,
      String friendName, String text) async {
    try {
      await ChatService.sendToFriend(
        uid: uid,
        myName: myName,
        friendId: friendId,
        friendName: friendName,
        text: text,
      );
    } catch (_) {}
  }
}
