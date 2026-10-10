import 'package:namer_app/services/balance_service.dart';

/// What a run of finished days adds up to.
class StreakResult {
  /// Finished days in the current streak (frozen days keep it alive but
  /// don't add to it).
  final int current;

  /// Freezes banked right now, ready to cover a missed day.
  final int freezes;

  /// Missed days (date keys) a freeze covered in the current streak.
  final Set<String> frozen;

  /// The longest streak in the whole history given.
  final int longest;

  /// Finished days still needed to earn the next freeze (0 when full).
  final int toNextFreeze;

  const StreakResult({
    required this.current,
    required this.freezes,
    required this.frozen,
    required this.longest,
    required this.toNextFreeze,
  });

  static const empty = StreakResult(
    current: 0,
    freezes: 0,
    frozen: <String>{},
    longest: 0,
    toNextFreeze: Streaks.earnEvery,
  );
}

/// Streaks with Streak Freezes.
///
/// Every 7 finished days in a row earns a freeze (you can bank up to 2).
/// If you miss a day and have a freeze, it's used automatically and your
/// streak carries on. Everything is worked out from your finished days, so
/// there's nothing extra to save and it can never get out of sync.
class Streaks {
  Streaks._();

  static const earnEvery = 7;
  static const maxFreezes = 2;

  /// Walks every day from [from] to [today]. [finished] holds the date keys
  /// ([BalanceService.dateKey]) of finished days. Today only counts once
  /// it's finished; an unfinished today isn't a missed day yet.
  static StreakResult compute(
    Set<String> finished, {
    required DateTime from,
    required DateTime today,
  }) {
    final todayKey = BalanceService.dateKey(today);
    var run = 0;
    var longest = 0;
    var freezes = 0;
    var sinceEarn = 0;
    var frozen = <String>{};

    var d = BalanceService.startOfDay(from);
    final end = BalanceService.startOfDay(today);
    while (!d.isAfter(end)) {
      final key = BalanceService.dateKey(d);
      if (finished.contains(key)) {
        run++;
        sinceEarn++;
        if (sinceEarn >= earnEvery) {
          sinceEarn = 0;
          if (freezes < maxFreezes) freezes++;
        }
        if (run > longest) longest = run;
      } else if (key == todayKey) {
        // Today isn't over yet.
      } else if (run > 0 && freezes > 0) {
        freezes--;
        frozen.add(key);
      } else {
        run = 0;
        sinceEarn = 0;
        freezes = 0;
        frozen = <String>{};
      }
      d = BalanceService.addDays(d, 1);
    }

    return StreakResult(
      current: run,
      freezes: freezes,
      frozen: frozen,
      longest: longest,
      toNextFreeze: freezes >= maxFreezes ? 0 : earnEvery - sinceEarn,
    );
  }
}
