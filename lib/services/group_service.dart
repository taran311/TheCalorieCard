import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

/// Leaving and deleting friend groups.
class GroupService {
  GroupService._();

  static DocumentReference<Map<String, dynamic>> _group(String id) =>
      BalanceService.db.collection('friend_groups').doc(id);

  /// What happens if [uid] leaves: the group carries on, is handed to
  /// someone else (they made it), or goes (they're the last one in it).
  static LeaveOutcome outcomeFor(Map<String, dynamic>? group, String uid) {
    final others = [
      for (final m in (group?['members'] as List?) ?? const [])
        if ('$m' != uid) '$m'
    ];
    if (others.isEmpty) return LeaveOutcome.deleted;
    if (group?['creator_id'] == uid) return LeaveOutcome.handedOver;
    return LeaveOutcome.left;
  }

  /// Takes [uid] out of the group and its group chat. If they made the
  /// group, the next member looks after it; if they were the last one in
  /// it, the group is deleted, so no group is ever left without anyone
  /// able to delete it.
  static Future<LeaveOutcome> leave(String uid, String groupId) async {
    final db = BalanceService.db;
    final ref = _group(groupId);
    final outcome = await db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return LeaveOutcome.deleted;
      final outcome = outcomeFor(data, uid);
      if (outcome == LeaveOutcome.deleted) {
        tx.delete(ref);
      } else {
        final next = [
          for (final m in (data['members'] as List?) ?? const [])
            if ('$m' != uid) '$m'
        ].first;
        tx.update(ref, {
          'members': FieldValue.arrayRemove([uid]),
          if (outcome == LeaveOutcome.handedOver) 'creator_id': next,
        });
      }
      return outcome;
    });
    // The group chat may not exist yet; that's fine.
    try {
      await db.collection('conversations').doc('group_$groupId').update({
        'participant_ids': FieldValue.arrayRemove([uid]),
      });
    } catch (_) {}
    return outcome;
  }

  /// Deletes the group for everyone (only offered to whoever looks after it).
  static Future<void> delete(String groupId) => _group(groupId).delete();
}

enum LeaveOutcome {
  /// Left; the group carries on.
  left,

  /// Left a group you made; the next member looks after it now.
  handedOver,

  /// You were the last one in it, so it's gone.
  deleted,
}
