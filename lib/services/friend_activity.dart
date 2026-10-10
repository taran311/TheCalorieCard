import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:namer_app/services/balance_service.dart';
import 'package:namer_app/services/chat_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A friend's day so far, in the card's terms: how much of their budget
/// they've spent and whether they've finished (closed) the day.
class FriendDay {
  /// They've closed their day on the Card.
  final bool finished;

  /// Calories spent today, if known.
  final double? spent;

  /// Today's budget (goal, plus anything moved in from a pot), if known.
  final double? budget;

  const FriendDay({this.finished = false, this.spent, this.budget});

  static const none = FriendDay();

  /// Builds a day from a `daily_logs` document's data ([log]).
  ///
  /// [spentNow] overrides the logged total (e.g. from a live food stream,
  /// which is more up to date). [fallbackGoal] is used when the log has
  /// no budget in it.
  factory FriendDay.fromLog(Map<String, dynamic>? log,
      {double? spentNow, double? fallbackGoal}) {
    double? n(dynamic v) => BalanceService.number(v);
    final totals = log?['totals'];
    final balances = log?['balances'];
    final goals = log?['goals'];
    final loggedSpent = totals is Map ? n(totals['calories']) : null;
    final left = balances is Map ? n(balances['calories']) : null;
    final goal = goals is Map ? n(goals['calorie_goal']) : null;

    // Left + spent is the day's real budget (it includes pot top-ups);
    // otherwise the goal saved that day, otherwise their current goal.
    double? budget;
    if (left != null && loggedSpent != null && left + loggedSpent > 0) {
      budget = left + loggedSpent;
    } else if (goal != null && goal > 0) {
      budget = goal;
    } else if (fallbackGoal != null && fallbackGoal > 0) {
      budget = fallbackGoal;
    }
    return FriendDay(
      finished: log?['finished'] == true,
      spent: spentNow ?? loggedSpent,
      budget: budget,
    );
  }

  /// Share of the budget spent (can go past 1), or null if unknown.
  double? get fraction {
    final s = spent, b = budget;
    if (s == null || b == null || b <= 0) return null;
    return s / b;
  }

  /// Whole-number percent of budget spent, or null if unknown.
  int? get percent {
    final f = fraction;
    return f == null ? null : (f * 100).round();
  }

  /// True while spending is within budget; null if unknown.
  bool? get onTrack {
    final s = spent, b = budget;
    if (s == null || b == null || b <= 0) return null;
    return s <= b;
  }

  bool get hasData => finished || fraction != null;

  /// "62% of budget spent · on track", "Finished ✓ · on budget" and so on.
  String get label {
    final p = percent;
    final track = onTrack;
    if (finished) {
      if (track == null) return 'Finished today ✓';
      return track ? 'Finished ✓ · on budget' : 'Finished ✓ · over budget';
    }
    if (p == null) return 'Nothing logged yet today';
    return track == false
        ? '$p% of budget spent · over'
        : '$p% of budget spent · on track';
  }
}

/// Friends' days: today's `daily_logs` snapshots, goals, food streams and
/// the "nudge to log" message.
class FriendActivity {
  FriendActivity._();

  /// Live updates of [uid]'s `daily_logs` doc for [day] (default today).
  static Stream<DocumentSnapshot<Map<String, dynamic>>> dayLog(String uid,
          [DateTime? day]) =>
      BalanceService.db
          .collection('daily_logs')
          .doc('${uid}_${BalanceService.dateKey(day ?? BalanceService.now())}')
          .snapshots();

  static final Map<String, Future<double?>> _goals = {};

  /// [uid]'s current calorie goal, read once per session (null if their
  /// profile can't be read).
  static Future<double?> goalOf(String uid) {
    return _goals.putIfAbsent(uid, () async {
      try {
        final doc = await BalanceService.userDataDoc(uid);
        final data = doc?.data();
        return data == null ? null : BalanceService.calorieGoalFrom(data);
      } catch (_) {
        _goals.remove(uid);
        return null;
      }
    });
  }

