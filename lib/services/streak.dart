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

  /// Rest days (date keys) taken during the current streak. They were
  /// skipped: they paused the streak without using a freeze.
  final Set<String> rested;

  const StreakResult({
    required this.current,
    required this.freezes,
    required this.frozen,
    required this.longest,
    required this.toNextFreeze,
    this.rested = const <String>{},
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
///
/// Rest days (`daily_logs.rest_day`, see RestDays) are skipped entirely:
/// they neither break a streak nor add to it, and don't use a freeze or
/// count towards earning one. A rest day wins over "finished" for the same
/// day, so a day can never both pause and extend a streak.
class Streaks {
  Streaks._();

  static const earnEvery = 7;
  static const maxFreezes = 2;

  /// Walks every day from [from] to [today]. [finished] holds the date keys
  /// ([BalanceService.dateKey]) of finished days. Today only counts once
  /// it's finished; an unfinished today isn't a missed day yet.
  /// [restDays] holds the date keys of rest days, which are skipped.
  static StreakResult compute(
    Set<String> finished, {
    required DateTime from,
    required DateTime today,
    Set<String> restDays = const <String>{},
  }) {
    final todayKey = BalanceService.dateKey(today);
    var run = 0;
    var longest = 0;
    var freezes = 0;
    var sinceEarn = 0;
    var frozen = <String>{};
    var rested = <String>{};

    var d = BalanceService.startOfDay(from);
    final end = BalanceService.startOfDay(today);
    while (!d.isAfter(end)) {
      final key = BalanceService.dateKey(d);
      if (restDays.contains(key)) {
        // Paused, not broken: as if the day wasn't on the calendar.
        if (run > 0) rested.add(key);
      } else if (finished.contains(key)) {
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
        rested = <String>{};
      }
      d = BalanceService.addDays(d, 1);
    }

    return StreakResult(
      current: run,
      freezes: freezes,
      frozen: frozen,
      longest: longest,
      toNextFreeze: freezes >= maxFreezes ? 0 : earnEvery - sinceEarn,
      rested: rested,
    );
  }
}
