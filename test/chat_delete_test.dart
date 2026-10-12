// Deleting a chat from your list, and deleting single messages.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:namer_app/services/chat_service.dart';

import 'test_helpers.dart';

void main() {
  late TestWorld w;
  const me = TestWorld.uid;
  const sam = TestWorld.otherUid;
  final convoId = ChatService.conversationId(me, sam);

  setUp(() => w = TestWorld()..install());
  tearDown(TestWorld.uninstall);

  DocumentReference<Map<String, dynamic>> convo() =>
      w.db.collection('conversations').doc(convoId);

  Future<Map<String, dynamic>> data() async => (await convo().get()).data()!;

  Future<void> say(String from, String text) => ChatService.sendToFriend(
        uid: from,
        myName: from,
        friendId: from == me ? sam : me,
        friendName: 'x',
        text: text,
      );

  group('hiddenFromList', () {
    final t1 = Timestamp.fromDate(DateTime(2026, 10, 12, 18));
    final t2 = Timestamp.fromDate(DateTime(2026, 10, 12, 19));

    test('not deleted: shows', () {
      expect(ChatService.hiddenFromList({'last_message_time': t1}, me),
          isFalse);
    });

    test('deleted with nothing new: hidden', () {
      expect(
          ChatService.hiddenFromList({
            'last_message_time': t1,
            'deleted_at': {me: t2},
          }, me),
          isTrue);
    });

    test('a new message since brings it back', () {
      expect(
          ChatService.hiddenFromList({
            'last_message_time': t2,
            'deleted_at': {me: t1},
          }, me),
          isFalse);
    });

    test('a delete still saving (no time yet) hides it straight away', () {
      expect(
          ChatService.hiddenFromList({
            'last_message_time': t1,
            'deleted_at': {me: null},
          }, me),
          isTrue);
    });

    test('only for the person who deleted it', () {
      expect(
          ChatService.hiddenFromList({
            'last_message_time': t1,
            'deleted_at': {me: t2},
          }, sam),
          isFalse);
    });
  });

  test('delete chat clears it and resets your unread count', () async {
    await say(sam, 'hi');
    await ChatService.deleteForMe(me, convoId);
    final c = await data();
    expect((c['deleted_at'] as Map).containsKey(me), isTrue);
    expect((c['cleared_at'] as Map).containsKey(me), isTrue);
    expect((c['unread_count'] as Map)[me], 0);
  });

  test('delete for me hides just that message, just for you', () async {
    await say(sam, 'one');
    await say(sam, 'two');
    final msgs = await convo().collection('messages').get();
    final first = msgs.docs.firstWhere((d) => d['message'] == 'one').id;
    await ChatService.hideMessageForMe(me, convoId, first);
    final c = await data();
    expect(ChatService.hiddenMessages(c, me), {first});
    expect(ChatService.hiddenMessages(c, sam), isEmpty);
  });

  test('delete for everyone removes it and fixes the preview', () async {
    await say(me, 'oops');
    final id = (await convo().collection('messages').get()).docs.single.id;
    await ChatService.deleteForEveryone(
        uid: me, conversationId: convoId, messageId: id, text: 'oops');
    expect((await convo().collection('messages').get()).docs, isEmpty);
    expect((await data())['last_message'], 'Message deleted');
  });
}
