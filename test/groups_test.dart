// Leaving friend groups, and clearing a chat just for yourself.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/chat_service.dart';
import 'package:namer_app/services/group_service.dart';

import 'test_helpers.dart';

void main() {
  late TestWorld w;
  const me = TestWorld.uid;
  const sam = TestWorld.otherUid;

  setUp(() => w = TestWorld()..install());
  tearDown(TestWorld.uninstall);

  Future<String> group(List<String> members, {String creator = me}) async {
    final ref = await w.db.collection('friend_groups').add({
      'name': 'Lunch Club',
      'creator_id': creator,
      'members': members,
    });
    return ref.id;
  }

  Future<Map<String, dynamic>?> read(String id) async =>
      (await w.db.collection('friend_groups').doc(id).get()).data();

  test('leaving someone else\'s group just takes you out', () async {
    final id = await group([me, sam], creator: sam);
    expect(await GroupService.leave(me, id), LeaveOutcome.left);
    final g = await read(id);
    expect(g?['members'], [sam]);
    expect(g?['creator_id'], sam);
  });

  test('leaving a group you made hands it to the next member', () async {
    final id = await group([me, sam, 'jess']);
    expect(await GroupService.leave(me, id), LeaveOutcome.handedOver);
    final g = await read(id);
    expect(g?['members'], [sam, 'jess']);
    expect(g?['creator_id'], sam);
  });

  test('the last one out deletes the group', () async {
    final id = await group([me]);
    expect(GroupService.outcomeFor(await read(id), me), LeaveOutcome.deleted);
    expect(await GroupService.leave(me, id), LeaveOutcome.deleted);
    expect(await read(id), isNull);
  });

  test('leaving also takes you out of the group chat', () async {
    final id = await group([me, sam], creator: sam);
    await w.db.collection('conversations').doc('group_$id').set({
      'participant_ids': [me, sam],
    });
    await GroupService.leave(me, id);
    final chat =
        (await w.db.collection('conversations').doc('group_$id').get()).data();
    expect(chat?['participant_ids'], [sam]);
  });

  test('clear chat hides older messages for you only', () async {
    await w.db.collection('conversations').doc('c1').set({
      'participant_ids': [me, sam],
      'unread_count': {me: 3, sam: 0},
    });
    await ChatService.clearForMe(me, 'c1');
    final convo = (await w.db.collection('conversations').doc('c1').get()).data();
    final cleared = ChatService.clearedAt(convo, me);
    expect(cleared, isNotNull);
    expect(ChatService.clearedAt(convo, sam), isNull);
    expect((convo?['unread_count'] as Map)[me], 0);

    final before = Timestamp.fromDate(cleared!.subtract(const Duration(minutes: 1)));
    final after = Timestamp.fromDate(cleared.add(const Duration(minutes: 1)));
    expect(ChatService.showsAfterClear(before, cleared), isFalse);
    expect(ChatService.showsAfterClear(after, cleared), isTrue);
    expect(ChatService.showsAfterClear(null, cleared), isTrue,
        reason: 'still sending');
    expect(ChatService.showsAfterClear(before, null), isTrue);

    // A chat that was never started: nothing to clear, no error.
    await ChatService.clearForMe(me, 'never-started');
  });
}