  /// Calls [onNewDay] just after the next local midnight. Screens use it to
  /// move their "today" on (a query fixed to yesterday would show zeros).
  static Timer atMidnight(VoidCallback onNewDay) {
    final now = BalanceService.now();
    final next = BalanceService.addDays(BalanceService.startOfDay(now), 1);
    return Timer(next.difference(now) + const Duration(seconds: 1), onNewDay);
  }

  /// Live food logged by [userIds] in [start, end), any number of people
  /// (Firestore's `whereIn` takes 30 at a time, so they're asked in 30s
  /// and the answers combined). Emits once every group has answered.
  /// Callers still filter by date, as [BalanceService.entrySnapshotsBetween]
  /// can fall back to whole histories.
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> foodBetween(
      List<String> userIds, DateTime start, DateTime end) {
    if (userIds.isEmpty) {
      return Stream.value(
          const <QueryDocumentSnapshot<Map<String, dynamic>>>[]);
    }
    final chunks = chunked(userIds, 30);
    final latest =
        List<List<QueryDocumentSnapshot<Map<String, dynamic>>>?>.filled(
            chunks.length, null);
    final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    late final StreamController<
        List<QueryDocumentSnapshot<Map<String, dynamic>>>> controller;
    controller = StreamController(
      onListen: () {
        for (var i = 0; i < chunks.length; i++) {
          subs.add(BalanceService.entrySnapshotsBetween(chunks[i], start, end)
              .listen(
            (snap) {
              latest[i] = snap.docs;
              if (latest.every((l) => l != null)) {
                controller.add([for (final l in latest) ...l!]);
              }
            },
            onError: controller.addError,
          ));
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return controller.stream;
  }

  /// [ids] in lists of at most [size].
  static List<List<String>> chunked(List<String> ids, int size) => [
        for (var i = 0; i < ids.length; i += size)
          ids.sublist(i, min(i + size, ids.length))
      ];

  // -------------------- Nudge to log --------------------
  //
  // Remembered on this device only (no new Firestore fields or rules):
  // at most one nudge per friend per day.

  static const _nudgeKey = 'friend_nudges';

  /// Whether [stored] (entries "friendId|dateKey") has a nudge to
  /// [friendId] on [today].
  @visibleForTesting
  static bool nudgedIn(List<String> stored, String friendId, String today) =>
      stored.contains('$friendId|$today');

  /// [stored] with today's nudge to [friendId] added, and older days
  /// dropped so the list never grows.
  @visibleForTesting
  static List<String> withNudge(
          List<String> stored, String friendId, String today) =>
      [
        for (final e in stored)
          if (e.endsWith('|$today') && e != '$friendId|$today') e,
        '$friendId|$today',
      ];

  static Future<bool> nudgedToday(String friendId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return nudgedIn(prefs.getStringList(_nudgeKey) ?? const [], friendId,
          BalanceService.dateKey(BalanceService.now()));
    } catch (_) {
      return false;
    }
  }

  /// The friendly chat message a nudge sends.
  static const nudgeText =
      '👋 Friendly nudge: have you logged today\'s food on the Card yet?';

  /// Sends [friendId] a nudge in your chat with them. Returns false (and
  /// sends nothing) if you've already nudged them today.
  static Future<bool> nudge({
    required String uid,
    required String myName,
    required String friendId,
    required String friendName,
  }) async {
    final today = BalanceService.dateKey(BalanceService.now());
    SharedPreferences? prefs;
    var stored = const <String>[];
    try {
      prefs = await SharedPreferences.getInstance();
      stored = prefs.getStringList(_nudgeKey) ?? const [];
    } catch (_) {}
    if (nudgedIn(stored, friendId, today)) return false;
    await ChatService.sendToFriend(
      uid: uid,
      myName: myName,
      friendId: friendId,
      friendName: friendName,
      text: nudgeText,
      extra: const {'type': 'nudge'},
    );
    try {
      await prefs?.setStringList(_nudgeKey, withNudge(stored, friendId, today));
    } catch (_) {}
    return true;
  }
}
