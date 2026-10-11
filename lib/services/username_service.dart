import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:namer_app/services/balance_service.dart';

/// Someone else already has that username.
class UsernameTakenException implements Exception {
  final String handle;

  const UsernameTakenException(this.handle);

  String get message => '@$handle is taken — try another';

  @override
  String toString() => message;
}

/// The username isn't allowed (too short, odd characters…). [message] is
/// ready to show.
class UsernameInvalidException implements Exception {
  final String message;

  const UsernameInvalidException(this.message);

  @override
  String toString() => message;
}

/// A person found from a username or an invite link.
class FoundUser {
  final String uid;

  /// Their `users/{uid}` doc (may be empty if it couldn't be read).
  final Map<String, dynamic> data;

  const FoundUser({required this.uid, required this.data});

  /// Their username, if they've picked one.
  String? get username => UsernameService.usernameFrom(data);
}

/// Usernames ("@taz"): a short, unique handle friends can add you by, and
/// that makes your invite link readable.
///
/// Stored twice: `usernames/{handle}` = {uid, created_at} is the lock that
/// makes each handle unique (a doc id can only exist once), and
/// `users/{uid}.username` is what the rest of the app reads. Both change
/// together in one transaction.
class UsernameService {
  UsernameService._();

  static const minLength = 3;
  static const maxLength = 20;

  /// Where invite links point.
  static const siteHost = 'thecaloriecard.com';

  /// Names that would look official or confusing on someone else.
  static const reserved = {
    'admin',
    'administrator',
    'calorie_card',
    'caloriecard',
    'help',
    'me',
    'moderator',
    'official',
    'settings',
    'staff',
    'support',
    'the_calorie_card',
    'thecaloriecard',
  };

  static final RegExp _allowed = RegExp(r'^[a-z0-9_]+$');

  static CollectionReference<Map<String, dynamic>> get _usernames =>
      BalanceService.db.collection('usernames');
  static CollectionReference<Map<String, dynamic>> get _users =>
      BalanceService.db.collection('users');

  /// "taz" from "@Taz " — usernames are matched without the @ and
  /// regardless of case.
  static String normalise(String input) =>
      input.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();

  /// Why [input] can't be a username, or null if it can. Checks the
  /// normalised form, so "@Taz" is fine (it becomes "taz").
  static String? validate(String input) {
    final h = normalise(input);
    if (h.isEmpty) return 'Pick a username.';
    if (h.length < minLength) {
      return 'Usernames need at least $minLength characters.';
    }
    if (h.length > maxLength) {
      return 'Usernames can be up to $maxLength characters.';
    }
    if (!_allowed.hasMatch(h)) {
      return 'Use only letters, numbers and _ (no spaces).';
    }
    if (reserved.contains(h)) return '@$h is taken — try another';
    return null;
  }

  /// The username in a `users/{uid}` doc, if any.
  static String? usernameFrom(Map<String, dynamic>? user) {
    final u = user?['username'];
    return u is String && u.isNotEmpty ? u : null;
  }

  /// Your current username, or null.
  static Future<String?> usernameOf(String uid) async {
    if (uid.isEmpty) return null;
    final doc = await _users.doc(uid).get();
    return usernameFrom(doc.data());
  }

  /// Claims [input] as [uid]'s username, releasing any old one in the same
  /// transaction. Returns the handle saved (lower-case, no @).
  ///
  /// Throws [UsernameInvalidException] if it isn't allowed and
  /// [UsernameTakenException] if someone else has it.
  static Future<String> claim(String uid, String input) async {
    final handle = normalise(input);
    final problem = validate(handle);
    if (problem != null) {
      if (reserved.contains(handle)) throw UsernameTakenException(handle);
      throw UsernameInvalidException(problem);
    }
    final db = BalanceService.db;
    final userRef = _users.doc(uid);
    final lockRef = _usernames.doc(handle);

    // Returns false (rather than throwing) when it's taken: an error thrown
    // inside a transaction can come back wrapped on some platforms.
    final claimed = await db.runTransaction<bool>((tx) async {
      // All reads before any writes.
      final userSnap = await tx.get(userRef);
      final lockSnap = await tx.get(lockRef);
      final old = usernameFrom(userSnap.data());
      DocumentSnapshot<Map<String, dynamic>>? oldLock;
      if (old != null && old != handle) {
        oldLock = await tx.get(_usernames.doc(old));
      }

      final owner = lockSnap.data()?['uid'];
      if (lockSnap.exists && owner != uid) return false;

      if (!lockSnap.exists) {
        tx.set(lockRef, {
          'uid': uid,
          'created_at': FieldValue.serverTimestamp(),
        });
      }
      // Free the old handle, but only if it's really ours.
      if (oldLock != null && oldLock.exists && oldLock.data()?['uid'] == uid) {
        tx.delete(oldLock.reference);
      }
      // update() when the doc exists so nothing else in it is touched.
      if (userSnap.exists) {
        tx.update(userRef, {'username': handle});
      } else {
        tx.set(userRef, {'username': handle});
      }
      return true;
    });
    if (!claimed) throw UsernameTakenException(handle);
    return handle;
  }

