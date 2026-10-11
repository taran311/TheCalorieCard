import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

/// A friend, as shown in pickers.
class Friend {
  final String id;
  final String name;

  const Friend({required this.id, required this.name});
}

/// Where you stand with someone, before sending them a friend request.
enum FriendRelation {
  /// It's you.
  self,

  /// Already friends.
  friends,

  /// You've asked them and they haven't answered.
  requestSent,

  /// They've asked you and you haven't answered.
  requestReceived,

  /// None of the above: a request can be sent.
  none,
}

/// [FriendsService.relationTo]'s answer. [requestId] and [requestFromEmail]
/// are set for [FriendRelation.requestReceived], so it can be accepted.
class FriendStatus {
  final FriendRelation relation;
  final String? requestId;
  final String? requestFromEmail;

  const FriendStatus(this.relation, {this.requestId, this.requestFromEmail});
}

/// Reads your friends list (`users/{uid}.friends`) with display names.
class FriendsService {
  FriendsService._();

  /// "sam.jones" from "sam.jones@gmail.com".
  static String displayName(String? email) {
    if (email == null || email.isEmpty) return 'Unknown';
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  /// The name to show for a `users/{uid}` doc: the display name they chose
  /// (Profile → Account), or else the start of their email.
  static String nameFromUser(Map<String, dynamic>? user) {
    final chosen = '${user?['display_name'] ?? ''}'.trim();
    if (chosen.isNotEmpty) return chosen;
    return displayName(user?['email'] as String?);
  }

  /// Names looked up by [nameFor], once each per session.
  static final Map<String, Future<String>> _names = {};

  /// The name to show for [uid], from their `users` doc. [email] is the
  /// fallback if the doc can't be read (e.g. your own, from sign-in).
  /// Failures aren't cached, so the next call tries again.
  static Future<String> nameFor(String uid, {String? email}) {
    if (uid.isEmpty) return Future.value(displayName(email));
    return _names.putIfAbsent(uid, () async {
      try {
        final doc = await BalanceService.db.collection('users').doc(uid).get();
        final data = doc.data();
        if (data == null) {
          _names.remove(uid);
          return displayName(email);
        }
        final name = nameFromUser(data);
        return name == 'Unknown' && email != null ? displayName(email) : name;
      } catch (_) {
        _names.remove(uid);
        return displayName(email);
      }
    });
  }

  /// Forgets cached names (e.g. after you change your display name).
  static void clearNameCache() => _names.clear();

  static Future<List<String>> friendIds(String uid) async {
    final doc = await BalanceService.db.collection('users').doc(uid).get();
    final list = doc.data()?['friends'];
    if (list is! List) return const [];
    return [for (final id in list) id.toString()];
  }

  static Future<List<Friend>> load(String uid) async {
    final ids = await friendIds(uid);
    final docs = await Future.wait(
        ids.map((id) => BalanceService.db.collection('users').doc(id).get()));
    final friends = [
      for (final d in docs)
        Friend(
          id: d.id,
          name: nameFromUser(d.data()),
        )
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return friends;
  }

  /// Takes [friendId] out of the friend groups [uid] made (and their group
  /// chats). Groups someone else made are left alone: only their maker can
  /// change who's in them. Returns the names of groups you share that you
  /// didn't make, so the person can be told.
  static Future<List<String>> removeFromMyGroups(
      String uid, String friendId) async {
    final db = BalanceService.db;
    final snap = await db
        .collection('friend_groups')
        .where('members', arrayContains: uid)
        .get();
    final notMine = <String>[];
    for (final g in snap.docs) {
      final data = g.data();
      final members = [
        for (final m in (data['members'] as List? ?? const [])) '$m'
      ];
      if (!members.contains(friendId)) continue;
      final name = '${data['name'] ?? ''}'.trim();
      if (data['creator_id'] != uid) {
        notMine.add(name.isEmpty ? 'Unnamed group' : name);
        continue;
      }
      await g.reference.update({
        'members': FieldValue.arrayRemove([friendId]),
      });
      // The group chat may not exist yet; that's fine.
      try {
        await db.collection('conversations').doc('group_${g.id}').update({
          'participant_ids': FieldValue.arrayRemove([friendId]),
        });
      } catch (_) {}
    }
    return notMine;
  }

  /// Where [myUid] stands with [otherUid]: you, friends, a request either
  /// way, or nothing yet.
  static Future<FriendStatus> relationTo(String myUid, String otherUid) async {
    if (otherUid == myUid) return const FriendStatus(FriendRelation.self);
    final db = BalanceService.db;
    final mine = await friendIds(myUid);
    if (mine.contains(otherUid)) {
      return const FriendStatus(FriendRelation.friends);
    }
    final sent = await db
        .collection('friend_requests')
        .where('from_user_id', isEqualTo: myUid)
        .where('to_user_id', isEqualTo: otherUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (sent.docs.isNotEmpty) {
      return const FriendStatus(FriendRelation.requestSent);
    }
    final received = await db
        .collection('friend_requests')
        .where('from_user_id', isEqualTo: otherUid)
        .where('to_user_id', isEqualTo: myUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (received.docs.isNotEmpty) {
      final r = received.docs.first;
      return FriendStatus(
        FriendRelation.requestReceived,
        requestId: r.id,
        requestFromEmail: r.data()['from_email'] as String?,
      );
    }
    return const FriendStatus(FriendRelation.none);
  }

  /// Sends a friend request from [myUid] to [toUid] — the same
  /// `friend_requests` doc whether they were found by email, username or
  /// link. Only writes when [relationTo] says [FriendRelation.none]; the
  /// returned status says what happened otherwise (the caller accepts a
  /// [FriendRelation.requestReceived] instead of asking back).
  static Future<FriendStatus> sendRequest({
    required String myUid,
    required String? myEmail,
    required String toUid,
    required String toEmail,
  }) async {
    final status = await relationTo(myUid, toUid);
    if (status.relation != FriendRelation.none) return status;
    await BalanceService.db.collection('friend_requests').add({
      'from_user_id': myUid,
      'from_email': myEmail ?? '',
      'to_user_id': toUid,
      'to_email': toEmail,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });
    return status;
  }

  /// Accepts request [requestId] from [fromUid]: marks it accepted and adds
  /// each of you to the other's friends, all at once.
  static Future<void> acceptRequest({
    required String requestId,
    required String myUid,
    required String fromUid,
  }) async {
    final db = BalanceService.db;
    await db.runTransaction((transaction) async {
      transaction.update(
        db.collection('friend_requests').doc(requestId),
        {'status': 'accepted'},
      );
      transaction.update(
        db.collection('users').doc(myUid),
        {
          'friends': FieldValue.arrayUnion([fromUid]),
        },
      );
      transaction.update(
        db.collection('users').doc(fromUid),
        {
          'friends': FieldValue.arrayUnion([myUid]),
        },
      );
    });
  }
}
