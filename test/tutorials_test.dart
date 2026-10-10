// Tutorials run on a pretend card. These check every script plays through
// cleanly on its own practice state, and the "even it out" plan maths.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/coach_service.dart';
import 'package:namer_app/ui/tutorials/tutorial_mock.dart';
import 'package:namer_app/ui/tutorials/tutorial_player.dart';
import 'package:namer_app/ui/tutorials/tutorial_scripts.dart';

void main() {
  test('every tutorial plays start to finish on practice data', () {
    expect(tutorials, isNotEmpty);
    final ids = <String>{};
    for (final t in tutorials) {
      expect(ids.add(t.id), isTrue, reason: 'duplicate id ${t.id}');
      expect(t.steps, isNotEmpty);
      final s = TutorialState();
      t.setup?.call(s);
      for (final step in t.steps) {
        step.complete(s);
      }
    }
  });

  test('add food tutorial: card goes down, then back up when removed', () {
    final t = tutorials.firstWhere((t) => t.id == 'add_food');
    final s = TutorialState();
    final start = s.left;
    // Up to and including "Add them to your card".
    for (final step in t.steps.take(6)) {
      step.complete(s);
    }
    expect(s.left, start - 452);
    expect(s.foodsIn('Lunch').map((f) => f.name),
        containsAll(['Chicken wrap', 'Apple']));
    for (final step in t.steps.skip(6)) {
      step.complete(s);
    }
    expect(s.left, start - 380, reason: 'apple swiped away');
  });

  test('going-over tutorial ends 320 over', () {
    final t = tutorials.firstWhere((t) => t.id == 'over');
    final s = TutorialState();
    t.setup!(s);
    expect(s.left, 198);
    t.steps[1].complete(s);
    expect(s.left, -320);
  });

  test('guess the calories tutorial ends with a finished game', () {
    final t = tutorials.firstWhere((t) => t.id == 'calorie_game');
    final s = TutorialState();
    for (final step in t.steps) {
      step.complete(s);
    }
    expect(s.screen, MockScreen.game);
    expect(s.showGameConfirm, isFalse);
    expect(s.gameTyped, '250');
    expect((s.gameMine, s.gameTheirs, s.gameOver), (5, 5, true));
  });

  test('step complete() types the full text', () {
    final s = TutorialState();
    TStep(
      title: 't',
      body: 'b',
      act: TAct.type,
      text: 'hello',
      onType: (s, t) => s.typed = t,
    ).complete(s);
    expect(s.typed, 'hello');
  });

  group('OffsetPlan', () {
    // 12 Oct 2026 is a Monday.
    test('spreads over the rest of the week', () {
      final p = OffsetPlan.compute(
          overBy: 300, goal: 2000, today: DateTime(2026, 10, 12));
      expect(p.days, 6);
      expect(p.perDay, 50);
      expect(p.nextWeek, isFalse);
      expect(p.partial, isFalse);
      expect(p.question, contains('300 kcal'));
    });

    test('Sunday spreads across next week', () {
      final p = OffsetPlan.compute(
          overBy: 350, goal: 2000, today: DateTime(2026, 10, 18));
      expect(p.nextWeek, isTrue);
      expect(p.days, 7);
      expect(p.perDay, 50);
      expect(p.summary, contains('next week'));
    });

    test('never more than 10% of the goal a day', () {
      final p = OffsetPlan.compute(
          overBy: 1500, goal: 1800, today: DateTime(2026, 10, 17));
      expect(p.days, 1);
      expect(p.perDay, 180);
      expect(p.partial, isTrue);
    });

    test('and never more than 200 kcal a day', () {
      final p = OffsetPlan.compute(
          overBy: 3000, goal: 3500, today: DateTime(2026, 10, 12));
      expect(p.perDay, 200);
    });
  });
}