  /// The uid that owns [handle] ("@taz" or "taz"), or null if nobody does.
  static Future<String?> lookup(String handle) async {
    final h = normalise(handle);
    if (h.length < minLength || h.length > maxLength || !_allowed.hasMatch(h)) {
      return null;
    }
    final doc = await _usernames.doc(h).get();
    final uid = doc.data()?['uid'];
    return uid is String && uid.isNotEmpty ? uid : null;
  }

  /// Finds the person an invite link points at: `?add=taz` (a username) or
  /// `?add=<uid>` (for people without one). Null if there's nobody.
  static Future<FoundUser?> resolve(String handleOrUid) async {
    final raw = handleOrUid.trim();
    if (raw.isEmpty) return null;

    final byHandle = await lookup(raw);
    if (byHandle != null) {
      final doc = await _users.doc(byHandle).get();
      return FoundUser(uid: byHandle, data: doc.data() ?? const {});
    }

    // Not a username: maybe a uid. Doc ids can't contain "/".
    if (raw.contains('/') || raw.startsWith('@')) return null;
    final doc = await _users.doc(raw).get();
    if (!doc.exists) return null;
    return FoundUser(uid: raw, data: doc.data() ?? const {});
  }

  /// A good first guess at a username, from the name they chose or the
  /// start of their email: "Sam Jones" → "sam_jones",
  /// "sam.jones@gmail.com" → "sam_jones". Always valid in shape (it may
  /// still be taken; see [suggestAvailable]).
  static String suggest({String? email, String? displayName}) {
    String clean(String? s) {
      var t = (s ?? '').toLowerCase();
      t = t.replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
      t = t.replaceAll(RegExp(r'_+'), '_');
      t = t.replaceAll(RegExp(r'^_+|_+$'), '');
      if (t.length > maxLength) {
        t = t.substring(0, maxLength).replaceAll(RegExp(r'_+$'), '');
      }
      return t;
    }

    final fromName = clean(displayName);
    if (fromName.length >= minLength && !reserved.contains(fromName)) {
      return fromName;
    }
    final at = (email ?? '').indexOf('@');
    final fromEmail = clean(at > 0 ? email!.substring(0, at) : email);
    if (fromEmail.length >= minLength && !reserved.contains(fromEmail)) {
      return fromEmail;
    }
    final short = fromName.isNotEmpty ? fromName : fromEmail;
    if (short.isEmpty) return 'card_holder';
    final padded = '${short}_card';
    return padded.length > maxLength
        ? padded.substring(0, maxLength)
        : padded;
  }

  /// [suggest], made free: tries it as is, then with a couple of digits on
  /// the end. Returns the suggestion even if every try was taken (they'll
  /// be told when they save).
  static Future<String> suggestAvailable({
    String? uid,
    String? email,
    String? displayName,
    Random? random,
  }) async {
    final base = suggest(email: email, displayName: displayName);
    final rng = random ?? Random();
    var candidate = base;
    for (var i = 0; i < 6; i++) {
      try {
        final owner = await lookup(candidate);
        if (owner == null || owner == uid) return candidate;
      } catch (_) {
        return base;
      }
      final digits = '${10 + rng.nextInt(90)}';
      final room = maxLength - digits.length;
      final stem = base.length > room ? base.substring(0, room) : base;
      candidate = '$stem$digits';
    }
    return base;
  }

  /// The link that opens the app on "Add <you> as a friend?":
  /// https://thecaloriecard.com/?add=taz
  static String inviteLink(String handleOrUid) =>
      Uri.https(siteHost, '/', {'add': handleOrUid}).toString();

  /// True if [input] reads as an email ("sam@x.com"), not "@sam".
  static bool looksLikeEmail(String input) => input.trim().indexOf('@') > 0;
}
