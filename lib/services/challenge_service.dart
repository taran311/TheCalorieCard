import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

enum ChallengeType {
  /// Who finishes the most days on budget.
  headToHead('head_to_head'),

  /// Everyone together reaches a number of finished days.
  group('group'),

  /// Everyone together logs a target amount of protein (grams).
  protein('protein'),

  /// Who logs something before [ChallengeService.earlyHour] on most days.
  earlyLogger('early_logger');

  final String id;
  const ChallengeType(this.id);

  static ChallengeType from(dynamic v) {
    for (final t in values) {
      if (t.id == v) return t;
    }
    return ChallengeType.headToHead;
  }

  /// Team challenges add everyone's score up towards a target; the others
  /// rank people against each other.
  bool get isTeam => this == group || this == protein;
}

/// A 7-day challenge between friends, stored in `challenges`.
class Challenge {
  final String id;
  final ChallengeType type;
  final String title;
  final String createdBy;
  final List<String> memberIds;
  final DateTime start; // the day it was started
  final DateTime end; // 7 days later (exclusive)
  final int target; // team challenges only (days, or grams of protein)

  /// Names saved when the challenge was made, so members who aren't your
  /// friends still show by name.
  final Map<String, String> names;

  const Challenge({
    required this.id,
    required this.type,
    required this.title,
    required this.createdBy,
    required this.memberIds,
    required this.start,
    required this.end,
    required this.target,
    this.names = const {},
  });

  bool get isOver => !BalanceService.now().isBefore(end);

  factory Challenge.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final start = ChallengeService.parseKey(d['start_key']) ??
        ChallengeService.weekStart(BalanceService.now());
    final rawNames = d['names'];
    return Challenge(
      id: doc.id,
      type: ChallengeType.from(d['type']),
      title: (d['title'] ?? 'Weekly challenge').toString(),
      createdBy: (d['created_by'] ?? '').toString(),
      memberIds: [for (final m in (d['member_ids'] as List? ?? const [])) '$m'],
      start: start,
      // Older challenges ran Monday to Sunday and have no end_key; seven
      // days from their start is the same thing.
      end: ChallengeService.parseKey(d['end_key']) ??
          BalanceService.addDays(start, ChallengeService.lengthDays),
      target: (BalanceService.number(d['target']) ?? 0).round(),
      names: {
        if (rawNames is Map)
          for (final e in rawNames.entries) '${e.key}': '${e.value}'
      },
    );
  }
}

/// Days counted for one person in a challenge.
class ChallengeScore {
  final String userId;
  final int finishedDays;
  final int onBudgetDays;

  /// Protein logged during the challenge, in grams.
  final double protein;

  /// Days they logged something before [ChallengeService.earlyHour].
  final int earlyDays;

  const ChallengeScore(this.userId, this.finishedDays, this.onBudgetDays,
      {this.protein = 0, this.earlyDays = 0});

  /// The number this person is ranked (or counted towards a target) by.
  num valueFor(ChallengeType type) => switch (type) {
        ChallengeType.headToHead => onBudgetDays,
        ChallengeType.group => finishedDays,
        ChallengeType.protein => protein,
        ChallengeType.earlyLogger => earlyDays,
      };
}

class ChallengeService {
  ChallengeService._();

  /// How long a challenge runs, counting the day it starts.
  static const lengthDays = 7;

  /// "Early logger": food logged before this hour counts.
  static const earlyHour = 11;

  static CollectionReference<Map<String, dynamic>> get _col =>
      BalanceService.db.collection('challenges');

  /// Monday of the week [d] falls in.
  static DateTime weekStart(DateTime d) {
    final day = BalanceService.startOfDay(d);
    return BalanceService.addDays(day, -(day.weekday - 1));
  }

