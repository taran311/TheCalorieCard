// Tests for the friends features: friends' days (activity strip and group
// cards), nudges, names, chat messages and removing a friend.

import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/chat_service.dart';
import 'package:namer_app/services/friend_activity.dart';
import 'package:namer_app/services/friends_service.dart';

import 'test_helpers.dart';

const me = TestWorld.uid;
const friend = TestWorld.otherUid;

void main() {
  group("A friend's day", () {
    test('budget is what was left plus what was spent (pot included)', () {
      final day = FriendDay.fromLog({
        'finished': false,
        'totals': {'calories': 1000},
        'balances': {'calories': 1150}, // 2000 goal + 150 from the pot
        'goals': {'calorie_goal': 2000},
      });
      expect(day.budget, 2150);
      expect(day.spent, 1000);
      expect(day.percent, 47);
      expect(day.onTrack, isTrue);
      expect(day.label, '47% of budget spent · on track');
    });

    test('falls back to the saved goal, then their current goal', () {
      expect(
          FriendDay.fromLog({
            'goals': {'calorie_goal': 1800},
            'totals': {'calories': 900},
          }).budget,
          1800);
      expect(FriendDay.fromLog(null, fallbackGoal: 2200).budget, 2200);
      expect(FriendDay.fromLog(null).budget, isNull);
    });

    test('live spending overrides the logged total', () {
      final day = FriendDay.fromLog({
        'totals': {'calories': 500},
        'balances': {'calories': 1500},
      }, spentNow: 2100);
      expect(day.spent, 2100);
      expect(day.onTrack, isFalse);
      expect(day.label, '105% of budget spent · over');
    });

    test('finished days say so', () {
      expect(
          FriendDay.fromLog({
            'finished': true,
            'totals': {'calories': 1900},
            'balances': {'calories': 100},
          }).label,
          'Finished ✓ · on budget');
      expect(FriendDay.fromLog({'finished': true}).label, 'Finished today ✓');
      expect(FriendDay.none.label, 'Nothing logged yet today');
      expect(FriendDay.none.hasData, isFalse);
    });
  });

  group('Nudges', () {
    test('once per friend per day, and old days are forgotten', () {
      var stored = <String>[];
      expect(FriendActivity.nudgedIn(stored, friend, '2026-10-09'), isFalse);
      stored = FriendActivity.withNudge(stored, friend, '2026-10-09');
      expect(FriendActivity.nudgedIn(stored, friend, '2026-10-09'), isTrue);
      expect(FriendActivity.nudgedIn(stored, 'other', '2026-10-09'), isFalse);
      // Next day: allowed again, and yesterday's entry is dropped.
      expect(FriendActivity.nudgedIn(stored, friend, '2026-10-10'), isFalse);
      stored = FriendActivity.withNudge(stored, 'other', '2026-10-10');
      expect(stored, ['other|2026-10-10']);
      // No duplicates.
      stored = FriendActivity.withNudge(stored, 'other', '2026-10-10');
      expect(stored, ['other|2026-10-10']);
    });
  });

  test('big groups are asked about in 30s', () {
    final ids = [for (var i = 0; i < 65; i++) 'u$i'];
    final chunks = FriendActivity.chunked(ids, 30);
    expect(chunks.map((c) => c.length), [30, 30, 5]);
    expect(chunks.expand((c) => c), ids);
  });

  group('With Firestore', () {
    late TestWorld w;

    setUp(() {
      w = TestWorld()..install();
      FriendsService.clearNameCache();
    });

    tearDown(TestWorld.uninstall);

    test('names: display name first, then the start of the email', () async {
      await w.db.collection('users').doc(me).set({
        'email': 'taran@example.com',
        'display_name': 'Taran S',
      });
      await w.db.collection('users').doc(friend).set({
        'email': 'sam.jones@example.com',
      });
      expect(await FriendsService.nameFor(me), 'Taran S');
      expect(await FriendsService.nameFor(friend), 'sam.jones');
      expect(await FriendsService.nameFor('nobody', email: 'x@y.com'), 'x');
    });

    test('chat messages can carry extra fields, but not override the basics',
        () async {
      await ChatService.sendToFriend(
        uid: me,
        myName: 'taran',
        friendId: friend,
        friendName: 'sam',
        text: 'Your turn',
        extra: {'type': 'game', 'game_id': 'g1', 'sender_id': 'evil'},
      );
      final msgs = await w.db
          .collection('conversations')
          .doc(ChatService.conversationId(me, friend))
          .collection('messages')
          .get();
      final m = msgs.docs.single.data();
      expect(m['type'], 'game');
      expect(m['game_id'], 'g1');
      expect(m['sender_id'], me);
      expect(m['message'], 'Your turn');
    });

    test('sending to a group starts its chat and counts unread', () async {
      await ChatService.sendToGroup(
        uid: me,
        myName: 'taran',
        groupId: 'lunch',
        groupName: 'Lunch Club',
        memberIds: [me, friend, 'user-3'],
        text: 'My week',
      );
      final convo =
          (await w.db.collection('conversations').doc('group_lunch').get())
              .data()!;
      expect(convo['is_group'], isTrue);
      expect(convo['last_message'], 'My week');
      expect(convo['unread_count'][friend], 1);
      expect(convo['unread_count']['user-3'], 1);
      expect(convo['unread_count'][me], 0);
    });

    test('removing a friend takes them out of groups you made only',
        () async {
      final mine = await w.db.collection('friend_groups').add({
        'name': 'Gym Buddies',
        'creator_id': me,
        'members': [me, friend, 'user-3'],
      });
      final theirs = await w.db.collection('friend_groups').add({
        'name': 'Lunch Club',
        'creator_id': 'user-3',
        'members': ['user-3', me, friend],
      });
      final unrelated = await w.db.collection('friend_groups').add({
        'name': 'Family',
        'creator_id': me,
        'members': [me, 'user-3'],
      });

      final shared = await FriendsService.removeFromMyGroups(me, friend);

      expect(shared, ['Lunch Club']);
      expect((await mine.get()).data()!['members'], [me, 'user-3']);
      expect((await theirs.get()).data()!['members'], ['user-3', me, friend]);
      expect((await unrelated.get()).data()!['members'], [me, 'user-3']);
    });
  });
}
