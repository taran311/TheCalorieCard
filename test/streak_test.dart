// Streaks and Streak Freezes are worked out from finished days alone.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/streak.dart';

void main() {
  // Saturday 10 Oct 2026.
  final today = DateTime(2026, 10, 10);
  DateTime ago(int n) => BalanceService.addDays(today, -n);
  Set<String> keys(Iterable<int> daysAgo) =>
      {for (final n in daysAgo) BalanceService.dateKey(ago(n))};

  StreakResult run(Set<String> finished) =>
      Streaks.compute(finished, from: ago(39), today: today);

  test('an unfinished today does not break the streak', () {
    final r = run(keys([1, 2, 3]));
    expect(r.current, 3);
    expect(r.freezes, 0);
    expect(r.toNextFreeze, 4);
  });

  test('a gap without a freeze ends the streak', () {
    final r = run(keys([1, 2, 4, 5]));
    expect(r.current, 2);
    expect(r.longest, 2);
  });

  test('7 days in a row earns a freeze, which covers a missed day', () {
    // Finished 10..4 days ago (7 days), missed 3 days ago, then 2 and 1.
    final r = run(keys([10, 9, 8, 7, 6, 5, 4, 2, 1]));
    expect(r.current, 9);
    expect(r.freezes, 0, reason: 'the freeze was used');
    expect(r.frozen, {BalanceService.dateKey(ago(3))});
  });

  test('freezes cap at 2 and are banked', () {
    final r = run(keys(List.generate(21, (i) => i + 1)));
    expect(r.current, 21);
    expect(r.freezes, Streaks.maxFreezes);
    expect(r.toNextFreeze, 0);
  });

  test('two misses in a row use two freezes', () {
    final r = run(keys([...List.generate(14, (i) => i + 4), 1]));
    expect(r.current, 15);
    expect(r.freezes, 0);
    expect(r.frozen.length, 2);
  });

  test('running out of freezes ends it', () {
    final r = run(keys([...List.generate(7, (i) => i + 5), 1]));
    // One freeze covers 4 days ago; 3 and 2 days ago aren't covered.
    expect(r.current, 1);
    expect(r.longest, 7);
    expect(r.frozen, isEmpty);
  });

  test('finishing today counts', () {
    final r = run(keys([0, 1]));
    expect(r.current, 2);
  });
}