  static DateTime? parseKey(dynamic key) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch('${key ?? ''}');
    if (m == null) return null;
    return DateTime(
        int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  /// A team protein target that suits [people]: [perPersonPerDay] grams
  /// each, every day of the challenge.
  static int proteinTarget(int people, {int perPersonPerDay = 100}) =>
      people * perPersonPerDay * lengthDays;

  /// Starts a challenge with you and [friendIds]. It starts today (so days
  /// before you started it never count) and runs for [lengthDays] days.
  ///
  /// [names] maps member ids to the names to show (yours and your
  /// friends'), saved on the challenge for members who aren't friends.
  static Future<String> create({
    required String uid,
    required ChallengeType type,
    required List<String> friendIds,
    int? target,
    String? title,
    Map<String, String> names = const {},
  }) async {
    final members = {uid, ...friendIds}.toList();
    if (members.length < 2) throw ArgumentError('Pick at least one friend');
    final start = BalanceService.startOfDay(BalanceService.now());
    final end = BalanceService.addDays(start, lengthDays);
    final teamTarget = switch (type) {
      ChallengeType.group => target ?? members.length * 4,
      ChallengeType.protein => target ?? proteinTarget(members.length),
      _ => 0,
    };
    final ref = await _col.add({
      'type': type.id,
      'title': (title == null || title.trim().isEmpty)
          ? defaultTitle(type, teamTarget)
          : title.trim(),
      'created_by': uid,
      'member_ids': members,
      'names': {
        for (final m in members)
          if ((names[m] ?? '').trim().isNotEmpty) m: names[m]!.trim()
      },
      'start_key': BalanceService.dateKey(start),
      'end_key': BalanceService.dateKey(end),
      'target': teamTarget,
      'created_at': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static String defaultTitle(ChallengeType type, int target) =>
      switch (type) {
        ChallengeType.group => 'Team goal: $target finished days',
        ChallengeType.protein => 'Team protein: ${target}g',
        ChallengeType.earlyLogger => 'Early logger: log before 11am',
        ChallengeType.headToHead => 'Most days on budget',
      };

  /// Your challenges: running ones, and ones that ended in the last week,
  /// newest first.
  static Stream<List<Challenge>> forUser(String uid) {
    final today = BalanceService.startOfDay(BalanceService.now());
    final cutoff = BalanceService.addDays(today, -7);
    return _col.where('member_ids', arrayContains: uid).snapshots().map(
          (snap) => [
            for (final d in snap.docs)
              if (Challenge.fromDoc(d).end.isAfter(cutoff))
                Challenge.fromDoc(d)
          ]..sort((a, b) => b.start.compareTo(a.start)),
        );
  }

  static Future<void> leave(String uid, Challenge c) =>
      _col.doc(c.id).update({
        'member_ids': FieldValue.arrayRemove([uid])
      });

  /// The challenge's days that have started so far (none in the future).
  static List<DateTime> daysSoFar(Challenge c) {
    final today = BalanceService.startOfDay(BalanceService.now());
    return [
      for (var d = c.start;
          d.isBefore(c.end) && !d.isAfter(today);
          d = BalanceService.addDays(d, 1))
        d
    ];
  }

  /// Each member's score so far in [c], best first.
  /// Day-based scores use the same `daily_logs` history as the hiscores.
  static Future<List<ChallengeScore>> scores(Challenge c) async {
    final days = daysSoFar(c);
    final results = await Future.wait(c.memberIds.map((uid) async {
      // One member's history being unreadable shouldn't hide everyone's
      // scores: they just show 0.
      try {
        return await _scoreFor(uid, c, days);
      } catch (_) {
        return ChallengeScore(uid, 0, 0);
      }
    }));
    results.sort((a, b) => b.valueFor(c.type).compareTo(a.valueFor(c.type)));
    return results;
  }

  static Future<ChallengeScore> _scoreFor(
      String uid, Challenge c, List<DateTime> days) async {
    if (days.isEmpty) return ChallengeScore(uid, 0, 0);
    if (c.type == ChallengeType.protein || c.type == ChallengeType.earlyLogger) {
      final entries = await BalanceService.entriesBetween(
          uid, days.first, BalanceService.addDays(days.last, 1));
      final data = [for (final e in entries) e.data()];
      return ChallengeScore(uid, 0, 0,
          protein: proteinFrom(data), earlyDays: earlyDaysFrom(data));
    }
    final logs = await Future.wait(days.map((d) => BalanceService.db
        .collection('daily_logs')
        .doc('${uid}_${BalanceService.dateKey(d)}')
        .get()));
    var finished = 0, onBudget = 0;
    for (final log in logs) {
      final data = log.data();
      if (data == null || data['finished'] != true) continue;
      finished++;
      final balances = data['balances'];
      final left = balances is Map
          ? BalanceService.number(balances['calories'])
          : null;
      if (left != null && left >= 0) onBudget++;
    }
    return ChallengeScore(uid, finished, onBudget);
  }

  /// Total protein (grams) in logged `user_food` entries.
  static double proteinFrom(Iterable<Map<String, dynamic>> entries) =>
      entries.fold(0.0, (sum, e) => sum + Macros.fromEntry(e).protein);

  /// Distinct days with something logged before [earlyHour] (local time).
  static int earlyDaysFrom(Iterable<Map<String, dynamic>> entries) {
    final days = <String>{};
    for (final e in entries) {
      final t = BalanceService.entryDate(e);
      if (t != null && t.hour < earlyHour) days.add(BalanceService.dateKey(t));
    }
    return days.length;
  }
}
