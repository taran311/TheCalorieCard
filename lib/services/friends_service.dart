import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

/// A friend, as shown in pickers.
class Friend {
  final String id;
  final String name;

  const Friend({required this.id, required this.name});
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
}
