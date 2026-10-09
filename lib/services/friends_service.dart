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
          name: displayName(d.data()?['email'] as String?),
        )
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return friends;
  }
}
