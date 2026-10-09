import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

enum ChallengeType {
  /// Who finishes the most days on budget this week.
  headToHead('head_to_head'),

  /// Everyone together reaches a number of finished days this week.
  group('group');

  final String id;
  const ChallengeType(this.id);

  static ChallengeType from(dynamic v) =>
      v == group.id ? ChallengeType.group : ChallengeType.headToHead;
}

/// A weekly challenge between friends, stored in `challenges`.
class Challenge {
  final String id;
  final ChallengeType type;
  final String title;
  final String createdBy;
  final List<String> memberIds;
  final DateTime start; // Monday
  final DateTime end; // the Monday after (exclusive)
  final int target; // group challenges only

  const Challenge({
    required this.id,
    required this.type,
    required this.title,
    required this.createdBy,
    required this.memberIds,
    required this.start,
    required this.end,
    required this.target,
  });

  bool get isOver => !BalanceService.now().isBefore(end);

  factory Challenge.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final start = ChallengeService.parseKey(d['start_key']) ??
        ChallengeService.weekStart(BalanceService.now());
    return Challenge(
      id: doc.id,
      type: ChallengeType.from(d['type']),
      title: (d['title'] ?? 'Weekly challenge').toString(),
      createdBy: (d['created_by'] ?? '').toString(),
      memberIds: [for (final m in (d['member_ids'] as List? ?? const [])) '$m'],
      start: start,
      end: BalanceService.addDays(start, 7),
      target: (BalanceService.number(d['target']) ?? 0).round(),
    );
  }
}

/// Days counted for one person in a challenge.
class ChallengeScore {
  final String userId;
  final int finishedDays;
  final int onBudgetDays;

  const ChallengeScore(this.userId, this.finishedDays, this.onBudgetDays);
}

class ChallengeService {
  ChallengeService._();

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

  /// Starts a challenge for this week with you and [friendIds].
  static Future<String> create({
    required String uid,
    required ChallengeType type,
    required List<String> friendIds,
    int? target,
    String? title,
  }) async {
    final members = {uid, ...friendIds}.toList();
    if (members.length < 2) throw ArgumentError('Pick at least one friend');
    final start = weekStart(BalanceService.now());
    final groupTarget = target ?? members.length * 4;
    final ref = await _col.add({
      'type': type.id,
      'title': (title == null || title.trim().isEmpty)
          ? (type == ChallengeType.group
              ? 'Team goal: $groupTarget finished days'
              : 'Most days on budget')
          : title.trim(),
      'created_by': uid,
      'member_ids': members,
      'start_key': BalanceService.dateKey(start),
      'target': type == ChallengeType.group ? groupTarget : 0,
      'created_at': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Your challenges, this week's and last week's, newest first.
  static Stream<List<Challenge>> forUser(String uid) {
    final cutoff = BalanceService.addDays(weekStart(BalanceService.now()), -7);
    return _col.where('member_ids', arrayContains: uid).snapshots().map(
          (snap) => [
            for (final d in snap.docs)
              if (!Challenge.fromDoc(d).start.isBefore(cutoff))
                Challenge.fromDoc(d)
          ]..sort((a, b) => b.start.compareTo(a.start)),
        );
  }

  static Future<void> leave(String uid, Challenge c) =>
      _col.doc(c.id).update({
        'member_ids': FieldValue.arrayRemove([uid])
      });

  /// Each member's finished and on-budget days so far in [c], best first.
  /// Uses the same `daily_logs` history as the hiscores.
  static Future<List<ChallengeScore>> scores(Challenge c) async {
    final today = BalanceService.startOfDay(BalanceService.now());
    final days = [
      for (var i = 0; i < 7; i++)
        if (!BalanceService.addDays(c.start, i).isAfter(today))
          BalanceService.addDays(c.start, i)
    ];
    final results = await Future.wait(c.memberIds.map((uid) async {
      // One member's history being unreadable shouldn't hide everyone's
      // scores: they just show 0.
      try {
        return await _scoreFor(uid, days);
      } catch (_) {
        return ChallengeScore(uid, 0, 0);
      }
    }));
    results.sort((a, b) => c.type == ChallengeType.group
        ? b.finishedDays.compareTo(a.finishedDays)
        : b.onBudgetDays.compareTo(a.onBudgetDays));
    return results;
  }

  static Future<ChallengeScore> _scoreFor(String uid, List<DateTime> days) async {
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
}
