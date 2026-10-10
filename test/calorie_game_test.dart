// Guess the Calories: dealing foods, hidden guesses, finishing and the
// head-to-head record.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/calorie_game.dart';

import 'test_helpers.dart';

const me = TestWorld.uid;
const friend = TestWorld.otherUid;

void main() {
  late TestWorld w;

  setUp(() {
    w = TestWorld()..install();
  });

  tearDown(TestWorld.uninstall);

  Future<String> newGame({bool notify = false}) => CalorieGameService.create(
        uid: me,
        myName: 'me',
        friendId: friend,
        friendName: 'sam',
        random: Random(1),
        notify: notify,
      );

  Future<CalorieGame> load(String id) async =>
      CalorieGame.fromDoc(await w.db.collection('calorie_games').doc(id).get());

  /// Guesses each food's real calories plus [offset].
  Future<CalorieGame> playAll(String id, String uid, {int offset = 0}) async {
    var g = await load(id);
    for (final f in g.foods) {
      g = await CalorieGameService.guess(
          gameId: id, uid: uid, kcal: f.kcal + offset, notify: false);
    }
    return g;
  }

  test('the food bank has sensible, distinct foods', () {
    expect(kGameFoods.length, greaterThanOrEqualTo(40));
    final names = kGameFoods.map((f) => '${f.name}|${f.portion}').toSet();
    expect(names.length, kGameFoods.length);
    for (final f in kGameFoods) {
      expect(f.kcal, inInclusiveRange(0, 1500), reason: f.name);
    }
  });

  test('a new game deals 5 different foods to both players', () async {
    final id = await newGame();
    final g = await load(id);
    expect(g.playerIds, [me, friend]);
    expect(g.foods.length, CalorieGameService.rounds);
    expect(g.foods.map((f) => f.name).toSet().length, CalorieGameService.rounds);
    expect(g.isFinished, isFalse);
    expect(g.nextFoodFor(me), 0);
    expect(g.nameOf(friend), 'sam');
  });

  test("can't start a game with yourself", () {
    expect(
      () => CalorieGameService.create(
          uid: me, myName: 'me', friendId: me, friendName: 'me', notify: false),
      throwsArgumentError,
    );
  });

  test('guesses go in order, and stop once you have guessed every food',
      () async {
    final id = await newGame();
    await CalorieGameService.guess(
        gameId: id, uid: me, kcal: 100, notify: false);
    await CalorieGameService.guess(
        gameId: id, uid: me, kcal: 100, notify: false);
    var g = await load(id);
    // Equal guesses are both kept (not merged like a set).
    expect(g.guessesOf(me), [100, 100]);
    expect(g.nextFoodFor(me), 2);

    g = await playAll(id, me);
    expect(g.doneBy(me), isTrue);
    expect(g.guessesOf(me).length, CalorieGameService.rounds);
    // One more is ignored.
    await CalorieGameService.guess(gameId: id, uid: me, kcal: 1, notify: false);
    expect((await load(id)).guessesOf(me).length, CalorieGameService.rounds);
  });

  test('the game only finishes, with a winner, once both have played',
      () async {
    final id = await newGame();
    var g = await playAll(id, me); // spot on: 100 a food
    expect(g.isFinished, isFalse);
    expect((await load(id)).winner, isNull);

    g = await playAll(id, friend, offset: 40);
    expect(g.isFinished, isTrue);
    final saved = await load(id);
    expect(saved.isFinished, isTrue);
    expect(saved.winner, me);
    expect(saved.scoreOf(me), 500);
    expect(saved.scoreOf(friend), lessThan(500));
  });

  test('the same total is a draw', () async {
    final id = await newGame();
    await playAll(id, me, offset: 10);
    await playAll(id, friend, offset: 10);
    final g = await load(id);
    expect(g.winner, CalorieGameService.draw);
    expect(g.isDraw, isTrue);
  });

  test('sorting puts games waiting for you first, then waiting on them',
      () async {
    final waitingOnFriend = await newGame();
    await playAll(waitingOnFriend, me);
    final myTurn = await newGame();
    final done = await newGame();
    await playAll(done, me);
    await playAll(done, friend);

    final games = await CalorieGameService.forUser(me).first;
    expect(games.map((g) => g.id).toList(), [myTurn, waitingOnFriend, done]);
    expect(CalorieGameService.waitingOn(me, games), 1);
    expect(CalorieGameService.waitingOn(friend, games), 2);
  });

  test('head-to-head record counts finished games only', () async {
    final a = await newGame();
    await playAll(a, me);
    await playAll(a, friend, offset: 50); // I win
    final b = await newGame();
    await playAll(b, me, offset: 50);
    await playAll(b, friend); // they win
    final c = await newGame();
    await playAll(c, me); // unfinished

    final games = await CalorieGameService.forUser(me).first;
    final r = CalorieGameService.recordAgainst(me, friend, games);
    expect((r.wins, r.losses, r.draws), (1, 1, 0));
    expect(games.where((g) => g.id == c).single.isFinished, isFalse);
  });

  test('cancelling removes an unfinished game but not a finished one',
      () async {
    final open = await newGame();
    await CalorieGameService.cancel(await load(open));
    expect((await w.db.collection('calorie_games').doc(open).get()).exists,
        isFalse);

    final over = await newGame();
    await playAll(over, me);
    await playAll(over, friend);
    await CalorieGameService.cancel(await load(over));
    expect((await w.db.collection('calorie_games').doc(over).get()).exists,
        isTrue);
  });

  test('starting a game and finishing it post in your chat', () async {
    final id = await newGame(notify: true);
    final g = await load(id);
    for (final f in g.foods) {
      await CalorieGameService.guess(gameId: id, uid: me, kcal: f.kcal);
    }
    for (final f in g.foods) {
      await CalorieGameService.guess(gameId: id, uid: friend, kcal: f.kcal * 2);
    }
    final convo = await w.db
        .collection('conversations')
        .doc(me.compareTo(friend) < 0 ? '${me}_$friend' : '${friend}_$me')
        .collection('messages')
        .get();
    final texts = convo.docs.map((d) => d['message'] as String).toList();
    expect(texts.any((t) => t.contains('challenged you')), isTrue);
    expect(texts.any((t) => t.contains('You won Guess the Calories')), isTrue);
    // Each one links to the game, so the chat can open it.
    for (final d in convo.docs) {
      expect(d['type'], 'game');
      expect(d['game_id'], id);
    }
  });
}
