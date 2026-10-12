// Tests for usernames (@taz) and for adding friends by username or link:
// rules for what's allowed, claiming and changing one, looking people up,
// suggestions, and the friend request it leads to.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/friends_service.dart';
import 'package:namer_app/services/username_service.dart';

import 'test_helpers.dart';

const me = TestWorld.uid;
const friend = TestWorld.otherUid;

void main() {
  group('Which usernames are allowed', () {
    test('3–20 lower-case letters, digits and _', () {
      expect(UsernameService.validate('taz'), isNull);
      expect(UsernameService.validate('sam_jones_99'), isNull);
      expect(UsernameService.validate('a' * 20), isNull);
      expect(UsernameService.validate('ab'), isNotNull);
      expect(UsernameService.validate('a' * 21), isNotNull);
      expect(UsernameService.validate('sam jones'), isNotNull);
      expect(UsernameService.validate('sam.jones'), isNotNull);
      expect(UsernameService.validate('sam-jones'), isNotNull);
      expect(UsernameService.validate(''), isNotNull);
    });

    test('the @ and capitals are ignored', () {
      expect(UsernameService.normalise(' @Taz '), 'taz');
      expect(UsernameService.validate('@Taz'), isNull);
    });

    test('official-looking names are taken', () {
      expect(UsernameService.validate('admin'), '@admin is taken — try another');
      expect(UsernameService.validate('TheCalorieCard'), isNotNull);
    });

    test('an email is told apart from a username', () {
      expect(UsernameService.looksLikeEmail('sam@example.com'), isTrue);
      expect(UsernameService.looksLikeEmail('@sam'), isFalse);
      expect(UsernameService.looksLikeEmail('sam'), isFalse);
    });

    test('invite links', () {
      expect(UsernameService.inviteLink('taz'),
          'https://thecaloriecard.com/?add=taz');
    });
  });

  group('Suggestions', () {
    test('from the display name, then the email', () {
      expect(UsernameService.suggest(displayName: 'Sam Jones'), 'sam_jones');
      expect(UsernameService.suggest(email: 'sam.jones@gmail.com'),
          'sam_jones');
      expect(
          UsernameService.suggest(
              displayName: 'Jo', email: 'jo.bloggs@x.com'),
          'jo_bloggs');
    });

    test('always a valid shape', () {
      for (final s in [
        UsernameService.suggest(displayName: 'Zoë-Anne O\'Brien-Smythe Jr'),
        UsernameService.suggest(email: 'a@b.com'),
        UsernameService.suggest(),
        UsernameService.suggest(displayName: '!!!'),
        UsernameService.suggest(email: 'admin@x.com'),
      ]) {
        expect(UsernameService.validate(s), isNull, reason: s);
      }
    });
  });

  group('With Firestore', () {
    late TestWorld w;

    setUp(() {
      w = TestWorld()..install();
      FriendsService.clearNameCache();
    });

    tearDown(TestWorld.uninstall);

    Future<void> addUser(String uid, String email, {String? name}) =>
        w.db.collection('users').doc(uid).set({
          'email': email,
          'friends': <String>[],
          if (name != null) 'display_name': name,
        });

    test('claiming saves the lock and the profile, and keeps the profile',
        () async {
      await addUser(me, 'taran@example.com', name: 'Taran');
      final saved = await UsernameService.claim(me, '@Taz');
      expect(saved, 'taz');

      final lock = (await w.db.collection('usernames').doc('taz').get()).data();
      expect(lock?['uid'], me);
      expect(lock?['created_at'], isNotNull);
      final user = (await w.db.collection('users').doc(me).get()).data()!;
      expect(user['username'], 'taz');
      expect(user['email'], 'taran@example.com');
      expect(user['display_name'], 'Taran');
      expect(await UsernameService.usernameOf(me), 'taz');
    });

    test("someone else's username is refused, whatever the case", () async {
      await addUser(me, 'taran@example.com');
      await addUser(friend, 'sam@example.com');
      await UsernameService.claim(friend, 'taz');

      await expectLater(
        UsernameService.claim(me, 'TAZ'),
        throwsA(isA<UsernameTakenException>().having(
            (e) => e.message, 'message', '@taz is taken — try another')),
      );
      expect(await UsernameService.lookup('taz'), friend);
      expect(
          (await w.db.collection('users').doc(me).get()).data()?['username'],
          isNull);
    });

    test('bad usernames are refused before anything is written', () async {
      await addUser(me, 'taran@example.com');
      await expectLater(UsernameService.claim(me, 'a b'),
          throwsA(isA<UsernameInvalidException>()));
      await expectLater(UsernameService.claim(me, 'support'),
          throwsA(isA<UsernameTakenException>()));
      expect((await w.db.collection('usernames').get()).docs, isEmpty);
    });

    test('changing frees the old one for someone else', () async {
      await addUser(me, 'taran@example.com');
      await addUser(friend, 'sam@example.com');
      await UsernameService.claim(me, 'taz');
      await UsernameService.claim(me, 'taran');

      expect((await w.db.collection('usernames').doc('taz').get()).exists,
          isFalse);
      expect(await UsernameService.lookup('taran'), me);
      expect(await UsernameService.lookup('taz'), isNull);
      expect(await UsernameService.usernameOf(me), 'taran');

      // Now someone else can have it.
      expect(await UsernameService.claim(friend, 'taz'), 'taz');
      expect(await UsernameService.lookup('@Taz'), friend);
    });

    test('claiming your own username again changes nothing', () async {
      await addUser(me, 'taran@example.com');
      await UsernameService.claim(me, 'taz');
      expect(await UsernameService.claim(me, 'taz'), 'taz');
      expect(await UsernameService.lookup('taz'), me);
      expect((await w.db.collection('usernames').get()).docs.length, 1);
    });

    test('works for someone with no profile yet', () async {
      await UsernameService.claim(me, 'taz');
      expect(await UsernameService.usernameOf(me), 'taz');
    });

    test('links find people by username or by id', () async {
      await addUser(friend, 'sam@example.com', name: 'Sam');
      await UsernameService.claim(friend, 'sam');

      final byName = await UsernameService.resolve('sam');
      expect(byName?.uid, friend);
      expect(byName?.username, 'sam');
      expect(FriendsService.nameFromUser(byName?.data), 'Sam');

      expect((await UsernameService.resolve(friend))?.uid, friend);
      expect(await UsernameService.resolve('nobody_here'), isNull);
      expect(await UsernameService.resolve(''), isNull);
      expect(await UsernameService.resolve('a/b'), isNull);
    });

    test('suggestions dodge names already taken', () async {
      await addUser(friend, 'sam@example.com');
      await UsernameService.claim(friend, 'sam_jones');

      final s = await UsernameService.suggestAvailable(
        uid: me,
        displayName: 'Sam Jones',
        random: Random(1),
      );
      expect(s, isNot('sam_jones'));
      expect(s, startsWith('sam_jones'));
      expect(UsernameService.validate(s), isNull);
      expect(await UsernameService.lookup(s), isNull);

      // Your own current username counts as free.
      expect(
          await UsernameService.suggestAvailable(
              uid: friend, displayName: 'Sam Jones'),
          'sam_jones');
    });

    group('Friend requests', () {
      setUp(() async {
        await addUser(me, 'taran@example.com');
        await addUser(friend, 'sam@example.com');
      });

      test('a new request is the same doc as the email flow makes', () async {
        final status = await FriendsService.sendRequest(
          myUid: me,
          myEmail: 'taran@example.com',
          toUid: friend,
          toEmail: 'sam@example.com',
        );
        expect(status.relation, FriendRelation.none);
        final docs = (await w.db.collection('friend_requests').get()).docs;
        expect(docs.length, 1);
        final r = docs.single.data();
        expect(r['from_user_id'], me);
        expect(r['from_email'], 'taran@example.com');
        expect(r['to_user_id'], friend);
        expect(r['to_email'], 'sam@example.com');
        expect(r['status'], 'pending');
        expect(r['timestamp'], isNotNull);

        // Asking twice doesn't send twice.
        final again = await FriendsService.sendRequest(
          myUid: me,
          myEmail: 'taran@example.com',
          toUid: friend,
          toEmail: 'sam@example.com',
        );
        expect(again.relation, FriendRelation.requestSent);
        expect(
            (await w.db.collection('friend_requests').get()).docs.length, 1);
      });

      test('yourself and existing friends are caught', () async {
        expect((await FriendsService.relationTo(me, me)).relation,
            FriendRelation.self);
        await w.db.collection('users').doc(me).update({
          'friends': [friend],
        });
        await w.db.collection('users').doc(friend).update({
          'friends': [me],
        });
        final status = await FriendsService.sendRequest(
          myUid: me,
          myEmail: 'taran@example.com',
          toUid: friend,
          toEmail: 'sam@example.com',
        );
        expect(status.relation, FriendRelation.friends);
        expect((await w.db.collection('friend_requests').get()).docs, isEmpty);
      });

      test('a one-sided friendship can be mended with a request', () async {
        // Left over from an older version: you have them, they don't
        // have you.
        await w.db.collection('users').doc(me).update({
          'friends': [friend],
        });
        final status = await FriendsService.sendRequest(
          myUid: me,
          myEmail: 'taran@example.com',
          toUid: friend,
          toEmail: 'sam@example.com',
        );
        expect(status.relation, FriendRelation.none);
        final sent = await w.db.collection('friend_requests').get();
        expect(sent.docs.length, 1);

        await FriendsService.acceptRequest(
          requestId: sent.docs.first.id,
          myUid: friend,
          fromUid: me,
        );
        expect(await FriendsService.friendIds(me), [friend]);
        expect(await FriendsService.friendIds(friend), [me]);
        expect((await FriendsService.relationTo(me, friend)).relation,
            FriendRelation.friends);
      });

      test('if they asked first, that request can be accepted', () async {
        final theirs = await w.db.collection('friend_requests').add({
          'from_user_id': friend,
          'from_email': 'sam@example.com',
          'to_user_id': me,
          'to_email': 'taran@example.com',
          'status': 'pending',
        });
        final status = await FriendsService.sendRequest(
          myUid: me,
          myEmail: 'taran@example.com',
          toUid: friend,
          toEmail: 'sam@example.com',
        );
        expect(status.relation, FriendRelation.requestReceived);
        expect(status.requestId, theirs.id);
        expect(status.requestFromEmail, 'sam@example.com');
        // Nothing new was sent the other way.
        expect(
            (await w.db.collection('friend_requests').get()).docs.length, 1);

        await FriendsService.acceptRequest(
          requestId: theirs.id,
          myUid: me,
          fromUid: friend,
        );
        expect((await theirs.get()).data()?['status'], 'accepted');
        expect(await FriendsService.friendIds(me), [friend]);
        expect(await FriendsService.friendIds(friend), [me]);
        expect((await FriendsService.relationTo(me, friend)).relation,
            FriendRelation.friends);
      });
    });
  });
}
