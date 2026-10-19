// Guess the Calories: dealing foods, hidden guesses, finishing and the
// head-to-head record; "Guess what I ate" (swap) games; ending games
// nobody moves in; and the "your turn" requests to the server.

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/calorie_game.dart';
import 'package:namer_app/services/statement_service.dart';

import 'test_helpers.dart';

const me = TestWorld.uid;
const friend = TestWorld.otherUid;

/// The 5 foods each player picks in a swap game.
final myPicks = kGameFoods.sublist(0, 5);
final theirPicks = kGameFoods.sublist(5, 10);

void main() {
  late TestWorld w;

  /// Requests that would have gone to the server, as {path, ...body}.
  final sent = <Map<String, dynamic>>[];

  setUp(() {
    w = TestWorld()..install();
    sent.clear();
    CalorieGameService.notifier = (path, body) async {
      sent.add({'path': path, ...body});
    };
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

  /// Guesses each food's real calories plus [offset] (the foods [uid] has
  /// to guess, in either kind of game).
  Future<CalorieGame> playAll(String id, String uid, {int offset = 0}) async {
    var g = await load(id);
    for (final f in g.foodsFor(uid)) {
      g = await CalorieGameService.guess(
          gameId: id, uid: uid, kcal: f.kcal + offset, notify: false);
    }
    return g;
  }

  Future<String> newSwap({bool notify = false}) => CalorieGameService.create(
        uid: me,
        myName: 'me',
        friendId: friend,
        friendName: 'sam',
        mode: GameMode.swap,
        picks: myPicks,
        notify: notify,
      );

  /// A swap game where both have picked.
  Future<String> readySwap() async {
    final id = await newSwap();
    await CalorieGameService.pick(id, friend, theirPicks, notify: false);
    return id;
  }

  List<String> names(List<GameFood> foods) => [for (final f in foods) f.name];

  Future<Map<String, dynamic>> raw(String id) async =>
      (await w.db.collection('calorie_games').doc(id).get()).data()!;

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

  test('a new game says what kind it is and when it ends', () async {
    final g = await load(await newGame());
    expect(g.mode, GameMode.classic);
    expect(g.isSwap, isFalse);
    expect(g.expiresAt, w.now.add(const Duration(days: 7)));
    expect(g.picks, isEmpty);
    expect(g.ready, isTrue);
    expect(g.isTurnOf(me), isTrue);
    expect(g.isTurnOf(friend), isTrue);
  });

  test('classic games saved without a mode still work', () async {
    final ref = await w.db.collection('calorie_games').add({
      'player_ids': [me, friend],
      'names': {me: 'me', friend: 'sam'},
      'created_by': me,
      'foods': [for (final f in kGameFoods.take(5)) f.toMap()],
      'guesses': {me: <int>[], friend: <int>[]},
      'status': 'active',
      'winner': null,
      'updated_at': Timestamp.fromDate(w.now),
    });
    var g = await load(ref.id);
    expect(g.mode, GameMode.classic);
    expect(names(g.foodsFor(me)), names(kGameFoods.take(5).toList()));
    expect(names(g.foodsFor(friend)), names(g.foods));
    expect(g.nextFoodFor(me), 0);
    expect(g.maxScore, 500);
    // No expires_at: a week after the last move.
    expect(g.endsAt, w.now.add(const Duration(days: 7)));

    await playAll(ref.id, me);
    g = await playAll(ref.id, friend, offset: 30);
    expect(g.isFinished, isTrue);
    expect(g.winner, me);
    expect((await load(ref.id)).scoreOf(me), 500);
  });

  group('Higher or Lower with a friend', () {
    Future<String> newHl() => CalorieGameService.create(
          uid: me,
          myName: 'me',
          friendId: friend,
          friendName: 'sam',
          mode: GameMode.higherLower,
          random: Random(3),
          notify: false,
        );

    /// Picks the right side of every pair, or the wrong side for the
    /// pairs in [wrong].
    Future<CalorieGame> answerAll(String id, String uid,
        {Set<int> wrong = const {}}) async {
      var g = await load(id);
      for (var i = 0; i < g.pairCount; i++) {
        final p = g.pairAt(i);
        final right = identical(p.higher, p.a) ? 0 : 1;
        g = await CalorieGameService.guess(
            gameId: id,
            uid: uid,
            kcal: wrong.contains(i) ? 1 - right : right,
            notify: false);
      }
      return g;
    }

    test('is saved as pairs both players answer', () async {
      final id = await newHl();
      final g = await load(id);
      expect((await raw(id))['mode'], 'higherLower');
      expect(g.isHigherLower, isTrue);
      expect(g.foods, hasLength(CalorieGameService.hlPairs * 2));
      expect(g.pairCount, CalorieGameService.hlPairs);
      expect(g.totalFor(me), CalorieGameService.hlPairs);
      expect(g.ready, isTrue);
      expect(g.nextFoodFor(me), 0);
      expect(g.shownMax, CalorieGameService.hlPairs);
      for (var i = 0; i < g.pairCount; i++) {
        final p = g.pairAt(i);
        expect(p.a.name, isNot(p.b.name));
        expect(p.difference, greaterThan(0));
      }
    });

    test('most right wins, and the score is how many right', () async {
      final id = await newHl();
      await answerAll(id, me, wrong: {0});
      final g = await answerAll(id, friend, wrong: {1, 2, 3});
      expect(g.isFinished, isTrue);
      expect(g.correctOf(me), CalorieGameService.hlPairs - 1);
      expect(g.correctOf(friend), CalorieGameService.hlPairs - 3);
      expect(g.shownScoreOf(me), CalorieGameService.hlPairs - 1);
      expect(g.winner, me);
      expect((await load(id)).doneBy(friend), isTrue);
    });

    test('a draw when both get the same number right', () async {
      final id = await newHl();
      await answerAll(id, me, wrong: {4});
      final g = await answerAll(id, friend, wrong: {7});
      expect(g.isDraw, isTrue);
    });
  });

  group('Guess what I ate', () {
    test('starting saves your picks and waits for your friend to pick',
        () async {
      final id = await newSwap();
      final g = await load(id);
      expect(g.mode, GameMode.swap);
      expect(g.foods, isEmpty);
      expect(names(g.picksOf(me)), names(myPicks));
      expect(g.hasPicked(me), isTrue);
      expect(g.needsPickFrom(friend), isTrue);
      expect(g.needsPickFrom(me), isFalse);
      expect(g.ready, isFalse);
      // Your friend guesses your foods; yours come once they've picked.
      expect(names(g.foodsFor(friend)), names(myPicks));
      expect(g.foodsFor(me), isEmpty);
      expect(g.nextFoodFor(me), isNull);
      expect(g.nextFoodFor(friend), isNull);
      expect(g.doneBy(me), isFalse);
      expect(g.totalFor(me), CalorieGameService.rounds);
      expect(g.isTurnOf(friend), isTrue);
      expect(g.isTurnOf(me), isFalse);
      expect(g.maxScore, 500);

      final data = await raw(id);
      expect(data['mode'], 'swap');
      expect((data['picks'] as Map).containsKey(friend), isTrue);
      expect((data['picks'] as Map)[friend], isNull);
      expect((data['picks'] as Map)[me], hasLength(5));
    });

    test('needs exactly 5 foods to start or to pick', () async {
      expect(
        () => CalorieGameService.create(
            uid: me,
            myName: 'me',
            friendId: friend,
            friendName: 'sam',
            mode: GameMode.swap,
            picks: myPicks.take(4).toList(),
            notify: false),
        throwsArgumentError,
      );
      expect(
        () => CalorieGameService.create(
            uid: me,
            myName: 'me',
            friendId: friend,
            friendName: 'sam',
            mode: GameMode.swap,
            notify: false),
        throwsArgumentError,
      );
      final id = await newSwap();
      expect(
        () => CalorieGameService.pick(id, friend, theirPicks.take(4).toList(),
            notify: false),
        throwsArgumentError,
      );
      expect(
        () => CalorieGameService.pick(
            id, friend, [...theirPicks, kGameFoods[20]],
            notify: false),
        throwsArgumentError,
      );
      expect((await load(id)).needsPickFrom(friend), isTrue);
    });

    test("nobody can guess until both have picked, and picking is once",
        () async {
      final id = await newSwap();
      await expectLater(
        CalorieGameService.guess(
            gameId: id, uid: friend, kcal: 100, notify: false),
        throwsStateError,
      );
      await expectLater(
        CalorieGameService.guess(gameId: id, uid: me, kcal: 100, notify: false),
        throwsStateError,
      );
      expect((await load(id)).guessesOf(me), isEmpty);

      final g = await CalorieGameService.pick(id, friend, theirPicks,
          notify: false);
      expect(g.ready, isTrue);
      expect(names((await load(id)).picksOf(friend)), names(theirPicks));

      // A second pick changes nothing.
      await CalorieGameService.pick(id, friend, myPicks, notify: false);
      expect(names((await load(id)).picksOf(friend)), names(theirPicks));
      // And classic games have nothing to pick.
      final classic = await newGame();
      await expectLater(
        CalorieGameService.pick(classic, friend, theirPicks, notify: false),
        throwsStateError,
      );
    });

    test("each guesses the other's foods, scored against those foods",
        () async {
      final id = await readySwap();
      var g = await load(id);
      expect(names(g.foodsFor(me)), names(theirPicks));
      expect(names(g.foodsFor(friend)), names(myPicks));
      expect(g.nextFoodFor(me), 0);
      expect(g.nextFoodFor(friend), 0);

      // Spot on for their foods: 100 a food.
      g = await playAll(id, me);
      expect(g.doneBy(me), isTrue);
      expect(g.nextFoodFor(me), isNull);
      expect(g.scoreOf(me), 500);
      expect(g.isFinished, isFalse);
      expect(g.isTurnOf(me), isFalse);
      expect(g.isTurnOf(friend), isTrue);

      // Guessing my foods' calories against THEIR foods would score
      // differently: check it's my foods that count.
      final friendGuess = myPicks[0].kcal;
      g = await CalorieGameService.guess(
          gameId: id, uid: friend, kcal: friendGuess, notify: false);
      expect(g.roundScoresOf(friend), [100]);
      expect(g.progressOf(friend), 1);
    });

    test('finishes with a winner once both have guessed 5', () async {
      final id = await readySwap();
      await playAll(id, me, offset: 60);
      final g = await playAll(id, friend);
      expect(g.isFinished, isTrue);
      final saved = await load(id);
      expect(saved.isFinished, isTrue);
      expect(saved.winner, friend);
      expect(saved.scoreOf(friend), 500);
      expect(saved.scoreOf(me), lessThan(500));
      // One more guess is ignored.
      await CalorieGameService.guess(gameId: id, uid: me, kcal: 1, notify: false);
      expect((await load(id)).guessesOf(me).length, CalorieGameService.rounds);
    });

    test('sorting and the waiting count include picking', () async {
      final needsFriendPick = await newSwap();
      final games = await CalorieGameService.forUser(me).first;
      expect(games.single.id, needsFriendPick);
      expect(CalorieGameService.waitingOn(me, games), 0);
      expect(CalorieGameService.waitingOn(friend, games), 1);
    });
  });

  group('your foods to pick from', () {
    CardTransaction tx(String name, double kcal,
            {String portion = '1 portion',
            String meal = 'Lunch',
            int hour = 12}) =>
        CardTransaction(
          id: '$name$hour',
          description: name,
          portion: portion,
          category: meal,
          time: DateTime(2026, 10, 9, hour),
          calories: kcal,
          protein: 0,
          carbs: 0,
          fat: 0,
        );

    test('each food once, newest first, with a meal emoji', () {
      final foods = CalorieGameService.pickableFoods([
        tx('Toast', 180, meal: 'Breakfast', hour: 8),
        tx('Soup', 220, hour: 13),
        tx('Toast', 180, meal: 'Breakfast', hour: 9),
        tx('Toast', 360, portion: '2 slices', meal: 'Breakfast', hour: 7),
        tx('Water', 0, hour: 10),
        tx('Recipe: Chilli', 540, portion: '1 serving', meal: 'Dinner',
            hour: 19),
        tx('Crisps', 130, meal: 'Snacks', hour: 16),
        tx('Pasta', 600, meal: 'Dinner', hour: 18),
      ]);
      expect(names(foods), ['Chilli', 'Pasta', 'Crisps', 'Soup', 'Toast', 'Toast']);
      expect([for (final f in foods) f.emoji],
          ['📖', '🍝', '🍪', '🥪', '🍳', '🍳']);
      expect(foods.first.portion, '1 serving');
      expect(foods.first.kcal, 540);
      // Zero-calorie foods are left out.
      expect(names(foods), isNot(contains('Water')));
    });

    test('loads the last 30 days of your log', () async {
      await w.addEntry(
          at: w.now.subtract(const Duration(days: 2)),
          description: 'Porridge',
          calories: 250,
          meal: 'Breakfast');
      await w.addEntry(
          at: w.now.subtract(const Duration(days: 45)),
          description: 'Old food',
          calories: 300);
      final foods = await CalorieGameService.loadPickable(me);
      expect(names(foods), ['Porridge']);
      expect(foods.single.emoji, '🍳');
    });
  });

  group('ending games nobody moves in', () {
    test('a guess or a pick pushes the end back a week', () async {
      final id = await readySwap();
      w.now = w.now.add(const Duration(days: 3));
      await CalorieGameService.guess(
          gameId: id, uid: me, kcal: 100, notify: false);
      expect((await load(id)).expiresAt, w.now.add(const Duration(days: 7)));

      final classic = await newGame();
      w.now = w.now.add(const Duration(days: 2));
      await CalorieGameService.guess(
          gameId: classic, uid: friend, kcal: 100, notify: false);
      expect(
          (await load(classic)).expiresAt, w.now.add(const Duration(days: 7)));

      final swap = await newSwap();
      w.now = w.now.add(const Duration(days: 1));
      await CalorieGameService.pick(swap, friend, theirPicks, notify: false);
      expect((await load(swap)).expiresAt, w.now.add(const Duration(days: 7)));
    });

    test('a game that is not stale is left alone', () async {
      final id = await newGame();
      await playAll(id, me);
      w.now = w.now.add(const Duration(days: 6));
      final g = await CalorieGameService.expireIfStale(await load(id), me);
      expect(g.isFinished, isFalse);
      final saved = await load(id);
      expect(saved.isFinished, isFalse);
      expect(saved.expired, isFalse);
    });

    test('the only player who finished wins', () async {
      final id = await newGame();
      await playAll(id, me);
      await CalorieGameService.guess(
          gameId: id, uid: friend, kcal: 100, notify: false);
      w.now = w.now.add(const Duration(days: 7, minutes: 1));

      var g = await load(id);
      expect(g.isStaleAt(w.now), isTrue);
      // Too late for more guesses.
      await expectLater(
        CalorieGameService.guess(
            gameId: id, uid: friend, kcal: 100, notify: false),
        throwsStateError,
      );

      g = await CalorieGameService.expireIfStale(g, friend);
      expect(g.isFinished, isTrue);
      final saved = await load(id);
      expect(saved.isFinished, isTrue);
      expect(saved.expired, isTrue);
      expect(saved.winner, me);

      // It counts in the record.
      final games = await CalorieGameService.forUser(me).first;
      final r = CalorieGameService.recordAgainst(me, friend, games);
      expect((r.wins, r.losses, r.draws), (1, 0, 0));
      final theirs = CalorieGameService.recordAgainst(friend, me, games);
      expect((theirs.wins, theirs.losses, theirs.draws), (0, 1, 0));
    });

    test("nobody finished: a draw that doesn't count", () async {
      final id = await newSwap(); // your friend never picks
      w.now = w.now.add(const Duration(days: 8));
      await CalorieGameService.expireIfStale(await load(id), me);
      final saved = await load(id);
      expect(saved.isFinished, isTrue);
      expect(saved.expired, isTrue);
      expect(saved.winner, CalorieGameService.draw);
      // Ending it twice changes nothing.
      await CalorieGameService.expireIfStale(saved, friend);
      expect((await load(id)).winner, CalorieGameService.draw);

      final games = await CalorieGameService.forUser(me).first;
      final r = CalorieGameService.recordAgainst(me, friend, games);
      expect(r.played, 0);
    });

    test('stale games sort with the finished ones and need nothing from you',
        () async {
      final stale = await newGame();
      w.now = w.now.add(const Duration(days: 8));
      final fresh = await newGame();
      final games = await CalorieGameService.forUser(me).first;
      expect(games.map((g) => g.id).toList(), [fresh, stale]);
      expect(CalorieGameService.waitingOn(me, games), 1);
    });
  });

  group('your turn notifications', () {
    test('sent on start, on picking, and when a player finishes their 5',
        () async {
      final id = await newSwap(notify: true);
      expect(sent, [
        {'path': '/notify/game', 'gameId': id, 'event': 'update'}
      ]);

      sent.clear();
      await CalorieGameService.pick(id, friend, theirPicks);
      expect(sent, [
        {'path': '/notify/game', 'gameId': id, 'event': 'update'}
      ]);

      sent.clear();
      final g = await load(id);
      for (final f in g.foodsFor(me).take(4)) {
        await CalorieGameService.guess(gameId: id, uid: me, kcal: f.kcal);
      }
      expect(sent, isEmpty);
      await CalorieGameService.guess(
          gameId: id, uid: me, kcal: g.foodsFor(me)[4].kcal);
      expect(sent, hasLength(1));

      sent.clear();
      for (final f in g.foodsFor(friend)) {
        await CalorieGameService.guess(gameId: id, uid: friend, kcal: f.kcal);
      }
      // Only the finishing guess.
      expect(sent, [
        {'path': '/notify/game', 'gameId': id, 'event': 'update'}
      ]);
      expect((await load(id)).isFinished, isTrue);
    });

    test('a nudge asks for a nudge push too', () async {
      final id = await newGame();
      await CalorieGameService.nudge(await load(id), me);
      expect(sent, [
        {'path': '/notify/game', 'gameId': id, 'event': 'nudge'}
      ]);
    });

    test('nothing is sent with notify off, and failures are ignored',
        () async {
      await newGame();
      await readySwap();
      expect(sent, isEmpty);

      CalorieGameService.notifier = (path, body) async {
        throw Exception('offline');
      };
      await CalorieGameService.notifyOpponent('x'); // doesn't throw
    });

    test('the request body', () {
      expect(CalorieGameService.notifyBody('g1'),
          {'gameId': 'g1', 'event': 'update'});
      expect(CalorieGameService.notifyBody('g1', nudge: true),
          {'gameId': 'g1', 'event': 'nudge'});
    });
  });

  test('chat messages name the kind of game', () async {
    await newSwap(notify: true);
    final convo = await w.db
        .collection('conversations')
        .doc(me.compareTo(friend) < 0 ? '${me}_$friend' : '${friend}_$me')
        .collection('messages')
        .get();
    final texts = convo.docs.map((d) => d['message'] as String).toList();
    expect(texts.single, contains('Guess what I ate'));
  });
}
