// Tests for goal weight, pace and the date you'd reach it.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/goal_maths.dart';

void main() {
  test('pace sets the daily calories', () {
    expect(paceCalories(2500, 'lose', 0.5), 1950);
    expect(paceCalories(2500, 'lose', 0.25), 2225);
    expect(paceCalories(2500, 'lose', 0.75), 1675);
    expect(paceCalories(2500, 'maintain', 0.5), 2500);
    expect(paceCalories(2500, 'gain', 0.25), 2775);
  });

  test('losing never goes below the safe floor', () {
    expect(paceCalories(1800, 'lose', 0.75, floor: 1400), 1400);
    // And the real pace is then slower than the one picked.
    expect(kgPerWeekAt(1800, 1400), closeTo(0.36, 0.01));
  });

  test('the goal date follows the pace', () {
    final start = DateTime(2026, 10, 21);
    // 10 kg at 0.5 kg a week: 20 weeks.
    expect(
        goalReachedBy(
            fromKg: 80, goalKg: 70, kgPerWeek: 0.5, start: start),
        DateTime(2027, 3, 10));
    expect(
        goalReachedBy(fromKg: 80, goalKg: 70, kgPerWeek: 0, start: start),
        isNull);
    expect(
        goalReachedBy(fromKg: 70, goalKg: 70, kgPerWeek: 0.5, start: start),
        start);
  });

  test('goal weight has to be the right way, and healthy', () {
    expect(goalWeightFits('lose', 80, 70), isTrue);
    expect(goalWeightFits('lose', 80, 85), isFalse);
    expect(goalWeightFits('gain', 60, 65), isTrue);
    expect(goalWeightFits('maintain', 60, 65), isFalse);
    expect(minHealthyKg(170), closeTo(53.5, 0.1));
  });

  test('saved paces are read back, gaining tops out at steady', () {
    expect(GoalPace.from(0.25), GoalPace.relaxed);
    expect(GoalPace.from(null), GoalPace.steady);
    expect(GoalPace.from(0.75, mode: 'gain'), GoalPace.steady);
    expect(GoalPace.forMode('gain'), [GoalPace.relaxed, GoalPace.steady]);
  });
}
